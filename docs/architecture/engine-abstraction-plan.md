# Engine Abstraction Plan (nftables / realm)

## Goal
Build a generic forwarding platform based on FLVX with pluggable forwarding engines:
- `realm`
- `nftables`
- `auto` (policy-selected)

## Scope
- Keep FLVX panel UX/API lifecycle for node, tunnel, forward management.
- Replace node data-plane execution logic with an engine adapter interface.
- Keep one-click install workflow for panel and node.

## Core Design
1. Control plane unchanged:
- `go-backend` remains source of truth for users/tunnels/forwards.

2. Node execution plane adds engine abstraction:
- Define engine adapter interface (`Apply`, `Delete`, `List`, `HealthCheck`, `DryRun`).
- Implement `realm` adapter and `nftables` adapter.
- Add `auto` engine selector by protocol + policy.

3. Safe rollout mechanism:
- Generated config in staging path.
- Syntax check before activation.
- Atomic apply and rollback on failure.

4. Safety protections:
- Rule shrink protection (block accidental mass delete unless force flag).
- State snapshots before every mutating operation.
- Engine operation audit log.

## Proposed API/Model additions
- Forward model extension:
  - `engine`: enum(`realm`,`nftables`,`auto`)
  - `engineOptions`: json
- Node capability field:
  - supported engines and runtime versions.

## Migration Path
1. Import existing forwards as `engine=auto`.
2. Keep current traffic running.
3. Migrate node-by-node with canary strategy.
4. Enable per-forward engine override from panel.
