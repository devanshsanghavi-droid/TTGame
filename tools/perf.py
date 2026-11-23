#!/usr/bin/env python3
"""Measure frame time, FPS and draw calls per era (3D rendered at 1920x1080).

    python3 tools/perf.py all            # every era -> captures/perf.json + table
    python3 tools/perf.py cambrian,egypt
    python3 tools/perf.py all --foreground   # macOS: visible window (most accurate)

On macOS the default is a background, off-screen window so it does not
interrupt you. The OS may throttle off-screen windows; if numbers look low,
re-run with --foreground.
"""
import argparse, json, os, platform, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("eras", nargs="?", default="all")
ap.add_argument("--godot", default="godot")
ap.add_argument("--foreground", action="store_true")
a = ap.parse_args()
log = os.path.join(ROOT, "captures", "perf.log")
os.makedirs(os.path.dirname(log), exist_ok=True)
args = ["--path", ROOT, "--resolution", "1920x1080", "--", "--perf=" + a.eras]
cmd = [a.godot] + args
if platform.system() == "Linux" and shutil.which("xvfb-run"):
    cmd = ["xvfb-run", "-a", "-s", "-screen 0 1920x1080x24"] + cmd
elif platform.system() == "Darwin" and not a.foreground:
    exe = os.path.realpath(shutil.which(a.godot) or a.godot)
    if "/Contents/MacOS/" in exe:
        cmd = ["open", "-g", "-n", "-W", "-a", exe.split("/Contents/MacOS/")[0], "--stdout", log, "--stderr", log,
               "--args"] + args + ["--bg=1"]
with open(log, "a") as f:
    subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, timeout=900)
res = json.load(open(os.path.join(ROOT, "captures", "perf.json")))
print("%-14s %8s %8s %8s %10s %11s  %s" % ("era", "avg ms", "p99 ms", "fps", "draw calls", "primitives", "3D res"))
for era, r in res.items():
    print("%-14s %8.2f %8.2f %8.1f %10d %11d  %s" % (era, r["avg_ms"], r["p99_ms"], r["avg_fps"], r["draw_calls"], r["primitives"], r["resolution"]))
if res:
    print("GPU:", next(iter(res.values()))["gpu"], "| quality:", next(iter(res.values()))["quality"])
