package socket

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

var ipv4Pattern = regexp.MustCompile(`^([0-9]{1,3}\.){3}[0-9]{1,3}$`)

type NftablesAdapterOptions struct {
	StateFilePath    string
	NFTConfPath      string
	ResolveIPv4      func(target string) (string, error)
	RunCheckAndApply func(confPath string) error
	RelayLANIP       string
}

type nftablesAdapter struct {
	opts NftablesAdapterOptions
}

func NewNftablesAdapter(opts NftablesAdapterOptions) ForwardEngine {
	if strings.TrimSpace(opts.StateFilePath) == "" {
		opts.StateFilePath = "/etc/relay-forwards.conf"
	}
	if strings.TrimSpace(opts.NFTConfPath) == "" {
		opts.NFTConfPath = "/etc/nftables.conf"
	}
	if opts.ResolveIPv4 == nil {
		opts.ResolveIPv4 = resolveTargetIPv4
	}
	if opts.RunCheckAndApply == nil {
		opts.RunCheckAndApply = func(confPath string) error {
			if err := exec.Command("nft", "-c", "-f", confPath).Run(); err != nil {
				return err
			}
			return exec.Command("nft", "-f", confPath).Run()
		}
	}
	if strings.TrimSpace(opts.RelayLANIP) == "" {
		opts.RelayLANIP = detectRelayLANIP()
	}
	return &nftablesAdapter{opts: opts}
}

func (n *nftablesAdapter) Name() string {
	return "nftables"
}

func (n *nftablesAdapter) DryRun(_ context.Context, req ForwardApplyRequest) (*ForwardApplyResult, error) {
	if err := validateForwardRules(req.Forwards); err != nil {
		return nil, err
	}
	if err := n.checkShrinkSafety(req); err != nil {
		return nil, err
	}
	if _, err := n.renderNftConfig(req.Forwards); err != nil {
		return nil, err
	}
	return &ForwardApplyResult{
		Engine:       n.Name(),
		RulesApplied: len(req.Forwards),
		Message:      "dry-run passed",
	}, nil
}

func (n *nftablesAdapter) Apply(_ context.Context, req ForwardApplyRequest) (*ForwardApplyResult, error) {
	if err := validateForwardRules(req.Forwards); err != nil {
		return nil, err
	}
	if err := n.checkShrinkSafety(req); err != nil {
		return nil, err
	}

	rendered, err := n.renderNftConfig(req.Forwards)
	if err != nil {
		return nil, err
	}
	stateContent := buildStateFile(req.Forwards)

	prevState, stateExists, err := readFileIfExists(n.opts.StateFilePath)
	if err != nil {
		return nil, fmt.Errorf("read state backup failed: %w", err)
	}
	prevNFT, nftExists, err := readFileIfExists(n.opts.NFTConfPath)
	if err != nil {
		return nil, fmt.Errorf("read nft backup failed: %w", err)
	}

	rollback := func() {
		_ = restoreFile(n.opts.StateFilePath, prevState, stateExists, 0600)
		_ = restoreFile(n.opts.NFTConfPath, prevNFT, nftExists, 0644)
	}

	if err := os.MkdirAll(filepath.Dir(n.opts.StateFilePath), 0755); err != nil {
		return nil, fmt.Errorf("prepare state dir failed: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(n.opts.NFTConfPath), 0755); err != nil {
		return nil, fmt.Errorf("prepare nft dir failed: %w", err)
	}

	if err := os.WriteFile(n.opts.StateFilePath, []byte(stateContent), 0600); err != nil {
		return nil, fmt.Errorf("write state failed: %w", err)
	}
	if err := os.WriteFile(n.opts.NFTConfPath, []byte(rendered), 0644); err != nil {
		rollback()
		return nil, fmt.Errorf("write nft failed: %w", err)
	}
	if err := n.opts.RunCheckAndApply(n.opts.NFTConfPath); err != nil {
		rollback()
		return nil, fmt.Errorf("apply nft failed: %w", err)
	}

	return &ForwardApplyResult{
		Engine:       n.Name(),
		RulesApplied: len(req.Forwards),
		Message:      "apply succeeded",
	}, nil
}

func (n *nftablesAdapter) checkShrinkSafety(req ForwardApplyRequest) error {
	if req.AllowShrink {
		return nil
	}
	currentCount := countPortDefines(n.opts.NFTConfPath)
	if currentCount > 0 && len(req.Forwards) < currentCount {
		return fmt.Errorf("safety check blocked apply: state rules %d < current nft config rules %d", len(req.Forwards), currentCount)
	}
	return nil
}

func (n *nftablesAdapter) renderNftConfig(forwards []ForwardPortRule) (string, error) {
	resolvedIPs := make([]string, 0, len(forwards))
	for _, f := range forwards {
		ip, err := n.opts.ResolveIPv4(f.Target)
		if err != nil {
			return "", fmt.Errorf("resolve target %s failed: %w", f.Target, err)
		}
		resolvedIPs = append(resolvedIPs, ip)
	}

	var b strings.Builder
	b.WriteString("#!/usr/sbin/nft -f\n")
	b.WriteString("flush ruleset\n\n")
	b.WriteString(fmt.Sprintf("define RELAY_LAN_IP = %s\n", n.opts.RelayLANIP))
	for i, f := range forwards {
		idx := i + 1
		b.WriteString(fmt.Sprintf("define DEST_IP_%d   = %s\n", idx, resolvedIPs[i]))
		b.WriteString(fmt.Sprintf("define DEST_PORT_%d = %d\n", idx, f.TargetPort))
		b.WriteString(fmt.Sprintf("define PORT_IN_%d   = %d\n", idx, f.RelayPort))
	}

	b.WriteString("table inet filter {\n")
	b.WriteString("    chain input { type filter hook input priority 0; policy drop;\n")
	b.WriteString("        ct state { established, related } accept\n")
	b.WriteString("        iif \"lo\" accept\n")
	b.WriteString("        ip protocol icmp accept\n")
	b.WriteString("        tcp dport 22 ct state new limit rate 10/minute burst 5 packets accept\n")
	b.WriteString("        tcp dport 22 ct state established accept\n")
	b.WriteString("        meta l4proto { tcp, udp } th dport { ")
	for i := range forwards {
		if i > 0 {
			b.WriteString(", ")
		}
		b.WriteString(fmt.Sprintf("$PORT_IN_%d", i+1))
	}
	b.WriteString(" } accept\n")
	b.WriteString("    }\n")

	b.WriteString("    chain forward { type filter hook forward priority 0; policy drop;\n")
	b.WriteString("        ct state { established, related } accept\n")
	for i := range forwards {
		b.WriteString(fmt.Sprintf("        ip daddr $DEST_IP_%d meta l4proto { tcp, udp } th dport $DEST_PORT_%d accept\n", i+1, i+1))
	}
	b.WriteString("    }\n")
	b.WriteString("}\n\n")

	b.WriteString("table ip nat {\n")
	b.WriteString("    chain prerouting { type nat hook prerouting priority dstnat; policy accept;\n")
	for i := range forwards {
		b.WriteString(fmt.Sprintf("        meta l4proto { tcp, udp } th dport $PORT_IN_%d dnat to $DEST_IP_%d:$DEST_PORT_%d\n", i+1, i+1, i+1))
	}
	b.WriteString("    }\n")
	b.WriteString("    chain postrouting { type nat hook postrouting priority srcnat; policy accept;\n")
	for i := range forwards {
		b.WriteString(fmt.Sprintf("        ip daddr $DEST_IP_%d meta l4proto { tcp, udp } th dport $DEST_PORT_%d snat to $RELAY_LAN_IP\n", i+1, i+1))
	}
	b.WriteString("    }\n")
	b.WriteString("}\n")
	return b.String(), nil
}

func validateForwardRules(forwards []ForwardPortRule) error {
	if len(forwards) == 0 {
		return fmt.Errorf("forwards cannot be empty")
	}
	seenRelay := make(map[int]struct{}, len(forwards))
	for _, f := range forwards {
		if strings.TrimSpace(f.Name) == "" {
			return fmt.Errorf("forward name is required")
		}
		if strings.Contains(f.Name, "|") {
			return fmt.Errorf("forward name cannot contain |")
		}
		if strings.TrimSpace(f.Target) == "" {
			return fmt.Errorf("target is required")
		}
		if f.TargetPort < 1 || f.TargetPort > 65535 {
			return fmt.Errorf("invalid targetPort: %d", f.TargetPort)
		}
		if f.RelayPort < 1 || f.RelayPort > 65535 {
			return fmt.Errorf("invalid relayPort: %d", f.RelayPort)
		}
		if _, ok := seenRelay[f.RelayPort]; ok {
			return fmt.Errorf("duplicate relayPort: %d", f.RelayPort)
		}
		seenRelay[f.RelayPort] = struct{}{}
	}
	return nil
}

func resolveTargetIPv4(target string) (string, error) {
	if ipv4Pattern.MatchString(target) {
		return target, nil
	}
	ips, err := net.LookupIP(target)
	if err != nil {
		return "", err
	}
	for _, ip := range ips {
		v4 := ip.To4()
		if v4 != nil {
			return v4.String(), nil
		}
	}
	return "", fmt.Errorf("no ipv4 for target %s", target)
}

func detectRelayLANIP() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "127.0.0.1"
	}
	for _, iface := range ifaces {
		if (iface.Flags&net.FlagUp) == 0 || (iface.Flags&net.FlagLoopback) != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			ipNet, ok := addr.(*net.IPNet)
			if !ok || ipNet.IP == nil {
				continue
			}
			v4 := ipNet.IP.To4()
			if v4 != nil {
				return v4.String()
			}
		}
	}
	return "127.0.0.1"
}

func countPortDefines(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	lines := strings.Split(string(data), "\n")
	count := 0
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "define PORT_IN_") {
			count++
		}
	}
	return count
}

func buildStateFile(forwards []ForwardPortRule) string {
	var b strings.Builder
	for _, f := range forwards {
		b.WriteString(fmt.Sprintf("%s|%s|%d|%d\n", f.Name, f.Target, f.TargetPort, f.RelayPort))
	}
	return b.String()
}

func readFileIfExists(path string) ([]byte, bool, error) {
	data, err := os.ReadFile(path)
	if err == nil {
		return data, true, nil
	}
	if os.IsNotExist(err) {
		return nil, false, nil
	}
	return nil, false, err
}

func restoreFile(path string, data []byte, existed bool, mode os.FileMode) error {
	if !existed {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	return os.WriteFile(path, data, mode)
}

func parseStateFile(path string) ([]ForwardPortRule, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	lines := strings.Split(string(data), "\n")
	out := make([]ForwardPortRule, 0, len(lines))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Split(line, "|")
		if len(parts) < 4 {
			continue
		}
		targetPort, err1 := strconv.Atoi(parts[2])
		relayPort, err2 := strconv.Atoi(parts[3])
		if err1 != nil || err2 != nil {
			continue
		}
		out = append(out, ForwardPortRule{
			Name:       parts[0],
			Target:     parts[1],
			TargetPort: targetPort,
			RelayPort:  relayPort,
		})
	}
	return out, nil
}
