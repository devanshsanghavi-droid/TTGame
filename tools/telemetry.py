#!/usr/bin/env python3
"""Summarise a telemetry log.

    python3 tools/telemetry.py greybox            # user://telemetry/test_greybox.jsonl
    python3 tools/telemetry.py greybox --from 10 --to 20 --every 0.5
    python3 tools/telemetry.py path/to/file.jsonl --kinds event,bot_fail

Prints every non-snapshot line, plus player snapshots thinned to --every seconds.
"""
import argparse, json, os, sys

def default_dir():
    home = os.path.expanduser("~")
    if sys.platform == "darwin":
        return os.path.join(home, "Library/Application Support/Godot/app_userdata/Fractured Hours/telemetry")
    if sys.platform.startswith("win"):
        return os.path.join(os.environ.get("APPDATA", home), "Godot/app_userdata/Fractured Hours/telemetry")
    return os.path.join(home, ".local/share/godot/app_userdata/Fractured Hours/telemetry")

ap = argparse.ArgumentParser()
ap.add_argument("log")
ap.add_argument("--from", dest="t0", type=float, default=0.0)
ap.add_argument("--to", dest="t1", type=float, default=1e9)
ap.add_argument("--every", type=float, default=2.0)
ap.add_argument("--kinds", default="")
ap.add_argument("--no-snaps", action="store_true")
a = ap.parse_args()
path = a.log if os.path.exists(a.log) else os.path.join(default_dir(), "test_%s.jsonl" % a.log)
kinds = set(k for k in a.kinds.split(",") if k)
last = -1e9
for line in open(path):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    t = d.get("t", 0)
    if t < a.t0 or t > a.t1:
        continue
    k = d.pop("kind", "?")
    if kinds and k not in kinds:
        continue
    if k == "snap":
        if a.no_snaps or t - last < a.every:
            continue
        last = t
        p = d.get("player", {})
        b = d.get("bot", {})
        print("%7.1f snap pos=%s %s spd=%.1f water=%.1f noise=%.2f meters=%s bot=%s/%s:%s '%s' glitch=%s ai=%s x=%s" % (
            t, p.get("pos"), p.get("state"), p.get("speed", 0), p.get("water", 0), p.get("noise", 0),
            {k2: round(v, 2) for k2, v in d.get("meters", {}).items()}, b.get("step"), b.get("of"), b.get("op"),
            b.get("label"), d.get("glitches"), json.dumps(d.get("ai", {}))[:160], json.dumps(d.get("x", {}))[:200]))
    else:
        d.pop("t", None)
        print("%7.1f %-14s %s" % (t, k, json.dumps(d)[:260]))
