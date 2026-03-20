# Engine Adapter Bootstrap Plan

- [x] Add forward engine interface and manager under go-gost/x/socket
- [x] Add nftables adapter with dry-run/apply/list/delete primitives
- [x] Add safety guard: block unintended shrink unless allowShrink
- [x] Add rollback behavior when apply validation fails
- [x] Add websocket command: ApplyPortForwards
- [x] Add unit tests for adapter and manager
- [x] Run go test for modified packages
