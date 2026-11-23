# FRACTURED HOURS

A 3D third-person adventure in Godot 4 (GDScript, Forward+). You are a time traveller whose
wrist AI, CHRONO, is malfunctioning. Each era, CHRONO predicts where the next portal opens.
Getting there is the game.

Eight eras: Cambrian tidal flats, Carboniferous swamp, Late Cretaceous, Pleistocene ice age,
Mohenjo-daro, Giza, Chola Thanjavur, medieval Europe.

## Setup

Requires Godot 4.7+ on PATH as `godot`, and Python 3 with Pillow.

```bash
python3 tools/fetch_assets.py      # CC0 textures, HDRIs, models (about 670 MB) + CREDITS.md
godot --headless --import          # first import (builds .godot/, a few minutes)
```

## Run

```bash
godot --path .                               # main menu
godot --path . -- --era=cambrian             # jump to an era
godot --path . -- --era=cambrian --autoplay  # watch the AutoPilot play it
```

Controls: WASD move, mouse look, Space jump (jump at ledges to climb), Shift sprint,
Ctrl/C crouch (while sprinting: slide), E interact, F or left mouse throw, Q scan,
R rewind 5 seconds, Tab lock-on, Esc pause. Gamepad is supported. Keys can be rebound in Settings.

## Test

```bash
godot --headless --path . -s tests/run_all.gd                        # everything, back to back
godot --headless --path . -s tests/run_all.gd -- --only=cambrian     # one era
```

For every era the runner loads the scene and asserts zero engine errors or warnings, then an
AutoPilot bot (NavigationAgent3D + scripted steps, driving the real player controller) must
finish the objectives and reach the portal inside the era's time limit. It also asserts that every
mechanic in `required_mechanics()` fired, 6+ events are registered, no event type is reused across
eras, and at least one CHRONO glitch fired. Exit code is 0 only if all pass. Results are also
written to `tests/last_report.json`.

Tests run 10x faster than real time with unchanged physics (600 ticks/s at time scale 10, so each
step is still 1/60 s).

### Telemetry

The `Telemetry` autoload writes JSON lines to `user://telemetry/` (player position and state,
meters, objectives, events, glitches, AI states, bot step, FPS, draw calls).

```bash
python3 tools/telemetry.py cambrian                  # summarise the last test run of an era
python3 tools/telemetry.py cambrian --from 40 --to 60 --every 0.5
```

## Capture

```bash
python3 tools/capture.py cambrian      # or: all
```

Runs a 12 second gameplay snippet plus the era's scripted camera shots through
`--write-movie` (PNG frames, real renderer; wrapped in `xvfb-run` on Linux) and writes
`captures/contact_sheet_<era>.png`. Review frames are kept as `captures/<era>/sel_*.png`.
On macOS the capture runs in the background with its window off-screen and unfocusable;
add `--foreground` to watch it.

## Performance

```bash
godot --path . -- --perf=all           # frame time, FPS, draw calls per era -> captures/perf.json
```

## Project layout

| Path | Contents |
|---|---|
| `scenes/eras/<era>/` | One scene per era (root node + era script; worlds are built in code) |
| `scripts/eras/` | `era_base.gd` and one script per era |
| `scripts/systems/` | Player, camera, CHRONO, Event Director, AutoPilot, telemetry, audio, portal |
| `scripts/kit/` | Builders: terrain, materials, meshes, lighting, water, people, creatures, foliage, FX |
| `scripts/ui/` | HUD, dialogue, menus |
| `shaders/` | Terrain splat, water, portal, glitch overlay, foliage |
| `assets/` | Fetched CC0 assets (not committed; see `CREDITS.md`) |
| `tests/`, `tools/` | Test runner, asset fetch, capture, telemetry viewer |

## Authoring an era

An era is a script extending `EraBase` (`scripts/eras/era_base.gd`) attached to the root of
`scenes/eras/<id>/<id>.tscn`. `scripts/eras/greybox.gd` is the smallest complete example;
`scripts/eras/cambrian.gd` is the quality bar.

Override:

| Hook | Purpose |
|---|---|
| `_configure()` | `era_id`, `spawn_pos`, `spawn_yaw`, `time_limit`, `flash_tint`, nav settings |
| `_build_world()` | Lighting (`EnvKit.build`), terrain, water, props, creatures, `portal = Portal.make(...)` |
| `_setup()` | Objectives, meters, glitch pool, Event Director events, intro lines |
| `_era_process(delta)` | Per-physics-frame logic. Use `wdelta(delta)` for world things so the time-stutter glitch slows them |
| `required_mechanics()` | Names that must be `mark()`ed during a bot run |
| `autopilot_plan()` | `AutoPilot` steps that complete the era |
| `capture_shots()` | Camera shots, each with an optional `setup` callable that poses the world |
| `water_height_at(pos)` | Water surface height (default: the global `water_level`) |
| `_on_era_flash(active)` | Gameplay effect of the 5 second era-flash glitch |
| `_on_respawn()` | Reset hazards after the player dies |

Rules every era follows:

- Call `mark("name")` whenever a mechanic actually fires. Tests assert on these.
- Register 6+ events with `director.add(id, type, trigger, variants)`. `type` strings must be
  unique across the whole game. Give events 2+ variants where it makes sense.
- Set `chrono.glitch_pool` (3+ entries). Add era-specific glitches with `chrono.register_glitch`.
- Survival meters exist only where needed: `add_meter(id, label)`, `set_meter(id, v)`.
- The route must change during the level. The portal opens when required objectives are done
  (`portal.auto_open`) or when you call `open_portal()`.
- No engine errors or warnings, ever. `ErrorWatch` counts them and the test fails.
- Materials: `MatLib.pbr(texture_name, opts)` only. No bare colours on large surfaces.

Useful kit calls:

```gdscript
EnvKit.build(self, {"hdri": "...", "fog_density": 0.006, "vol_density": 0.03, "grade_shadow": Color(...)})
terrain = Terrain.create(self, {"size": 384.0, "res": 257, "height": func(x, z): ..., "a": "tex", "b": "tex", "c": "tex"})
WaterKit.plane(self, Vector3(0, level, 0), Vector2(400, 400), {"clarity": 2.0})
var b := BlockBatch.new(); b.material = MatLib.pbr("sandstone_blocks_08"); add_child(b); b.wall(a, c, height, thickness); b.commit()
MeshKit.solid_rock(self, pos, scale, mat, seed)        # rock with convex collider
MeshKit.loft(points, radii, mat, parent)                # organic tube: limbs, necks, trunks, tusks
Humanoid.create({"skin": ..., "top": ["rough_linen", tint], "skirt": 0.5, "head": "turban"})
Interactable.make(parent, pos, "Prompt", func(player): ...)
Carryable.make(parent, pos, "rock", visual_node)
ClimbSurface.make(parent, face_center, width, height, rot_y)
CoverZone.make(parent, pos, size)
MatLib.decal(parent, pos, size, "moss")                 # grime, moss, sand, soot, damp, lichen, snow, ash
add_checkpoint(pos, radius, index); add_poi(node, "label")
emit_noise(pos, radius, loudness)                       # nodes in group "hearing" get hear(pos, loudness, source)
dialogue.start({"start": {"who": "...", "text": "...", "choices": [{"text": "...", "goto": "..."}]}})
chrono.say("line"); chrono.trigger_glitch("yell")
```

## Credits

See `CREDITS.md` for every third-party asset with source and licence.
