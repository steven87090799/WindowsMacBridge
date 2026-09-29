#!/usr/bin/env python3
"""Bounded, privacy-preserving resource sample for the installed app.

Records process liveness, CPU time, RSS and occasional physical footprint only.
No keyboard events, clipboard data, window titles or document names are read.
"""

from __future__ import annotations

import argparse
import csv
import os
import plistlib
from pathlib import Path
import re
import subprocess
import time
from datetime import datetime, timezone


APP_PATH = "/Applications/WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge"
FINDER_PATH = "/Applications/WindowsMacBridge.app/Contents/PlugIns/WindowsMacBridgeFinderSync.appex/Contents/MacOS/WindowsMacBridgeFinderSync"
PHYSICAL_RE = re.compile(r"^Physical footprint:\s+(\S+)", re.MULTILINE)


def command(*args: str, timeout: int = 10) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)


def app_pid(executable: str = APP_PATH) -> int | None:
    pattern = f"^{re.escape(executable)}" + (r"( |$)" if executable == FINDER_PATH else "$" )
    result = command("pgrep", "-f", pattern)
    if result.returncode != 0:
        return None
    return int(result.stdout.splitlines()[0])


def cpu_seconds(value: str) -> float:
    days, separator, value_without_days = value.partition("-")
    day_seconds = int(days) * 86_400 if separator else 0
    value = value_without_days if separator else value
    parts = value.split(":")
    total = 0.0
    for part in parts:
        total = total * 60 + float(part)
    return total + day_seconds


def interval_cpu(previous: tuple[int, float, float] | None,
                 pid: int, elapsed: float, cpu: float) -> float | str:
    if previous is None or previous[0] != pid or elapsed <= previous[1] or cpu < previous[2]:
        return ""
    return round(100 * (cpu - previous[2]) / (elapsed - previous[1]), 4)


def system_sample() -> tuple[str | float, str | float, str | float]:
    """On-demand system context; top collects totals only, no process listing."""
    try:
        top = command("top", "-l", "1", "-n", "0", timeout=10).stdout
        cpu = re.search(r"CPU usage:\s+([\d.]+)% user,\s+([\d.]+)% sys", top)
        swap = command("sysctl", "-n", "vm.swapusage").stdout
        used = re.search(r"used\s*=\s*([\d.]+)M", swap)
        vm = command("vm_stat").stdout
        size = re.search(r"page size of (\d+) bytes", vm)
        compressed = re.search(r"Pages occupied by compressor:\s+(\d+)", vm)
        return (round(float(cpu[1]) + float(cpu[2]), 2) if cpu else "",
                float(used[1]) if used else "",
                round(int(size[1]) * int(compressed[1]) / 1_048_576, 2) if size and compressed else "")
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return "", "", ""


def sample(elapsed: float, footprint: bool, executable: str = APP_PATH) -> list[str | int | float]:
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    try:
        pid = app_pid(executable)
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
    parser.add_argument("--phase", default="unspecified", help="Label interaction, idle or another measured phase")
    parser.add_argument("--include-finder", action="store_true")
    parser.add_argument("--include-system", action="store_true", help="System totals only when footprint is sampled")
    args = parser.parse_args()
    if not 1 <= args.interval_seconds <= 3_600 or not 1 <= args.duration_seconds <= 86_400:
        parser.error("duration or interval outside bounded range")
    if not 1 <= args.footprint_every <= 1_000:
        parser.error("footprint frequency outside bounded range")

    args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    start = time.monotonic()
    deadline = start + args.duration_seconds
    previous: dict[str, tuple[int, float, float]] = {}
    identities: dict[int, tuple[str, str, str]] = {}
    with os.fdopen(fd, "w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["utc", "elapsed_s", "status", "pid", "cpu_time_s",
                         "rss_kib", "state", "physical_footprint", "role", "phase",
                         "installed_version", "installed_build", "installed_git_revision", "interval_cpu_percent",
                         "system_cpu_busy_percent", "system_swap_used_mib", "system_compressed_mib"])
        count = 0
        while True:
            now = time.monotonic()
            measure_footprint = count % args.footprint_every == 0 or now >= deadline
            system = system_sample() if args.include_system and measure_footprint else ("", "", "")
            roles = [("main", APP_PATH)] + ([("finder-extension", FINDER_PATH)] if args.include_finder else [])
            for role, executable in roles:
                row = sample(time.monotonic() - start, measure_footprint, executable)
                identity = ("", "", "")
                cpu_percent: str | float = ""
                if row[2] == "running":
                    pid, elapsed, cpu = int(row[3]), float(row[1]), float(row[4])
                    if pid not in identities:
                        try:
                            with open("/Applications/WindowsMacBridge.app/Contents/Info.plist", "rb") as info:
                                metadata = plistlib.load(info)
                            identities[pid] = tuple(str(metadata.get(key, "")) for key in
                                                    ("CFBundleShortVersionString", "CFBundleVersion", "WMBGitRevision"))
                        except (OSError, ValueError, plistlib.InvalidFileException):
                            identities[pid] = identity
                    identity = identities[pid]
                    cpu_percent = interval_cpu(previous.get(role), pid, elapsed, cpu)
                    previous[role] = (pid, elapsed, cpu)
                else:
                    previous.pop(role, None)
                writer.writerow(row + [role, args.phase, *identity, cpu_percent, *system])
            file.flush()
            count += 1
            if now >= deadline:
                break
            next_at = min(start + count * args.interval_seconds, deadline)
            time.sleep(max(0, next_at - time.monotonic()))


if __name__ == "__main__":
    main()
