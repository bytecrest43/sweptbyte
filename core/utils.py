"""
utils.py — Shared utilities for SweptByte core modules.
Zero external dependencies — stdlib only.
"""

import os
import subprocess


# ── Size formatting ────────────────────────────────────────────

def human_size(num_bytes: int) -> str:
    """Convert bytes to a human-readable string (e.g. 4.2 GB)."""
    if num_bytes == 0:
        return "0 B"
    size = float(num_bytes)
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(size) < 1024.0:
            return f"{size:.1f} {unit}"
        size /= 1024.0
    return f"{num_bytes:.1f} PB"


def size_color(num_bytes: int) -> str:
    """Return ANSI color code based on size — gold < 100MB, amber < 1GB, red >= 1GB."""
    gb = num_bytes / (1024 ** 3)
    if gb >= 1.0:
        return "\033[91m"       # red
    elif gb >= 0.1:
        return "\033[38;5;220m" # bright gold
    else:
        return "\033[33m"       # gold


# ── Directory size ─────────────────────────────────────────────

def get_dir_size(path: str) -> int:
    """
    Return total size of a directory tree in bytes.
    Skips permission errors and broken symlinks silently.
    """
    total = 0
    try:
        with os.scandir(path) as it:
            for entry in it:
                try:
                    if entry.is_file(follow_symlinks=False):
                        total += entry.stat(follow_symlinks=False).st_size
                    elif entry.is_dir(follow_symlinks=False):
                        total += get_dir_size(entry.path)
                except (OSError, PermissionError):
                    continue
    except (OSError, PermissionError):
        pass
    return total


# ── Shell command runner ───────────────────────────────────────

REAL_HOME = os.environ.get("REAL_HOME", os.path.expanduser("~"))


def run_command(cmd: list[str]) -> tuple[str, int]:
    """
    Run a command without invoking a shell.
    Returns (stdout_stripped, returncode).
    """
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True
    )
    return result.stdout.strip(), result.returncode


# ── Path helpers ───────────────────────────────────────────────

SKIP_DIRS = frozenset([
    "/proc", "/sys", "/dev", "/run",
    "/snap", "/boot", "/lost+found",
])

def should_skip(path: str) -> bool:
    """Return True if a directory should be excluded from scanning."""
    return path in SKIP_DIRS or path.startswith("/proc/")

