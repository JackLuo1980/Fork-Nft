#!/usr/bin/env python3
"""
Export nftables DNAT counter deltas to panel /flow/upload, so nft-only forwarding
can still update forward traffic statistics.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="nftables flow exporter")
    p.add_argument("--panel-base", required=True, help="e.g. http://38.165.47.12:6365")
    p.add_argument("--panel-user", required=True)
    p.add_argument("--panel-password", required=True)
    p.add_argument("--panel-secret", default="", help="optional, fallback reads agent config")
    p.add_argument("--agent-config", default="/etc/flux_agent/config.json")
    p.add_argument("--relay-state", default="/etc/relay-forwards.conf")
    p.add_argument("--cache-file", default="/var/lib/fork-nft/nft-flow-exporter.json")
    p.add_argument("--nft-family", default="ip")
    p.add_argument("--nft-table", default="nat")
    p.add_argument("--nft-chain", default="prerouting")
    p.add_argument("--timeout", type=float, default=8.0)
    return p.parse_args()


def read_panel_secret(args: argparse.Namespace) -> str:
    if args.panel_secret.strip():
        return args.panel_secret.strip()
    cfg = json.loads(pathlib.Path(args.agent_config).read_text(encoding="utf-8"))
    secret = str(cfg.get("secret", "")).strip()
    if not secret:
        raise RuntimeError("panel secret is empty (use --panel-secret or fix agent config)")
    return secret


def http_post_json(url: str, payload: dict, headers: dict[str, str], timeout: float) -> dict:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    for k, v in headers.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"http {e.code} {url}: {detail}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"request failed {url}: {e}") from e
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"invalid json from {url}: {raw}") from e


def panel_login(base: str, username: str, password: str, timeout: float) -> str:
    obj = http_post_json(
        f"{base.rstrip('/')}/api/v1/user/login",
        {"username": username, "password": password},
        {},
        timeout,
    )
    if int(obj.get("code", -1)) != 0:
        raise RuntimeError(f"panel login failed: {obj}")
    token = str((obj.get("data") or {}).get("token", "")).strip()
    if not token:
        raise RuntimeError("panel login token is empty")
    return token


def fetch_forwards(base: str, token: str, timeout: float) -> dict[str, str]:
    obj = http_post_json(
        f"{base.rstrip('/')}/api/v1/forward/list",
        {},
        {"Authorization": token},
        timeout,
    )
    if int(obj.get("code", -1)) != 0:
        raise RuntimeError(f"forward/list failed: {obj}")
    out: dict[str, str] = {}
    for row in obj.get("data") or []:
        name = str(row.get("name", "")).strip()
        if not name:
            continue
        fid = int(row.get("id") or 0)
        uid = int(row.get("userId") or 0)
        if fid <= 0 or uid <= 0:
            continue
        out[name] = f"{fid}_{uid}_0"
    return out


def parse_relay_state(path: str) -> list[dict]:
    entries: list[dict] = []
    for raw in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [x.strip() for x in line.split("|")]
        if len(parts) != 4:
            continue
        name, host, target_port, relay_port = parts
        if not name or not host:
            continue
        if not target_port.isdigit() or not relay_port.isdigit():
            continue
        entries.append(
            {
                "name": name,
                "target_host": host,
                "target_port": int(target_port),
                "relay_port": int(relay_port),
            }
        )
    return entries


def load_nft_chain(family: str, table: str, chain: str) -> dict[int, int]:
    cmd = ["nft", "-j", "list", "chain", family, table, chain]
    raw = subprocess.check_output(cmd, text=True)
    doc = json.loads(raw)
    port_bytes: dict[int, int] = {}
    for item in doc.get("nftables") or []:
        rule = (item or {}).get("rule")
        if not rule:
            continue
        dport: int | None = None
        bytes_count: int | None = None
        for expr in rule.get("expr") or []:
            match = expr.get("match")
            if match:
                left = match.get("left") or {}
                payload = left.get("payload") or {}
                if payload.get("protocol") == "th" and payload.get("field") == "dport":
                    right = match.get("right")
                    if isinstance(right, int):
                        dport = right
            counter = expr.get("counter")
            if isinstance(counter, dict):
                bytes_count = int(counter.get("bytes") or 0)
        if dport is not None and bytes_count is not None:
            port_bytes[dport] = bytes_count
    return port_bytes


def load_cache(path: str) -> dict:
    p = pathlib.Path(path)
    if not p.exists():
        return {"ports": {}}
    try:
        obj = json.loads(p.read_text(encoding="utf-8"))
        if not isinstance(obj, dict):
            return {"ports": {}}
        ports = obj.get("ports")
        if not isinstance(ports, dict):
            obj["ports"] = {}
        return obj
    except Exception:
        return {"ports": {}}


def save_cache(path: str, ports: dict[int, int]) -> None:
    p = pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "updated_at": int(time.time()),
        "ports": {str(k): int(v) for k, v in sorted(ports.items())},
    }
    p.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def upload_flow(base: str, secret: str, items: list[dict], timeout: float) -> None:
    url = f"{base.rstrip('/')}/flow/upload?secret={urllib.parse.quote(secret)}"
    body = json.dumps(items, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        text = resp.read().decode("utf-8", errors="replace").strip()
    if text != "ok":
        raise RuntimeError(f"flow upload failed: {text}")


def main() -> int:
    args = parse_args()
    secret = read_panel_secret(args)
    token = panel_login(args.panel_base, args.panel_user, args.panel_password, args.timeout)
    service_by_name = fetch_forwards(args.panel_base, token, args.timeout)
    relay_entries = parse_relay_state(args.relay_state)
    if not relay_entries:
        print("no valid relay entries")
        return 1

    current_bytes = load_nft_chain(args.nft_family, args.nft_table, args.nft_chain)
    if not current_bytes:
        print("no nft rules with counters found in target chain")
        return 2

    cache = load_cache(args.cache_file)
    prev_ports = cache.get("ports") or {}

    items: list[dict] = []
    matched_ports = 0
    for entry in relay_entries:
        name = entry["name"]
        relay_port = int(entry["relay_port"])
        if relay_port not in current_bytes:
            continue
        matched_ports += 1
        current = int(current_bytes[relay_port])
        previous = int(prev_ports.get(str(relay_port), current))
        delta = current - previous
        if delta <= 0:
            continue
        service_name = service_by_name.get(name)
        if not service_name:
            continue
        items.append({"n": service_name, "u": 0, "d": int(delta)})

    save_cache(args.cache_file, current_bytes)

    if matched_ports == 0:
        print("no relay ports matched nft counter rules (check dport and chain)")
        return 2

    if not items:
        print("no delta to upload")
        return 0

    upload_flow(args.panel_base, secret, items, args.timeout)
    total = sum(int(x["u"]) + int(x["d"]) for x in items)
    print(f"uploaded {len(items)} flow items, bytes={total}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # pylint: disable=broad-except
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
