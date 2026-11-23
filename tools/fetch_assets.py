#!/usr/bin/env python3
"""Fetch every CC0 asset FRACTURED HOURS uses into assets/.

Sources: Poly Haven (textures, HDRIs, models), ambientCG (textures),
Kenney (audio), Google Fonts (one OFL font).

Idempotent: files already on disk are skipped. Writes assets/manifest.json
(used by the game for HDRI sun directions) and regenerates CREDITS.md.

    python3 tools/fetch_assets.py            # everything, 1k textures
    python3 tools/fetch_assets.py --res 2k   # sharper textures
    python3 tools/fetch_assets.py --only textures,hdris
"""
import argparse
import io
import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
UA = {"User-Agent": "fractured-hours-asset-fetch/1.0"}

# ---------------------------------------------------------------- asset lists
PH_TEXTURES = [
    # Cambrian
    "damp_beach_sand", "coast_sand_rocks_02", "low_tide_rocks", "rock_face_03",
    "dark_rock", "aerial_rocks_02", "coast_land_rocks_01", "dry_riverbed_rock",
    # Carboniferous
    "brown_mud_leaves_01", "mud_forest", "forest_floor", "bark_willow_02",
    "palm_tree_bark", "moss_wood", "burned_ground_01", "brown_mud_02",
    # Cretaceous
    "forest_ground_04", "forrest_ground_01", "pine_bark", "metasequoia_bark",
    "mossy_rock", "river_small_rocks", "leaves_forest_ground",
    # Pleistocene
    "snow_02", "snow_field_aerial", "snow_04", "rock_face_04", "lichen_rock",
    "rocks_ground_05", "cliff_side",
    # Indus
    "medieval_red_brick", "brown_brick_02", "brick_floor_003", "clay_plaster",
    "dry_ground_01", "mud_cracked_dry_03", "red_dirt_mud_01",
    # Egypt
    "sand_01", "aerial_sand", "large_sandstone_blocks", "sandstone_blocks_08",
    "white_sandstone_blocks_02", "sandstone_cracks", "clay_block_wall", "gravelly_sand",
    # Chola
    "granite_wall", "granite_tile_03", "red_sandstone_wall", "rock_pitted_mossy",
    "weathered_brown_planks", "wood_planks_grey", "fabric_pattern_05",
    # Medieval
    "castle_wall_slates", "medieval_blocks_05", "castle_brick_07", "cobblestone_floor_04",
    "thatch_roof_angled", "medieval_wood", "plastered_stone_wall", "brown_mud_03",
    "stony_dirt_path", "roof_slates_02", "aerial_grass_rock",
    # Shared
    "rusty_metal_02", "brown_leather", "rough_linen", "wool_boucle", "fabric_leather_02",
    "denim_fabric", "bark_brown_02", "rough_wood", "wood_planks", "rock_boulder_dry", "rock_06",
]

PH_HDRIS = [
    "kloofendal_misty_morning_puresky", "kloofendal_overcast_puresky",
    "kloofendal_48d_partly_cloudy_puresky", "qwantani_night_puresky",
    "qwantani_dusk_2_puresky", "snow_field_puresky", "qwantani_afternoon_puresky",
    "overcast_soil_puresky", "syferfontein_0d_clear_puresky", "qwantani_sunset_puresky",
    "belfast_sunset_puresky", "kloppenheim_06_puresky", "wasteland_clouds_puresky",
]

PH_MODELS = [
    "boulder_01", "rock_07", "rock_09", "rock_moss_set_01", "rock_moss_set_02",
    "coast_rocks_01", "coast_rocks_02", "coast_rocks_03", "coast_rocks_05",
    "coast_land_rocks_02", "coastal_cliff_01", "coastal_cliff_02",
    "namaqualand_boulder_02", "namaqualand_boulder_03", "namaqualand_boulder_05",
    "namaqualand_cliff_01", "stone_01", "sand_rocks_small_01", "rock_face_01",
    "fern_02", "grass_medium_01", "shrub_01", "shrub_03", "shrub_04", "nettle_plant",
    "island_tree_01", "island_tree_02",
    "dead_tree_trunk", "dead_tree_trunk_02", "tree_stump_01", "pine_roots",
    "root_cluster_01", "moss_01",
    "wooden_barrels_01", "wooden_crate_01", "wicker_basket_01", "ceramic_vase_01",
    "ceramic_vase_03", "brass_pot_01", "brass_diya_lantern", "brass_vase_01",
    "wooden_bucket_01", "kite_shield", "large_castle_door", "wooden_ladder",
    "treasure_chest", "stone_fire_pit", "wooden_axe", "antique_estoc",
]

# ambientCG: local name -> asset id
ACG_TEXTURES = {
    "acg_ice": "Ice002",
    "acg_snow": "Snow006",
    "acg_lava": "Lava004",
    "acg_bronze": "Metal008",
    "acg_charred_wood": "Wood026",
    "acg_fabric": "Fabric030",
}

KENNEY_PACKS = ["impact-sounds", "rpg-audio", "interface-sounds"]

FONT_DIRS = [("cormorantgaramond", "CormorantGaramond"), ("ebgaramond", "EBGaramond")]

# ------------------------------------------------------------------- helpers
credits = {"textures": [], "hdris": [], "models": [], "audio": [], "fonts": []}
manifest = {"textures": {}, "hdris": {}, "models": {}, "audio": {}, "fonts": {}}
problems = []
notes = []


def http(url, binary=True, timeout=120):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def get_json(url):
    return json.loads(http(url, binary=False))


def save(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = http(url)
    with open(path + ".part", "wb") as f:
        f.write(data)
    os.replace(path + ".part", path)
    return True


def write_import(path, normal=False):
    """Sidecar so Godot imports with mipmaps + VRAM compression from the first import."""
    imp = path + ".import"
    if os.path.exists(imp):
        return
    res = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
    with open(imp, "w") as f:
        f.write(
            '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
            '[deps]\n\nsource_file="%s"\n\n[params]\n\n'
            'compress/mode=2\ncompress/high_quality=%s\ncompress/lossy_quality=0.7\n'
            'compress/hdr_compression=1\ncompress/normal_map=%d\ncompress/channel_pack=0\n'
            'mipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=""\n'
            'process/fix_alpha_border=true\nprocess/premult_alpha=false\n'
            'process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n'
            'process/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n'
            % (res, "true" if normal else "false", 1 if normal else 0)
        )


def pick(d, keys):
    for k in keys:
        if k in d:
            return d[k]
    return None


# --------------------------------------------------------------- Poly Haven
def ph_texture(tid, res):
    out_dir = os.path.join(ASSETS, "textures", tid)
    try:
        files = get_json("https://api.polyhaven.com/files/" + tid)
    except Exception as e:
        problems.append("texture %s: %s" % (tid, e))
        return
    maps = {
        "diff": ["Diffuse", "diff", "Color", "col_01", "col_1", "coll1"],
        "nor": ["nor_gl", "Normal"],
        "arm": ["arm", "ARM"],
    }
    got = {}
    for short, keys in maps.items():
        entry = pick(files, keys)
        if not entry:
            continue
        r = entry.get(res) or entry.get("1k") or next(iter(entry.values()))
        fmt = "jpg" if "jpg" in r else ("png" if "png" in r else None)
        if not fmt:
            continue
        path = os.path.join(out_dir, "%s_%s.%s" % (tid, short, fmt))
        try:
            save(r[fmt]["url"], path)
            write_import(path, normal=(short == "nor"))
            got[short] = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
        except Exception as e:
            problems.append("texture %s/%s: %s" % (tid, short, e))
    if "arm" not in got:
        # Older assets ship AO and Rough separately: pack them.
        try:
            from PIL import Image
            rough = pick(files, ["Rough", "rough"])
            ao = pick(files, ["AO", "ao"])
            if rough:
                rr = rough.get(res) or rough.get("1k")
                rimg = Image.open(io.BytesIO(http(rr["jpg"]["url"]))).convert("L")
                if ao:
                    ar = ao.get(res) or ao.get("1k")
                    aimg = Image.open(io.BytesIO(http(ar["jpg"]["url"]))).convert("L").resize(rimg.size)
                else:
                    aimg = Image.new("L", rimg.size, 255)
                path = os.path.join(out_dir, "%s_arm.jpg" % tid)
                os.makedirs(out_dir, exist_ok=True)
                Image.merge("RGB", (aimg, rimg, Image.new("L", rimg.size, 0))).save(path, quality=92)
                write_import(path)
                got["arm"] = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
        except Exception as e:
            problems.append("texture %s/arm-pack: %s" % (tid, e))
    if "diff" in got:
        manifest["textures"][tid] = got
        credits["textures"].append((tid, "Poly Haven", "https://polyhaven.com/a/" + tid, "CC0 1.0"))
    else:
        problems.append("texture %s: no diffuse map found" % tid)


def sun_from_preview(jpg_bytes):
    """Brightest region of the equirect preview -> unit sun direction (Godot axes)."""
    from PIL import Image
    img = Image.open(io.BytesIO(jpg_bytes)).convert("L").resize((512, 256))
    px = img.load()
    best = max(px[x, y] for y in range(128) for x in range(512))
    sx = sy = n = 0.0
    # centroid of near-max pixels, handling the wrap seam with a circular mean
    cs = sn = 0.0
    for y in range(140):
        for x in range(512):
            if px[x, y] >= best - 6:
                a = x / 512.0 * math.tau
                cs += math.cos(a)
                sn += math.sin(a)
                sy += y
                n += 1
    theta = math.atan2(sn, cs) % math.tau
    v = (sy / n + 0.5) / 256.0
    y = math.cos(v * math.pi)
    r = math.sin(v * math.pi)
    return [round(r * math.sin(theta), 4), round(y, 4), round(-r * math.cos(theta), 4)]


def ph_hdri(hid, res):
    try:
        files = get_json("https://api.polyhaven.com/files/" + hid)
        entry = files["hdri"].get(res) or files["hdri"]["1k"]
        path = os.path.join(ASSETS, "hdri", hid + ".hdr")
        save(entry["hdr"]["url"], path)
        sun = [0.4, 0.6, 0.5]
        try:
            sun = sun_from_preview(http(files["tonemapped"]["url"]))
        except Exception as e:
            problems.append("hdri %s sun estimate: %s" % (hid, e))
        manifest["hdris"][hid] = {
            "path": "res://assets/hdri/%s.hdr" % hid,
            "sun": sun,
        }
        credits["hdris"].append((hid, "Poly Haven", "https://polyhaven.com/a/" + hid, "CC0 1.0"))
    except Exception as e:
        problems.append("hdri %s: %s" % (hid, e))


def ph_model(mid, res):
    try:
        files = get_json("https://api.polyhaven.com/files/" + mid)
        g = files["gltf"]
        entry = (g.get(res) or g.get("1k") or next(iter(g.values())))["gltf"]
        out_dir = os.path.join(ASSETS, "models", mid)
        save(entry["url"], os.path.join(out_dir, mid + ".gltf"))
        for rel, inc in entry.get("include", {}).items():
            p = os.path.join(out_dir, rel)
            save(inc["url"], p)
            low = rel.lower()
            if low.endswith((".jpg", ".png")):
                write_import(p, normal=("_nor" in low))
        manifest["models"][mid] = "res://assets/models/%s/%s.gltf" % (mid, mid)
        credits["models"].append((mid, "Poly Haven", "https://polyhaven.com/a/" + mid, "CC0 1.0"))
    except Exception as e:
        problems.append("model %s: %s" % (mid, e))


# ----------------------------------------------------------------- ambientCG
def acg_texture(local, aid, res):
    from PIL import Image
    out_dir = os.path.join(ASSETS, "textures", local)
    diff = os.path.join(out_dir, local + "_diff.jpg")
    entry = {
        "diff": "res://assets/textures/%s/%s_diff.jpg" % (local, local),
        "nor": "res://assets/textures/%s/%s_nor.jpg" % (local, local),
        "arm": "res://assets/textures/%s/%s_arm.jpg" % (local, local),
    }
    try:
        if not os.path.exists(diff):
            url = "https://ambientcg.com/get?file=%s_%s-JPG.zip" % (aid, res.upper())
            z = zipfile.ZipFile(io.BytesIO(http(url)))
            names = z.namelist()

            def find(suffix):
                for n in names:
                    if n.endswith(suffix):
                        return Image.open(io.BytesIO(z.read(n)))
                return None

            col = find("_Color.jpg")
            nor = find("_NormalGL.jpg")
            rough = find("_Roughness.jpg")
            ao = find("_AmbientOcclusion.jpg")
            metal = find("_Metalness.jpg")
            if col is None:
                raise RuntimeError("no colour map in zip")
            os.makedirs(out_dir, exist_ok=True)
            col.convert("RGB").save(diff, quality=92)
            if nor is not None:
                nor.convert("RGB").save(os.path.join(out_dir, local + "_nor.jpg"), quality=92)
            size = col.size
            r = rough.convert("L").resize(size) if rough is not None else Image.new("L", size, 180)
            a = ao.convert("L").resize(size) if ao is not None else Image.new("L", size, 255)
            m = metal.convert("L").resize(size) if metal is not None else Image.new("L", size, 0)
            Image.merge("RGB", (a, r, m)).save(os.path.join(out_dir, local + "_arm.jpg"), quality=92)
        for k in ("diff", "nor", "arm"):
            p = os.path.join(out_dir, "%s_%s.jpg" % (local, k))
            if os.path.exists(p):
                write_import(p, normal=(k == "nor"))
            else:
                entry.pop(k, None)
        manifest["textures"][local] = entry
        credits["textures"].append(("%s (%s)" % (local, aid), "ambientCG",
                                    "https://ambientcg.com/view?id=" + aid, "CC0 1.0"))
    except Exception as e:
        problems.append("ambientCG %s (%s): %s" % (local, aid, e))


# -------------------------------------------------------------------- Kenney
def kenney_pack(slug):
    out_dir = os.path.join(ASSETS, "audio", "kenney", slug)
    try:
        if not os.path.isdir(out_dir) or not os.listdir(out_dir):
            # Same request the site's own Download button makes: a signed, short-lived link.
            token = ("assets/" + slug).encode().hex()
            url = get_json("https://kenney.nl/download-link/" + token).get("url")
            if not url:
                raise RuntimeError("no download link returned")
            url = urllib.parse.urljoin("https://kenney.nl/", url)
            z = zipfile.ZipFile(io.BytesIO(http(url, timeout=300)))
            os.makedirs(out_dir, exist_ok=True)
            for n in z.namelist():
                if n.lower().endswith((".ogg", ".wav")):
                    with open(os.path.join(out_dir, os.path.basename(n)), "wb") as f:
                        f.write(z.read(n))
        files = sorted(f for f in os.listdir(out_dir) if f.lower().endswith((".ogg", ".wav")))
        manifest["audio"][slug] = ["res://assets/audio/kenney/%s/%s" % (slug, f) for f in files]
        credits["audio"].append((slug, "Kenney", "https://kenney.nl/assets/" + slug, "CC0 1.0"))
    except Exception as e:
        notes.append("kenney %s: %s. Kenney blocks scripted downloads; the game falls back to its "
                     "own synthesised effects. To use the pack, download it by hand from "
                     "https://kenney.nl/assets/%s and unzip the .ogg files into assets/audio/kenney/%s/"
                     % (slug, e, slug, slug))


# --------------------------------------------------------------------- fonts
def font():
    for folder, name in FONT_DIRS:
        try:
            listing = get_json("https://api.github.com/repos/google/fonts/contents/ofl/" + folder)
            ttfs = [e for e in listing if e["name"].endswith(".ttf") and "Italic" not in e["name"]]
            if not ttfs:
                continue
            path = os.path.join(ASSETS, "fonts", name + ".ttf")
            save(ttfs[0]["download_url"], path)
            manifest["fonts"]["serif"] = "res://assets/fonts/%s.ttf" % name
            credits["fonts"].append((name, "Google Fonts",
                                     "https://fonts.google.com/specimen/" + name, "SIL OFL 1.1"))
            return
        except Exception as e:
            problems.append("font %s: %s" % (folder, e))


# ------------------------------------------------------------------- credits
def write_credits():
    lines = [
        "# Credits",
        "",
        "FRACTURED HOURS is built in Godot Engine 4 (MIT licence).",
        "",
        "Every third-party asset is listed below with its source and licence. ",
        "All are fetched by `tools/fetch_assets.py`; none are modified beyond format ",
        "conversion and channel packing. Everything not listed here (creatures, people, ",
        "architecture, foliage cards, VFX, procedural audio beds) is generated in code ",
        "by this project.",
        "",
    ]
    titles = [("textures", "PBR textures"), ("hdris", "HDRI skies"), ("models", "3D models"),
              ("audio", "Audio"), ("fonts", "Fonts")]
    for key, title in titles:
        rows = sorted(set(credits[key]))
        lines += ["## %s (%d)" % (title, len(rows)), "", "| Asset | Source | Licence |", "|---|---|---|"]
        for name, src, url, lic in rows:
            lines.append("| [%s](%s) | %s | %s |" % (name, url, src, lic))
        lines.append("")
    with open(os.path.join(ROOT, "CREDITS.md"), "w") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--res", default="1k", choices=["1k", "2k", "4k"])
    ap.add_argument("--hdri-res", default="2k", choices=["1k", "2k", "4k"])
    ap.add_argument("--only", default="textures,hdris,models,acg,audio,fonts")
    args = ap.parse_args()
    only = set(args.only.split(","))
    jobs = []
    if "textures" in only:
        jobs += [(ph_texture, (t, args.res)) for t in PH_TEXTURES]
    if "hdris" in only:
        jobs += [(ph_hdri, (h, args.hdri_res)) for h in PH_HDRIS]
    if "models" in only:
        jobs += [(ph_model, (m, "1k")) for m in PH_MODELS]
    if "acg" in only:
        jobs += [(acg_texture, (k, v, args.res)) for k, v in ACG_TEXTURES.items()]
    if "audio" in only:
        jobs += [(kenney_pack, (p,)) for p in KENNEY_PACKS]
    if "fonts" in only:
        jobs += [(font, ())]
    print("fetching %d assets into %s" % (len(jobs), ASSETS))
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(fn, *a) for fn, a in jobs]
        for i, f in enumerate(futs):
            f.result()
            if (i + 1) % 20 == 0:
                print("  %d/%d" % (i + 1, len(jobs)))
    # merge with an existing manifest so partial --only runs do not lose entries
    mpath = os.path.join(ASSETS, "manifest.json")
    if os.path.exists(mpath):
        old = json.load(open(mpath))
        for k, v in old.items():
            if isinstance(v, dict):
                merged = dict(v)
                merged.update(manifest.get(k, {}))
                manifest[k] = merged
    # drop entries whose files are gone
    def on_disk(res_path):
        return os.path.exists(os.path.join(ROOT, res_path.replace("res://", "")))
    manifest["models"] = {k: v for k, v in manifest["models"].items() if on_disk(v)}
    manifest["hdris"] = {k: v for k, v in manifest["hdris"].items() if on_disk(v["path"])}
    manifest["textures"] = {k: v for k, v in manifest["textures"].items() if on_disk(v.get("diff", "x"))}
    os.makedirs(ASSETS, exist_ok=True)
    json.dump(manifest, open(mpath, "w"), indent=1, sort_keys=True)
    if only >= {"textures", "hdris", "models", "acg", "audio", "fonts"}:
        write_credits()
    print("done. textures=%d hdris=%d models=%d audio packs=%d fonts=%d" % (
        len(manifest["textures"]), len(manifest["hdris"]), len(manifest["models"]),
        len(manifest["audio"]), len(manifest["fonts"])))
    for n in notes:
        print("NOTE: " + n)
    if problems:
        print("PROBLEMS (%d):" % len(problems))
        for p in problems:
            print("  - " + p)
        sys.exit(1)


if __name__ == "__main__":
    main()
