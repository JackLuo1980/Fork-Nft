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
	engine, ok := m.Get(engineName)
	if !ok {
		return nil, fmt.Errorf("forward engine not found: %s", engineName)
	}
	return engine.DryRun(ctx, req)
}

func (m *ForwardEngineManager) Apply(ctx context.Context, engineName string, req ForwardApplyRequest) (*ForwardApplyResult, error) {
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
		m.Register(&realmForwardAdapter{})
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
	return "gost"
}

type realmForwardAdapter struct{}

func (r *realmForwardAdapter) Name() string { return "realm" }

func (r *realmForwardAdapter) DryRun(_ context.Context, _ ForwardApplyRequest) (*ForwardApplyResult, error) {
	return nil, fmt.Errorf("realm engine is not implemented yet")
}

func (r *realmForwardAdapter) Apply(_ context.Context, _ ForwardApplyRequest) (*ForwardApplyResult, error) {
	return nil, fmt.Errorf("realm engine is not implemented yet")
}
