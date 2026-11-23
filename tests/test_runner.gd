extends Node
## Loads each era, asserts a clean load, runs the AutoPilot through it and
## asserts: era completed in time, required objectives done, every required
## mechanic fired, 6+ events registered, no event type reused across eras,
## at least one CHRONO glitch, zero engine errors or warnings.

const MIN_EVENTS := 6
const WALL_CLOCK_LIMIT := 420.0

var results: Array = []
var seen_event_types := {}


func _ready() -> void:
	Game.mode = "test"
	Game.bot_enabled = true
	# Run faster than real time WITHOUT changing the simulation: Godot multiplies
	# the physics step by time_scale, so raising the tick rate by the same factor
	# keeps every physics step at exactly 1/60 s.
	var speed := maxi(1, int(Game.user_args.get("speed", "10")))
	Engine.physics_ticks_per_second = 60 * speed
	Engine.time_scale = float(speed)
	Engine.max_physics_steps_per_frame = 64
	_run.call_deferred()


func _run() -> void:
	var ids: Array = ["greybox"] + Game.era_ids()
	if Game.user_args.has("only"):
		ids = String(Game.user_args.only).split(",")
	var unit := await _unit_tests()
	results.append(unit)
	for id in ids:
		if not ResourceLoader.exists(Game.era_scene(id)):
			results.append({"id": id, "ok": false, "skipped": true, "problems": ["scene not built yet"], "time": 0.0})
			continue
		results.append(await _run_era(id))
	_report()


func _unit_tests() -> Dictionary:
	var problems: Array = []
	ErrorWatch.take()
	# mesh kit
	var rock := MeshKit.rock_mesh(1)
	if rock.get_surface_count() != 1:
		problems.append("rock_mesh produced no surface")
	var loft := MeshKit.loft_mesh(PackedVector3Array([Vector3.ZERO, Vector3.UP, Vector3(0, 2, 1)]), [0.3, 0.2, 0.1])
	if loft.get_aabb().size.y < 1.9:
		problems.append("loft_mesh has wrong bounds")
	# materials are never default grey
	var m := MatLib.pbr("rock_face_03")
	if m.albedo_texture == null or not m.normal_enabled:
		problems.append("MatLib.pbr returned a material without albedo/normal")
	# event director variants
	var types := {}
	for e in Game.ERAS:
		types[e.id] = true
	if types.size() != 8:
		problems.append("expected 8 eras, found %d" % types.size())
	# translation scramble changes text
	var ch := ChronoDevice.new()
	ch.translation_broken = true
	if ch.translate("Hello there traveller") == "Hello there traveller":
		problems.append("translation failure does not scramble text")
	ch.free()
	await get_tree().process_frame
	for e in ErrorWatch.take():
		problems.append("[%s] %s  %s" % [e.kind, e.msg, e.where])
	return {"id": "unit", "ok": problems.is_empty(), "problems": problems, "time": 0.0}


func _run_era(id: String) -> Dictionary:
	var res := {"id": id, "ok": false, "problems": [], "time": 0.0, "mechanics": {}, "events_fired": 0, "events": 0, "deaths": 0}
	var problems: Array = res.problems
	ErrorWatch.take()
	Telemetry.open("test_" + id)
	var wall0 := Time.get_ticks_msec()
	var scene: PackedScene = load(Game.era_scene(id))
	var era: Node = scene.instantiate()
	get_tree().root.add_child(era)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for e in ErrorWatch.take():
		problems.append("load [%s] %s  %s" % [e.kind, e.msg, e.where])
	if not (era is EraBase) or not (era as EraBase).is_ready:
		problems.append("scene root is not a ready EraBase")
		era.queue_free()
		return res
	var eb := era as EraBase
	res.load_ms = Time.get_ticks_msec() - wall0
	# ---- static checks
	res.events = eb.director.events.size()
	if eb.director.events.size() < MIN_EVENTS:
		problems.append("only %d events registered (need %d+)" % [eb.director.events.size(), MIN_EVENTS])
	var own := {}
	for t in eb.director.types():
		if own.has(t):
			problems.append("event type '%s' used twice in this era" % t)
		own[t] = true
		if seen_event_types.has(t) and seen_event_types[t] != id:
			problems.append("event type '%s' already used by era '%s'" % [t, seen_event_types[t]])
		seen_event_types[t] = id
	if eb.portal == null:
		problems.append("era has no portal")
	if eb.objectives.is_empty():
		problems.append("era has no objectives")
	if eb.chrono.glitch_pool.size() < 3:
		problems.append("glitch pool has %d entries (need 3+)" % eb.chrono.glitch_pool.size())
	if eb.autopilot_plan().is_empty():
		problems.append("era has no autopilot plan")
	# ---- bot run
	var bot := AutoPilot.new()
	eb.add_child(bot)
	bot.start(eb)
	while not eb.is_complete and bot.fail_reason == "" and eb.elapsed < eb.time_limit:
		await get_tree().physics_frame
		if (Time.get_ticks_msec() - wall0) / 1000.0 > WALL_CLOCK_LIMIT:
			problems.append("wall-clock limit hit at game time %.0fs" % eb.elapsed)
			break
	res.time = eb.elapsed
	res.deaths = eb.deaths
	res.mechanics = eb.mechanics.duplicate()
	res.events_fired = eb.director.fired.size()
	res.fired = eb.director.fired.duplicate()
	res.glitches = eb.chrono.stats.glitches.duplicate()
	res.bot_step = "%d/%d" % [bot.index, bot.plan.size()]
	if bot.fail_reason != "":
		problems.append("bot failed: " + bot.fail_reason)
	if not eb.is_complete:
		problems.append("era not completed (t=%.0fs of %.0fs, bot step %s, player at %s)" % [eb.elapsed, eb.time_limit, res.bot_step, str(eb.player.global_position.snapped(Vector3.ONE * 0.1))])
	if not eb.objectives_complete():
		var missing := []
		for o in eb.objectives:
			if not o.done and not o.optional:
				missing.append(o.id)
		problems.append("objectives not done: " + ", ".join(missing))
	for mech in eb.required_mechanics():
		if int(eb.mechanics.get(mech, 0)) <= 0:
			problems.append("mechanic never fired: " + str(mech))
	if int(eb.mechanics.get("glitch", 0)) <= 0:
		problems.append("no CHRONO glitch fired")
	if eb.director.fired.size() < mini(MIN_EVENTS, eb.director.events.size()) - 2:
		problems.append("only %d of %d events fired" % [eb.director.fired.size(), eb.director.events.size()])
	for e in ErrorWatch.take():
		problems.append("run [%s] %s  %s" % [e.kind, e.msg, e.where])
	res.telemetry = Telemetry.global_path()
	Telemetry.flush()
	Telemetry.set_era(null)
	era.queue_free()
	for i in 4:
		await get_tree().physics_frame
	for e in ErrorWatch.take():
		problems.append("unload [%s] %s  %s" % [e.kind, e.msg, e.where])
	res.wall = (Time.get_ticks_msec() - wall0) / 1000.0
	res.ok = problems.is_empty()
	return res


func _report() -> void:
	var failed := 0
	print("")
	print("================ FRACTURED HOURS TEST REPORT ================")
	for r in results:
		var status := "PASS"
		if r.get("skipped", false):
			status = "SKIP"
			failed += 1
		elif not r.ok:
			status = "FAIL"
			failed += 1
		print("%-5s %-14s game %6.1fs  wall %5.1fs  events %s/%s  deaths %s  bot %s" % [
			status, r.id, r.get("time", 0.0), r.get("wall", 0.0), str(r.get("events_fired", "-")),
			str(r.get("events", "-")), str(r.get("deaths", "-")), str(r.get("bot_step", "-"))])
		for p in r.problems:
			print("        - " + str(p))
		if r.has("telemetry") and not r.ok:
			print("        telemetry: " + str(r.telemetry))
	print("==============================================================")
	print("%d passed, %d failed" % [results.size() - failed, failed])
	var f := FileAccess.open("res://tests/last_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	get_tree().quit(1 if failed > 0 else 0)
