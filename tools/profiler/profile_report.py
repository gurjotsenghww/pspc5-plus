#!/usr/bin/env python3
"""
Performance Profiler Report Generator for PSPC5 Plus.
Analyzes runtime logs and diagnostic output to aggregate frame metrics:
- Frame times and instantaneous FPS
- GPU wait times and command submissions
- Staging buffer throughput and allocations
- Shader compilation and pipeline warmup latency
"""

import sys
import re
import json
from dataclasses import dataclass, asdict
from typing import List, Optional

@dataclass
class FrameStats:
    total_frames: int = 0
    min_frame_ms: float = float("inf")
    max_frame_ms: float = 0.0
    avg_frame_ms: float = 0.0
    avg_fps: float = 0.0
    total_gpu_wait_ms: float = 0.0
    staging_bytes: int = 0
    warmup_pipelines: int = 0

def analyze_log(log_path: str) -> Optional[FrameStats]:
    try:
        with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading {log_path}: {e}", file=sys.stderr)
        return None

    stats = FrameStats()
    frame_times: List[float] = []

    frame_re = re.compile(r"frame\s+time[:=]\s*([0-9.]+)\s*ms", re.IGNORECASE)
    flip_re = re.compile(r"flip\s+interval[:=]\s*([0-9.]+)\s*ms", re.IGNORECASE)
    gpu_wait_re = re.compile(r"gpu\s+wait[:=]\s*([0-9.]+)\s*ms", re.IGNORECASE)
    staging_re = re.compile(r"staging\s+([0-9]+)\s*distinct.*([0-9]+)\s*MiB", re.IGNORECASE)
    warmup_re = re.compile(r"warmup\s+complete:\s*compiled=([0-9]+)", re.IGNORECASE)

    for line in lines:
        m = frame_re.search(line) or flip_re.search(line)
        if m:
            ms = float(m.group(1))
            frame_times.append(ms)
            stats.min_frame_ms = min(stats.min_frame_ms, ms)
            stats.max_frame_ms = max(stats.max_frame_ms, ms)

        w = gpu_wait_re.search(line)
        if w:
            stats.total_gpu_wait_ms += float(w.group(1))

        st = staging_re.search(line)
        if st:
            stats.staging_bytes += int(st.group(2)) * 1024 * 1024

        wm = warmup_re.search(line)
        if wm:
            stats.warmup_pipelines += int(wm.group(1))

    if frame_times:
        stats.total_frames = len(frame_times)
        stats.avg_frame_ms = sum(frame_times) / len(frame_times)
        if stats.avg_frame_ms > 0:
            stats.avg_fps = 1000.0 / stats.avg_frame_ms
    else:
        stats.min_frame_ms = 0.0

    return stats

def main():
    if len(sys.argv) < 2:
        print("Usage: profile_report.py <log_file> [--json]")
        sys.exit(1)

    log_file = sys.argv[1]
    output_json = "--json" in sys.argv

    stats = analyze_log(log_file)
    if not stats:
        sys.exit(1)

    if output_json:
        print(json.dumps(asdict(stats), indent=2))
    else:
        print("=========================================")
        print("   PSPC5 Plus Performance Profile Report ")
        print("=========================================")
        print(f"Total Measured Frames:   {stats.total_frames}")
        print(f"Average Frame Time:      {stats.avg_frame_ms:.2f} ms ({stats.avg_fps:.2f} FPS)")
        print(f"Min / Max Frame Time:    {stats.min_frame_ms:.2f} ms / {stats.max_frame_ms:.2f} ms")
        print(f"Cumulative GPU Wait:     {stats.total_gpu_wait_ms:.2f} ms")
        print(f"Staged Buffer Memory:    {stats.staging_bytes / (1024*1024):.2f} MiB")
        print(f"Pipelines Compiled:      {stats.warmup_pipelines}")
        print("=========================================")

if __name__ == "__main__":
    main()
