extends EraBase
## Scratch level for the people kit: every Outfits preset in a line-up, a milling
## Crowd with a cover zone, a loop-walking work gang, and Npcs that patrol, work,
## sit, talk, notice the player, hear noise, chase and lose track again.
## The _build_* functions are self-contained so other levels can copy them.

var _lineup: Array[Humanoid] = []
var _lineup_origin := Vector3.ZERO
var _lineup_dir := Vector3.RIGHT
var _lineup_face := Vector3.BACK
var _lineup_spacing := 1.15
var _crowd: Crowd
var _gang: Crowd
var _guard: Npc
var _chaser: Npc
var _noticed := false
var _alerted := false
var _lost := false
var _heard := false
var _caught := false


func _configure() -> void:
	era_id = "lab_people"
	spawn_pos = Vector3(-24, 3, 36)
	spawn_yaw = 0.0
	time_limit = 240.0


func _height(x: float, z: float) -> float:
	return 1.0 + sin(x * 0.05) * 0.3 + cos(z * 0.045) * 0.3


func _build_world() -> void:
	EnvKit.build(self, {"hdri": "kloofendal_48d_partly_cloudy_puresky", "fog_density": 0.003, "vol_density": 0.01})
	terrain = Terrain.create(self, {
		"size": 128.0, "res": 129, "chunks": 4, "height": _height,
		"a": "stony_dirt_path", "b": "rock_face_03", "c": "aerial_grass_rock",
		"color": func(x: float, z: float, _h: float, _s: float) -> Color: return Color(clampf(sin(x * 0.2) * cos(z * 0.17) + 0.4, 0.0, 1.0), 0, 0),
	})
	_build_lineup(on_ground(-21.5, 28), Vector3.RIGHT, Vector3.BACK)
	_build_crowd(on_ground(-14, 4), Vector2(14, 14), 150 if Game.user_args.has("stress") else 60)
	_build_gang([on_ground(6, -8), on_ground(22, -8), on_ground(22, -16), on_ground(6, -16)], 18)
	_build_patrol([on_ground(8, 14), on_ground(22, 14)])
	_build_chaser(on_ground(14, -2))
	_build_workers(on_ground(0, 12))
	if Game.user_args.has("stress"):
		for i in 24:
			var p := on_ground(-30.0 + (i % 8) * 8.0, -22.0 - (i / 8) * 5.0)
			Npc.make(self, p, Outfits.NAMES[i % Outfits.NAMES.size()], {"seed": i, "name": "Stress%d" % i}).wander(p, 4.0)
	portal = Portal.make(self, on_ground(0, -30))


# ------------------------------------------------------------ copyable builders
## Every outfit preset, two seeds each (a man and a woman where the preset has both),
## shoulder to shoulder along `dir`, looking toward `face`.
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


## Call every frame: breathing idle, and the drummer / artisan do their thing.
func _animate_lineup(delta: float) -> void:
	for h in _lineup:
		h.animate(delta, 0.0, String(h.cfg.get("anim", "walk")))


## Camera shots that cover the whole line-up, `per_shot` people at a time.
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


## A milling crowd that also hides the player.
func _build_crowd(center: Vector3, area: Vector2, count := 60) -> void:
	_crowd = Crowd.make(self, {"center": center, "size": area, "count": count, "seed": 11,
		"outfits": ["chola_devotee", "chola_devotee", "chola_artisan", "chola_devotee", "chola_drummer", "chola_sailor", "chola_devotee", "chola_artisan"]})
	_crowd.add_cover()


## A work gang walking a closed loop in a loose file.
func _build_gang(loop: Array, count := 18) -> void:
	_gang = Crowd.make(self, {"loop": loop, "count": count, "seed": 5, "speed": 1.1, "spread": 0.7,
		"outfits": ["egypt_worker"], "variants": 6})


## A guard walking back and forth who notices the player (look, do not chase).
func _build_patrol(points: Array) -> void:
	_guard = Npc.make(self, points[0], "medieval_guard", {"seed": 2, "name": "Guard", "react": "look",
		"solid": Game.user_args.has("solid"), "ray_ground": Game.user_args.has("solid")})
	_guard.patrol(points, false)
	_guard.noticed.connect(func(_p: Player) -> void:
		_noticed = true
		mark("npc_noticed")
		complete_objective("noticed"))
	_guard.alerted.connect(func(_p: Player) -> void:
		_alerted = true
		mark("npc_alerted"))
	_guard.lost.connect(func(_p: Player) -> void:
		_lost = true
		mark("npc_lost"))
	_guard.heard.connect(func(_pos: Vector3, _loud: float, _src: String) -> void:
		_heard = true
		mark("npc_heard"))


## A soldier who runs the player down once alerted.
func _build_chaser(pos: Vector3) -> void:
	_chaser = Npc.make(self, pos, "chola_soldier", {"seed": 4, "name": "Chaser", "react": "chase", "yaw": PI, "vision_range": 12.0})
	_chaser.caught.connect(func(_p: Player) -> void:
		if not _caught:
			_caught = true
			mark("npc_caught")
			chrono.say("He has caught you. He seems unsure what to do next. So am I.")
			_chaser.react = "look")


## People at work and at rest: a mason hammering, a drummer, one sitting on the ground,
## one on a stone, two in conversation, a wanderer and a follower.
func _build_workers(c: Vector3) -> void:
	var at := func(dx: float, dz: float) -> Vector3: return on_ground(c.x + dx, c.z + dz)
	Npc.make(self, at.call(-3, 0), "chola_artisan", {"seed": 0, "name": "Mason", "yaw": PI, "perceptive": false}).work()
	Npc.make(self, at.call(-1.5, 0), "chola_drummer", {"seed": 1, "name": "Drummer", "yaw": PI, "perceptive": false}).work()
	Npc.make(self, at.call(0, 0), "indus_citizen", {"seed": 3, "name": "Sitter", "yaw": PI, "perceptive": false}).sit(true)
	var stone := MeshKit.solid_rock(self, at.call(1.6, 0.25) + Vector3.UP * 0.12, Vector3(0.42, 0.5, 0.42), MatLib.pbr("rock_06", {"scale": 0.8}), 5)
	stone.name = "Seat"
	Npc.make(self, at.call(1.6, 0), "egypt_worker", {"seed": 0, "name": "Rester", "yaw": PI, "perceptive": false}).sit()
	var a := Npc.make(self, at.call(3.4, 0), "medieval_peasant", {"seed": 1, "name": "TalkerA", "perceptive": false})
	var b := Npc.make(self, at.call(4.5, 0.2), "medieval_monk", {"seed": 4, "name": "TalkerB", "perceptive": false})
	a.set_yaw(-PI / 2)
	b.set_yaw(PI / 2)
	a.talk(b)
	b.talk(a)
	var w := Npc.make(self, at.call(8, -3), "indus_trader", {"seed": 0, "name": "Wanderer", "perceptive": false})
	w.wander(at.call(8, -3), 4.0)
	Npc.make(self, at.call(9, -3), "indus_trader", {"seed": 1, "name": "Follower", "perceptive": false}).follow(w, 1.6)


# ------------------------------------------------------------------------ era
func _setup() -> void:
	chrono.glitch_pool = ["time_stutter", "yell", "translation_failure"]
	chrono.glitch_interval = Vector2(60, 90)
	add_objective("noticed", "Get noticed by the guard")
	director.add("lineup", "labp_lineup", {"at": on_ground(-20, 31), "radius": 5.0},
		[["a", func() -> void: chrono.say("Nineteen kinds of people. All of them better dressed than you.")],
		 ["b", func() -> void: chrono.say("A queue. Humans have always had queues.")]])
	director.add("timer", "labp_timer", {"time": 4.0}, [["a", func() -> void: mark("timed_event")]])
	director.add("seen", "labp_seen", {"when": func() -> bool: return _noticed},
		[["a", func() -> void: chrono.say("The guard has seen you. Wave. No. Do not wave.")]])
	director.add("alarm", "labp_alarm", {"when": func() -> bool: return _alerted},
		[["a", func() -> void: chrono.say("He is certain now. Blend in. There is a crowd for that.")]])
	director.add("crowd", "labp_crowd", {"at": on_ground(-14, 4), "radius": 6.0},
		[["a", func() -> void: chrono.say("Crowd. Nobody looks at anybody in a crowd.")]])
	director.add("gang", "labp_gang", {"at": on_ground(10, -2), "radius": 7.0},
		[["a", func() -> void: chrono.say("A work gang, going round in circles. I sympathise.")]])
	director.add("exit", "labp_exit", {"at": on_ground(0, -26), "radius": 6.0},
		[["a", func() -> void: chrono.say("Portal ahead. Try to leave before anyone asks for papers.")]])


func _era_process(delta: float) -> void:
	_animate_lineup(wdelta(delta))
	if player.cover_count > 0 and _crowd.contains(player.global_position):
		mark("crowd_cover")


func required_mechanics() -> Array:
	return ["npc_noticed", "npc_alerted", "npc_heard", "npc_lost", "npc_caught", "crowd_cover", "glitch:yell", "event", "portal_entered"]


func autopilot_plan() -> Array:
	var AP := AutoPilot
	return [
		AP.label("walk the line-up"),
		AP.goto(on_ground(-21, 31), {"direct": true}),
		AP.goto(on_ground(20, 31), {"direct": true}),
		AP.label("get noticed"),
		AP.goto(on_ground(15, 17.5), {"direct": true, "tol": 0.8}),
		AP.until(func() -> bool: return _noticed, 40.0),
		AP.until(func() -> bool: return _alerted, 40.0),
		AP.run(func() -> void: chrono.trigger_glitch("yell")),
		AP.until(func() -> bool: return _heard, 5.0),
		AP.label("lose him in the crowd"),
		AP.goto(on_ground(-13, 4), {"direct": true, "tol": 1.0}),
		AP.until(func() -> bool: return _lost, 60.0),
		AP.label("get chased"),
		AP.goto(on_ground(11.5, 4), {"direct": true, "tol": 1.0}),
		AP.until(func() -> bool: return _caught, 40.0),
		AP.label("portal"),
		AP.goto(func() -> Vector3: return portal.global_position, {"direct": true, "tol": 0.6}),
	]


func capture_shots() -> Array:
	var shots := _lineup_shots(4, 3.3, 50.0, "close")
	var cc := on_ground(-14, 4, 1.0)
	shots.append({"name": "crowd", "from": cc + Vector3(11, 4.5, 10), "to": cc, "time": 0.8})
	shots.append({"name": "crowd_close", "from": cc + Vector3(1.5, 0.7, 8.5), "to": cc + Vector3(0, 0.2, 0), "time": 0.8, "fov": 50.0})
	var gc := on_ground(14, -8, 1.0)
	shots.append({"name": "gang", "from": gc + Vector3(-5, 1.6, 3.5), "to": gc + Vector3(0, 0, 0), "time": 0.8})
	var wc := on_ground(1, 12, 1.0)
	shots.append({"name": "workers", "from": wc + Vector3(-1.2, 0.4, 3.6), "to": wc + Vector3(-1.2, -0.1, 0), "time": 0.8, "fov": 55.0})
	shots.append({"name": "talkers", "from": wc + Vector3(3.0, 0.4, 3.4), "to": wc + Vector3(3.0, -0.1, 0), "time": 0.8, "fov": 55.0})
	shots.append({"name": "workers2", "from": wc + Vector3(4.5, 0.6, 0.5), "to": wc + Vector3(7.5, 0, -3), "time": 0.8, "fov": 55.0})
	shots.append({"name": "guard", "from": on_ground(11, 18.5, 1.5), "to": on_ground(15.5, 15, 1.0), "time": 0.8, "fov": 55.0,
		"setup": func() -> void:
			player.teleport(on_ground(15, 17.5, 0.2))
			_guard.global_position = on_ground(13.5, 14)
			_guard.awareness = 0.0})
	return shots
