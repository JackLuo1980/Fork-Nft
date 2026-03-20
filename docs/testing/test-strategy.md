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
