#!/usr/bin/env python3
"""
report.py - Disk snapshot and per-category cleanup report for SweptByte.

Usage:
  python3 report.py --snapshot              -> prints USED_BYTES:TOTAL_BYTES
  python3 report.py --compare 'USED:TOTAL'  -> prints formatted cleanup report
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from typing import Any


SCAN_OUTPUT = "/tmp/sweptbyte-scan.json"

R = "\033[0m"
BOLD = "\033[1m"
GOLD = "\033[33m"
BRIGHT_GOLD = "\033[38;5;220m"
GREEN = "\033[38;5;178m"
GREY = "\033[90m"
SILVER = "\033[37m"
G_CHECK = "✔"
G_DIAMOND = "◆"
G_BAR = "─"
COLS = 72


def human_size(num_bytes: int) -> str:
    size = float(max(0, num_bytes))
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024 or unit == "TB":
            if unit == "B":
                return f"{size:.0f} B"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{num_bytes} B"


def snapshot() -> str:
    usage = shutil.disk_usage("/")
    return f"{usage.used}:{usage.total}"


def run_command(cmd: list[str], timeout: int = 10) -> tuple[str, int]:
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip(), result.returncode
    except (OSError, subprocess.SubprocessError):
        return "", 1


def get_dir_size(path: str) -> int:
    if not path or not os.path.exists(path):
        return 0
    if os.path.isfile(path) and not os.path.islink(path):
        try:
            return os.path.getsize(path)
        except OSError:
            return 0

    total = 0
    for dirpath, dirnames, filenames in os.walk(path, topdown=True, followlinks=False):
        dirnames[:] = [d for d in dirnames if d not in {".git"}]
        for name in filenames:
            fpath = os.path.join(dirpath, name)
            try:
                total += os.stat(fpath, follow_symlinks=False).st_size
            except (OSError, PermissionError):
                continue
    return total


def parse_size_string(value: str) -> int:
    match = re.search(r"([\d.]+)\s*([KMGT]?i?B|[KMGT]B|B)", value, re.I)
    if not match:
        return 0
    number = float(match.group(1))
    unit = match.group(2).upper().replace("IB", "B")
    multipliers = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3, "TB": 1024**4}
    return int(number * multipliers.get(unit, 1))


def load_scan() -> dict[str, Any] | None:
    try:
        with open(SCAN_OUTPUT, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None


def paths_from(entries: list[Any]) -> list[str]:
    paths = []
    for entry in entries:
        if isinstance(entry, dict) and entry.get("path"):
            paths.append(str(entry["path"]))
        elif isinstance(entry, str):
            paths.append(entry)
    return paths


def before_size(categories: dict[str, Any], key: str) -> int:
    data = categories.get(key, {})
    if key == "app_cache":
        return sum(int(app.get("size_bytes", 0) or 0) for app in data.get("apps", []))
    if key == "dev_cache":
        return sum(int(tool.get("size_bytes", 0) or 0) for tool in data.get("tools", []))
    if key in {"docker", "flatpak"}:
        return int(data.get("reclaimable_bytes", 0) or 0)
    return int(data.get("size_bytes", 0) or 0)


def docker_after_size() -> int:
    if not shutil.which("docker"):
        return 0
    _, code = run_command(["docker", "info"], timeout=6)
    if code != 0:
        return 0
    out, code = run_command(["docker", "system", "df", "--format", "json"], timeout=12)
    if code != 0:
        return 0
    total = 0
    for line in out.splitlines():
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        total += parse_size_string(str(item.get("Reclaimable", "")))
    return total


def after_size(categories: dict[str, Any], key: str) -> int:
    data = categories.get(key, {})
    if key == "app_cache":
        return sum(get_dir_size(str(app.get("path", ""))) for app in data.get("apps", []) if app.get("exists"))
    if key == "dev_cache":
        return sum(get_dir_size(str(tool.get("path", ""))) for tool in data.get("tools", []) if tool.get("exists"))
    if key == "docker":
        return docker_after_size()
    if key == "flatpak":
        return 0
    if key == "snap":
        return get_dir_size(str(data.get("path", "")))
    return sum(get_dir_size(path) for path in paths_from(data.get("paths", [])))


def fallback_compare(snapshot_str: str) -> None:
    parts = snapshot_str.split(":")
    if len(parts) != 2:
        print("report.py --compare: invalid snapshot format (expected USED:TOTAL)", file=sys.stderr)
        sys.exit(1)
    before_used = int(parts[0])
    before_total = int(parts[1])
    current = shutil.disk_usage("/")
    freed = max(0, before_used - current.used)

    print()
    print(f"{BRIGHT_GOLD}{'═' * COLS}{R}")
    print()
    print(f"  {BRIGHT_GOLD}{G_DIAMOND} DISK REPORT{R}")
    print()
    print(f"  {GREY}Before{R}        {GOLD}{human_size(before_used):>8}{R} used   ({human_size(before_total)} total)")
    print(f"  {GREY}After{R}         {GOLD}{human_size(current.used):>8}{R} used   ({human_size(current.total)} total)")
    print(f"  {GREY}Freed{R}         {GREEN}{human_size(freed):>8}{R}")
    print()
    print(f"  {GREEN}{G_CHECK}  System cleaned successfully.{R}")
    print()
    print(f"{BRIGHT_GOLD}{'═' * COLS}{R}")
    print()


def compare(snapshot_str: str) -> None:
    try:
        parts = snapshot_str.split(":")
        if len(parts) == 2:
            int(parts[0])
            int(parts[1])
    except ValueError:
        print("report.py --compare: snapshot must contain valid integers", file=sys.stderr)
        sys.exit(1)

    scan = load_scan()
    if not scan:
        fallback_compare(snapshot_str)
        return

    categories = scan.get("categories", {})
    rows = [
        ("Package cache", "package_cache"),
        ("App caches", "app_cache"),
        ("System caches", "system_cache"),
        ("Journal logs", "logs"),
        ("Temp files", "temp_files"),
        ("Trash", "trash"),
        ("Developer caches", "dev_cache"),
        ("Docker", "docker"),
        ("Snap", "snap"),
        ("Flatpak", "flatpak"),
    ]

    calculated = []
    for label, key in rows:
        before = before_size(categories, key)
        after = after_size(categories, key)
        if before == 0 and after == 0:
            continue
        calculated.append((label, before, after, max(0, before - after)))

    total_before = sum(row[1] for row in calculated)
    total_after = sum(row[2] for row in calculated)
    total_freed = max(0, total_before - total_after)

    print()
    print(f"{BRIGHT_GOLD}{'═' * COLS}{R}")
    print(f"  {BRIGHT_GOLD}{G_DIAMOND} DISK REPORT{R}")
    print()
    print(f"  {GREY}{'Category':<20}{R} {SILVER}{'Before':>10}{R}  {SILVER}{'After':>10}{R}  {SILVER}{'Freed':>10}{R}")
    print(f"  {GREY}{G_BAR * 54}{R}")
    for label, before, after, freed in calculated:
        print(
            f"  {GREY}{label:<20}{R} "
            f"{GOLD}{human_size(before):>10}{R}  "
            f"{GOLD}{human_size(after):>10}{R}  "
            f"{GREEN}{human_size(freed):>10}{R}"
        )
    print(f"  {GREY}{G_BAR * 54}{R}")
    print(
        f"  {BOLD}{GREY}{'Total':<20}{R} "
        f"{GOLD}{BOLD}{human_size(total_before):>10}{R}  "
        f"{GOLD}{BOLD}{human_size(total_after):>10}{R}  "
        f"{GREEN}{BOLD}{human_size(total_freed):>10}{R}"
    )
    print()
    print(f"  {GREEN}{G_CHECK}  System cleaned successfully.{R}")
    print(f"{BRIGHT_GOLD}{'═' * COLS}{R}")
    print()


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--snapshot" in args:
        print(snapshot())
    elif "--compare" in args:
        idx = args.index("--compare") + 1
        if idx >= len(args):
            print("report.py --compare: missing snapshot argument", file=sys.stderr)
            sys.exit(1)
        compare(args[idx])
    else:
        print("Usage: report.py --snapshot | --compare 'USED:TOTAL'", file=sys.stderr)
        sys.exit(1)
