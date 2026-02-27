package repo

import (
	"errors"
	"testing"

	gsqlite "github.com/glebarez/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func TestMigrateSchemaRunsPostgresIDRepairEvenAtCurrentVersion(t *testing.T) {
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

	if err := db.Exec(`CREATE TABLE schema_version (version INTEGER NOT NULL DEFAULT 0)`).Error; err != nil {
		t.Fatalf("create schema_version: %v", err)
	}
	if err := db.Exec(`INSERT INTO schema_version(version) VALUES(?)`, currentSchemaVersion).Error; err != nil {
		t.Fatalf("seed schema_version: %v", err)
	}

	called := 0
	original := ensurePostgresIDDefaultsFn
	ensurePostgresIDDefaultsFn = func(db *gorm.DB) error {
		called++
		return nil
	}
	t.Cleanup(func() {
		ensurePostgresIDDefaultsFn = original
	})

	if err := migrateSchema(db); err != nil {
		t.Fatalf("migrateSchema: %v", err)
	}
	if called != 1 {
		t.Fatalf("expected postgres id repair to run once, got %d", called)
	}
}

func TestMigrateSchemaReturnsPostgresIDRepairError(t *testing.T) {
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

	if err := db.Exec(`CREATE TABLE schema_version (version INTEGER NOT NULL DEFAULT 0)`).Error; err != nil {
		t.Fatalf("create schema_version: %v", err)
	}
	if err := db.Exec(`INSERT INTO schema_version(version) VALUES(?)`, currentSchemaVersion).Error; err != nil {
		t.Fatalf("seed schema_version: %v", err)
	}

	wantErr := errors.New("repair failed")
	original := ensurePostgresIDDefaultsFn
	ensurePostgresIDDefaultsFn = func(db *gorm.DB) error {
		return wantErr
	}
	t.Cleanup(func() {
		ensurePostgresIDDefaultsFn = original
	})

	err = migrateSchema(db)
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected error %v, got %v", wantErr, err)
	}
}

func TestMigrateSchemaRunsViteConfigValueMigrationForLegacySchema(t *testing.T) {
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

	if err := db.Exec(`CREATE TABLE schema_version (version INTEGER NOT NULL DEFAULT 0)`).Error; err != nil {
		t.Fatalf("create schema_version: %v", err)
	}
	if err := db.Exec(`INSERT INTO schema_version(version) VALUES(?)`, 2).Error; err != nil {
		t.Fatalf("seed schema_version: %v", err)
	}

	originalIDRepair := ensurePostgresIDDefaultsFn
	ensurePostgresIDDefaultsFn = func(db *gorm.DB) error {
		return nil
	}
	t.Cleanup(func() {
		ensurePostgresIDDefaultsFn = originalIDRepair
	})

	called := 0
	originalMigrate := migrateViteConfigValueColumnTypeFn
	migrateViteConfigValueColumnTypeFn = func(db *gorm.DB) error {
		called++
		return nil
	}
	t.Cleanup(func() {
		migrateViteConfigValueColumnTypeFn = originalMigrate
	})

	if err := migrateSchema(db); err != nil {
		t.Fatalf("migrateSchema: %v", err)
	}

	if called != 1 {
		t.Fatalf("expected vite_config migration to run once, got %d", called)
	}
}

func TestMigrateSchemaReturnsViteConfigMigrationError(t *testing.T) {
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

	if err := db.Exec(`CREATE TABLE schema_version (version INTEGER NOT NULL DEFAULT 0)`).Error; err != nil {
		t.Fatalf("create schema_version: %v", err)
	}
	if err := db.Exec(`INSERT INTO schema_version(version) VALUES(?)`, 2).Error; err != nil {
		t.Fatalf("seed schema_version: %v", err)
	}

	originalIDRepair := ensurePostgresIDDefaultsFn
	ensurePostgresIDDefaultsFn = func(db *gorm.DB) error {
		return nil
	}
	t.Cleanup(func() {
		ensurePostgresIDDefaultsFn = originalIDRepair
	})

	wantErr := errors.New("vite config migration failed")
	originalMigrate := migrateViteConfigValueColumnTypeFn
	migrateViteConfigValueColumnTypeFn = func(db *gorm.DB) error {
		return wantErr
	}
	t.Cleanup(func() {
		migrateViteConfigValueColumnTypeFn = originalMigrate
	})

	err = migrateSchema(db)
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected error %v, got %v", wantErr, err)
	}
}
