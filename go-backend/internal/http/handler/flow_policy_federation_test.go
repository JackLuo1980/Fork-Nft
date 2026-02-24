package handler

import (
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"go-backend/internal/store/repo"
)

func TestProcessFlowItemTracksPeerShareFlowAndEnforcesLimit(t *testing.T) {
	r, err := repo.Open(filepath.Join(t.TempDir(), "panel.db"))
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	now := time.Now().UnixMilli()
	if err := r.CreatePeerShare(&repo.PeerShare{
		Name:           "flow-share",
		NodeID:         1,
		Token:          "flow-share-token",
		MaxBandwidth:   3000,
		CurrentFlow:    1000,
		PortRangeStart: 32000,
		PortRangeEnd:   32010,
		IsActive:       1,
		CreatedTime:    now,
		UpdatedTime:    now,
	}); err != nil {
		t.Fatalf("create peer share: %v", err)
	}
	share, err := r.GetPeerShareByToken("flow-share-token")
	if err != nil || share == nil {
		t.Fatalf("load peer share: %v", err)
	}

	if err := r.DB().Exec(`
		INSERT INTO peer_share_runtime(id, share_id, node_id, reservation_id, resource_key, binding_id, role, chain_name, service_name, protocol, strategy, port, target, applied, status, created_time, updated_time)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, 17, share.ID, share.NodeID, "res-17", "rk-17", "17", "exit", "", "fed_svc_17", "tls", "round", 32001, "", 1, 1, now, now).Error; err != nil {
		t.Fatalf("insert peer_share_runtime: %v", err)
	}

	h := &Handler{repo: r}
	h.processFlowItem(flowItem{N: "fed_svc_17", U: 1200, D: 900})

	updatedShare, err := r.GetPeerShare(share.ID)
	if err != nil || updatedShare == nil {
		t.Fatalf("reload share: %v", err)
	}
	if updatedShare.CurrentFlow != 3100 {
		t.Fatalf("expected current_flow=3100, got %d", updatedShare.CurrentFlow)
	}

	runtime, err := r.GetPeerShareRuntimeByID(17)
	if err != nil || runtime == nil {
		t.Fatalf("reload runtime: %v", err)
	}
	if runtime.Status != 0 {
		t.Fatalf("expected runtime status=0 after limit enforcement, got %d", runtime.Status)
	}
}

func TestProcessFlowItemTracksPeerShareFlowForFederationPortForward(t *testing.T) {
	r, err := repo.Open(filepath.Join(t.TempDir(), "panel-forward.db"))
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	now := time.Now().UnixMilli()
	if err := r.CreatePeerShare(&repo.PeerShare{
		Name:           "forward-share",
		NodeID:         1,
		Token:          "forward-share-token",
		MaxBandwidth:   0,
		CurrentFlow:    0,
		PortRangeStart: 30000,
		PortRangeEnd:   30010,
		IsActive:       1,
		CreatedTime:    now,
		UpdatedTime:    now,
	}); err != nil {
		t.Fatalf("create peer share: %v", err)
	}
	share, err := r.GetPeerShareByToken("forward-share-token")
	if err != nil || share == nil {
		t.Fatalf("load peer share: %v", err)
	}

	if err := r.DB().Exec(`
		INSERT INTO user(id, user, pwd, role_id, exp_time, flow, in_flow, out_flow, flow_reset_time, num, created_time, updated_time, status)
		VALUES(2, 'u2', 'x', 1, ?, 99999, 0, 0, 1, 1, ?, ?, 1)
	`, now+24*60*60*1000, now, now).Error; err != nil {
		t.Fatalf("insert user: %v", err)
	}

	tunnelName := "Share-" + strconv.FormatInt(share.ID, 10) + "-Port-30001"
	if err := r.DB().Exec(`
		INSERT INTO tunnel(id, name, traffic_ratio, type, protocol, flow, created_time, updated_time, status, in_ip, inx)
		VALUES(1, ?, 1.0, 1, 'tls', 1, ?, ?, 1, NULL, 0)
	`, tunnelName, now, now).Error; err != nil {
		t.Fatalf("insert tunnel: %v", err)
	}

	if err := r.DB().Exec(`
		INSERT INTO user_tunnel(id, user_id, tunnel_id, speed_id, num, flow, in_flow, out_flow, flow_reset_time, exp_time, status)
		VALUES(10, 2, 1, NULL, 1, 99999, 0, 0, 1, ?, 1)
	`, now+24*60*60*1000).Error; err != nil {
		t.Fatalf("insert user_tunnel: %v", err)
	}

	if err := r.DB().Exec(`
		INSERT INTO forward(id, user_id, user_name, name, tunnel_id, remote_addr, strategy, in_flow, out_flow, created_time, updated_time, status, inx)
		VALUES(20, 2, 'u2', 'f20', 1, '1.1.1.1:443', 'fifo', 0, 0, ?, ?, 1, 0)
	`, now, now).Error; err != nil {
		t.Fatalf("insert forward: %v", err)
	}

	h := &Handler{repo: r}
	h.processFlowItem(flowItem{N: "20_2_10", U: 120, D: 80})

	updatedShare, err := r.GetPeerShare(share.ID)
	if err != nil || updatedShare == nil {
		t.Fatalf("reload share: %v", err)
	}
	if updatedShare.CurrentFlow != 200 {
		t.Fatalf("expected current_flow=200, got %d", updatedShare.CurrentFlow)
	}
}
