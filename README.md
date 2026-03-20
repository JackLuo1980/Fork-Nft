# Fork-Nft (FLVX)

> FLVX 的通用转发面板分支，面向 `nftables / realm` 多引擎场景，并兼容现有面板管理体验。

## 项目定位

`Fork-Nft` 不是只针对 PO0 的私有脚本仓库，而是一个可开源复用的中转管理项目：

- 控制面继续使用 FLVX 面板模型（用户/节点/隧道/转发）
- 数据面支持按转发选择引擎（当前可选 `gost` / `nftables` / `realm`）
- 提供一键部署、增量同步、联调测试与迁移能力

## 近期核心改动

### 1) 转发引擎字段全链路打通
- `forward.engine` 已贯通后端模型、API、列表展示、导入导出与迁移。
- 后端下发节点运行命令时会显式携带 `forwarder.engine`。
- 前端转发配置页支持选择引擎并持久化。

### 2) PO0 增量同步能力（nft-only）
- 新增脚本：`scripts/sync-po0-forwards-to-panel.sh`
- 从 PO0 的 `/etc/relay-forwards.conf` 读取现有转发，自动同步到面板。
- 同步时强制写入 `engine=nftables`，不会写入 `gost`。

### 3) 引擎联调脚本
- 新增脚本：`scripts/e2e-engine-check.sh`
- 可在远程开发机一键验证：
  - 面板创建转发时 `engine` 持久化
  - 运行时 `UpdateService` 下发体含 `forwarder.engine`

### 4) 回归测试补强
- 新增/补强 `engine` 相关单元与契约测试。
- 新增脚本级测试：`tests/scripts/test_sync_po0_forwards.sh`

### 5) nft 模式流量统计补齐
- 新增 `scripts/nft-flow-exporter.py`（读取 nft counter 增量并上报面板 `/flow/upload`）。
- 新增 `scripts/install-nft-flow-exporter.sh`（一键安装 systemd 定时任务）。
- `go-gost` nftables 规则模板已加入 `counter`，支持后续流量采样。

## 功能特性

- 支持 TCP / UDP 转发
- 支持端口转发与隧道转发
- 支持节点分享（面板对接面板）
- 支持分组权限管理（隧道分组、用户分组）
- 支持批量下发、批量启停等运维操作
- 支持按隧道账号控制转发与流量策略
- 支持转发级引擎选择（`gost` / `nftables` / `realm`）
- 支持从 PO0 增量同步转发到面板（可锁定 `nftables`）

## 目录说明

- `go-backend/`：控制面后端服务
- `vite-frontend/`：前端管理面板
- `go-gost/`：节点代理与执行侧实现
- `scripts/`：联调与运维脚本（含 PO0 同步）
- `docs/`：部署、架构与测试文档

## 部署方式

详细部署文档见：`docs/deploy/fork-nft-deploy.md`

### 方式 A：一键脚本部署（发布版）

面板端：

```bash
curl -L https://raw.githubusercontent.com/JackLuo1980/Fork-Nft/main/panel_install.sh -o panel_install.sh && chmod +x panel_install.sh && ./panel_install.sh
```

节点端：

```bash
curl -L https://raw.githubusercontent.com/JackLuo1980/Fork-Nft/main/install.sh -o install.sh && chmod +x install.sh && ./install.sh
```

### 方式 B：源码构建部署（推荐用于 Fork 功能验证）

在服务器上：

```bash
git clone https://github.com/JackLuo1980/Fork-Nft.git
cd Fork-Nft

# 构建 Fork 后端/前端镜像
(cd go-backend && docker build -t fork-nft-backend:latest .)
(cd vite-frontend && docker build -t fork-nft-frontend:latest .)

# 覆盖 compose 镜像
cat > docker-compose.override.yml <<'YAML'
services:
  backend:
    image: fork-nft-backend:latest
  frontend:
    image: fork-nft-frontend:latest
YAML

# 启动
cp -n .env.example .env 2>/dev/null || true
docker compose -f docker-compose-v4.yml -f docker-compose.override.yml up -d
```

## 默认端口与登录

- 前端面板：`http://<server_ip>:6366/`
- 后端 API：`http://<server_ip>:6365`
- 默认管理员：
  - 用户名：`admin_user`
  - 密码：`admin_user`

> 首次登录后请立即修改默认密码。

## PO0 转发同步到面板（nft-only）

```bash
bash scripts/sync-po0-forwards-to-panel.sh \
  --po0-host <po0_ip> \
  --po0-password '<po0_root_password>' \
  --panel-base 'http://<panel_ip>:6365'
```

可先预演：

```bash
bash scripts/sync-po0-forwards-to-panel.sh \
  --po0-host <po0_ip> \
  --po0-password '<po0_root_password>' \
  --panel-base 'http://<panel_ip>:6365' \
  --dry-run
```

同步脚本默认行为：

- 自动读取 PO0 状态文件 `/etc/relay-forwards.conf`
- 自动创建/复用节点 `PO0-<ip>` 与隧道 `PO0-NFT-SYNC`
- 按名称增量创建或更新转发
- 强制校验目标转发 `engine=nftables`

## 测试与验收

### 本地脚本测试

```bash
./tests/scripts/test_sync_po0_forwards.sh
```

### 远程引擎 E2E

```bash
scripts/e2e-engine-check.sh --host <server_ip> --password '<root_password>'
```

### nft 流量导出器（nft-only 推荐）

在节点机执行：

```bash
bash scripts/install-nft-flow-exporter.sh \
  --panel-base 'http://<panel_ip>:6365' \
  --panel-user '<panel_user>' \
  --panel-password '<panel_password>'
```

检查状态：

```bash
systemctl status nft-flow-exporter.timer --no-pager -l
journalctl -u nft-flow-exporter.service -n 50 --no-pager
```

常用参数：

- `--keep-fork-backend`：联调后保留 Fork 后端镜像
- `--skip-build`：跳过远程重建镜像

## 已知注意事项

- 如果后端不是 Fork 版本，`engine` 字段可能无法按预期持久化；建议使用“源码构建部署”或确认后端镜像版本。
- `panel_install.sh/install.sh` 仍基于 FLVX 发布仓库；Fork 特性验证建议使用源码镜像方式。

## 节点引擎白名单（避免误用 gost）

可在节点 `flux_agent` 服务上设置：

```bash
FORKNFT_ALLOWED_ENGINES=nftables,realm,auto
FORKNFT_FORWARD_ENGINE=auto
```

说明：

- `FORKNFT_ALLOWED_ENGINES`：节点允许执行的引擎列表（逗号分隔）；未包含的引擎会被节点拒绝。
- `FORKNFT_FORWARD_ENGINE`：当请求未显式传 `engine` 时的默认值（本项目当前默认 `auto`）。
- 例如要把某台节点锁死为 nft-only：`FORKNFT_ALLOWED_ENGINES=nftables`。

## Original Project

- Name: `flux-panel`
- Source: https://github.com/bqlpfy/flux-panel
- License: Apache License 2.0

## 免责声明

本项目仅供个人学习与研究使用。请仅在合法、合规、安全的前提下使用，任何滥用或违法行为后果由使用者自行承担。
