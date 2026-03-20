# Fork-Nft 部署与运维指南

## 1. 目标

本文档用于统一 Fork-Nft 的部署口径，覆盖：

- 面板部署
- 节点接入
- PO0 增量同步
- nftables 引擎验收

## 2. 端口约定

- 前端：`6366`
- 后端 API：`6365`

## 3. 部署模式

### 模式 A：发布版一键脚本

适用于快速起盘，使用 FLVX 发布镜像。

```bash
# panel
curl -L https://raw.githubusercontent.com/JackLuo1980/Fork-Nft/main/panel_install.sh -o panel_install.sh && chmod +x panel_install.sh && ./panel_install.sh

# node
curl -L https://raw.githubusercontent.com/JackLuo1980/Fork-Nft/main/install.sh -o install.sh && chmod +x install.sh && ./install.sh
```

### 模式 B：Fork 源码镜像（推荐）

适用于验证/上线 Fork-Nft 新能力（engine 字段等）。

```bash
git clone https://github.com/JackLuo1980/Fork-Nft.git
cd Fork-Nft

(cd go-backend && docker build -t fork-nft-backend:latest .)
(cd vite-frontend && docker build -t fork-nft-frontend:latest .)

cat > docker-compose.override.yml <<'YAML'
services:
  backend:
    image: fork-nft-backend:latest
  frontend:
    image: fork-nft-frontend:latest
YAML

docker compose -f docker-compose-v4.yml -f docker-compose.override.yml up -d
```

## 4. 首次登录

- URL: `http://<panel_ip>:6366/`
- 用户名：`admin_user`
- 密码：`admin_user`

首次登录后请立即修改默认密码。

## 5. PO0 增量同步（nft-only）

脚本：`scripts/sync-po0-forwards-to-panel.sh`

### 5.1 干跑

```bash
bash scripts/sync-po0-forwards-to-panel.sh \
  --po0-host <po0_ip> \
  --po0-password '<po0_root_password>' \
  --panel-base 'http://<panel_ip>:6365' \
  --dry-run
```

### 5.2 正式执行

```bash
bash scripts/sync-po0-forwards-to-panel.sh \
  --po0-host <po0_ip> \
  --po0-password '<po0_root_password>' \
  --panel-base 'http://<panel_ip>:6365'
```

### 5.3 默认行为

- 读取 PO0 `/etc/relay-forwards.conf`
- 创建/复用节点 `PO0-<ip>`
- 创建/复用隧道 `PO0-NFT-SYNC`
- 同步转发并强制 `engine=nftables`
- 状态文件按 `name|host|target_port|relay_port` 解析（`inPort=relay_port`）

## 5.4 nft-only 流量统计（推荐开启）

在节点执行：

```bash
bash scripts/install-nft-flow-exporter.sh \
  --panel-base 'http://<panel_ip>:6365' \
  --panel-user '<panel_user>' \
  --panel-password '<panel_password>'
```

检查：

```bash
systemctl status nft-flow-exporter.timer --no-pager -l
journalctl -u nft-flow-exporter.service -n 50 --no-pager
```

## 6. 验收清单

### 6.1 引擎字段

面板 `forward/list` 中目标记录应满足：

- `engine=nftables`
- `inPort` 与 PO0 状态文件一致
- `remoteAddr` 与 PO0 状态文件一致

### 6.2 远程联调

```bash
scripts/e2e-engine-check.sh --host <server_ip> --password '<root_password>'
```

可选参数：

- `--keep-fork-backend`：联调后保留 Fork 后端镜像
- `--skip-build`：跳过远程重建镜像

## 7. 常见问题

### 7.0 节点不允许 gost（推荐）

在节点服务环境变量设置：

```bash
FORKNFT_ALLOWED_ENGINES=nftables,realm,auto
FORKNFT_FORWARD_ENGINE=auto
```

如果要 nft-only：

```bash
FORKNFT_ALLOWED_ENGINES=nftables
FORKNFT_FORWARD_ENGINE=nftables
```

### 7.1 “部分节点不在线”

创建隧道时报该错误通常是节点 agent 未连上面板。

处理步骤：

1. 检查节点 `systemctl status flux_agent`
2. 检查面板 `node/list` 中状态
3. 对于受限网络，优先使用离线方式上传 agent 二进制并手工注册

### 7.2 同步后 engine 丢失

现象：`forward.list` 中 `engine` 为空或回退。

根因通常是后端仍在旧镜像。

处理：切换到 Fork 后端镜像并重跑同步。
