#!/usr/bin/env bash
set -euo pipefail

# Sync relay forwards from PO0 (/etc/relay-forwards.conf) into panel forwards.
# Hard-locked: engine=nftables. gost is never used.

ENGINE_LOCK="nftables"

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

log() {
  echo "[sync] $*"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

parse_relay_lines() {
  local content="$1"
  python3 - "$content" <<'PY'
import json, sys
content = sys.argv[1]
for raw in content.splitlines():
    line = raw.strip()
    if not line or line.startswith('#'):
        continue
    parts = [p.strip() for p in line.split('|')]
    if len(parts) != 4:
        continue
    name, host, in_port, target_port = parts
    if not name or not host:
        continue
    if not in_port.isdigit() or not target_port.isdigit():
        continue
    print(json.dumps({
        'name': name,
        'target_host': host,
        'in_port': int(in_port),
        'target_port': int(target_port),
    }, ensure_ascii=False, separators=(',', ':')))
PY
}

build_forward_payload() {
  local name="$1"
  local in_port="$2"
  local target_host="$3"
  local target_port="$4"
  local tunnel_id="$5"
  python3 - "$name" "$in_port" "$target_host" "$target_port" "$tunnel_id" "$ENGINE_LOCK" <<'PY'
import json, sys
name, in_port, host, target_port, tunnel_id, engine = sys.argv[1:]
obj = {
    'name': name,
    'tunnelId': int(tunnel_id),
    'inPort': int(in_port),
    'remoteAddr': f'{host}:{target_port}',
    'strategy': 'fifo',
    'engine': engine,
}
print(json.dumps(obj, ensure_ascii=False, separators=(',', ':')))
PY
}

build_forward_update_payload() {
  local forward_id="$1"
  local name="$2"
  local in_port="$3"
  local target_host="$4"
  local target_port="$5"
  local tunnel_id="$6"
  python3 - "$forward_id" "$name" "$in_port" "$target_host" "$target_port" "$tunnel_id" "$ENGINE_LOCK" <<'PY'
import json, sys
forward_id, name, in_port, host, target_port, tunnel_id, engine = sys.argv[1:]
obj = {
    'id': int(forward_id),
    'name': name,
    'tunnelId': int(tunnel_id),
    'inPort': int(in_port),
    'remoteAddr': f'{host}:{target_port}',
    'strategy': 'fifo',
    'engine': engine,
}
print(json.dumps(obj, ensure_ascii=False, separators=(',', ':')))
PY
}

api() {
  local path="$1"
  local body="$2"
  curl -fsS -X POST "${PANEL_BASE}${path}" \
    -H "Authorization: ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body"
}

ensure_code_zero() {
  local response="$1"
  local code
  code="$(printf '%s' "$response" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("code",-1))')"
  [[ "$code" == "0" ]] || die "panel api error: $response"
}

usage() {
  cat <<'HELP'
Usage:
  bash scripts/sync-po0-forwards-to-panel.sh \
    --po0-host 111.229.215.107 \
    --po0-password 'xxxx' \
    --panel-base 'http://38.165.47.12:6365' \
    [--po0-user root] \
    [--state-file /etc/relay-forwards.conf] \
    [--panel-user admin_user] \
    [--panel-password admin_user] \
    [--node-name 'PO0-111.229.215.107'] \
    [--tunnel-name 'PO0-NFT-SYNC'] \
    [--dry-run]
HELP
}

PO0_HOST=""
PO0_USER="root"
PO0_PASSWORD=""
STATE_FILE="/etc/relay-forwards.conf"
PANEL_BASE=""
PANEL_USER="admin_user"
PANEL_PASSWORD="admin_user"
NODE_NAME=""
TUNNEL_NAME="PO0-NFT-SYNC"
DRY_RUN=0
TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --po0-host) PO0_HOST="$2"; shift 2 ;;
    --po0-user) PO0_USER="$2"; shift 2 ;;
    --po0-password) PO0_PASSWORD="$2"; shift 2 ;;
    --state-file) STATE_FILE="$2"; shift 2 ;;
    --panel-base) PANEL_BASE="$2"; shift 2 ;;
    --panel-user) PANEL_USER="$2"; shift 2 ;;
    --panel-password) PANEL_PASSWORD="$2"; shift 2 ;;
    --node-name) NODE_NAME="$2"; shift 2 ;;
    --tunnel-name) TUNNEL_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0 2>/dev/null || true
fi

require_cmd curl
require_cmd python3
require_cmd sshpass

PO0_HOST="$(trim "$PO0_HOST")"
PO0_PASSWORD="$(trim "$PO0_PASSWORD")"
PANEL_BASE="$(trim "$PANEL_BASE")"
NODE_NAME="$(trim "$NODE_NAME")"
TUNNEL_NAME="$(trim "$TUNNEL_NAME")"

[[ -n "$PO0_HOST" ]] || die "--po0-host is required"
[[ -n "$PO0_PASSWORD" ]] || die "--po0-password is required"
[[ -n "$PANEL_BASE" ]] || die "--panel-base is required"
[[ -n "$TUNNEL_NAME" ]] || die "--tunnel-name is required"
[[ "$ENGINE_LOCK" == "nftables" ]] || die "engine lock must be nftables"

if [[ -z "$NODE_NAME" ]]; then
  NODE_NAME="PO0-${PO0_HOST}"
fi

log "read relay state from ${PO0_USER}@${PO0_HOST}:${STATE_FILE}"
STATE_CONTENT="$(sshpass -p "$PO0_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${PO0_USER}@${PO0_HOST}" "cat '$STATE_FILE'")"
PARSED_LINES="$(parse_relay_lines "$STATE_CONTENT")"
PARSED_COUNT="$(printf '%s\n' "$PARSED_LINES" | sed '/^$/d' | wc -l | tr -d ' ')"
[[ "$PARSED_COUNT" != "0" ]] || die "no valid relay entries found in ${STATE_FILE}"
log "found ${PARSED_COUNT} relay entries"

log "panel login: ${PANEL_BASE}"
LOGIN_JSON="$(curl -fsS -X POST "${PANEL_BASE}/api/v1/user/login" -H "Content-Type: application/json" -d "{\"username\":\"${PANEL_USER}\",\"password\":\"${PANEL_PASSWORD}\"}")"
ensure_code_zero "$LOGIN_JSON"
TOKEN="$(printf '%s' "$LOGIN_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("data",{}).get("token",""))')"
[[ -n "$TOKEN" ]] || die "login token missing"

NODE_LIST="$(api '/api/v1/node/list' '{}')"
ensure_code_zero "$NODE_LIST"
NODE_ID="$(printf '%s' "$NODE_LIST" | python3 -c 'import json,sys; n=sys.argv[1]; rows=json.load(sys.stdin).get("data") or []; print(next((str(r.get("id")) for r in rows if r.get("name")==n), ""))' "$NODE_NAME")"
if [[ -z "$NODE_ID" ]]; then
  NODE_CREATE="$(python3 - "$NODE_NAME" "$PO0_HOST" <<'PY'
import json, sys
name, ip = sys.argv[1:]
print(json.dumps({
  'name': name,
  'serverIp': ip,
  'port': '1000-65535',
  'tcpListenAddr': '0.0.0.0',
  'udpListenAddr': '0.0.0.0',
  'http': 0,
  'tls': 1,
  'socks': 0,
  'isRemote': 0,
}, ensure_ascii=False, separators=(',', ':')))
PY
)"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] would create node: ${NODE_NAME}"
    NODE_ID="999991"
  else
    log "create node: ${NODE_NAME}"
    RESP="$(api '/api/v1/node/create' "$NODE_CREATE")"
    ensure_code_zero "$RESP"
    NODE_LIST="$(api '/api/v1/node/list' '{}')"
    ensure_code_zero "$NODE_LIST"
    NODE_ID="$(printf '%s' "$NODE_LIST" | python3 -c 'import json,sys; n=sys.argv[1]; rows=json.load(sys.stdin).get("data") or []; print(next((str(r.get("id")) for r in rows if r.get("name")==n), ""))' "$NODE_NAME")"
  fi
fi
[[ -n "$NODE_ID" ]] || die "failed to locate node id for ${NODE_NAME}"
log "use node id: ${NODE_ID}"

TUNNEL_LIST="$(api '/api/v1/tunnel/list' '{}')"
ensure_code_zero "$TUNNEL_LIST"
TUNNEL_ID="$(printf '%s' "$TUNNEL_LIST" | python3 -c 'import json,sys; n=sys.argv[1]; rows=json.load(sys.stdin).get("data") or []; print(next((str(r.get("id")) for r in rows if r.get("name")==n), ""))' "$TUNNEL_NAME")"
if [[ -z "$TUNNEL_ID" ]]; then
  TUNNEL_CREATE="$(python3 - "$TUNNEL_NAME" "$NODE_ID" "$PO0_HOST" <<'PY'
import json, sys
name, node_id, in_ip = sys.argv[1:]
print(json.dumps({
  'name': name,
  'type': 1,
  'status': 1,
  'inIp': in_ip,
  'inNodeId': [{'nodeId': int(node_id)}],
  'chainNodes': [],
  'flow': 1,
  'trafficRatio': 1,
}, ensure_ascii=False, separators=(',', ':')))
PY
)"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] would create tunnel: ${TUNNEL_NAME}"
    TUNNEL_ID="999992"
  else
    log "create tunnel: ${TUNNEL_NAME}"
    RESP="$(api '/api/v1/tunnel/create' "$TUNNEL_CREATE")"
    ensure_code_zero "$RESP"
    TUNNEL_LIST="$(api '/api/v1/tunnel/list' '{}')"
    ensure_code_zero "$TUNNEL_LIST"
    TUNNEL_ID="$(printf '%s' "$TUNNEL_LIST" | python3 -c 'import json,sys; n=sys.argv[1]; rows=json.load(sys.stdin).get("data") or []; print(next((str(r.get("id")) for r in rows if r.get("name")==n), ""))' "$TUNNEL_NAME")"
  fi
fi
[[ -n "$TUNNEL_ID" ]] || die "failed to locate tunnel id for ${TUNNEL_NAME}"
log "use tunnel id: ${TUNNEL_ID}"

FORWARD_LIST="$(api '/api/v1/forward/list' '{}')"
ensure_code_zero "$FORWARD_LIST"

CREATE_COUNT=0
UPDATE_COUNT=0
SKIP_COUNT=0

while IFS= read -r row; do
  [[ -n "$row" ]] || continue

  name="$(printf '%s' "$row" | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')"
  in_port="$(printf '%s' "$row" | python3 -c 'import json,sys; print(json.load(sys.stdin)["in_port"])')"
  target_host="$(printf '%s' "$row" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_host"])')"
  target_port="$(printf '%s' "$row" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_port"])')"
  remote_addr="${target_host}:${target_port}"

  existing="$(printf '%s' "$FORWARD_LIST" | python3 -c 'import json,sys; n=sys.argv[1]; rows=json.load(sys.stdin).get("data") or []; import json as _j; print(next((_j.dumps(r,ensure_ascii=False,separators=(",",":")) for r in rows if r.get("name")==n), ""))' "$name")"

  if [[ -z "$existing" ]]; then
    payload="$(build_forward_payload "$name" "$in_port" "$target_host" "$target_port" "$TUNNEL_ID")"
    if [[ "$DRY_RUN" == "1" ]]; then
      log "[dry-run] create forward: ${name} ${in_port} -> ${remote_addr}"
    else
      log "create forward: ${name} ${in_port} -> ${remote_addr}"
      resp="$(api '/api/v1/forward/create' "$payload")"
      ensure_code_zero "$resp"
    fi
    CREATE_COUNT=$((CREATE_COUNT + 1))
    continue
  fi

  old_id="$(printf '%s' "$existing" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
  old_in_port="$(printf '%s' "$existing" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("inPort",""))')"
  old_remote_addr="$(printf '%s' "$existing" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("remoteAddr",""))')"
  old_engine="$(printf '%s' "$existing" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("engine",""))')"

  if [[ "$old_in_port" == "$in_port" && "$old_remote_addr" == "$remote_addr" && "$old_engine" == "$ENGINE_LOCK" ]]; then
    SKIP_COUNT=$((SKIP_COUNT + 1))
    continue
  fi

  payload="$(build_forward_update_payload "$old_id" "$name" "$in_port" "$target_host" "$target_port" "$TUNNEL_ID")"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] update forward: ${name} ${in_port} -> ${remote_addr}"
  else
    log "update forward: ${name} ${in_port} -> ${remote_addr}"
    resp="$(api '/api/v1/forward/update' "$payload")"
    ensure_code_zero "$resp"
  fi
  UPDATE_COUNT=$((UPDATE_COUNT + 1))
done <<< "$PARSED_LINES"

if [[ "$DRY_RUN" == "0" ]]; then
  FINAL_LIST="$(api '/api/v1/forward/list' '{}')"
  ensure_code_zero "$FINAL_LIST"
  FINAL_LIST_JSON="$FINAL_LIST" PARSED_LINES_JSON="$PARSED_LINES" python3 - "$ENGINE_LOCK" <<'PY'
import json, os, sys
engine = sys.argv[1]
rows = json.loads(os.environ['FINAL_LIST_JSON']).get('data') or []
by_name = {r.get('name'): r for r in rows}
desired = [json.loads(x) for x in os.environ.get('PARSED_LINES_JSON', '').splitlines() if x.strip()]
for d in desired:
    row = by_name.get(d['name'])
    if not row:
        print(f"forward missing after sync: {d['name']}", file=sys.stderr)
        sys.exit(1)
    if str(row.get('inPort')) != str(d['in_port']):
        print(f"inPort mismatch for {d['name']}: {row.get('inPort')} != {d['in_port']}", file=sys.stderr)
        sys.exit(1)
    expected = f"{d['target_host']}:{d['target_port']}"
    if str(row.get('remoteAddr')) != expected:
        print(f"remoteAddr mismatch for {d['name']}: {row.get('remoteAddr')} != {expected}", file=sys.stderr)
        sys.exit(1)
    if str(row.get('engine', '')) != engine:
        print(f"engine mismatch for {d['name']}: {row.get('engine')} != {engine}", file=sys.stderr)
        sys.exit(1)
PY
fi

log "done. created=${CREATE_COUNT}, updated=${UPDATE_COUNT}, skipped=${SKIP_COUNT}, engine=${ENGINE_LOCK}"
