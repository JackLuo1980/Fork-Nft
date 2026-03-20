# One-Click Deployment Roadmap

## Target UX
- Panel:
  - one command install/update/uninstall
- Node:
  - one command install/update/uninstall
  - selectable default engine (`realm`/`nftables`/`auto`)

## Deliverables
1. Panel installer parity with FLVX scripts.
2. Node installer with engine runtime checks.
3. Health command with machine-readable output.
4. Backup and restore command set.
5. Migration command from FLVX/gost-compatible state.

## Security Baseline
- Enforce HTTPS for panel endpoints.
- Token/secret validation for node registration.
- Audit logs for all mutating operations.
