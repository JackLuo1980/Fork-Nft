#!/bin/bash

set -e

REPO="JackLuo1980/Fork-Nft"
INSTALL_DIR="/etc/flux_agent"

get_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "amd64"
            ;;
    esac
}

maybe_proxy_url() {
  local url="$1"
  echo "https://gcode.hostcentral.cc/${url}"
}

resolve_version() {
  if [[ -n "${VERSION:-}" ]]; then
    echo "$VERSION"
    return 0
  fi
  if [[ -n "${FLUX_VERSION:-}" ]]; then
    echo "$FLUX_VERSION"
    return 0
  fi

  latest_url="https://github.com/${REPO}/releases/latest"
  api_url="https://api.github.com/repos/${REPO}/releases/latest"

  effective_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' -L "$(maybe_proxy_url "$latest_url")" 2>/dev/null || true)
  tag="${effective_url##*/}"
  if [[ -n "$tag" && "$tag" != "latest" ]]; then
    echo "$tag"
    return 0
  fi

  api_tag=$(curl -fsSL "$(maybe_proxy_url "$api_url")" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)
  if [[ -n "$api_tag" ]]; then
    echo "$api_tag"
    return 0
  fi

  echo "无法获取最新版本号"
  return 1
}

check_and_install_tcpkill() {
  if command -v tcpkill &> /dev/null; then
    return 0
  fi
  
  OS_TYPE=$(uname -s)
  SUDO_CMD=""
  [[ $EUID -ne 0 ]] && SUDO_CMD="sudo"
  
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    command -v brew &> /dev/null && brew install dsniff &> /dev/null
    return 0
  fi
  
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
  elif [ -f /etc/redhat-release ]; then
    DISTRO="rhel"
  elif [ -f /etc/debian_version ]; then
    DISTRO="debian"
  else
    return 0
  fi
  
  case $DISTRO in
    ubuntu|debian)
      $SUDO_CMD apt update &> /dev/null
      $SUDO_CMD apt install -y dsniff &> /dev/null
      ;;
    centos|rhel|fedora)
      if command -v dnf &> /dev/null; then
        $SUDO_CMD dnf install -y dsniff &> /dev/null
      elif command -v yum &> /dev/null; then
        $SUDO_CMD yum install -y dsniff &> /dev/null
      fi
      ;;
    alpine)
      $SUDO_CMD apk add --no-cache dsniff &> /dev/null
      ;;
    arch|manjaro)
      $SUDO_CMD pacman -S --noconfirm dsniff &> /dev/null
      ;;
  esac
  
  return 0
}

RESOLVED_VERSION=$(resolve_version) || exit 1
ARCH=$(get_architecture)
DOWNLOAD_URL=$(maybe_proxy_url "https://github.com/${REPO}/releases/download/${RESOLVED_VERSION}/gost-${ARCH}")

echo "==============================================="
echo "Flux Agent 安装脚本"
echo "==============================================="
echo "版本: $RESOLVED_VERSION"
echo "架构: $ARCH"
echo "服务器: $SERVER_ADDR"
echo "==============================================="

if [[ -z "$SERVER_ADDR" || -z "$SECRET" ]]; then
  echo "错误: 必须提供 -a (服务器地址) 和 -s (密钥) 参数"
  echo "用法: ./install.sh -a <服务器地址> -s <密钥> [VERSION=<版本号>]"
  exit 1
fi

check_and_install_tcpkill

mkdir -p "$INSTALL_DIR"

if systemctl list-units --full -all | grep -Fq "flux_agent.service"; then
  echo "检测到已存在的 flux_agent 服务，停止并禁用..."
  systemctl stop flux_agent 2>/dev/null
  systemctl disable flux_agent 2>/dev/null
fi

[[ -f "$INSTALL_DIR/flux_agent" ]] && rm -f "$INSTALL_DIR/flux_agent"

echo "下载 flux_agent..."
curl -L "$DOWNLOAD_URL" -o "$INSTALL_DIR/flux_agent"
if [[ ! -f "$INSTALL_DIR/flux_agent" || ! -s "$INSTALL_DIR/flux_agent" ]]; then
  echo "错误: 下载失败，请检查网络或版本号"
  exit 1
fi
chmod +x "$INSTALL_DIR/flux_agent"
echo "下载完成"

CONFIG_FILE="$INSTALL_DIR/config.json"
echo "创建配置文件..."
cat > "$CONFIG_FILE" <<EOF
{
  "addr": "$SERVER_ADDR",
  "secret": "$SECRET"
}
EOF

GOST_CONFIG="$INSTALL_DIR/gost.json"
[[ ! -f "$GOST_CONFIG" ]] && echo "{}" > "$GOST_CONFIG"

chmod 600 "$INSTALL_DIR"/*.json

SERVICE_FILE="/etc/systemd/system/flux_agent.service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Flux_agent Proxy Service
After=network.target

[Service]
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/flux_agent
Restart=on-failure
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable flux_agent
systemctl start flux_agent

if systemctl is-active --quiet flux_agent; then
  echo "==============================================="
  echo "✅ 安装成功"
  echo "==============================================="
  echo "服务状态: 运行中"
  echo "配置目录: $INSTALL_DIR"
  echo "==============================================="
else
  echo "==============================================="
  echo "❌ 服务启动失败"
  echo "==============================================="
  echo "请执行: systemctl status flux_agent --no-pager"
  exit 1
fi

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
rm -f "$SCRIPT_PATH"
