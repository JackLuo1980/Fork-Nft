package socket

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolveForwardEngineName(t *testing.T) {
	t.Setenv("FORKNFT_FORWARD_ENGINE", "")
	if got := resolveForwardEngineName(""); got != "gost" {
		t.Fatalf("expected default gost, got %q", got)
	}

	t.Setenv("FORKNFT_FORWARD_ENGINE", "nftables")
	if got := resolveForwardEngineName(""); got != "nftables" {
		t.Fatalf("expected env nftables, got %q", got)
	}

	if got := resolveForwardEngineName("realm"); got != "realm" {
		t.Fatalf("expected request realm override, got %q", got)
	}
}

func TestNftablesAdapterApplyBlocksUnintendedShrink(t *testing.T) {
	dir := t.TempDir()
	statePath := filepath.Join(dir, "relay-forwards.conf")
	nftPath := filepath.Join(dir, "nftables.conf")

	if err := os.WriteFile(nftPath, []byte("define PORT_IN_1 = 30001\ndefine PORT_IN_2 = 30002\n"), 0600); err != nil {
		t.Fatalf("write nft: %v", err)
	}
	if err := os.WriteFile(statePath, []byte("old1|1.1.1.1|1001|30001\nold2|1.1.1.2|1002|30002\n"), 0600); err != nil {
		t.Fatalf("write state: %v", err)
	}

	adapter := NewNftablesAdapter(NftablesAdapterOptions{
		StateFilePath: statePath,
		NFTConfPath:   nftPath,
		ResolveIPv4: func(target string) (string, error) {
			return "203.0.113.10", nil
		},
		RunCheckAndApply: func(_ string) error { return nil },
	})

	_, err := adapter.Apply(context.Background(), ForwardApplyRequest{
		AllowShrink: false,
		Forwards: []ForwardPortRule{
			{Name: "new", Target: "a.example.com", TargetPort: 443, RelayPort: 31000},
		},
	})
	if err == nil || !strings.Contains(err.Error(), "safety check blocked") {
		t.Fatalf("expected safety check blocked error, got %v", err)
	}
}

func TestNftablesAdapterRollbackOnRunnerFailure(t *testing.T) {
	dir := t.TempDir()
	statePath := filepath.Join(dir, "relay-forwards.conf")
	nftPath := filepath.Join(dir, "nftables.conf")

	origState := "old|1.1.1.1|1001|30001\n"
	origNFT := "define PORT_IN_1 = 30001\n"
	if err := os.WriteFile(statePath, []byte(origState), 0600); err != nil {
		t.Fatalf("write state: %v", err)
	}
	if err := os.WriteFile(nftPath, []byte(origNFT), 0600); err != nil {
		t.Fatalf("write nft: %v", err)
	}

	adapter := NewNftablesAdapter(NftablesAdapterOptions{
		StateFilePath: statePath,
		NFTConfPath:   nftPath,
		ResolveIPv4: func(target string) (string, error) {
			return "203.0.113.11", nil
		},
		RunCheckAndApply: func(_ string) error { return errors.New("nft -c failed") },
	})

	_, err := adapter.Apply(context.Background(), ForwardApplyRequest{
		AllowShrink: true,
		Forwards: []ForwardPortRule{
			{Name: "new", Target: "b.example.com", TargetPort: 443, RelayPort: 30001},
		},
	})
	if err == nil {
		t.Fatalf("expected apply failure")
	}

	gotState, err := os.ReadFile(statePath)
	if err != nil {
		t.Fatalf("read state: %v", err)
	}
	if string(gotState) != origState {
		t.Fatalf("state not rolled back, got %q", string(gotState))
	}

	gotNFT, err := os.ReadFile(nftPath)
	if err != nil {
		t.Fatalf("read nft: %v", err)
	}
	if string(gotNFT) != origNFT {
		t.Fatalf("nft not rolled back, got %q", string(gotNFT))
	}
}
