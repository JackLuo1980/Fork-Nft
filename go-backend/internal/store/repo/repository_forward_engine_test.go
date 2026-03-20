package repo

import (
	"testing"
	"time"

	gsqlite "github.com/glebarez/sqlite"
	"go-backend/internal/store/model"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func TestCreateAndUpdateForwardPersistsEngine(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	now := time.Now().UnixMilli()
	forwardID, err := r.CreateForwardTx(
		1, "u1", "fwd-1", 1, "203.0.113.10:443",
		"fifo", "realm",
		now, 1, []int64{11}, 18080, "", nil,
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
	if created.Engine != "realm" {
		t.Fatalf("expected created engine realm, got %q", created.Engine)
	}

	if err := r.UpdateForward(
		forwardID, "fwd-1-updated", 1, "203.0.113.11:443",
		"round", "nftables",
		now+1, nil,
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
	if updated.Engine != "nftables" {
		t.Fatalf("expected updated engine nftables, got %q", updated.Engine)
	}

	r.RollbackForwardFields(
		forwardID, 1, "u1", "fwd-1", 1, "203.0.113.10:443",
		"fifo", "realm",
		1, nil, now+2,
	)
	rolledBack, err := r.GetForwardRecord(forwardID)
	if err != nil {
		t.Fatalf("get rolled back forward: %v", err)
	}
	if rolledBack == nil {
		t.Fatal("expected rolled back forward")
	}
	if rolledBack.Engine != "realm" {
		t.Fatalf("expected rollback engine realm, got %q", rolledBack.Engine)
	}
}

func TestListForwardsNormalizesEmptyEngineToGost(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	now := time.Now().UnixMilli()
	row := model.Forward{
		UserID:      1,
		UserName:    "u1",
		Name:        "fwd-empty-engine",
		TunnelID:    1,
		RemoteAddr:  "198.51.100.1:10001",
		Strategy:    "fifo",
		Engine:      " ",
		CreatedTime: now,
		UpdatedTime: now,
		Status:      1,
		Inx:         1,
	}
	if err := r.db.Create(&row).Error; err != nil {
		t.Fatalf("insert forward: %v", err)
	}

	items, err := r.ListForwards()
	if err != nil {
		t.Fatalf("list forwards: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("expected 1 forward, got %d", len(items))
	}

	engine, _ := items[0]["engine"].(string)
	if engine != "gost" {
		t.Fatalf("expected normalized engine gost, got %q", engine)
	}
}

func TestImportForwardsDefaultsEngineToGost(t *testing.T) {
	r, err := Open(":memory:")
	if err != nil {
		t.Fatalf("open repo: %v", err)
	}
	defer r.Close()

	now := time.Now().UnixMilli()
	forwards := []model.ForwardBackup{
		{
			ID:          101,
			UserID:      7,
			UserName:    "u7",
			Name:        "fwd-import",
			TunnelID:    8,
			RemoteAddr:  "203.0.113.22:443",
			Strategy:    "fifo",
			Engine:      "",
			InFlow:      0,
			OutFlow:     0,
			CreatedTime: now,
			UpdatedTime: now,
			Status:      1,
			Inx:         1,
		},
	}

	if err := r.db.Transaction(func(tx *gorm.DB) error {
		_, err := importForwards(tx, forwards, now)
		return err
	}); err != nil {
		t.Fatalf("import forwards: %v", err)
	}

	var saved model.Forward
	if err := r.db.Where("id = ?", 101).First(&saved).Error; err != nil {
		t.Fatalf("query imported forward: %v", err)
	}
	if saved.Engine != "gost" {
		t.Fatalf("expected imported engine gost, got %q", saved.Engine)
	}
}

func TestMigrateSchemaNormalizesEmptyForwardEngine(t *testing.T) {
	db, err := gorm.Open(gsqlite.Open(":memory:"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	t.Cleanup(func() {
		sqlDB, _ := db.DB()
		if sqlDB != nil {
			_ = sqlDB.Close()
		}
	})

	if err := db.AutoMigrate(&model.SchemaVersion{}, &model.Forward{}); err != nil {
		t.Fatalf("auto migrate: %v", err)
	}
	setSchemaVersion(db, 6)

	now := time.Now().UnixMilli()
	forward := model.Forward{
		UserID:      1,
		UserName:    "u1",
		Name:        "fwd-migrate",
		TunnelID:    1,
		RemoteAddr:  "203.0.113.1:443",
		Strategy:    "fifo",
		Engine:      " ",
		CreatedTime: now,
		UpdatedTime: now,
		Status:      1,
		Inx:         1,
	}
	if err := db.Create(&forward).Error; err != nil {
		t.Fatalf("insert forward: %v", err)
	}

	if err := migrateSchema(db); err != nil {
		t.Fatalf("migrateSchema: %v", err)
	}

	var out model.Forward
	if err := db.Where("id = ?", forward.ID).First(&out).Error; err != nil {
		t.Fatalf("query forward: %v", err)
	}
	if out.Engine != "gost" {
		t.Fatalf("expected migrated engine gost, got %q", out.Engine)
	}
}
