#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/sync-po0-forwards-to-panel.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "missing script: $SCRIPT" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$SCRIPT"

assert_eq() {
  local got="$1"
  local want="$2"
  local msg="$3"
  if [[ "$got" != "$want" ]]; then
    echo "[FAIL] $msg" >&2
    echo "  got:  $got" >&2
    echo "  want: $want" >&2
    exit 1
  fi
}

assert_contains() {
  local text="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$text" != *"$needle"* ]]; then
    echo "[FAIL] $msg" >&2
    echo "  text: $text" >&2
    echo "  missing: $needle" >&2
    exit 1
  fi
}

test_parse_lines() {
  local input
  input=$'\n# comment\nA|1.2.3.4|23202|12071\nB|hktnat.jung.eu.org|13608|31001\n'
  local out
  out="$(parse_relay_lines "$input")"
  local count
  count="$(printf '%s\n' "$out" | sed '/^$/d' | wc -l | tr -d ' ')"
  assert_eq "$count" "2" "parse_relay_lines should keep only valid records"
  assert_contains "$out" '"name":"A"' "first record name"
  assert_contains "$out" '"target_host":"hktnat.jung.eu.org"' "domain target should be preserved"
}

test_engine_lock() {
  local payload
  payload="$(build_forward_payload 'demo' 12345 '1.2.3.4' 80 9)"
  assert_contains "$payload" '"engine":"nftables"' "payload engine must be nftables"
  if [[ "$payload" == *'"engine":"gost"'* ]]; then
    echo "[FAIL] payload must never contain gost" >&2
    exit 1
  fi
}

test_parse_lines
test_engine_lock

echo "PASS: sync-po0 tests"
