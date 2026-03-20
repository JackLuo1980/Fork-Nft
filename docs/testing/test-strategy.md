# Test Strategy for Engine Migration

## Quality Gates
No production rollout unless all gates pass.

## Test Layers
1. Unit tests
- Engine adapters: render/validate/apply/delete behavior.
- Selector policy: `auto` routing decisions.
- Safety guards: shrink protection, backup creation.

2. Integration tests
- Backend API -> node command dispatch -> engine apply loop.
- Forward create/update/delete with both engines.
- Rollback path when apply fails.

3. End-to-end tests
- Deploy panel + node in Docker compose lab.
- Create forwards from API/UI, verify connectivity.
- Restart/reload scenarios keep state consistent.

4. Regression tests
- Existing FLVX behaviors remain available (auth, node lifecycle, forward lifecycle).
- Data migration from old records.

5. Reliability tests
- Repeated apply/delete cycles.
- Concurrent operations from multiple users.
- Restart chaos tests for node service.

6. Performance smoke tests
- Baseline throughput and latency under sample load for both engines.

## Release Criteria
- All automated tests green in CI.
- Canary node runs 72h without critical incidents.
- Rollback tested and documented.

## Remote Engine E2E Command
Use this script to validate the full path on a remote dev server:
- Panel forward engine selection
- Backend persistence
- Runtime `UpdateService` payload including `forwarder.engine`

Command:
```bash
scripts/e2e-engine-check.sh --host <server_ip> --password '<root_password>'
```

Notes:
- Default behavior restores backend image to base compose config after check.
- Use `--keep-fork-backend` to keep backend on fork test image.

## PO0 Sync Script Tests
Use these checks for PO0 incremental sync workflow:

1. Local script unit test
```bash
./tests/scripts/test_sync_po0_forwards.sh
```

2. Dry-run against real PO0 state file
```bash
bash scripts/sync-po0-forwards-to-panel.sh \
  --po0-host <po0_ip> \
  --po0-password '<po0_root_password>' \
  --panel-base 'http://<panel_ip>:6365' \
  --dry-run
```

3. Live sync and nftables lock verification
```bash
bash scripts/sync-po0-forwards-to-panel.sh \
  --po0-host <po0_ip> \
  --po0-password '<po0_root_password>' \
  --panel-base 'http://<panel_ip>:6365'
```

Acceptance:
- synced forwards match `/etc/relay-forwards.conf`
- every synced forward reports `engine=nftables`
