#!/usr/bin/env python3
"""Remove tmux-ai-necromancer debug logs without requiring tmux or a shell."""

from __future__ import annotations

import argparse
import os
import re
import time
from pathlib import Path


DEFAULT_LOG_DIR = Path.home() / ".tmux-ai-necromancer-logs"
DEFAULT_SNAPSHOT_DIR = Path.home() / ".claude" / "tmux-snapshots"

UNIT_SECONDS = {"d": 86400, "h": 3600, "m": 60, "s": 1}
DURATION_PART = re.compile(r"(\d+)([dhms])")


def path_from_env_or_default(env_name: str, default: Path) -> Path:
    return Path(os.environ.get(env_name, str(default))).expanduser()


def parse_duration(spec: str) -> int:
    """'7d' / '90m' / '1d12h30m' -> seconds. Mirrors the shell script's parser."""
    parts = DURATION_PART.findall(spec)
    if not parts or "".join(n + u for n, u in parts) != spec:
        raise argparse.ArgumentTypeError(
            f"not a duration: {spec} (expected e.g. 30m, 12h, 7d, 1d12h)"
        )
    total = sum(int(number) * UNIT_SECONDS[unit] for number, unit in parts)
    if total <= 0:
        raise argparse.ArgumentTypeError(f"duration must be positive: {spec}")
    return total


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Remove tmux-ai-necromancer debug logs."
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=path_from_env_or_default("NECROMANCER_LOG_DIR", DEFAULT_LOG_DIR),
        help="debug-log directory (default: %(default)s)",
    )
    parser.add_argument(
        "--snapshot-dir",
        type=Path,
        default=path_from_env_or_default(
            "NECROMANCER_SNAPSHOT_DIR", DEFAULT_SNAPSHOT_DIR
        ),
        help="snapshot directory containing autosave.log (default: %(default)s)",
    )
    parser.add_argument(
        "--older-than",
        type=parse_duration,
        metavar="SPEC",
        help="keep logs younger than SPEC (30m, 12h, 7d, 1d12h30m); "
        "default is to remove them all",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="show files without removing them"
    )
    return parser.parse_args()


def log_files(
    log_dir: Path, snapshot_dir: Path, max_age_seconds: int | None = None
) -> list[Path]:
    files: list[Path] = []
    if log_dir.is_dir():
        files.extend(sorted(path for path in log_dir.glob("*.log") if path.is_file()))
        files.extend(sorted(path for path in log_dir.glob("*.log.old") if path.is_file()))

    autosave_log = snapshot_dir / "autosave.log"
    if autosave_log.is_file():
        files.append(autosave_log)
    files = list(dict.fromkeys(files))

    if max_age_seconds is None:
        return files
    cutoff = time.time() - max_age_seconds
    return [path for path in files if path.stat().st_mtime <= cutoff]


def main() -> int:
    args = parse_args()
    log_dir = args.log_dir.expanduser()
    snapshot_dir = args.snapshot_dir.expanduser()
    files = log_files(log_dir, snapshot_dir, args.older_than)

    for path in files:
        if args.dry_run:
            print(f"Would remove: {path}")
        else:
            path.unlink()
            print(f"Removed: {path}")

    if not args.dry_run and log_dir.is_dir():
        try:
            log_dir.rmdir()
        except OSError:
            pass

    action = "Would remove" if args.dry_run else "Removed"
    print(f"{action} {len(files)} debug log file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
