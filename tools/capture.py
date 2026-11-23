#!/usr/bin/env python3
"""Visual capture for FRACTURED HOURS.

Runs each era's gameplay snippet + scripted camera flythrough with Godot's
--write-movie (PNG frames), then builds captures/contact_sheet_<era>.png.

    python3 tools/capture.py cambrian           # one era
    python3 tools/capture.py all                # every era that exists
    python3 tools/capture.py cambrian --fps 12 --res 1280x720 --keep-frames
    python3 tools/capture.py cambrian --shot 2  # only one flythrough shot

On Linux the engine is wrapped in xvfb-run (a real renderer is still needed).
The frames kept for review are captures/<era>/sel_*.png.
"""
import argparse, glob, json, os, platform, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ERAS = ["cambrian", "carboniferous", "cretaceous", "pleistocene", "indus", "egypt", "chola", "medieval"]


def run_era(era, a):
    out = os.path.join(ROOT, "captures", era)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    cmd = [a.godot, "--path", ROOT, "--write-movie", os.path.join(out, "f.png"),
           "--fixed-fps", str(a.fps), "--resolution", a.res, "--", "--capture=" + era,
           "--snippet=%s" % a.snippet]
    if a.shot:
        cmd.append("--shot=" + a.shot)
    if platform.system() == "Linux" and shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1920x1080x24"] + cmd
    log = open(os.path.join(out, "godot.log"), "w")
    r = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=a.timeout)
    log.close()
    errs = [l.rstrip() for l in open(os.path.join(out, "godot.log"), errors="replace")
            if "ERROR" in l or "WARNING" in l]
    frames = sorted(glob.glob(os.path.join(out, "f*.png")))
    meta_path = os.path.join(out, "shots.json")
    if not frames or not os.path.exists(meta_path):
        print("[%s] capture FAILED (exit %s, %d frames). See %s" % (era, r.returncode, len(frames), log.name))
        return False
    meta = json.load(open(meta_path))
    picks = []
    for s in meta["shots"]:
        first, last = s["first"], min(s["last"], len(frames) - 1)
        n = 4 if s["gameplay"] else 2
        for i in range(n):
            k = (i + 0.7) / n if not s["gameplay"] else (i + 0.9) / n
            idx = min(max(int(first + (last - first) * k), 0), len(frames) - 1)
            picks.append((s["name"], idx))
    sheet(era, frames, picks, a)
    keep = set()
    for j, (name, idx) in enumerate(picks):
        dst = os.path.join(out, "sel_%02d_%s.png" % (j, name.replace(" ", "_")))
        shutil.copy(frames[idx], dst)
        keep.add(dst)
    if not a.keep_frames:
        for f in frames:
            os.remove(f)
        for w in glob.glob(os.path.join(out, "*.wav")):
            os.remove(w)
    print("[%s] %d frames, %d shots -> captures/contact_sheet_%s.png  (%d engine errors/warnings)" % (
        era, len(frames), len(meta["shots"]), era, len(errs)))
    for e in errs[:12]:
        print("    " + e[:200])
    return True


def sheet(era, frames, picks, a):
    from PIL import Image, ImageDraw
    cols = 4
    tw, th = 640, 360
    rows = (len(picks) + cols - 1) // cols
    img = Image.new("RGB", (cols * tw, rows * th), (12, 12, 12))
    d = ImageDraw.Draw(img)
    for j, (name, idx) in enumerate(picks):
        im = Image.open(frames[idx]).convert("RGB").resize((tw, th), Image.LANCZOS)
        x, y = (j % cols) * tw, (j // cols) * th
        img.paste(im, (x, y))
        d.rectangle([x, y + th - 20, x + 8 * len(name) + 70, y + th], fill=(0, 0, 0))
        d.text((x + 6, y + th - 17), "%s  #%d" % (name, idx), fill=(230, 225, 210))
    img.save(os.path.join(ROOT, "captures", "contact_sheet_%s.png" % era))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("eras", nargs="+")
    ap.add_argument("--fps", type=int, default=12)
    ap.add_argument("--res", default="1280x720")
    ap.add_argument("--snippet", default="12")
    ap.add_argument("--shot", default="")
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--keep-frames", action="store_true")
    a = ap.parse_args()
    eras = a.eras
    if eras == ["all"]:
        eras = [e for e in ERAS if os.path.exists(os.path.join(ROOT, "scenes", "eras", e, e + ".tscn"))]
    ok = True
    for e in eras:
        ok = run_era(e, a) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
