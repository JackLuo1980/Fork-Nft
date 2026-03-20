#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

usage() {
  cat <<'HELP'
Usage:
  bash scripts/install-nft-flow-exporter.sh \
    --panel-base 'http://<panel_ip>:6365' \
    --panel-user '<panel_user>' \
    --panel-password '<panel_password>' \
    [--panel-secret '<node_secret>']

Installs:
  /usr/local/bin/nft-flow-exporter.py
  /etc/systemd/system/nft-flow-exporter.service
  /etc/systemd/system/nft-flow-exporter.timer
HELP
}

PANEL_BASE=""
PANEL_USER=""
PANEL_PASSWORD=""
PANEL_SECRET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --panel-base) PANEL_BASE="$2"; shift 2 ;;
    --panel-user) PANEL_USER="$2"; shift 2 ;;
    --panel-password) PANEL_PASSWORD="$2"; shift 2 ;;
    --panel-secret) PANEL_SECRET="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$PANEL_BASE" ]] || die "--panel-base is required"
[[ -n "$PANEL_USER" ]] || die "--panel-user is required"
[[ -n "$PANEL_PASSWORD" ]] || die "--panel-password is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v nft >/dev/null 2>&1 || die "nft is required"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/nft-flow-exporter.py"
[[ -f "$SRC" ]] || die "missing ${SRC}"

install -m 0755 "$SRC" /usr/local/bin/nft-flow-exporter.py

ENV_FILE="/etc/default/nft-flow-exporter"
{
  echo "PANEL_BASE=${PANEL_BASE}"
  echo "PANEL_USER=${PANEL_USER}"
  echo "PANEL_PASSWORD=${PANEL_PASSWORD}"
  echo "PANEL_SECRET=${PANEL_SECRET}"
} > "$ENV_FILE"
chmod 0600 "$ENV_FILE"

cat > /etc/systemd/system/nft-flow-exporter.service <<'UNIT'
[Unit]
Description=NFT Flow Exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/default/nft-flow-exporter
ExecStart=/usr/bin/env python3 /usr/local/bin/nft-flow-exporter.py --panel-base ${PANEL_BASE} --panel-user ${PANEL_USER} --panel-password ${PANEL_PASSWORD} --panel-secret ${PANEL_SECRET}
UNIT

cat > /etc/systemd/system/nft-flow-exporter.timer <<'UNIT'
[Unit]
Description=Run NFT Flow Exporter every 10s

[Timer]
OnBootSec=20s
OnUnitActiveSec=10s
AccuracySec=1s
Unit=nft-flow-exporter.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now nft-flow-exporter.timer
systemctl start nft-flow-exporter.service || true
systemctl status nft-flow-exporter.timer --no-pager -l | sed -n '1,40p'

echo "[ok] nft-flow-exporter installed"
