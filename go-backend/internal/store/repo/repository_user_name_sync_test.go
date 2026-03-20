package repo

import (
	"testing"
	"time"

	"go-backend/internal/store/model"
)

func TestUpdateUserNameAndPasswordSyncsForwardUserName(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	now := time.Now().UnixMilli()
	user := model.User{
		ID:          1001,
		User:        "admin_user",
		Pwd:         "old-hash",
		RoleID:      0,
		ExpTime:     now + 86400000,
		Flow:        0,
		CreatedTime: now,
		Status:      1,
	}
	if err := r.db.Create(&user).Error; err != nil {
		t.Fatalf("insert user: %v", err)
	}

	forward := model.Forward{
		UserID:      user.ID,
		UserName:    user.User,
		Name:        "fwd-1",
		TunnelID:    1,
		RemoteAddr:  "203.0.113.1:443",
		Strategy:    "fifo",
		Engine:      "nftables",
		CreatedTime: now,
		UpdatedTime: now,
		Status:      1,
		Inx:         1,
	}
	if err := r.db.Create(&forward).Error; err != nil {
		t.Fatalf("insert forward: %v", err)
	}

	if err := r.UpdateUserNameAndPassword(user.ID, "jack", "new-hash", now+1); err != nil {
		t.Fatalf("update user name and password: %v", err)
	}

	var got model.Forward
	if err := r.db.First(&got, forward.ID).Error; err != nil {
		t.Fatalf("query forward: %v", err)
	}
	if got.UserName != "jack" {
		t.Fatalf("expected forward.user_name to be jack, got %q", got.UserName)
	}
}

func TestUpdateUserWithoutPasswordSyncsForwardUserName(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	now := time.Now().UnixMilli()
	user := model.User{
		ID:            1002,
		User:          "legacy_name",
		Pwd:           "hash",
		RoleID:        1,
		ExpTime:       now + 86400000,
		Flow:          1024,
		FlowResetTime: 1,
		Num:           3,
		CreatedTime:   now,
		Status:        1,
	}
	if err := r.db.Create(&user).Error; err != nil {
		t.Fatalf("insert user: %v", err)
	}

	forward := model.Forward{
		UserID:      user.ID,
		UserName:    user.User,
		Name:        "fwd-2",
		TunnelID:    2,
		RemoteAddr:  "203.0.113.2:443",
		Strategy:    "fifo",
		Engine:      "nftables",
		CreatedTime: now,
		UpdatedTime: now,
		Status:      1,
		Inx:         1,
	}
	if err := r.db.Create(&forward).Error; err != nil {
		t.Fatalf("insert forward: %v", err)
	}

	if err := r.UpdateUserWithoutPassword(user.ID, "jack", user.Flow, user.Num, user.ExpTime, user.FlowResetTime, user.Status, now+1); err != nil {
		t.Fatalf("update user without password: %v", err)
	}

	var got model.Forward
	if err := r.db.First(&got, forward.ID).Error; err != nil {
		t.Fatalf("query forward: %v", err)
	}
	if got.UserName != "jack" {
		t.Fatalf("expected forward.user_name to be jack, got %q", got.UserName)
	}
}
