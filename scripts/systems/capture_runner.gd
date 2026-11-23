extends Node
## Visual capture: a gameplay snippet (bot playing, HUD on) followed by the
## era's scripted camera shots (HUD off). Run through tools/capture.py, which
## adds --write-movie so every frame lands in captures/<era>/ as PNG.
##
## Shot format (EraBase.capture_shots()):
##   {"from": Vector3, "to": Vector3,          camera position and look-at target
##    "from2": Vector3, "to2": Vector3,        optional end pose (camera glides)
##    "time": 3.0, "fov": 60.0,
##    "setup": Callable,                       pose the world first (tide in, fire lit ...)
##    "name": "wide establishing"}

const SNIPPET_SECONDS := 12.0
const SETTLE_FRAMES := 10

var era: EraBase
var cam: Camera3D
var timeline: Array = []
var era_id := ""


func _ready() -> void:
	era_id = String(Game.user_args.get("capture", "greybox"))
	_run.call_deferred()


func _frame() -> int:
	return Engine.get_frames_drawn()


func _run() -> void:
	var scene: PackedScene = load(Game.era_scene(era_id))
	era = scene.instantiate()
	get_tree().root.add_child(era)
	await get_tree().process_frame
	# ---- gameplay snippet
	era.camera_rig.make_current()
	var bot := AutoPilot.new()
	era.add_child(bot)
	bot.start(era)
	var f0 := _frame()
	var t := 0.0
	var snippet := float(Game.user_args.get("snippet", SNIPPET_SECONDS))
	while t < snippet and not era.is_complete:
		await get_tree().process_frame
		t += get_process_delta_time()
	timeline.append({"name": "gameplay", "first": f0, "last": _frame(), "gameplay": true})
	# ---- flythrough
	bot.queue_free()
	era.bot = null
	era.player.input.clear()
	era.player.invulnerable = true
	era.chrono.glitches_enabled = false
	era.chrono.end_all_glitches()
	era.hud.set_ui_visible(false)
	era.hud.fade_to(0.0, 100.0)
	cam = Camera3D.new()
	cam.far = 4000.0
	cam.near = 0.1
	era.add_child(cam)
	cam.make_current()
	var shots: Array = era.capture_shots()
	var only := String(Game.user_args.get("shot", ""))
	for i in shots.size():
		var s: Dictionary = shots[i]
		var shot_name := String(s.get("name", "shot%d" % i))
		if only != "" and only != shot_name and only != str(i):
			continue
		if s.has("setup"):
			(s["setup"] as Callable).call()
		var from: Vector3 = s["from"]
		var to: Vector3 = s["to"]
		var from2: Vector3 = s.get("from2", from)
		var to2: Vector3 = s.get("to2", to)
		cam.fov = s.get("fov", 60.0)
		cam.global_position = from
		cam.look_at(to, Vector3.UP)
		for _k in SETTLE_FRAMES:
			await get_tree().process_frame
		var first := _frame()
		var dur: float = s.get("time", 3.0)
		var tt := 0.0
		while tt < dur:
			var k := smoothstep(0.0, 1.0, tt / dur)
			cam.global_position = from.lerp(from2, k)
			cam.look_at(to.lerp(to2, k), Vector3.UP)
			await get_tree().process_frame
			tt += get_process_delta_time()
		timeline.append({"name": shot_name, "first": first, "last": _frame(), "gameplay": false})
	var out := ProjectSettings.globalize_path("res://captures/%s" % era_id)
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out + "/shots.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"era": era_id, "shots": timeline,
		"viewport": [get_viewport().size.x, get_viewport().size.y]}, "  "))
	f.close()
	Telemetry.flush()
	get_tree().quit()
