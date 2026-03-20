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
