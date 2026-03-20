#!/usr/bin/env python3
"""
Export nftables counter deltas to panel /flow/upload, preserving nft-only forwarding.

Flow source:
1) ip nat prerouting dnat counters -> map relay_port -> target_ip:target_port
2) inet filter forward counters:
   - daddr+ dport counter => upload (client -> target)
   - saddr+ sport counter => download (target -> client)
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


def nft_list_chain(family: str, table: str, chain: str) -> list[dict]:
    raw = subprocess.check_output(["nft", "-j", "list", "chain", family, table, chain], text=True)
    doc = json.loads(raw)
    return doc.get("nftables") or []


def extract_match_port(expr: dict, field: str) -> int | None:
    match = expr.get("match")
    if not isinstance(match, dict):
        return None
    left = match.get("left") or {}
    payload = left.get("payload") or {}
    if payload.get("protocol") != "th" or payload.get("field") != field:
        return None
    right = match.get("right")
    if isinstance(right, int):
        return right
    return None


def extract_match_ip(expr: dict, key: str) -> str | None:
    match = expr.get("match")
    if not isinstance(match, dict):
        return None
    left = match.get("left") or {}
    payload = left.get("payload") or {}
    if payload.get("protocol") != "ip" or payload.get("field") != key:
        return None
    right = match.get("right")
    if isinstance(right, str):
        return right.strip()
    return None


def extract_counter_bytes(exprs: list[dict]) -> int | None:
    for expr in exprs:
        counter = expr.get("counter")
        if isinstance(counter, dict):
            return int(counter.get("bytes") or 0)
    return None


def load_prerouting_map() -> dict[int, dict]:
    # relay_port -> {"target_ip": str, "target_port": int, "bytes": int}
    result: dict[int, dict] = {}
    for item in nft_list_chain("ip", "nat", "prerouting"):
        rule = (item or {}).get("rule")
        if not rule:
            continue
        exprs = rule.get("expr") or []
        relay_port = None
        target_ip = None
        target_port = None
        bytes_count = extract_counter_bytes(exprs)
        for expr in exprs:
            port = extract_match_port(expr, "dport")
            if port is not None:
                relay_port = port
            dnat = expr.get("dnat")
            if isinstance(dnat, dict):
                target_ip = str(dnat.get("addr") or "").strip()
                try:
                    target_port = int(dnat.get("port") or 0)
                except (TypeError, ValueError):
                    target_port = 0
        if relay_port and target_ip and target_port and bytes_count is not None:
            result[int(relay_port)] = {
                "target_ip": target_ip,
                "target_port": int(target_port),
                "bytes": int(bytes_count),
            }
    return result


def load_forward_direction_counters() -> tuple[dict[str, int], dict[str, int]]:
    # key => "ip:port"
    up: dict[str, int] = {}
    down: dict[str, int] = {}
    for item in nft_list_chain("inet", "filter", "forward"):
        rule = (item or {}).get("rule")
        if not rule:
            continue
        exprs = rule.get("expr") or []
        bytes_count = extract_counter_bytes(exprs)
        if bytes_count is None:
            continue
        daddr = None
        dport = None
        saddr = None
        sport = None
        for expr in exprs:
            ip = extract_match_ip(expr, "daddr")
            if ip:
                daddr = ip
            ip = extract_match_ip(expr, "saddr")
            if ip:
                saddr = ip
            p = extract_match_port(expr, "dport")
            if p is not None:
                dport = p
            p = extract_match_port(expr, "sport")
            if p is not None:
                sport = p

        if daddr and dport:
            up[f"{daddr}:{dport}"] = int(bytes_count)
        if saddr and sport:
            down[f"{saddr}:{sport}"] = int(bytes_count)
    return up, down


def load_cache(path: str) -> dict:
    p = pathlib.Path(path)
    if not p.exists():
        return {}
    try:
        obj = json.loads(p.read_text(encoding="utf-8"))
        return obj if isinstance(obj, dict) else {}
    except Exception:
        return {}


def save_cache(path: str, prerouting_map: dict[int, dict], up_map: dict[str, int], down_map: dict[str, int]) -> None:
    p = pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "updated_at": int(time.time()),
        "prerouting": {str(k): int(v.get("bytes", 0)) for k, v in sorted(prerouting_map.items())},
        "forward_up": {k: int(v) for k, v in sorted(up_map.items())},
        "forward_down": {k: int(v) for k, v in sorted(down_map.items())},
    }
    p.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def delta(current: int, previous: int) -> int:
    if current < previous:
        return 0
    d = current - previous
    return d if d > 0 else 0


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

    prerouting_map = load_prerouting_map()
    if not prerouting_map:
        print("no nft prerouting rules with counters found")
        return 2
    up_map, down_map = load_forward_direction_counters()

    cache = load_cache(args.cache_file)
    prev_prerouting = cache.get("prerouting") if isinstance(cache.get("prerouting"), dict) else {}
    prev_up = cache.get("forward_up") if isinstance(cache.get("forward_up"), dict) else {}
    prev_down = cache.get("forward_down") if isinstance(cache.get("forward_down"), dict) else {}

    items: list[dict] = []
    matched_ports = 0
    for entry in relay_entries:
        name = entry["name"]
        relay_port = int(entry["relay_port"])
        service_name = service_by_name.get(name)
        if not service_name:
            continue
        pr = prerouting_map.get(relay_port)
        if not pr:
            continue
        matched_ports += 1
        target_key = f"{pr['target_ip']}:{pr['target_port']}"

        current_up = int(up_map.get(target_key, 0))
        current_down = int(down_map.get(target_key, 0))
        current_pr = int(pr.get("bytes", 0))

        d_up = delta(current_up, int(prev_up.get(target_key, current_up)))
        d_down = delta(current_down, int(prev_down.get(target_key, current_down)))
        # Fallback: if forward-chain counters absent, keep at least one-direction visibility.
        if d_up == 0 and d_down == 0:
            d_up = delta(current_pr, int(prev_prerouting.get(str(relay_port), current_pr)))

        if d_up <= 0 and d_down <= 0:
            continue
        items.append({"n": service_name, "u": int(d_up), "d": int(d_down)})

    save_cache(args.cache_file, prerouting_map, up_map, down_map)

    if matched_ports == 0:
        print("no relay ports matched nft prerouting counters")
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
