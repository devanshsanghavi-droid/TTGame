extends EraBase
## Developer test level. Exercises every shared system so the harness can
## verify the controller, CHRONO, the Event Director, dialogue and checkpoints
## before any real era depends on them.

var _gong_hit := false
var _talked := false
var _rock: Carryable
var _npc_talk: Interactable
var _lever: Interactable
var _test_drain := true


func _configure() -> void:
	era_id = "greybox"
	spawn_pos = Vector3(0, 3, 44)
	spawn_yaw = 0.0
	time_limit = 240.0


func _height(x: float, z: float) -> float:
	var h := 1.0 + sin(x * 0.08) * 0.4 + cos(z * 0.06) * 0.4
	# swim pool between z = -2 and z = -14
	var pool := clampf(1.0 - absf(z + 8.0) / 6.0, 0.0, 1.0) * clampf(1.0 - absf(x) / 9.0, 0.0, 1.0)
	h -= smoothstep(0.0, 0.5, pool) * 4.2
	return h


func _build_world() -> void:
	EnvKit.build(self, {"hdri": "kloppenheim_06_puresky", "fog_density": 0.006, "vol_density": 0.02})
	terrain = Terrain.create(self, {
		"size": 128.0, "res": 129, "chunks": 4, "height": _height,
		"a": "stony_dirt_path", "b": "rock_face_03", "c": "aerial_grass_rock",
		"color": func(x: float, z: float, _h: float, _s: float) -> Color: return Color(clampf(sin(x * 0.2) * cos(z * 0.17) + 0.4, 0.0, 1.0), 0, 0),
	})
	water_level = 0.4
	WaterKit.plane(self, Vector3(0, water_level, -8), Vector2(24, 18))
	var stone := MatLib.pbr("medieval_blocks_05", {"scale": 0.4})
	var b := BlockBatch.new()
	b.material = stone
	add_child(b)
	# 1. mantle ledge at z = 34 (1.6 m high, 5 m deep), side walls force the route
	b.add(Vector3(0, 1.8, 32), Vector3(14, 2.0, 5))
	b.wall(Vector3(-7.5, 0, 40), Vector3(-7.5, 0, 26), 5.0, 1.0)
	b.wall(Vector3(7.5, 0, 40), Vector3(7.5, 0, 26), 5.0, 1.0)
	# 2. crouch tunnel at z = 18..22: lintel 1.25 m above the ground
	b.wall(Vector3(-7.5, 0, 22), Vector3(-1.2, 0, 22), 4.0, 4.0)
	b.wall(Vector3(1.2, 0, 22), Vector3(7.5, 0, 22), 4.0, 4.0)
	b.add(Vector3(0, 3.6, 22), Vector3(2.4, 2.2, 4.0))
	# 4. climb wall at z = -22 (6 m), platform behind it
	b.add(Vector3(0, 3.6, -26), Vector3(12, 7.2, 8))
	b.wall(Vector3(-6.5, 0, -16), Vector3(-6.5, 0, -30), 9.0, 1.0)
	b.wall(Vector3(6.5, 0, -16), Vector3(6.5, 0, -30), 9.0, 1.0)
	b.commit()
	ClimbSurface.make(self, Vector3(0, 4.0, -22), 4.0, 6.6, 0.0)
	MatLib.decal(self, Vector3(0, 4, -21.9), Vector3(5, 6, 5), "moss")
	# 5. rock + gong on the platform
	var rock_vis := MeshKit.mi(MeshKit.rock_mesh(4, 2), MatLib.pbr("rock_06", {"scale": 1.2, "world": false}))
	rock_vis.scale = Vector3.ONE * 0.22
	_rock = Carryable.make(self, Vector3(1.5, 7.6, -25), "rock", rock_vis)
	var gong := StaticBody3D.new()
	gong.position = Vector3(-4, 8.6, -29.3)
	var gcs := CollisionShape3D.new()
	gcs.shape = MeshKit.box_shape(Vector3(2.4, 2.4, 0.3))
	gong.add_child(gcs)
	MeshKit.cyl(1.2, 1.2, 0.12, MatLib.metal("acg_bronze", Color(0.8, 0.6, 0.35), 0.4), Vector3.ZERO, gong).rotation.x = PI / 2
	gong.collision_layer = 1 | 4
	add_child(gong)
	_rock.impact.connect(func(pos: Vector3, _speed: float) -> void:
		emit_noise(pos, 30.0, 1.0, "rock")
		if pos.distance_to(gong.global_position) < 4.0 and not _gong_hit:
			_gong_hit = true
			mark("throw_hit")
			Sfx.play("bell", pos)
			complete_objective("gong"))
	# 6. stairs down behind the platform and an NPC
	var steps := BlockBatch.new()
	steps.material = stone
	add_child(steps)
	for i in 14:
		steps.add(Vector3(0, 7.2 - 0.5 * (i + 1) + 0.25 - 3.0, -30.5 - i * 0.9), Vector3(4, 6.5, 0.9))
	steps.commit()
	var npc := Humanoid.create({"top": ["rough_linen", Color(0.5, 0.42, 0.3)], "skirt": 0.5, "head": "hair", "beard": true})
	npc.position = on_ground(3.0, -48.0)
	npc.rotation.y = PI
	add_child(npc)
	_npc_talk = Interactable.make(self, npc.position + Vector3.UP, "Talk", _start_talk, 2.6)
	add_poi(_npc_talk, "Someone")
	portal = Portal.make(self, on_ground(0, -57))
	add_checkpoint(on_ground(0, 12, 1.0), 5.0, 1)
	add_checkpoint(on_ground(0, -18, 1.0), 5.0, 2)


func _setup() -> void:
	chrono.glitch_pool = ["gravity_flicker", "era_flash", "translation_failure", "time_stutter", "yell"]
	chrono.glitch_interval = Vector2(20, 30)
	add_meter("test", "Test meter", 1.0)
	add_objective("gong", "Throw the rock at the gong")
	add_objective("talk", "Talk to the stranger")
	director.add("ledge_hint", "gb_ledge", {"at": Vector3(0, 1, 38), "radius": 4.0},
		[["a", func() -> void: chrono.say("A ledge. Jump at it. Trust me, I have read about legs.")],
		 ["b", func() -> void: chrono.say("Ledge ahead. Humans go up these. Apparently.")]])
	director.add("tunnel_hint", "gb_tunnel", {"at": Vector3(0, 1, 25), "radius": 3.0},
		[["a", func() -> void: chrono.say("Low clearance. Crouch, or keep the concussion. Your choice.")]])
	director.add("pool_hint", "gb_pool", {"at": Vector3(0, 1, 0), "radius": 4.0},
		[["a", func() -> void: chrono.say("Water. I am rated to three metres. You are rated to worse.")]])
	director.add("timer", "gb_timer", {"time": 6.0}, [["a", func() -> void: mark("timed_event")], ["b", func() -> void: mark("timed_event")]])
	director.add("pred", "gb_predicate", {"when": func() -> bool: return player.counters.climb > 0},
		[["a", func() -> void: chrono.say("Climbing. Bold, for a species that invented stairs.")]])
	director.add("after_gong", "gb_chain", {"when": func() -> bool: return _gong_hit}, [["a", func() -> void: mark("chained_event")]], {"delay": 0.5})


func _start_talk(_p: Player) -> void:
	dialogue.start({
		"start": {"who": "Stranger", "text": "You fell out of the sky. Is that normal where you are from?", "goto": "q"},
		"q": {"who": "Stranger", "text": "Well?", "choices": [
			{"text": "Yes. Very normal.", "goto": "ok"},
			{"text": "My wrist did it.", "goto": "ok", "do": func() -> void: mark("choice_wrist")},
		]},
		"ok": {"who": "CHRONO", "text": "For the record, it was mostly my fault. Portal is that way.",
			"do": func() -> void:
				_talked = true
				complete_objective("talk")},
	})


func _era_process(delta: float) -> void:
	if _test_drain:
		set_meter("test", meter("test") - delta * 0.01)
		mark("meter_drain")
	if player.state == Player.State.SWIM:
		mark("swim")


func required_mechanics() -> Array:
	return ["swim", "throw_hit", "dialogue", "checkpoint", "chrono_scan", "chrono_rewind", "glitch:gravity_flicker",
		"glitch:era_flash", "glitch:translation_failure", "glitch:time_stutter", "glitch:yell", "meter_drain",
		"timed_event", "chained_event", "death", "noise_event", "event", "portal_entered"]


func autopilot_plan() -> Array:
	var AP := AutoPilot
	return [
		AP.label("mantle"),
		AP.goto(Vector3(0, 0, 35.2), {"direct": true, "tol": 0.8}),
		AP.drive(func(bot: AutoPilot, _d: float) -> bool:
			bot.player.input.world_move = Vector3.FORWARD
			if bot.player.is_on_floor() and bot.player.global_position.y < 2.0:
				bot.player.input.press("jump")
			return bot.player.global_position.y > 2.6 and bot.player.state == Player.State.GROUND, 12.0),
		AP.goto(Vector3(0, 0, 27), {"direct": true}),
		AP.label("crouch tunnel"),
		AP.goto(Vector3(0, 0, 24.6), {"direct": true, "tol": 0.5}),
		AP.goto(Vector3(0, 0, 19.0), {"direct": true, "crouch": true, "tol": 0.7}),
		AP.label("sprint and slide"),
		AP.drive(func(bot: AutoPilot, _d: float) -> bool:
			var inp := bot.player.input
			inp.world_move = Vector3.FORWARD
			inp.sprint = true
			inp.crouch = bot.player.horizontal_speed() > 7.0 and bot.player.is_on_floor()
			return bot.player.counters.slide > 0, 8.0),
		AP.wait(1.0),
		AP.press("scan"),
		AP.run(func() -> void: chrono.trigger_glitch("gravity_flicker")),
		AP.label("swim"),
		AP.goto(Vector3(0, 0, -17), {"direct": true, "tol": 1.0, "timeout": 40.0}),
		AP.run(func() -> void: chrono.trigger_glitch("time_stutter")),
		AP.label("rewind"),
		AP.wait(1.0),
		AP.press("rewind"),
		AP.until(func() -> bool: return chrono.stats.rewinds > 0, 5.0),
		AP.goto(Vector3(0, 0, -17), {"direct": true, "tol": 1.0, "timeout": 40.0}),
		AP.label("death and respawn"),
		AP.run(func() -> void: player.kill("test")),
		AP.until(func() -> bool: return player.alive, 10.0),
		AP.label("climb"),
		AP.goto(Vector3(0, 0, -21.0), {"direct": true, "tol": 0.6}),
		AP.climb(7.0),
		AP.label("throw"),
		AP.use(func() -> Node: return _rock),
		AP.goto(Vector3(-4, 0, -25.5), {"direct": true, "tol": 0.5, "ytol": 20.0}),
		AP.drive(func(bot: AutoPilot, _d: float) -> bool:
			bot.player.input.world_move = Vector3.FORWARD * 0.3
			return bot.step_time > 0.4, 3.0),
		AP.press("throw"),
		AP.until(func() -> bool: return _gong_hit, 6.0),
		AP.run(func() -> void: chrono.trigger_glitch("yell")),
		AP.run(func() -> void: chrono.trigger_glitch("era_flash")),
		AP.label("talk"),
		AP.goto(Vector3(0, 0, -31.5), {"direct": true, "tol": 0.8, "ytol": 20.0}),
		AP.goto(Vector3(0, 0, -45.0), {"direct": true, "tol": 1.0, "ytol": 20.0}),
		AP.run(func() -> void: chrono.trigger_glitch("translation_failure")),
		AP.use(func() -> Node: return _npc_talk),
		AP.choose(1),
		AP.until(func() -> bool: return _talked, 10.0),
		AP.label("portal"),
		AP.goto(func() -> Vector3: return portal.global_position, {"tol": 0.6}),
	]


func capture_shots() -> Array:
	return [
		{"from": Vector3(14, 9, 50), "to": Vector3(0, 2, 20), "from2": Vector3(10, 7, 40), "to2": Vector3(0, 2, 10), "time": 3.0},
		{"from": Vector3(-14, 6, 4), "to": Vector3(0, 3, -24), "time": 3.0},
		{"from": Vector3(8, 4, -44), "to": Vector3(0, 2, -57), "time": 3.0, "setup": func() -> void: open_portal()},
	]
