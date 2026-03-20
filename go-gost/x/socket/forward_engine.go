package socket

import (
	"context"
	"fmt"
	"os"
	"strings"
	"sync"
)

type ForwardPortRule struct {
	Name       string `json:"name"`
	Target     string `json:"target"`
	TargetPort int    `json:"targetPort"`
	RelayPort  int    `json:"relayPort"`
	Protocol   string `json:"protocol,omitempty"`
}

type ForwardApplyRequest struct {
	AllowShrink bool              `json:"allowShrink"`
	Forwards    []ForwardPortRule `json:"forwards"`
}

type ForwardApplyResult struct {
	Engine       string `json:"engine"`
	RulesApplied int    `json:"rulesApplied"`
	Message      string `json:"message,omitempty"`
}

type ForwardEngine interface {
	Name() string
	DryRun(ctx context.Context, req ForwardApplyRequest) (*ForwardApplyResult, error)
	Apply(ctx context.Context, req ForwardApplyRequest) (*ForwardApplyResult, error)
}

type ForwardEngineManager struct {
	mu      sync.RWMutex
	engines map[string]ForwardEngine
}

func NewForwardEngineManager() *ForwardEngineManager {
	return &ForwardEngineManager{
		engines: make(map[string]ForwardEngine),
	}
}

func (m *ForwardEngineManager) Register(engine ForwardEngine) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.engines[strings.ToLower(strings.TrimSpace(engine.Name()))] = engine
}

func (m *ForwardEngineManager) Get(name string) (ForwardEngine, bool) {
	key := strings.ToLower(strings.TrimSpace(name))
	m.mu.RLock()
	defer m.mu.RUnlock()
	engine, ok := m.engines[key]
	return engine, ok
}

func (m *ForwardEngineManager) DryRun(ctx context.Context, engineName string, req ForwardApplyRequest) (*ForwardApplyResult, error) {
	if strings.EqualFold(engineName, "auto") {
		engineName = selectAutoEngineName(req.Forwards)
	}
	if !isForwardEngineAllowed(engineName) {
		return nil, fmt.Errorf("forward engine blocked by node policy: %s", engineName)
	}
	engine, ok := m.Get(engineName)
	if !ok {
		return nil, fmt.Errorf("forward engine not found: %s", engineName)
	}
	return engine.DryRun(ctx, req)
}

func (m *ForwardEngineManager) Apply(ctx context.Context, engineName string, req ForwardApplyRequest) (*ForwardApplyResult, error) {
	if strings.EqualFold(engineName, "auto") {
		engineName = selectAutoEngineName(req.Forwards)
	}
	if !isForwardEngineAllowed(engineName) {
		return nil, fmt.Errorf("forward engine blocked by node policy: %s", engineName)
	}
	engine, ok := m.Get(engineName)
	if !ok {
		return nil, fmt.Errorf("forward engine not found: %s", engineName)
	}
	return engine.Apply(ctx, req)
}

var (
	defaultForwardEngineManagerOnce sync.Once
	defaultForwardEngineManagerInst *ForwardEngineManager
)

func defaultForwardEngineManager() *ForwardEngineManager {
	defaultForwardEngineManagerOnce.Do(func() {
		m := NewForwardEngineManager()
		m.Register(NewNftablesAdapter(NftablesAdapterOptions{}))
		m.Register(NewRealmAdapter(RealmAdapterOptions{}))
		defaultForwardEngineManagerInst = m
	})
	return defaultForwardEngineManagerInst
}

func resolveForwardEngineName(requestEngine string) string {
	req := strings.ToLower(strings.TrimSpace(requestEngine))
	if req != "" {
		return req
	}
	env := strings.ToLower(strings.TrimSpace(os.Getenv("FORKNFT_FORWARD_ENGINE")))
	if env != "" {
		return env
	}
	return "auto"
}

func selectAutoEngineName(forwards []ForwardPortRule) string {
	for _, f := range forwards {
		if strings.EqualFold(strings.TrimSpace(f.Protocol), "udp") {
			return "nftables"
		}
	}
	return "realm"
}

func isForwardEngineAllowed(engineName string) bool {
	engineName = strings.ToLower(strings.TrimSpace(engineName))
	if engineName == "" {
		return false
	}
	allowedRaw := strings.TrimSpace(os.Getenv("FORKNFT_ALLOWED_ENGINES"))
	if allowedRaw == "" {
		return true
	}
	for _, part := range strings.Split(allowedRaw, ",") {
		if strings.ToLower(strings.TrimSpace(part)) == engineName {
			return true
		}
	}
	return false
}
