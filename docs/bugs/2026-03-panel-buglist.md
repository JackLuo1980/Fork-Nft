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

## BUG-20260320-04 nft 流量统计不准确（缓存失效）

- 状态：`DONE`
- 发现时间：2026-03-20 13:40
- 影响：
  - 面板显示流量（100 KB）与实际 nft counter（218 KB）不一致。
  - 用户反馈"红色框的部分和实际使用的流量对不上"。
- 根因：
  - nft 规则重置后 counter 归零，但缓存文件保留旧值。
  - delta = current - previous ≤ 0，流量导出器认为"无新流量"。
- 数据对比：
  | 端口 | 转发 | nft counter | 数据库 inFlow | 差异 |
  |------|------|-------------|---------------|------|
  | 31000 | JP-CO | 137,541 B | 62,396 B | 75,145 B |
  | 31001 | HK-Jinx | 85,019 B | 27,659 B | 57,360 B |
  | 12071 | Boil HKT | 512 B | 512 B | 0 B |
- 修复：
  - 删除缓存文件：`rm -f /var/lib/fork-nft/nft-flow-exporter.json`
  - 缓存自动重新初始化为当前 nft counter 值
  - 流量导出器恢复正常上报
- 预防措施：
  - 重新部署 nft 规则或重启节点时，必须删除缓存文件
  - 添加到 `install-nft-flow-exporter.sh` 的部署检查清单
- 回归：
  - 检查缓存值是否 ≤ 当前 nft counter
  - 检查日志中 `uploaded X flow items` 是否正常

## BUG-20260320-05 新建转发默认落到 `gost`，不符合“避免误用 gost”要求

- 状态：`DONE`
- 影响：
  - 新建时若未显式改引擎，配置会默认走 `gost`。
  - 在禁止 `gost` 的服务器上可能导致下发失败或运行偏离预期。
- 根因：
  - 前后端的默认引擎归一化逻辑均以 `gost` 为默认值。
- 修复：
  - 前端创建/编辑默认值改为 `auto`，并在表单描述中明确提示“节点禁止 gost 时不要选 gost”。
  - 后端 `normalizeForwardEngine` 默认值与非法值回退改为 `auto`。
  - 节点侧 `resolveForwardEngineName` 默认值改为 `auto`。
- 回归：
  - `go test ./internal/http/handler -run 'TestNormalizeForwardEngine' -count=1`
  - `go test ./socket -run 'TestResolveForwardEngineName' -count=1`

## BUG-20260320-06 需要节点级引擎限制，防止某台机误下发 `gost`

- 状态：`DONE`
- 影响：
  - 仅靠每条转发人工选择容易误操作，不能保证节点层面策略一致。
- 根因：
  - 节点侧此前没有“允许引擎白名单”拦截机制。
- 修复：
  - 新增节点环境变量 `FORKNFT_ALLOWED_ENGINES`（逗号分隔白名单）。
  - 在节点执行 `Apply/DryRun` 前校验引擎是否允许；不允许时直接拒绝执行并返回错误。
  - 文档补充 nft-only 与“禁用 gost”配置示例。
- 回归：
  - `go test ./socket -run 'TestIsForwardEngineAllowed' -count=1`
  - 线上验证：将 `FORKNFT_ALLOWED_ENGINES` 设为不含 `gost` 后，选择 `gost` 的任务会被节点拒绝。

## 防漏项（每次发布前执行）

1. 运行 repo/handler/socket 的相关回归测试。
2. 执行 `./tests/scripts/test_sync_po0_forwards.sh`。
3. 若使用 nft 模式，确认规则包含 `counter` 且 `nft-flow-exporter.timer` 为 active。
4. **新增**：确认缓存文件值 ≤ 当前 nft counter 值。
5. 线上抽样核对：
   - 转发映射（`inPort` / `remoteAddr`）
   - 诊断结果
   - 流量增长（`forward.list` 的 `inFlow/outFlow`）
   - **新增**：缓存文件与 nft counter 的一致性
