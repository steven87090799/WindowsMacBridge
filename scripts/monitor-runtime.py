#!/usr/bin/env python3
"""Bounded, privacy-preserving resource sample for the installed app.

Records process liveness, CPU time, RSS and occasional physical footprint only.
No keyboard events, clipboard data, window titles or document names are read.
"""

from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path
import re
import subprocess
import time
from datetime import datetime, timezone


APP_PATH = "/Applications/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge"
PHYSICAL_RE = re.compile(r"^Physical footprint:\s+(\S+)", re.MULTILINE)


def command(*args: str, timeout: int = 10) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)


def app_pid() -> int | None:
    result = command("pgrep", "-f", f"^{re.escape(APP_PATH)}$")
    if result.returncode != 0:
        return None
    return int(result.stdout.splitlines()[0])


def cpu_seconds(value: str) -> float:
    parts = value.split(":")
    total = 0.0
    for part in parts:
        total = total * 60 + float(part)
    return total


def sample(elapsed: float, footprint: bool) -> list[str | int | float]:
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    try:
        pid = app_pid()
        if pid is None:
            return [timestamp, round(elapsed, 1), "down", "", "", "", "", ""]
        result = command("ps", "-p", str(pid), "-o", "time=,rss=,state=")
        fields = result.stdout.split()
        if result.returncode != 0 or len(fields) != 3:
            return [timestamp, round(elapsed, 1), "disappeared", pid, "", "", "", ""]
        cpu, rss, state = fields
        physical = ""
        if footprint:
            vmmap = command("vmmap", "-summary", str(pid), timeout=15)
            if vmmap.returncode == 0:
                match = PHYSICAL_RE.search(vmmap.stdout)
                physical = match.group(1) if match else ""
        return [timestamp, round(elapsed, 1), "running", pid,
                cpu_seconds(cpu), int(rss), state, physical]
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        return [timestamp, round(elapsed, 1), "sample_error", "", "", "", "", ""]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration-seconds", type=int, default=10_800)
    parser.add_argument("--interval-seconds", type=int, default=60)
    parser.add_argument("--footprint-every", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.interval_seconds <= 3_600 or not 1 <= args.duration_seconds <= 86_400:
        parser.error("duration or interval outside bounded range")
    if not 1 <= args.footprint_every <= 1_000:
        parser.error("footprint frequency outside bounded range")

    args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    start = time.time()
    deadline = start + args.duration_seconds
    with os.fdopen(fd, "w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["utc", "elapsed_s", "status", "pid", "cpu_time_s",
                         "rss_kib", "state", "physical_footprint"])
        count = 0
        while True:
            now = time.time()
            writer.writerow(sample(now - start, count % args.footprint_every == 0))
            file.flush()
            count += 1
            if now >= deadline:
                break
            next_at = min(start + count * args.interval_seconds, deadline)
            time.sleep(max(0, next_at - time.time()))


if __name__ == "__main__":
    main()
