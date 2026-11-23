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
## Hard stop so a broken run can never write frames forever.
const MAX_FRAMES := 2500

var era: EraBase
var cam: Camera3D
var timeline: Array = []
var era_id := ""

var _frame0 := 0
var _drawn0 := 0


## macOS stops rendering windows it considers hidden (off-screen, covered or
## minimised), so a background capture needs a window that is really visible.
## Shrink it to a thumbnail in the top-right corner, on top and unfocusable. The
## scene still renders at 1920x1080 (viewport stretch); only the preview is small.
static func park_window(win: Window) -> void:
	var game: Node = win.get_tree().root.get_node_or_null("Game")
	if OS.get_name() != "macOS" or game == null or not game.user_args.has("bg"):
		return
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_size = Vector2i(1920, 1080)
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.unfocusable = true
	win.always_on_top = true
	win.borderless = true
	var scr := DisplayServer.get_primary_screen()
	var origin := DisplayServer.screen_get_position(scr)
	var size := DisplayServer.screen_get_size(scr)
	win.size = Vector2i(128, 72)
	# several captures may run at once: stack the thumbnails instead of overlapping
	win.position = origin + Vector2i(size.x - 134, 34 + (OS.get_process_id() % 9) * 76)


func _ready() -> void:
	park_window(get_window())
	_frame0 = Engine.get_process_frames()
	_drawn0 = Engine.get_frames_drawn()
	era_id = String(Game.user_args.get("capture", "greybox"))
	_run.call_deferred()


## Movie frames are written once per process iteration, so index by those.
func _frame() -> int:
	return Engine.get_process_frames() - _frame0


var _forced := 0


func _process(delta: float) -> void:
	# If the OS says the window cannot draw (hidden, covered, app in the
	# background) the engine skips rendering and the movie would repeat a stale
	# frame. Render it ourselves so every written frame is real.
	if not DisplayServer.window_can_draw():
		RenderingServer.force_draw(false, delta)
		_forced += 1
	if _frame() > MAX_FRAMES:
		push_error("capture exceeded %d frames; aborting" % MAX_FRAMES)
		get_tree().quit(1)


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
	# shots pose the world themselves; scripted events must not undo the pose
	era.director.enabled = false
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
		"process_frames": _frame(), "drawn_frames": Engine.get_frames_drawn() - _drawn0 + _forced, "forced_frames": _forced,
		"viewport": [get_viewport().size.x, get_viewport().size.y]}, "  "))
	f.close()
	Telemetry.flush()
	get_tree().quit()
