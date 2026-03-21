package repo

import (
	"testing"

	"go-backend/internal/store/model"
)

func TestCreateForwardPersistsForwardType(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	forwardID, err := r.CreateForwardTx(
		1, "u1", "fwd-port", 1, "203.0.113.10:443",
		"fifo", "auto",
		0, 1, []int64{11}, 18080, "", nil, "port_forward", "tcp",
	)
	if err != nil {
		t.Fatalf("create forward: %v", err)
	}

	created, err := r.GetForwardRecord(forwardID)
	if err != nil {
		t.Fatalf("get created forward: %v", err)
	}
	if created == nil {
		t.Fatal("expected created forward")
	}
	if created.ForwardType != "port_forward" {
		t.Fatalf("expected created forwardType port_forward, got %q", created.ForwardType)
	}
	if created.Protocols != "tcp" {
		t.Fatalf("expected created protocols tcp, got %q", created.Protocols)
	}

	tunnelForwardID, err := r.CreateForwardTx(
		1, "u1", "fwd-tunnel", 1, "203.0.113.10:443",
		"fifo", "auto",
		0, 2, []int64{11}, 18081, "", nil, "tunnel_forward", "udp",
	)
	if err != nil {
		t.Fatalf("create tunnel forward: %v", err)
	}

	tunnelForward, err := r.GetForwardRecord(tunnelForwardID)
	if err != nil {
		t.Fatalf("get tunnel forward: %v", err)
	}
	if tunnelForward == nil {
		t.Fatal("expected tunnel forward")
	}
	if tunnelForward.ForwardType != "tunnel_forward" {
		t.Fatalf("expected created forwardType tunnel_forward, got %q", tunnelForward.ForwardType)
	}
	if tunnelForward.Protocols != "udp" {
		t.Fatalf("expected created protocols udp, got %q", tunnelForward.Protocols)
	}

	bothProtocolID, err := r.CreateForwardTx(
		1, "u1", "fwd-both", 1, "203.0.113.10:443",
		"fifo", "auto",
		0, 3, []int64{11}, 18082, "", nil, "port_forward", "both",
	)
	if err != nil {
		t.Fatalf("create both protocol forward: %v", err)
	}

	bothProtocolForward, err := r.GetForwardRecord(bothProtocolID)
	if err != nil {
		t.Fatalf("get both protocol forward: %v", err)
	}
	if bothProtocolForward == nil {
		t.Fatal("expected both protocol forward")
	}
	if bothProtocolForward.Protocols != "both" {
		t.Fatalf("expected created protocols both, got %q", bothProtocolForward.Protocols)
	}
}

func TestUpdateForwardPersistsForwardType(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	now := int64(0)
	forwardID, err := r.CreateForwardTx(
		1, "u1", "fwd-1", 1, "203.0.113.10:443",
		"fifo", "auto",
		now, 1, []int64{11}, 18080, "", nil, "port_forward", "tcp",
	)
	if err != nil {
		t.Fatalf("create forward: %v", err)
	}

	if err := r.UpdateForward(
		forwardID, "fwd-1-updated", 1, "203.0.113.11:443",
		"round", "nftables",
		now, nil, "tunnel_forward", "udp",
	); err != nil {
		t.Fatalf("update forward: %v", err)
	}

	updated, err := r.GetForwardRecord(forwardID)
	if err != nil {
		t.Fatalf("get updated forward: %v", err)
	}
	if updated == nil {
		t.Fatal("expected updated forward")
	}
	if updated.ForwardType != "tunnel_forward" {
		t.Fatalf("expected updated forwardType tunnel_forward, got %q", updated.ForwardType)
	}
	if updated.Protocols != "udp" {
		t.Fatalf("expected updated protocols udp, got %q", updated.Protocols)
	}

	if err := r.UpdateForward(
		forwardID, "fwd-1-updated-2", 1, "203.0.113.12:443",
		"fifo", "realm",
		now, nil, "port_forward", "both",
	); err != nil {
		t.Fatalf("update forward again: %v", err)
	}

	updatedAgain, err := r.GetForwardRecord(forwardID)
	if err != nil {
		t.Fatalf("get updated forward again: %v", err)
	}
	if updatedAgain == nil {
		t.Fatal("expected updated forward again")
	}
	if updatedAgain.ForwardType != "port_forward" {
		t.Fatalf("expected updated forwardType port_forward, got %q", updatedAgain.ForwardType)
	}
	if updatedAgain.Protocols != "both" {
		t.Fatalf("expected updated protocols both, got %q", updatedAgain.Protocols)
	}
}

func TestUpdateForwardPreservesForwardTypeWhenEmpty(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	now := int64(0)
	forwardID, err := r.CreateForwardTx(
		1, "u1", "fwd-1", 1, "203.0.113.10:443",
		"fifo", "auto",
		now, 1, []int64{11}, 18080, "", nil, "tunnel_forward", "udp",
	)
	if err != nil {
		t.Fatalf("create forward: %v", err)
	}

	created, err := r.GetForwardRecord(forwardID)
	if err != nil {
		t.Fatalf("get created forward: %v", err)
	}
	if created == nil {
		t.Fatal("expected created forward")
	}
	originalForwardType := created.ForwardType
	originalProtocols := created.Protocols

	if err := r.UpdateForward(
		forwardID, "fwd-1-updated", 1, "203.0.113.11:443",
		"round", "nftables",
		now, nil, "", "",
	); err != nil {
		t.Fatalf("update forward: %v", err)
	}

	updated, err := r.GetForwardRecord(forwardID)
	if err != nil {
		t.Fatalf("get updated forward: %v", err)
	}
	if updated == nil {
		t.Fatal("expected updated forward")
	}
	if updated.ForwardType != originalForwardType {
		t.Fatalf("expected forwardType to be preserved, got %q", updated.ForwardType)
	}
	if updated.Protocols != originalProtocols {
		t.Fatalf("expected protocols to be preserved, got %q", updated.Protocols)
	}
}

func TestForwardPortHasProtocol(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	forwardID, err := r.CreateForwardTx(
		1, "u1", "fwd-1", 1, "203.0.113.10:443",
		"fifo", "auto",
		0, 1, []int64{11}, 18080, "", nil, "port_forward", "both",
	)
	if err != nil {
		t.Fatalf("create forward: %v", err)
	}

	var forwardPorts []model.ForwardPort
	if err := r.db.Where("forward_id = ?", forwardID).Find(&forwardPorts).Error; err != nil {
		t.Fatalf("get forward ports: %v", err)
	}

	if len(forwardPorts) != 1 {
		t.Fatalf("expected 1 forward port, got %d", len(forwardPorts))
	}

	if forwardPorts[0].Protocol != "both" {
		t.Fatalf("expected forward port protocol both, got %q", forwardPorts[0].Protocol)
	}
}

func TestListForwardsReturnsForwardType(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	_, _ = r.CreateForwardTx(
		1, "u1", "fwd-port", 1, "203.0.113.10:443",
		"fifo", "auto",
		0, 1, []int64{11}, 18080, "", nil, "port_forward", "tcp",
	)
	_, _ = r.CreateForwardTx(
		1, "u1", "fwd-tunnel", 1, "203.0.113.10:444",
		"fifo", "auto",
		0, 2, []int64{11}, 18081, "", nil, "tunnel_forward", "udp",
	)

	forwards, err := r.ListForwards()
	if err != nil {
		t.Fatalf("list forwards: %v", err)
	}

	if len(forwards) != 2 {
		t.Fatalf("expected 2 forwards, got %d", len(forwards))
	}

	portForwardFound := false
	tunnelForwardFound := false
	for _, fwd := range forwards {
		if fwd["forwardType"] == "port_forward" {
			portForwardFound = true
		}
		if fwd["forwardType"] == "tunnel_forward" {
			tunnelForwardFound = true
		}
	}

	if !portForwardFound {
		t.Fatal("expected to find port_forward type")
	}
	if !tunnelForwardFound {
		t.Fatal("expected to find tunnel_forward type")
	}
}
