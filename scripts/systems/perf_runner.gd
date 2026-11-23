extends Node
## Performance measurement: --perf=<era|all>. Renders the 3D scene at an
## internal 1920x1080, vsync off, bot playing, and logs frame time, FPS and
## draw calls per era to captures/perf.json.

const WARMUP := 4.0
const MEASURE := 12.0

var results := {}


func _ready() -> void:
	load("res://scripts/systems/capture_runner.gd").park_window(get_window())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	var arg := String(Game.user_args.get("perf", "all"))
	var ids: Array = Game.era_ids() if arg == "all" or arg == "1" else Array(arg.split(","))
	for id in ids:
		if not ResourceLoader.exists(Game.era_scene(id)):
			continue
		await _measure(id)
	var out := ProjectSettings.globalize_path("res://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out + "/perf.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("")
	print("era             avg ms   p99 ms   avg fps  draw calls  primitives   3D resolution")
	for id in results:
		var r: Dictionary = results[id]
		print("%-14s %7.2f  %7.2f  %8.1f  %10d  %10d   %s" % [id, r.avg_ms, r.p99_ms, r.avg_fps, r.draw_calls, r.primitives, r.resolution])
	get_tree().quit()


func _measure(id: String) -> void:
	var era: EraBase = (load(Game.era_scene(id)) as PackedScene).instantiate()
	get_tree().root.add_child(era)
	await get_tree().process_frame
	var vp := get_viewport()
	var win: Vector2i = get_window().size
	# internal 3D resolution of 1080 lines regardless of the window we were given
	var res_txt: String
	if get_window().content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
		vp.scaling_3d_scale = 1.0
		res_txt = "1920x1080"
	else:
		vp.scaling_3d_scale = clampf(1080.0 / float(win.y), 0.25, 2.0)
		res_txt = "%dx%d" % [int(win.x * vp.scaling_3d_scale), int(win.y * vp.scaling_3d_scale)]
	var bot := AutoPilot.new()
	era.add_child(bot)
	bot.start(era)
	era.player.invulnerable = true
	var t := 0.0
	while t < WARMUP:
		await get_tree().process_frame
		t += get_process_delta_time()
	var samples := PackedFloat32Array()
	var draws := 0.0
	var prims := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while (Time.get_ticks_usec() - t0) / 1e6 < MEASURE:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - last) / 1000.0)
		last = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	samples.sort()
	var sum := 0.0
	for s in samples:
		sum += s
	var n := maxi(samples.size(), 1)
	results[id] = {
		"avg_ms": sum / n, "p99_ms": samples[int(n * 0.99) - 1] if n > 1 else 0.0,
		"avg_fps": 1000.0 / maxf(sum / n, 0.001), "frames": n,
		"draw_calls": int(draws / n), "primitives": int(prims / n), "resolution": res_txt,
		"gpu": RenderingServer.get_video_adapter_name(), "quality": Game.settings.quality,
	}
	Telemetry.log_event("perf", results[id])
	era.queue_free()
	for i in 4:
		await get_tree().process_frame
