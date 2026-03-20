#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/e2e-engine-check.sh --host <ip> --password <root_password> [options]

Options:
  --ssh-port <port>           SSH port (default: 22)
  --workdir <path>            Remote compose dir (default: /opt/Fork-Nft)
  --repo-url <url>            Repo url to build backend image (default: https://github.com/JackLuo1980/Fork-Nft)
  --keep-fork-backend         Keep remote backend on fork test image after check (default: restore base compose image)
  --skip-build                Skip rebuilding fork backend image on remote host
  -h, --help                  Show this help

Example:
  scripts/e2e-engine-check.sh --host 38.165.47.12 --password 'dmgbZVKT8786'
USAGE
}

HOST=""
PASSWORD=""
SSH_PORT="22"
WORKDIR="/opt/Fork-Nft"
REPO_URL="https://github.com/JackLuo1980/Fork-Nft"
KEEP_FORK_BACKEND="0"
SKIP_BUILD="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --password)
      PASSWORD="${2:-}"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="${2:-}"
      shift 2
      ;;
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --keep-fork-backend)
      KEEP_FORK_BACKEND="1"
      shift
      ;;
    --skip-build)
      SKIP_BUILD="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" || -z "$PASSWORD" ]]; then
  echo "--host and --password are required" >&2
  usage
  exit 1
fi

if ! command -v sshpass >/dev/null 2>&1; then
  echo "sshpass is required on local machine" >&2
  exit 1
fi

SSH_BASE=(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "root@$HOST")

echo "[local] start engine e2e on $HOST"

"${SSH_BASE[@]}" \
  KEEP_FORK_BACKEND="$KEEP_FORK_BACKEND" \
  SKIP_BUILD="$SKIP_BUILD" \
  WORKDIR="$WORKDIR" \
  REPO_URL="$REPO_URL" \
  'bash -s' <<'REMOTE'
set -euo pipefail

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

remove_stale_backend_containers() {
  local names
  names=$(docker ps -a --format '{{.Names}}' | grep -E '(^flux-panel-backend$|_flux-panel-backend$)' || true)
  if [[ -n "$names" ]]; then
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      docker rm -f "$n" >/dev/null 2>&1 || true
    done <<<"$names"
  fi
}

wait_backend_healthy() {
  local retry=30
  local status
  while (( retry > 0 )); do
    status=$(docker inspect -f '{{.State.Health.Status}}' flux-panel-backend 2>/dev/null || echo "unknown")
    if [[ "$status" == "healthy" ]]; then
      return 0
    fi
    sleep 2
    retry=$((retry-1))
  done
  return 1
}

BASE="http://127.0.0.1:6365"
SRC_DIR="/opt/Fork-Nft-src"
OVERRIDE_FILE="${WORKDIR}/docker-compose.engine-test.yml"
FORK_IMAGE="fork-nft-backend:engine-e2e"
NOW_TAG="$(date +%s)"
NODE_NAME="e2e-remote-node-${NOW_TAG}"
TUNNEL_NAME="e2e-tunnel-${NOW_TAG}"
FORWARD_NAME="e2e-forward-${NOW_TAG}"
FORWARD_PORT=19081
MOCK_TOKEN="mocktoken"
NODE_ID=""
TUNNEL_ID=""
FORWARD_ID=""
TOKEN=""

api() {
  local path="$1"
  local body="$2"
  curl -sS -X POST "${BASE}${path}" \
    -H "Authorization: ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${body}"
}

e2e_cleanup_resources() {
  set +e
  [[ -n "$FORWARD_ID" ]] && api "/api/v1/forward/delete" "{\"id\":${FORWARD_ID}}" >/dev/null 2>&1 || true
  [[ -n "$TUNNEL_ID" ]] && api "/api/v1/tunnel/delete" "{\"id\":${TUNNEL_ID}}" >/dev/null 2>&1 || true
  [[ -n "$NODE_ID" ]] && api "/api/v1/node/delete" "{\"id\":${NODE_ID}}" >/dev/null 2>&1 || true
  docker rm -f mock-fed >/dev/null 2>&1 || true
}

restore_backend_if_needed() {
  if [[ "${KEEP_FORK_BACKEND}" == "1" ]]; then
    echo "[remote] keep fork backend image enabled"
    return 0
  fi

  echo "[remote] restore backend to base compose image"
  rm -f "$OVERRIDE_FILE"
  remove_stale_backend_containers
  (cd "$WORKDIR" && compose -f docker-compose-v4.yml up -d backend)
  wait_backend_healthy || {
    echo "[remote] warning: backend restore did not become healthy in time" >&2
    return 1
  }
}

finalize() {
  local exit_code=$?
  e2e_cleanup_resources
  restore_backend_if_needed || true
  if [[ $exit_code -ne 0 ]]; then
    echo "[remote] engine e2e failed"
  fi
  exit $exit_code
}
trap finalize EXIT

echo "[remote] prepare backend image"
if [[ "${SKIP_BUILD}" != "1" ]]; then
  rm -rf "$SRC_DIR"
  git clone --depth 1 "$REPO_URL" "$SRC_DIR"
  (cd "$SRC_DIR/go-backend" && docker build -t "$FORK_IMAGE" .)
fi

cat > "$OVERRIDE_FILE" <<EOF2
services:
  backend:
    image: $FORK_IMAGE
EOF2

remove_stale_backend_containers
(cd "$WORKDIR" && compose -f docker-compose-v4.yml -f docker-compose.engine-test.yml up -d backend)
wait_backend_healthy || {
  echo "[remote] backend not healthy after fork image switch" >&2
  exit 1
}

echo "[remote] login"
LOGIN_JSON=$(curl -sS -X POST "${BASE}/api/v1/user/login" -H "Content-Type: application/json" -d '{"username":"admin_user","password":"admin_user"}')
TOKEN=$(printf "%s" "$LOGIN_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("data",{}).get("token",""))')
[[ -n "$TOKEN" ]] || {
  echo "[remote] login failed: $LOGIN_JSON" >&2
  exit 1
}

echo "[remote] start mock-fed"
docker rm -f mock-fed >/dev/null 2>&1 || true
docker run -d --name mock-fed --network gost-network python:3.11-alpine sh -lc '
cat > /tmp/mock.py <<"PY"
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        l=int(self.headers.get("Content-Length","0")); b=self.rfile.read(l).decode() if l>0 else ""
        with open("/tmp/payload.json","w",encoding="utf-8") as f:
            json.dump({"path":self.path,"auth":self.headers.get("Authorization",""),"body":b},f,ensure_ascii=False)
        if self.path!="/api/v1/federation/runtime/command":
            self.send_response(404); self.end_headers(); self.wfile.write(b"{\"code\":404,\"msg\":\"not found\"}"); return
        if self.headers.get("Authorization","")!="Bearer mocktoken":
            self.send_response(401); self.end_headers(); self.wfile.write(b"{\"code\":401,\"msg\":\"unauthorized\"}"); return
        self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers()
        self.wfile.write(json.dumps({"code":0,"msg":"ok","data":{"type":"UpdateService","success":True,"message":"ok","data":{}}}).encode())
    def log_message(self, fmt, *args):
        return
HTTPServer(("0.0.0.0",18080),H).serve_forever()
PY
python /tmp/mock.py
' >/dev/null
sleep 1

echo "[remote] create remote node"
NODE_CREATE=$(api "/api/v1/node/create" "{\"name\":\"${NODE_NAME}\",\"serverIp\":\"mock-fed\",\"isRemote\":1,\"remoteUrl\":\"http://mock-fed:18080\",\"remoteToken\":\"${MOCK_TOKEN}\",\"tcpListenAddr\":\"0.0.0.0\",\"udpListenAddr\":\"0.0.0.0\",\"status\":1}")
[[ "$(printf "%s" "$NODE_CREATE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("code",-1))')" == "0" ]] || {
  echo "[remote] node create failed: $NODE_CREATE" >&2
  exit 1
}
NODE_ID=$(api "/api/v1/node/list" '{}' | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data",[]); n=[x for x in d if x.get("name","")==sys.argv[1]]; print(n[0].get("id","") if n else "")' "$NODE_NAME")
[[ -n "$NODE_ID" ]] || { echo "[remote] resolve node id failed" >&2; exit 1; }

echo "[remote] create tunnel"
TUNNEL_CREATE=$(api "/api/v1/tunnel/create" "{\"name\":\"${TUNNEL_NAME}\",\"type\":1,\"status\":1,\"inNodeId\":[{\"nodeId\":${NODE_ID}}]}")
[[ "$(printf "%s" "$TUNNEL_CREATE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("code",-1))')" == "0" ]] || {
  echo "[remote] tunnel create failed: $TUNNEL_CREATE" >&2
  exit 1
}
TUNNEL_ID=$(api "/api/v1/tunnel/list" '{}' | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data",[]); n=[x for x in d if x.get("name","")==sys.argv[1]]; print(n[0].get("id","") if n else "")' "$TUNNEL_NAME")
[[ -n "$TUNNEL_ID" ]] || { echo "[remote] resolve tunnel id failed" >&2; exit 1; }

echo "[remote] create forward engine=realm"
FORWARD_CREATE=$(api "/api/v1/forward/create" "{\"name\":\"${FORWARD_NAME}\",\"tunnelId\":${TUNNEL_ID},\"inPort\":${FORWARD_PORT},\"remoteAddr\":\"1.1.1.1:443\",\"strategy\":\"fifo\",\"engine\":\"realm\"}")
[[ "$(printf "%s" "$FORWARD_CREATE" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("code",-1))')" == "0" ]] || {
  echo "[remote] forward create failed: $FORWARD_CREATE" >&2
  exit 1
}
FORWARD_LIST=$(api "/api/v1/forward/list" '{}')
FORWARD_ID=$(printf "%s" "$FORWARD_LIST" | python3 -c 'import json,sys; d=json.load(sys.stdin).get("data",[]); n=[x for x in d if x.get("name","")==sys.argv[1]]; print(n[0].get("id","") if n else "")' "$FORWARD_NAME")

echo "[remote] assert runtime payload"
docker exec mock-fed cat /tmp/payload.json > /tmp/mock_payload_host.json
python3 - <<'PY'
import json
p=json.load(open('/tmp/mock_payload_host.json','r',encoding='utf-8'))
body=json.loads(p.get('body') or '{}')
services=body.get('data') or []
eng=[(s.get('forwarder') or {}).get('engine') for s in services]
assert p.get('path')=='/api/v1/federation/runtime/command', p
assert body.get('commandType')=='UpdateService', body
assert eng and all(x=='realm' for x in eng), eng
print('captured_commandType=', body.get('commandType'))
print('captured_engines=', eng)
PY

echo "[remote] assert list api engine"
python3 - <<PY
import json
obj=json.loads('''$FORWARD_LIST''')
row=next((x for x in (obj.get('data') or []) if x.get('name')=='${FORWARD_NAME}'), None)
assert row and row.get('engine')=='realm', row
print('forward_id=', row.get('id'))
print('forward_engine=', row.get('engine'))
PY

echo "[remote] E2E_OK"
REMOTE

echo "[local] engine e2e done"
