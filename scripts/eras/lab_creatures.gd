extends EraBase
## Lab level for the creature + NPC kit: one of every CreatureKit animal walking a
## path, every Outfits preset in a line-up, a crowd, a patrolling Npc, and an
## arthropleura the bot has to ride.

var _lineup: Array[Humanoid] = []
var _lineup_origin := Vector3.ZERO
var _lineup_dir := Vector3.RIGHT
var _lineup_face := Vector3.BACK
var _lineup_spacing := 1.15
var _crowd: Crowd
var _guard: Npc
var _noticed := false

var _c := {}                         # kind -> Creature
var _crawler: CreatureCrawler
var _rex: CreatureWalker
var _ptero: CreatureFlyer
var _riders: Array = []              # [Humanoid, mode]
var _ride_time := 0.0
var _ride_dist := 0.0
var _ride_walk := 0.0
var _ride_last := Vector3.ZERO
var _footfalls := 0
var _rex_heard := false
var _swooped := false


func _configure() -> void:
	era_id = "lab_creatures"
	spawn_pos = Vector3(-24, 3, 58)
	spawn_yaw = 0.0
	time_limit = 300.0
	nav_enabled = false


func _height(x: float, z: float) -> float:
	return 1.0 + sin(x * 0.031) * 0.7 + cos(z * 0.027) * 0.7 + sin((x + z) * 0.09) * 0.12


func _build_world() -> void:
	EnvKit.build(self, {"hdri": "kloofendal_48d_partly_cloudy_puresky", "fog_density": 0.0018, "vol_density": 0.006})
	terrain = Terrain.create(self, {
		"size": 384.0, "res": 193, "chunks": 8, "height": _height,
		"a": "stony_dirt_path", "b": "rock_face_03", "c": "aerial_grass_rock",
		"color": func(x: float, z: float, _h: float, _s: float) -> Color: return Color(clampf(sin(x * 0.11) * cos(z * 0.09) + 0.55, 0.0, 1.0), 0, 0),
	})
	# ---- people
	_build_lineup(on_ground(-21.5, 50), Vector3.RIGHT, Vector3.BACK)
	_build_crowd(on_ground(-34, 36), Vector2(12, 12), 40)
	_build_patrol([on_ground(24, 40), on_ground(38, 40)])
	# ---- creatures
	_crawler = _add("arthropleura", Vector3(-7, 0, 27), 0.0, [Vector3(7, 0, 27), Vector3(7, 0, 21), Vector3(-7, 0, 21), Vector3(-7, 0, 27)]) as CreatureCrawler
	_add("meganeura", Vector3(-14, 0, 22), 0.0, [], {"count": 12, "radius": 5.0})
	CreatureKit.spawn(self, "meganeura", on_ground(-22, 26), {"era": self, "count": 5, "radius": 1.5, "hover": 1.5, "seed": 3})
	_add("horse", Vector3(14, 0, 30), -PI * 0.5, [Vector3(30, 0, 30), Vector3(30, 0, 22), Vector3(14, 0, 22), Vector3(14, 0, 30)], {"caparison": true, "coat": "grey", "speed": 1.7})
	_add("ox", Vector3(-22, 0, 14), PI * 0.5, [Vector3(-40, 0, 14), Vector3(-40, 0, 6), Vector3(-22, 0, 6), Vector3(-22, 0, 14)], {"hump": true, "seed": 1})
	_add("cave_bear", Vector3(-30, 0, -8), PI * 0.5, [Vector3(-50, 0, -8), Vector3(-50, 0, -20), Vector3(-30, 0, -20), Vector3(-30, 0, -8)])
	_add("woolly_rhino", Vector3(-20, 0, -34), PI * 0.5, [Vector3(-48, 0, -34), Vector3(-48, 0, -50), Vector3(-20, 0, -50), Vector3(-20, 0, -34)])
	_add("elephant", Vector3(34, 0, 8), 0.0, [Vector3(34, 0, -14), Vector3(52, 0, -14), Vector3(52, 0, 8), Vector3(34, 0, 8)], {"howdah": true})
	_rex = _add("trex", Vector3(8, 0, -30), -PI * 0.5, [Vector3(40, 0, -30), Vector3(40, 0, -52), Vector3(8, 0, -52), Vector3(8, 0, -30)]) as CreatureWalker
	_add("mammoth", Vector3(-60, 0, -70), PI * 0.5, [Vector3(-110, 0, -70), Vector3(-110, 0, -110), Vector3(-60, 0, -110), Vector3(-60, 0, -70)])
	CreatureKit.herd(self, "mammoth", 3, [on_ground(-70, -86), on_ground(-120, -86), on_ground(-120, -130), on_ground(-70, -130)], true, {"era": self, "seed": 4})
	_add("sauropod", Vector3(40, 0, -100), -PI * 0.5, [Vector3(120, 0, -100), Vector3(120, 0, -150), Vector3(40, 0, -150), Vector3(40, 0, -100)])
	CreatureKit.herd(self, "sauropod", 2, [on_ground(60, -128), on_ground(130, -128), on_ground(130, -170), on_ground(60, -170)], true, {"era": self, "seed": 7})
	_ptero = CreatureKit.spawn(self, "quetzalcoatlus", on_ground(30, 0, 26.0), {"era": self}) as CreatureFlyer
	_ptero.circle(on_ground(0, 0), 42.0, 26.0)
	_c["quetzalcoatlus"] = _ptero
	# riders: a knight on the destrier, a soldier in the howdah
	_seat_rider(_c["horse"], Outfits.make("medieval_knight", 0), "ride")
	_seat_rider(_c["elephant"], Outfits.make("chola_soldier", 2), "sit_ground")
	# heavy feet shake the camera and thump
	for kind: String in ["trex", "sauropod", "mammoth", "elephant"]:
		var cr: Creature = _c[kind]
		cr.footfall.connect(_on_footfall.bind(cr))
	_rex.heard.connect(func(_pos: Vector3, _loud: float, _src: String) -> void:
		_rex_heard = true
		mark("creature_heard"))
	_ptero.swooped.connect(func(_pos: Vector3) -> void:
		_swooped = true
		mark("ptero_swoop"))
	portal = Portal.make(self, on_ground(0, 8))


func _add(kind: String, at: Vector3, yaw: float, path: Array, opts: Dictionary = {}) -> Creature:
	var o := opts.duplicate()
	o["era"] = self
	o["yaw"] = yaw
	var cr := CreatureKit.spawn(self, kind, on_ground(at.x, at.z), o)
	var pts: Array = []
	for p: Vector3 in path:
		pts.append(on_ground(p.x, p.z))
	if pts.size() > 0:
		cr.set_path(pts, true)
	_c[kind] = cr
	return cr


func _seat_rider(mount: Creature, rider: Humanoid, mode: String) -> void:
	var w := mount as CreatureWalker
	w.seat.add_child(rider)
	rider.position = Vector3(0, -0.9 if mode == "ride" else -0.5, 0)
	_riders.append([rider, mode])


func _on_footfall(pos: Vector3, weight: float, _cr: Creature) -> void:
	_footfalls += 1
	mark("footfall")
	var d := pos.distance_to(player.global_position)
	if d < 60.0:
		camera_rig.add_shake(weight * 0.35 / (1.0 + d * 0.12))
		Sfx.play("thud", pos, -6.0 - d * 0.2, 0.6)


# ------------------------------------------------------------------- people
func _build_lineup(origin: Vector3, dir: Vector3, face: Vector3, spacing := 1.15) -> void:
	_lineup_origin = origin
	_lineup_dir = dir.normalized()
	_lineup_face = face.normalized()
	_lineup_spacing = spacing
	var i := 0
	for outfit in Outfits.names():
		for s in 2:
			var h := Outfits.make(outfit, s)
			var p := origin + _lineup_dir * spacing * i
			h.position = on_ground(p.x, p.z)
			h.rotation.y = atan2(-_lineup_face.x, -_lineup_face.z)
			h.name = "%s_%d" % [outfit, s]
			add_child(h)
			_lineup.append(h)
			i += 1


func _animate_lineup(delta: float) -> void:
	for h in _lineup:
		h.animate(delta, 0.0, String(h.cfg.get("anim", "walk")))


func _lineup_shots(per_shot := 8, dist := 5.6, fov := 50.0, prefix := "lineup") -> Array:
	var shots: Array = []
	var n := _lineup.size()
	var k := 0
	while k < n:
		var last := mini(k + per_shot, n) - 1
		var mid := _lineup_origin + _lineup_dir * _lineup_spacing * (k + last) * 0.5
		mid = on_ground(mid.x, mid.z, 1.0)
		shots.append({"name": "%s%d" % [prefix, k / per_shot], "from": mid + _lineup_face * dist + Vector3.UP * 0.45, "to": mid, "time": 0.4, "fov": fov})
		k += per_shot
	return shots


func _build_crowd(center: Vector3, area: Vector2, count := 60) -> void:
	_crowd = Crowd.make(self, {"center": center, "size": area, "count": count, "seed": 11,
		"outfits": ["chola_devotee", "chola_devotee", "chola_artisan", "indus_citizen", "chola_drummer", "egypt_worker", "medieval_peasant", "indus_trader"]})
	_crowd.add_cover()


func _build_patrol(points: Array) -> void:
	_guard = Npc.make(self, points[0], "medieval_guard", {"seed": 2, "name": "Guard", "react": "look"})
	_guard.patrol(points, false)
	_guard.noticed.connect(func(_p: Player) -> void:
		_noticed = true
		mark("npc_noticed"))


# ---------------------------------------------------------------------- era
func _setup() -> void:
	chrono.glitch_pool = ["time_stutter", "yell", "gravity_flicker"]
	chrono.glitch_interval = Vector2(70, 100)
	add_objective("ride", "Ride the arthropleura")
	director.add("lineup", "labc_lineup", {"at": on_ground(-20, 53), "radius": 5.0},
		[["a", func() -> void: chrono.say("Nineteen wardrobes. None of them yours.")],
		 ["b", func() -> void: chrono.say("People, in rows. Do not touch the exhibits.")]])
	director.add("timer", "labc_timer", {"time": 4.0}, [["a", func() -> void: mark("timed_event")]])
	director.add("seen", "labc_seen", {"when": func() -> bool: return _noticed},
		[["a", func() -> void: chrono.say("The guard has noticed you. Look harmless. Harder.")]])
	director.add("ride", "labc_ride", {"when": func() -> bool: return _ride_time > 0.5},
		[["a", func() -> void: chrono.say("You are standing on an arthropod the length of a sofa. It has not noticed.")],
		 ["b", func() -> void: chrono.say("Public transport, Carboniferous edition. No timetable.")]])
	director.add("roar", "labc_rex_roar", {"when": func() -> bool: return _rex_heard},
		[["roar", func() -> void:
			_rex.roar()
			Sfx.play("roar", _rex.global_position)],
		 ["stare", func() -> void: _rex.look_at_target(player)]], {"delay": 0.6})
	director.add("swoop", "labc_swoop", {"time": 30.0},
		[["dive", func() -> void: _ptero.dive_at(player.global_position + Vector3(6, 6, 0))],
		 ["pass", func() -> void: _ptero.dive_at(on_ground(0, 24, 9.0))]])
	director.add("exit", "labc_exit", {"at": on_ground(0, 8), "radius": 6.0},
		[["a", func() -> void: chrono.say("Portal. Mind the wildlife on the way out.")]])
	_rex.look_at_target(player)
	Telemetry.log_event("creature_stats", CreatureKit.stats())


func _era_process(delta: float) -> void:
	var wd := wdelta(delta)
	_animate_lineup(wd)
	for r: Array in _riders:
		var h: Humanoid = r[0]
		if r[1] == "ride":
			CreatureKit.pose_rider(h, wd)
		else:
			h.animate(wd, 0.0, r[1])
	# riding: time on the back, how far the animal carried us, how much we walked ourselves
	var p := player.global_position
	if _crawler.is_carrying(player):
		if _ride_time > 0.0:
			_ride_dist += Vector2(p.x - _ride_last.x, p.z - _ride_last.z).length()
			_ride_walk += player.horizontal_speed() * delta
		_ride_time += delta
		_ride_last = p
		if _ride_time >= 3.0 and _ride_dist > 1.5 and _ride_dist > _ride_walk * 1.5:
			mark("ride_arthropleura")
			complete_objective("ride")
	elif _ride_time < 3.0:
		_ride_time = 0.0
		_ride_dist = 0.0
		_ride_walk = 0.0


func _telemetry_extra() -> Dictionary:
	return {"ride_t": _ride_time, "ride_dist": _ride_dist, "ride_walk": _ride_walk, "footfalls": _footfalls,
		"on_back": _crawler.is_carrying(player), "noticed": _noticed}


func required_mechanics() -> Array:
	return ["npc_noticed", "ride_arthropleura", "footfall", "creature_heard", "glitch:time_stutter", "event", "portal_entered"]


func _ride_drive(b: AutoPilot, _delta: float) -> bool:
	var inp := b.player.input
	var p := player.global_position
	var target := _crawler.back_point(0.45)
	var flat := Vector3(target.x - p.x, 0.0, target.z - p.z)
	var d := flat.length()
	if _crawler.is_carrying(player):
		inp.world_move = (flat * 2.0).limit_length(0.5)
	elif player.is_on_floor():
		inp.world_move = flat.normalized() * (1.0 if d > 2.6 else 0.3)
		if d < 1.0:
			inp.press("jump")
	else:
		inp.world_move = (flat * 1.5).limit_length(0.3)
	return objective_is_done("ride") and _ride_time >= 4.0


func autopilot_plan() -> Array:
	var AP := AutoPilot
	return [
		AP.label("walk the line-up"),
		AP.goto(on_ground(-21, 53), {"direct": true}),
		AP.goto(on_ground(22, 53), {"direct": true}),
		AP.label("get noticed"),
		AP.goto(on_ground(31, 43.5), {"direct": true, "tol": 0.8}),
		AP.until(func() -> bool: return _noticed, 40.0),
		AP.label("noise + stutter"),
		AP.run(func() -> void: emit_noise(player.global_position, 150.0, 1.0, "test")),
		AP.run(func() -> void: chrono.trigger_glitch("time_stutter")),
		AP.label("ride the arthropleura"),
		AP.goto(on_ground(0, 31), {"direct": true, "tol": 1.5}),
		AP.drive(_ride_drive, 120.0),
		AP.label("portal"),
		AP.goto(func() -> Vector3: return portal.global_position, {"direct": true, "tol": 0.6}),
	]


# ------------------------------------------------------------------ capture
## Puts a creature at the start of a straight run so the shot shows it mid-stride.
func _stage(kind: String, x: float, z: float, yaw: float) -> void:
	var cr: Creature = _c[kind]
	var pos := on_ground(x, z)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	director.enabled = false          # no swoops or roars while posing for the camera
	if cr is CreatureFlyer:
		pos.y += 14.0
		(cr as CreatureFlyer).warp(pos, yaw)
		cr.set_path([pos + fwd * 600.0], false)
		cr.speed = 2.0
		cr.cur_speed = 2.0
		return
	if cr.has_method("warp"):
		cr.call("warp", pos - fwd * 1.0, yaw)
	else:
		cr.global_position = pos
	if not (cr is CreatureSwarm):
		var far := pos + fwd * 300.0
		cr.set_path([on_ground(far.x, far.z)], false)
		cr.cur_speed = cr.speed


func _creature_shots(kind: String, x: float, z: float, hero: bool, yaw := -PI * 0.5) -> Array:
	var sz: Vector2 = CreatureKit.SIZES[kind]
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var side := Vector3(0, 0, 1) if absf(fwd.x) > 0.5 else Vector3(1, 0, 0)
	var cr: Creature = _c[kind]
	var adv := (2.2 if cr is CreatureFlyer else cr.speed * 1.1) - 1.0
	if cr is CreatureCrawler:
		adv -= 1.25
	var c := on_ground(x, z) + fwd * adv
	var up := 14.0 if kind == "quetzalcoatlus" else 0.0
	var len := sz.x if kind != "quetzalcoatlus" else 11.0
	var h := sz.y if kind != "quetzalcoatlus" else 3.0
	var setup := func() -> void: _stage(kind, x, z, yaw)
	var out: Array = [{"name": kind + "_side", "setup": setup, "time": 0.4, "fov": 45.0,
		"from": c + side * (len * 1.15 + 1.6) + Vector3.UP * (up + maxf(h * 0.4, 0.5)), "to": c + Vector3.UP * (up + h * 0.48)}]
	if hero:
		out.append({"name": kind + "_hero", "setup": setup, "time": 0.4, "fov": 62.0,
			"from": c + fwd * (len * 0.62 + 1.0) + side * (len * 0.28 + 0.8) + Vector3.UP * (0.5 + up * 0.2), "to": c + fwd * len * 0.1 + Vector3.UP * (up + h * 0.62)})
	return out


func capture_shots() -> Array:
	var shots: Array = []
	shots.append_array(_creature_shots("mammoth", 80, 90, true))
	shots.append_array(_creature_shots("elephant", 80, 60, true))
	shots.append_array(_creature_shots("woolly_rhino", 80, 30, true))
	shots.append_array(_creature_shots("cave_bear", 80, 10, false))
	shots.append_array(_creature_shots("horse", 80, -10, true))
	shots.append_array(_creature_shots("ox", 80, -25, false))
	shots.append_array(_creature_shots("trex", 90, -50, true))
	shots.append_array(_creature_shots("sauropod", 100, -90, true))
	shots.append_array(_creature_shots("quetzalcoatlus", -60, 20, true))
	shots.append_array(_creature_shots("arthropleura", -60, 60, false))
	var mg := on_ground(-22, 26, 1.5)
	shots.append({"name": "meganeura", "from": mg + Vector3(0.6, 0.2, 3.4), "to": mg, "time": 0.4, "fov": 50.0})
	shots.append({"name": "ride", "from": on_ground(-57, 63, 1.6), "to": on_ground(-61, 60, 0.6), "time": 1.0, "fov": 55.0,
		"setup": func() -> void:
			_stage("arthropleura", -58, 60, -PI * 0.5)
			player.teleport(_crawler.back_point(0.5) + Vector3.UP * 0.05)})
	shots.append({"name": "herds", "from": on_ground(-52, -66, 3.0), "to": on_ground(-78, -92, 2.5), "time": 0.5, "fov": 50.0,
		"setup": func() -> void: _stage("mammoth", -62, -80, PI * 0.5)})
	shots.append({"name": "scale", "from": on_ground(118, -84, 1.7), "to": on_ground(100, -90, 6.0), "time": 0.5, "fov": 70.0,
		"setup": func() -> void:
			_stage("sauropod", 100, -90, -PI * 0.5)
			player.teleport(on_ground(106, -84, 0.1))})
	shots.append_array(_lineup_shots(8, 5.4, 50.0, "lineup"))
	var cc := on_ground(-34, 36, 1.0)
	shots.append({"name": "crowd", "from": cc + Vector3(10, 4.0, 9), "to": cc, "time": 0.5})
	shots.append({"name": "guard", "from": on_ground(27, 44.5, 1.5), "to": on_ground(31.5, 41, 1.0), "time": 0.5, "fov": 55.0,
		"setup": func() -> void:
			player.teleport(on_ground(31, 43.5, 0.2))
			_guard.global_position = on_ground(29.5, 40)})
	# capture in short batches: `tools/capture.py lab_creatures --shot set0` .. set5
	# (a long off-screen run stops drawing on macOS after a few hundred frames)
	var sel := String(Game.user_args.get("shot", ""))
	if sel.begins_with("set"):
		var per := 6
		var n := int(sel.substr(3))
		var sub: Array = shots.slice(n * per, (n + 1) * per)
		var labels: Array = []
		for sh: Dictionary in sub:
			labels.append(sh.name)
			sh["name"] = sel
		print("SHOT_LABELS ", ",".join(labels))
		return sub
	return shots
