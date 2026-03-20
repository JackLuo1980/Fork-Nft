# Fork-Nft Bug 清单（2026-03）

## 状态说明

- `OPEN`：待修复
- `IN_PROGRESS`：修复中
- `DONE`：已修复并回归

## BUG-20260320-01 用户名改成 `jack` 后仍显示 `admin_user`

- 状态：`DONE`
- 影响：界面用户标识与真实账号不一致，容易误判权限归属。
- 复现：
  1. 登录后通过“修改账号密码”改用户名为 `jack`。
  2. 回到转发卡片区域仍显示 `admin_user`。
- 根因：
  - 仅更新 `user.user`，未同步历史 `forward.user_name`。
- 修复：
  - 后端 `UpdateUserNameAndPassword` / `UpdateUserWithPassword` / `UpdateUserWithoutPassword` 增加同事务同步 `forward.user_name`。
- 回归：
  - `go test ./internal/store/repo -run 'TestUpdateUser(NameAndPassword|WithoutPassword)SyncsForwardUserName' -count=1`

## BUG-20260320-02 PO0 同步后入口端口/目标端口错位，导致诊断误报失败

- 状态：`DONE`
- 影响：
  - 面板中 `inPort` 与 `remoteAddr` 映射错误。
  - 诊断会探测到错误目标端口，出现“所有 TCP 连接尝试都失败”。
- 复现：
  1. 用 `scripts/sync-po0-forwards-to-panel.sh` 同步 PO0 状态文件。
  2. 发现面板转发为“入口=目标端口，目标=relay 端口”。
- 根因：
  - 脚本把 `/etc/relay-forwards.conf` 的字段 `name|host|target_port|relay_port` 错当成 `name|host|in_port|target_port`。
- 修复：
  - 更正脚本端口解析：`in_port=relay_port`，`target_port=target_port`。
- 回归：
  - `./tests/scripts/test_sync_po0_forwards.sh`
  - 线上复核：`JP-CO` 现为 `inPort=31000`、`remoteAddr=198.176.52.9:55894`，诊断返回成功。

## BUG-20260320-03 nft 模式流量统计为 0

- 状态：`DONE`
- 影响：节点实际转发有流量，但面板统计为 0B。
- 根因：
  - nft DNAT 转发绕过了服务层统计事件，默认不会产生可直接上报的 per-forward 流量。
  - 现网 nft 规则未开启 `counter`，无法读取每端口字节数。
- 修复：
  - `go-gost/x/socket/forward_engine_nftables.go`：生成规则时为 DNAT/SNAT 添加 `counter`。
  - 新增 `scripts/nft-flow-exporter.py`：按端口读取 nft counter 增量并上报 `/flow/upload`。
  - 新增 `scripts/install-nft-flow-exporter.sh`：安装 systemd timer（10s 周期）。
- 回归：
  - `go test ./socket -run 'TestNftablesAdapterRenderIncludesCounters|TestNftablesAdapterApplyBlocksUnintendedShrink' -count=1`
  - `python3 -m py_compile scripts/nft-flow-exporter.py`

## 防漏项（每次发布前执行）

1. 运行 repo/handler/socket 的相关回归测试。
2. 执行 `./tests/scripts/test_sync_po0_forwards.sh`。
3. 若使用 nft 模式，确认规则包含 `counter` 且 `nft-flow-exporter.timer` 为 active。
4. 线上抽样核对：
   - 转发映射（`inPort` / `remoteAddr`）
   - 诊断结果
   - 流量增长（`forward.list` 的 `inFlow/outFlow`）。
