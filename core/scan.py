#!/usr/bin/env python3
"""
scan.py - Deep system intelligence for SweptByte.

Builds /tmp/sweptbyte-scan.json before cleaning so shell modules can make
targeted, data-driven cleanup decisions.
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any


SCAN_OUTPUT = None  # Set dynamically based on user home
MIN_LARGE_FILE = 100 * 1024 * 1024
SCAN_DEADLINE_SECONDS = 55
MAX_REPORTED_LARGE_FILES = 200
CLEANABLE_CATEGORIES = [
    "package_cache",
    "system_cache",
    "app_cache",
    "logs",
    "temp_files",
    "trash",
    "dev_cache",
    "docker",
    "snap",
    "flatpak",
]

R = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
GREY = "\033[90m"
GOLD = "\033[33m"
BRIGHT_GOLD = "\033[38;5;220m"
GREEN = "\033[38;5;178m"
SILVER = "\033[37m"
G_DIAMOND = "◆"


def run_command(cmd: list[str], timeout: int = 12, user: str | None = None) -> tuple[str, int]:
    if user and os.geteuid() == 0:
        cmd = ["sudo", "-u", user, *cmd]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip(), result.returncode
    except (OSError, subprocess.SubprocessError):
        return "", 1


def human_size(num_bytes: int) -> str:
    size = float(max(0, num_bytes))
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024 or unit == "TB":
            if unit == "B":
                return f"{size:.0f} B"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{num_bytes} B"


def real_user() -> str | None:
    return os.environ.get("SUDO_USER") or os.environ.get("USER")


def get_default_output() -> str:
    """Get user-specific output path for scan results."""
    home = os.path.expanduser("~")
    scan_dir = os.path.join(home, ".sweptbyte")
    return os.path.join(scan_dir, "scan.json")


def path_exists(path: str) -> bool:
    try:
        return os.path.exists(path)
    except OSError:
        return False


def file_count_and_size(path: str, deadline: float | None = None) -> tuple[int, int]:
    total = 0
    count = 0
    if not path_exists(path):
        return 0, 0

    if os.path.isfile(path) and not os.path.islink(path):
        try:
            return os.path.getsize(path), 1
        except OSError:
            return 0, 0

    for dirpath, dirnames, filenames in os.walk(path, topdown=True, followlinks=False):
        if deadline and time.monotonic() > deadline:
            break
        dirnames[:] = [
            d for d in dirnames
            if not should_skip_path(os.path.join(dirpath, d))
        ]
        for name in filenames:
            fpath = os.path.join(dirpath, name)
            try:
                st = os.stat(fpath, follow_symlinks=False)
            except (OSError, PermissionError):
                continue
            if not os.path.islink(fpath):
                total += st.st_size
                count += 1
    return total, count


def dir_size(path: str, deadline: float | None = None) -> int:
    size, _ = file_count_and_size(path, deadline)
    return size


def path_entry(path: str, include_count: bool = False, deadline: float | None = None) -> dict[str, Any]:
    size, count = file_count_and_size(path, deadline)
    entry: dict[str, Any] = {"path": path, "size_bytes": size, "exists": path_exists(path)}
    if include_count:
        entry["file_count"] = count
    return entry


def parse_mem_available_linux() -> tuple[int, bool]:
    meminfo = Path("/proc/meminfo")
    if not meminfo.exists():
        return 0, False
    try:
        for line in meminfo.read_text(errors="ignore").splitlines():
            if line.startswith("MemAvailable:"):
                kb = int(line.split()[1])
                available = kb * 1024
                return available, available < 512 * 1024 * 1024
    except (OSError, ValueError):
        pass
    return 0, False


def parse_mem_available_macos() -> tuple[int, bool]:
    pages_free = 0
    page_size = 4096
    out, code = run_command(["sysctl", "-n", "hw.pagesize"])
    if code == 0:
        try:
            page_size = int(out)
        except ValueError:
            pass

    out, code = run_command(["vm_stat"])
    if code == 0:
        for line in out.splitlines():
            if line.startswith(("Pages free", "Pages inactive", "Pages speculative")):
                numbers = re.findall(r"\d+", line)
                if numbers:
                    pages_free += int(numbers[0])

    available = pages_free * page_size
    return available, available < 512 * 1024 * 1024


def network_mounts() -> set[str]:
    mounts: set[str] = set()
    network_types = {"nfs", "nfs4", "cifs", "smbfs", "sshfs", "fuse.sshfs"}
    try:
        with open("/proc/mounts", "r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                parts = line.split()
                if len(parts) >= 3 and parts[2] in network_types:
                    mounts.add(parts[1].replace("\\040", " "))
    except OSError:
        pass
    return mounts


NETWORK_MOUNTS = network_mounts()
SKIP_PREFIXES = (
    "/proc", "/sys", "/dev", "/run", "/snap",
    "/lost+found", "/mnt", "/media", "/Volumes",
)


def should_skip_path(path: str) -> bool:
    try:
        real = os.path.realpath(path)
    except OSError:
        real = path
    if any(real == p or real.startswith(f"{p}/") for p in SKIP_PREFIXES):
        return True
    if any(real == p or real.startswith(f"{p}/") for p in NETWORK_MOUNTS):
        return True
    return False


def scan_package_cache(os_name: str, real_home: str, deadline: float) -> dict[str, Any]:
    paths: list[str] = []
    if os_name == "macos":
        for brew in ("/opt/homebrew/bin/brew", "/usr/local/bin/brew"):
            if os.path.exists(brew):
                out, code = run_command([brew, "--cache"], user=real_user())
                if code == 0 and out:
                    paths.append(out.splitlines()[0])
                break
    else:
        paths = [
            "/var/cache/apt/archives/",
            "/var/cache/pacman/pkg/",
            "/var/cache/dnf/",
            "/var/cache/apk/",
        ]

    entries = [path_entry(path, include_count=True, deadline=deadline) for path in paths if path_exists(path)]
    return {
        "size_bytes": sum(int(p["size_bytes"]) for p in entries),
        "file_count": sum(int(p.get("file_count", 0)) for p in entries),
        "paths": entries,
    }


def scan_system_cache(os_name: str, real_home: str, deadline: float) -> dict[str, Any]:
    paths = (
        ["/Library/Caches/", os.path.join(real_home, "Library/Caches/")]
        if os_name == "macos"
        else ["/var/cache/fontconfig/", "/var/cache/thumbnails/", os.path.join(real_home, ".cache/thumbnails/")]
    )
    entries = [path_entry(path, deadline=deadline) for path in paths if path_exists(path)]
    return {"size_bytes": sum(int(p["size_bytes"]) for p in entries), "paths": entries}


def scan_app_cache(os_name: str, real_home: str, deadline: float) -> dict[str, Any]:
    if os_name == "macos":
        rels = [
            ("Chrome", "Library/Caches/Google/Chrome"),
            ("Firefox", "Library/Caches/Firefox"),
            ("VS Code", "Library/Caches/com.microsoft.VSCode"),
            ("Slack", "Library/Caches/com.tinyspeck.slackmacgap"),
            ("Spotify", "Library/Caches/com.spotify.client"),
            ("Discord", "Library/Caches/com.hnc.Discord"),
            ("Teams", "Library/Caches/com.microsoft.teams"),
            ("Slack app cache", "Library/Application Support/Slack/Cache"),
            ("Discord app cache", "Library/Application Support/discord/Cache"),
        ]
    else:
        rels = [
            ("Chrome", ".cache/google-chrome"),
            ("Chromium", ".cache/chromium"),
            ("Firefox", ".cache/mozilla/firefox"),
            ("VS Code", ".cache/Code"),
            ("VS Code logs", ".config/Code/logs"),
            ("Slack", ".cache/slack"),
            ("Spotify", ".cache/spotify"),
            ("Discord", ".cache/discord"),
            ("Discord Cache", ".config/discord/Cache"),
            ("Teams", ".cache/teams"),
        ]

    apps = []
    for name, rel in rels:
        path = os.path.join(real_home, rel)
        apps.append({"name": name, "path": path, "size_bytes": dir_size(path, deadline), "exists": path_exists(path)})

    if os_name != "macos":
        for path in glob.glob(os.path.join(real_home, "snap/*/common/.cache")):
            apps.append({"name": "Snap app cache", "path": path, "size_bytes": dir_size(path, deadline), "exists": path_exists(path)})

    return {"apps": apps}


def scan_logs(os_name: str, real_home: str, deadline: float) -> dict[str, Any]:
    paths = ["/var/log/"]
    journal_usage = ""
    if os_name == "macos":
        paths.extend([os.path.join(real_home, "Library/Logs/"), "/Library/Logs/"])
    else:
        paths.append("/run/log/journal/")
        if shutil.which("journalctl"):
            journal_usage, _ = run_command(["journalctl", "--disk-usage"], timeout=8)

    entries = [path_entry(path, deadline=deadline) for path in paths if path_exists(path)]
    return {"size_bytes": sum(int(p["size_bytes"]) for p in entries), "paths": entries, "journal_disk_usage": journal_usage}


def scan_temp_files(os_name: str, real_home: str, deadline: float) -> dict[str, Any]:
    paths = ["/tmp/", "/var/tmp/"]
    if os_name == "macos":
        paths.extend(["/private/tmp/", os.environ.get("TMPDIR", "")])
    entries = [path_entry(path, deadline=deadline) for path in paths if path and path_exists(path)]
    return {"size_bytes": sum(int(p["size_bytes"]) for p in entries), "paths": entries}


def scan_trash(os_name: str, real_home: str, deadline: float) -> dict[str, Any]:
    path = os.path.join(real_home, ".Trash/" if os_name == "macos" else ".local/share/Trash/files/")
    entries = [path_entry(path, deadline=deadline)] if path_exists(path) else []
    return {"size_bytes": sum(int(p["size_bytes"]) for p in entries), "paths": entries}


def scan_dev_cache(os_name: str, real_home: str, deadline: float) -> dict[str, Any]:
    rels = [
        ("pip", ".cache/pip"),
        ("npm", ".npm/_cacache"),
        ("yarn", ".yarn/cache"),
        ("yarn", ".cache/yarn"),
        ("pnpm", ".local/share/pnpm/store"),
        ("cargo", ".cargo/registry"),
        ("gradle", ".gradle/caches"),
        ("maven", ".m2/repository"),
        ("go", "go/pkg/mod"),
        ("composer", ".composer/cache"),
    ]
    if os_name == "macos":
        rels.append(("pip", "Library/Caches/pip"))

    tools = []
    for name, rel in rels:
        path = os.path.join(real_home, rel)
        tools.append({"name": name, "path": path, "size_bytes": dir_size(path, deadline), "exists": path_exists(path)})
    return {"tools": tools}


def parse_size_string(value: str) -> int:
    match = re.search(r"([\d.]+)\s*([KMGT]?i?B|[KMGT]B|B)", value, re.I)
    if not match:
        return 0
    number = float(match.group(1))
    unit = match.group(2).upper().replace("IB", "B")
    multipliers = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3, "TB": 1024**4}
    return int(number * multipliers.get(unit, 1))


def scan_docker() -> dict[str, Any]:
    if not shutil.which("docker"):
        return {"available": False, "reclaimable_bytes": 0, "items": []}
    _, code = run_command(["docker", "info"], timeout=8)
    if code != 0:
        return {"available": False, "reclaimable_bytes": 0, "items": []}

    out, code = run_command(["docker", "system", "df", "--format", "json"], timeout=15)
    items: list[dict[str, Any]] = []
    total = 0
    if code == 0:
        for line in out.splitlines():
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            reclaimable = parse_size_string(str(item.get("Reclaimable", "")))
            total += reclaimable
            item["reclaimable_bytes"] = reclaimable
            items.append(item)
    return {"available": True, "reclaimable_bytes": total, "items": items}


def scan_snap(os_name: str, deadline: float) -> dict[str, Any]:
    if os_name == "macos" or not shutil.which("snap"):
        return {"available": False, "size_bytes": 0}
    path = "/var/lib/snapd/cache/"
    return {"available": path_exists(path), "size_bytes": dir_size(path, deadline), "path": path}


def scan_flatpak(os_name: str) -> dict[str, Any]:
    if os_name == "macos" or not shutil.which("flatpak"):
        return {"available": False, "reclaimable_bytes": 0}
    out, code = run_command(["flatpak", "list", "--runtime", "--columns=size"], timeout=15, user=real_user())
    total = 0
    if code == 0:
        for line in out.splitlines():
            total += parse_size_string(line)
    return {"available": True, "reclaimable_bytes": total}


def scan_large_files(os_name: str, deadline: float) -> dict[str, Any]:
    roots = ["/Users/", "/var/", "/tmp/"] if os_name == "macos" else ["/home/", "/root/", "/var/", "/tmp/", "/opt/"]
    files: list[dict[str, Any]] = []
    for root in roots:
        if not path_exists(root) or should_skip_path(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
            if time.monotonic() > deadline:
                break
            dirnames[:] = [
                d for d in dirnames
                if not should_skip_path(os.path.join(dirpath, d)) and d != ".git"
            ]
            for name in filenames:
                path = os.path.join(dirpath, name)
                try:
                    st = os.stat(path, follow_symlinks=False)
                except (OSError, PermissionError):
                    continue
                if st.st_size >= MIN_LARGE_FILE:
                    files.append({"path": path, "size_bytes": st.st_size})
                    files.sort(key=lambda item: int(item["size_bytes"]), reverse=True)
                    if len(files) > MAX_REPORTED_LARGE_FILES:
                        files.pop()
    files.sort(key=lambda item: int(item["size_bytes"]), reverse=True)
    return {"size_bytes": sum(int(item["size_bytes"]) for item in files), "files": files}


def scan_node_modules(real_home: str, deadline: float) -> dict[str, Any]:
    dirs: list[dict[str, Any]] = []
    if not path_exists(real_home):
        return {"dirs": dirs}
    for dirpath, dirnames, _ in os.walk(real_home, topdown=True, followlinks=False):
        if time.monotonic() > deadline:
            break
        dirnames[:] = [
            d for d in dirnames
            if d not in {".git", "__pycache__"} and not should_skip_path(os.path.join(dirpath, d))
        ]
        if "node_modules" in dirnames:
            path = os.path.join(dirpath, "node_modules")
            try:
                modified = dt.datetime.fromtimestamp(os.path.getmtime(path)).isoformat(timespec="seconds")
            except OSError:
                modified = ""
            dirs.append({"path": path, "size_bytes": dir_size(path, deadline), "last_modified": modified})
            dirnames.remove("node_modules")
    dirs.sort(key=lambda item: int(item["size_bytes"]), reverse=True)
    return {"dirs": dirs}


def scan_broken_symlinks(real_home: str) -> dict[str, Any]:
    roots = ["/usr/local/", "/usr/bin/", "/usr/lib/", real_home]
    broken: list[str] = []
    for root in roots:
        if not path_exists(root) or should_skip_path(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
            dirnames[:] = [d for d in dirnames if d != ".git" and not should_skip_path(os.path.join(dirpath, d))]
            for name in [*dirnames, *filenames]:
                path = os.path.join(dirpath, name)
                try:
                    if os.path.islink(path) and not os.path.exists(path):
                        broken.append(path)
                except OSError:
                    continue
    return {"paths": broken}


def scan_swap(skip_swap_clear: bool) -> dict[str, Any]:
    total = 0
    used = 0
    swaps = Path("/proc/swaps")
    if swaps.exists():
        try:
            for line in swaps.read_text(errors="ignore").splitlines()[1:]:
                parts = line.split()
                if len(parts) >= 5:
                    total += int(parts[2]) * 1024
                    used += int(parts[3]) * 1024
        except (OSError, ValueError):
            pass
    elif shutil.which("swapon"):
        out, code = run_command(["swapon", "--show", "--bytes", "--noheadings"])
        if code == 0:
            for line in out.splitlines():
                parts = line.split()
                if len(parts) >= 4:
                    try:
                        total += int(parts[2])
                        used += int(parts[3])
                    except ValueError:
                        continue
    return {"total_bytes": total, "used_bytes": used, "free_bytes": max(0, total - used), "skip_clear": skip_swap_clear}


def scan_kernels(os_name: str) -> dict[str, Any]:
    current, _ = run_command(["uname", "-r"])
    if os_name != "debian" or not shutil.which("dpkg"):
        return {"current": current, "removable": []}
    out, code = run_command(["dpkg", "-l", "linux-image-*"], timeout=15)
    removable = []
    if code == 0:
        for line in out.splitlines():
            if not line.startswith("ii"):
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            pkg = parts[1]
            if pkg == "linux-image-generic" or current in pkg:
                continue
            removable.append(pkg)
    return {"current": current, "removable": removable}


def recursive_size_sum(value: Any) -> int:
    if isinstance(value, dict):
        if "reclaimable_bytes" in value:
            return int(value.get("reclaimable_bytes", 0) or 0)
        if "size_bytes" in value:
            return int(value.get("size_bytes", 0) or 0)
        return sum(recursive_size_sum(child) for child in value.values())
    if isinstance(value, list):
        return sum(recursive_size_sum(item) for item in value)
    return 0


def cleanable_size(categories: dict[str, Any]) -> int:
    return sum(category_size(categories, name) for name in CLEANABLE_CATEGORIES)


def report_only_findings(categories: dict[str, Any]) -> dict[str, int]:
    large_files = categories.get("large_files", {})
    node_modules = categories.get("node_modules", {})
    return {
        "large_files_bytes": int(large_files.get("size_bytes", 0) or 0),
        "node_modules_bytes": sum(
            int(item.get("size_bytes", 0) or 0)
            for item in node_modules.get("dirs", [])
        ),
    }


def build_report(os_name: str, real_home: str, output: str) -> dict[str, Any]:
    deadline = time.monotonic() + SCAN_DEADLINE_SECONDS
    if os_name == "macos":
        _, skip_swap_clear = parse_mem_available_macos()
    else:
        _, skip_swap_clear = parse_mem_available_linux()

    categories = {
        "package_cache": scan_package_cache(os_name, real_home, deadline),
        "system_cache": scan_system_cache(os_name, real_home, deadline),
        "app_cache": scan_app_cache(os_name, real_home, deadline),
        "logs": scan_logs(os_name, real_home, deadline),
        "temp_files": scan_temp_files(os_name, real_home, deadline),
        "trash": scan_trash(os_name, real_home, deadline),
        "dev_cache": scan_dev_cache(os_name, real_home, deadline),
        "docker": scan_docker(),
        "snap": scan_snap(os_name, deadline),
        "flatpak": scan_flatpak(os_name),
        "large_files": scan_large_files(os_name, deadline),
        "node_modules": scan_node_modules(real_home, deadline),
        "broken_symlinks": scan_broken_symlinks(real_home),
        "swap": scan_swap(skip_swap_clear) if os_name != "macos" else {"total_bytes": 0, "used_bytes": 0, "skip_clear": True},
        "kernels": scan_kernels(os_name),
    }

    report = {
        "os": os_name,
        "real_home": real_home,
        "skip_swap_clear": skip_swap_clear,
        "restart_required": False,
        "categories": categories,
        "report_only": report_only_findings(categories),
        "total_reclaimable_bytes": cleanable_size(categories),
    }

    # Ensure output directory exists with proper permissions
    try:
        output_dir = os.path.dirname(output)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir, mode=0o755, exist_ok=True)
    except (OSError, PermissionError) as e:
        print(f"Warning: Could not create output directory: {e}", file=__import__('sys').stderr)

    # Write report with error handling
    try:
        with open(output, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
    except (OSError, PermissionError) as e:
        print(f"Error writing report to {output}: {e}", file=__import__('sys').stderr)
        print(f"Attempting to write to alternate location...", file=__import__('sys').stderr)
        # Fallback to /dev/null if all else fails (still completes the scan)
        try:
            alt_output = os.path.join(os.path.expanduser("~"), ".sweptbyte", "scan.json")
            os.makedirs(os.path.dirname(alt_output), mode=0o755, exist_ok=True)
            with open(alt_output, "w", encoding="utf-8") as fh:
                json.dump(report, fh, indent=2)
            print(f"Report written to: {alt_output}", file=__import__('sys').stderr)
        except Exception as fallback_error:
            print(f"Failed to write to fallback location: {fallback_error}", file=__import__('sys').stderr)

    return report


def category_size(categories: dict[str, Any], name: str) -> int:
    value = categories.get(name, {})
    if "size_bytes" in value:
        return int(value.get("size_bytes", 0) or 0)
    if name == "app_cache":
        return sum(int(app.get("size_bytes", 0) or 0) for app in value.get("apps", []))
    if name == "dev_cache":
        return sum(int(tool.get("size_bytes", 0) or 0) for tool in value.get("tools", []))
    if name in {"docker", "flatpak"}:
        return int(value.get("reclaimable_bytes", 0) or 0)
    if name == "large_files":
        return sum(int(item.get("size_bytes", 0) or 0) for item in value.get("files", []))
    if name == "node_modules":
        return sum(int(item.get("size_bytes", 0) or 0) for item in value.get("dirs", []))
    return 0


def names_present(items: list[dict[str, Any]], key: str = "name", limit: int = 4) -> str:
    names = [str(item.get(key, "")) for item in items if item.get("exists") and int(item.get("size_bytes", 0) or 0) > 0]
    return "  ".join(names[:limit])


def display_path(path: str, real_home: str) -> str:
    return path.replace(real_home, "~", 1) if path.startswith(real_home) else path


def print_summary(report: dict[str, Any]) -> None:
    c = report["categories"]
    real_home = report["real_home"]
    total = int(report["total_reclaimable_bytes"])
    app_names = names_present(c["app_cache"]["apps"])
    dev_names = names_present(c["dev_cache"]["tools"])
    large_files = c["large_files"]["files"]
    node_dirs = c["node_modules"]["dirs"]
    large_hint = "  ".join(display_path(f["path"], real_home) for f in large_files[:2])
    node_hint = "  ".join(display_path(d["path"], real_home) for d in node_dirs[:2])

    print()
    print(f"  {BRIGHT_GOLD}{G_DIAMOND} SCAN COMPLETE{R} {GREY}-{R} {GOLD}{BOLD}{human_size(total)}{R} {SILVER}reclaimable{R}")
    print()
    print(f"  {GREY}{'Package cache':<20}{R}{GOLD}{human_size(category_size(c, 'package_cache')):>10}{R}")
    print(f"  {GREY}{'App caches':<20}{R}{GOLD}{human_size(category_size(c, 'app_cache')):>10}{R}    {SILVER}{app_names}{R}")
    print(f"  {GREY}{'System caches':<20}{R}{GOLD}{human_size(category_size(c, 'system_cache')):>10}{R}")
    print(f"  {GREY}{'Journal logs':<20}{R}{GOLD}{human_size(category_size(c, 'logs')):>10}{R}")
    print(f"  {GREY}{'Temp files':<20}{R}{GOLD}{human_size(category_size(c, 'temp_files')):>10}{R}")
    print(f"  {GREY}{'Trash':<20}{R}{GOLD}{human_size(category_size(c, 'trash')):>10}{R}")
    print(f"  {GREY}{'Developer caches':<20}{R}{GOLD}{human_size(category_size(c, 'dev_cache')):>10}{R}    {SILVER}{dev_names}{R}")
    print(f"  {GREY}{'Docker':<20}{R}{GOLD}{human_size(category_size(c, 'docker')):>10}{R}")
    print(f"  {GREY}{'Large files':<20}{R}{GOLD}{len(large_files):>10} files{R}    {SILVER}{large_hint}{R}")
    print(f"  {GREY}{'node_modules':<20}{R}{GOLD}{len(node_dirs):>10} dirs{R}     {SILVER}{node_hint}{R}")
    print(f"  {GREY}{'Swap used':<20}{R}{GOLD}{human_size(int(c['swap'].get('used_bytes', 0) or 0)):>10}{R}")
    print(f"  {GREY}{'Kernels removable':<20}{R}{GOLD}{len(c['kernels'].get('removable', [])):>10}{R}")
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description="Deep SweptByte system scan")
    parser.add_argument("--os", dest="os_name", required=True)
    parser.add_argument("--real-home", required=True)
    parser.add_argument("--output", default=get_default_output())
    args = parser.parse_args()

    report = build_report(args.os_name, args.real_home, args.output)
    print_summary(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
