package handler

import "testing"

func TestShouldRequirePasswordChange(t *testing.T) {
	if !shouldRequirePasswordChange("admin_user", "anything") {
		t.Fatalf("default admin username should require password change")
	}
	if !shouldRequirePasswordChange("someone", "admin_user") {
		t.Fatalf("default admin password should require password change")
	}
	if shouldRequirePasswordChange("someone", "secret123") {
		t.Fatalf("non-default credentials should not require password change")
	}
}
