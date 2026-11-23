extends EraBase
## FX lab. One station per FxKit effect along a path from spawn to the portal,
## so the bot run exercises every constructor headless and the capture shots
## show every effect in the real renderer.

const FIELD_W := 26
const FIELD_H := 19
const FIELD_CELL := 3.0
const FIELD_ORIGIN := Vector3(18, 0, -58)

var lamps: FxLamps
var campfire: FxFire
var brazier: FxFire
var wall_fire: FxFire
var torches: Array[FxFire] = []
var field: FxFireField
var beam: FxBeam
var chimney: FxEmitter

var _weather := {}
var _lamp_target := 0.0
var _lamps_lit := 0.0
var _block: MeshInstance3D
var _block_rest := Vector3.ZERO
var _stone: MeshInstance3D
var _stone_t := -1.0
var _impact_pos := Vector3.ZERO
var _pond := Vector3(-12, 0, 12)
var _beam_pts: Array = []
var _beam_k := 0.0
var _beam_on := false
var _brazier_use: Interactable
var _ca := {}                    # Vector2i -> [fuel, heat]
var _ca_t := 0.0
var _ca_running := false
var _sand_phase := 0
var _sand_t := 0.0
var _base_fog := 0.0
var _sched: Array = []           # [time, Callable]
var _shook := 0.0
var _perf_case := ""


func _configure() -> void:
	era_id = "lab_fx"
	spawn_pos = Vector3(0, 3, 62)
	spawn_yaw = 0.0
	time_limit = 240.0
	nav_enabled = false
	# perf poses: python3 tools/perf.py lab_fx,fxcase_field400  (calm | field400 | wildfire | <weather kind>)
	if Game.mode == "perf":
		for tok in String(Game.user_args.get("perf", "")).split(","):
			if tok.begins_with("fxcase_"):
				_perf_case = tok.trim_prefix("fxcase_")
		if _perf_case != "":
			spawn_pos = Vector3(2, 3, -12)
			spawn_yaw = -1.12


func _height(x: float, z: float) -> float:
	var h := 1.0 + sin(x * 0.05) * 0.35 + cos(z * 0.043) * 0.3 + sin((x + z) * 0.11) * 0.08
	var d := Vector2(x - _pond.x, z - _pond.z).length()
	h -= smoothstep(9.0, 3.0, d) * 1.9
	return h


func _build_world() -> void:
	EnvKit.build(self, {
		"hdri": "qwantani_dusk_2_puresky", "sky_energy": 0.42, "sun_energy": 0.8, "sun_color": Color(1.0, 0.66, 0.44),
		"fog_density": 0.0035, "fog_color": Color(0.16, 0.17, 0.22), "vol_density": 0.012, "vol_ambient": 0.2,
		"ambient_energy": 0.8, "fog_aerial": 0.3, "grade_shadow": Color(0.0, 0.003, 0.01),
	})
	terrain = Terrain.create(self, {
		"size": 224.0, "res": 129, "chunks": 4, "height": _height,
		"a": "dry_ground_01", "b": "rock_face_03", "c": "brown_mud_leaves_01",
		"color": func(x: float, z: float, _h: float, _s: float) -> Color:
			return Color(clampf(sin(x * 0.13) * cos(z * 0.11) * 0.6 + 0.5, 0.0, 1.0), 0, 0),
	})
	_base_fog = env.fog_density
	water_level = _height(_pond.x, _pond.z) + 1.25
	WaterKit.plane(self, Vector3(_pond.x, water_level, _pond.z), Vector2(22, 22), {"clarity": 1.4})
	var stone := MatLib.pbr("medieval_blocks_05", {"scale": 0.4})
	var rock := MatLib.pbr("rock_06", {"scale": 0.6})
	_build_lamps(stone)
	_build_camp(rock)
	_build_hut(stone)
	_build_block(stone)
	_build_pond(rock)
	_build_beam(stone)
	_build_shed(stone)
	_build_impact(stone, rock)
	_build_wildfire()
	# signal brazier + portal
	var bpos := on_ground(3.2, -55.0)
	MeshKit.cyl(0.5, 0.3, 0.9, MatLib.metal("rusty_metal_02", Color(0.5, 0.45, 0.4), 0.7), bpos + Vector3(0, 0.45, 0), self, 10)
	brazier = FxKit.fire(self, bpos + Vector3(0, 0.95, 0), {"size": 0.7, "intensity": 0.0, "shadow": true})
	_brazier_use = Interactable.make(self, bpos + Vector3(0, 1.0, 0), "Light the brazier", func(_p: Player) -> void:
		brazier.ignite()
		complete_objective("signal"), 2.6, true)
	add_poi(_brazier_use, "Signal brazier")
	portal = Portal.make(self, on_ground(0, -62))
	add_checkpoint(on_ground(0, 20, 1.0), 5.0, 1)
	add_checkpoint(on_ground(0, -30, 1.0), 5.0, 2)


# ---------------------------------------------------------------- stations
func _build_lamps(stone: Material) -> void:
	var b := BlockBatch.new()
	b.material = stone
	add_child(b)
	var base := on_ground(-7.0, 51.0)
	var pts := PackedVector3Array()
	for s in 4:
		var w := 7.0 - s * 1.2
		var top := base.y + 0.3 * (s + 1)
		b.add(Vector3(base.x, top - 0.6, base.z - s * 0.55), Vector3(w, 1.2, 3.2 - s * 0.55))
		var n := int(w / 0.24)
		for i in n:
			var x := base.x - w * 0.5 + 0.15 + (w - 0.3) * float(i) / float(n - 1)
			pts.append(Vector3(x + sin(i * 3.1 + s) * 0.03, top + 0.035, base.z + 1.45 - s * 0.28 + cos(i * 1.7) * 0.05))
	b.commit()
	# lamps lining the path and scattered on the ground before the steps
	for i in 12:
		for side in [-1.0, 1.0]:
			var p := on_ground(side * 1.9 + sin(i * 1.3) * 0.15, 58.5 - i * 1.15, 0.045)
			pts.append(p)
	for i in 26:
		var a := float(i) * 2.4
		var r := 0.6 + fmod(float(i) * 0.37, 1.0) * 2.2
		pts.append(on_ground(base.x + cos(a) * r * 1.6, base.z + 3.2 + sin(a) * r * 0.5, 0.045))
	lamps = FxKit.lamps(self, pts, {"lit": false, "max_lights": 8})
	# clay dishes under the flames
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dish := CylinderMesh.new()
	dish.top_radius = 0.06
	dish.bottom_radius = 0.035
	dish.height = 0.035
	dish.radial_segments = 8
	dish.rings = 1
	dish.material = MatLib.pbr("clay_plaster", {"scale": 2.0, "world": false, "tint": Color(0.55, 0.36, 0.26)})
	mm.mesh = dish
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i] - Vector3(0, 0.025, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _build_camp(rock: Material) -> void:
	var c := on_ground(6.0, 42.0)
	var bark := MatLib.pbr("acg_charred_wood", {"scale": 1.2, "world": false})
	for i in 9:
		var a := TAU * i / 9.0
		var m := MeshKit.mi(MeshKit.rock_mesh(40 + i, 2), rock, c + Vector3(cos(a) * 0.75, 0.08, sin(a) * 0.75), self)
		m.scale = Vector3(0.24, 0.2, 0.24)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var lg := MeshKit.cyl(0.07, 0.09, 1.0, bark, c + Vector3(cos(a) * 0.22, 0.32, sin(a) * 0.22), self, 8)
		lg.rotation = Vector3(0.75 * sin(a), 0.0, -0.75 * cos(a))
	campfire = FxKit.fire(self, c + Vector3(0, 0.12, 0), {"size": 1.0, "shadow": true, "scorch": true})
	# torches on posts either side of the path: plain lights + the flicker helper
	var wood := MatLib.pbr("rough_wood", {"scale": 1.5, "world": false})
	for side in [-1.0, 1.0]:
		var p := on_ground(side * 2.6, 36.0)
		MeshKit.cyl(0.05, 0.07, 2.2, wood, p + Vector3(0, 1.1, 0), self, 8)
		torches.append(FxKit.fire(self, p + Vector3(0, 2.25, 0), {"size": 0.42, "smoke": true, "embers": true}))


func _build_hut(stone: Material) -> void:
	var c := on_ground(-9.0, 30.0)
	var b := BlockBatch.new()
	b.material = stone
	add_child(b)
	b.wall(c + Vector3(-2.5, 0, -2), c + Vector3(2.5, 0, -2), 2.8, 0.5)
	b.wall(c + Vector3(-2.5, 0, 2), c + Vector3(2.5, 0, 2), 2.8, 0.5)
	b.wall(c + Vector3(-2.5, 0, -2), c + Vector3(-2.5, 0, 2), 2.8, 0.5)
	b.wall(c + Vector3(2.5, 0, -2), c + Vector3(2.5, 0, 2), 2.8, 0.5)
	b.add(c + Vector3(0, 3.0, 0), Vector3(5.8, 0.4, 4.8))
	b.add(c + Vector3(-1.4, 4.0, 0.6), Vector3(0.9, 1.7, 0.9))
	b.commit()
	chimney = FxKit.smoke(self, c + Vector3(-1.4, 4.9, 0.6), {"size": 0.42, "height": 13.0})


func _build_block(stone: Material) -> void:
	var c := on_ground(6.5, 24.0)
	var wood := MatLib.pbr("rough_wood", {"scale": 1.2, "world": false})
	for sx in [-1.0, 1.0]:
		MeshKit.cyl(0.09, 0.11, 5.6, wood, c + Vector3(sx * 1.3, 2.8, 0), self, 8)
	MeshKit.box(Vector3(3.0, 0.2, 0.2), wood, c + Vector3(0, 5.6, 0), self)
	_block_rest = c + Vector3(0, 4.6, 0)
	_block = MeshKit.box(Vector3(1.3, 1.1, 1.3), stone, _block_rest, self)


func _build_pond(rock: Material) -> void:
	for i in 7:
		var a := float(i) * 0.9 + 0.4
		var p := Vector3(_pond.x + cos(a) * 7.6, 0, _pond.z + sin(a) * 7.6)
		MeshKit.solid_rock(self, on_ground(p.x, p.z, 0.2), Vector3(0.8, 0.6, 0.7) * (0.7 + 0.5 * fmod(i * 0.37, 1.0)), rock, 60 + i, a)
	FxKit.mist(self, Vector3(_pond.x, water_level + 0.35, _pond.z), {"size": Vector3(6.5, 0.35, 6.5)})
	FxKit.spray(self, Vector3(_pond.x + 5.2, water_level + 0.1, _pond.z + 3.4), {"width": 4.0, "height": 2.0, "interval": 3.0, "dir": Vector3(1, 0, 0.6)}).rotation.y = -0.9


func _build_beam(stone: Material) -> void:
	var bronze := MatLib.metal("acg_bronze", Color(0.85, 0.66, 0.4), 0.2)
	var m1 := on_ground(8.0, 3.5, 1.9)
	var m2 := on_ground(8.0, -4.5, 1.9)
	for m: Vector3 in [m1, m2]:
		MeshKit.cyl(0.07, 0.09, 1.9, stone, m - Vector3(0, 0.95, 0), self, 8)
		var disc := MeshKit.cyl(0.42, 0.42, 0.04, bronze, m, self, 20)
		disc.rotation = Vector3(PI / 2, PI / 4 * (1.0 if m == m1 else -1.0), 0)
	var b := BlockBatch.new()
	b.material = stone
	add_child(b)
	var wc := on_ground(15.5, -4.5)
	b.wall(wc + Vector3(0, 0, -2.5), wc + Vector3(0, 0, 2.5), 4.0, 0.7)
	b.commit()
	var src := on_ground(17.0, 3.5, 6.5)
	_beam_pts = [src, m1, m2, Vector3(wc.x - 0.36, m2.y, wc.z)]
	beam = FxKit.beam(self, {"radius": 0.2})
	_route_beam(0.0)


func _route_beam(k: float) -> void:
	# k = 0: the first mirror throws the light into the ground; k = 1: full route onto the wall
	_beam_k = k
	var m1: Vector3 = _beam_pts[1]
	if k < 0.999:
		var miss := on_ground(m1.x - 1.2, m1.z - 2.5)
		var aim: Vector3 = miss.lerp(_beam_pts[2], k)
		beam.set_points([_beam_pts[0], m1, aim])
	else:
		beam.set_points(_beam_pts)


func _build_shed(stone: Material) -> void:
	var c := on_ground(-9.5, -10.0)
	var b := BlockBatch.new()
	b.material = stone
	add_child(b)
	b.wall(c + Vector3(-3, 0, -3), c + Vector3(3, 0, -3), 4.2, 0.6)
	b.wall(c + Vector3(-3, 0, 3), c + Vector3(3, 0, 3), 4.2, 0.6)
	b.wall(c + Vector3(-3, 0, -3), c + Vector3(-3, 0, 3), 4.2, 0.6)
	b.wall(c + Vector3(3, 0, -3), c + Vector3(3, 0, -0.9), 4.2, 0.6)
	b.wall(c + Vector3(3, 0, 0.9), c + Vector3(3, 0, 3), 4.2, 0.6)
	b.add(c + Vector3(3, 3.4, 0), Vector3(0.6, 1.6, 1.8))
	# roof in two slabs with a slit between them
	b.add(c + Vector3(-2.3, 4.4, 0), Vector3(2.2, 0.4, 6.8))
	b.add(c + Vector3(2.3, 4.4, 0), Vector3(2.2, 0.4, 6.8))
	b.add(c + Vector3(0, 4.4, -2.4), Vector3(2.4, 0.4, 2.0))
	b.add(c + Vector3(0, 4.4, 2.4), Vector3(2.4, 0.4, 2.0))
	b.commit()
	var shaft := SpotLight3D.new()
	shaft.light_color = Color(1.0, 0.86, 0.66)
	shaft.light_energy = 14.0
	shaft.spot_range = 16.0
	shaft.spot_angle = 12.0
	shaft.spot_attenuation = 0.6
	shaft.shadow_enabled = true
	shaft.light_volumetric_fog_energy = 5.0
	add_child(shaft)
	var top := c + Vector3(1.6, 12.0, 0.3)
	var floor_hit := c + Vector3(-0.9, 0.0, -0.2)
	shaft.look_at_from_position(top, floor_hit, Vector3.UP)
	FxKit.god_rays(self, c + Vector3(-0.3, 2.1, 0), {"size": Vector3(2.4, 2.0, 2.6)})
	# the visible shaft is the beam effect again, wide and faint
	var roof := top.lerp(floor_hit, (top.y - (c.y + 4.4)) / (top.y - floor_hit.y))
	FxKit.beam(self, {"radius": 0.75, "opacity": 0.16, "glow": false}).set_points([roof, floor_hit])


func _build_impact(stone: Material, rock: Material) -> void:
	var c := on_ground(-13.0, -24.0)
	_impact_pos = c
	var b := BlockBatch.new()
	b.material = stone
	add_child(b)
	b.wall(c + Vector3(-4, 0, -3.5), c + Vector3(-1.5, 0, -3.5), 2.6, 0.8)
	b.wall(c + Vector3(1.0, 0, -3.5), c + Vector3(4, 0, -3.5), 1.6, 0.8)
	b.commit()
	_stone = MeshKit.mi(MeshKit.rock_mesh(77, 2), rock, c + Vector3(0, 40, 0), self)
	_stone.scale = Vector3.ONE * 0.55
	_stone.visible = false


func _build_wildfire() -> void:
	field = FxKit.fire_field(self, {"cell_size": FIELD_CELL, "height": ground_y, "flame_height": 4.0, "max_cells": 600})
	field.position = FIELD_ORIGIN
	field.bind_environment(env, sun)
	var wp := on_ground(101.0, -30.0)
	wall_fire = FxKit.fire(self, wp, {"size": 9.0, "width": 30.0, "intensity": 0.0})
	wall_fire.rotation.y = PI / 2


# ------------------------------------------------------------------- setup
func _setup() -> void:
	chrono.glitch_pool = ["gravity_flicker", "time_stutter", "yell", "translation_failure"]
	chrono.glitch_interval = Vector2(40, 60)
	add_objective("signal", "Light the signal brazier by the portal")
	director.add("lamps", "labx_lamps", {"at": Vector3(0, 1, 56), "radius": 7.0},
		[["wave", func() -> void: _lamp_target = 1.0],
		 ["half", func() -> void: _lamp_target = 1.0]])
	director.add("weather", "labx_weather", {"time": 4.0},
		[["snow", func() -> void: _start_weather("snow")],
		 ["rain", func() -> void: _start_weather("rain")],
		 ["ash", func() -> void: _start_weather("ash")]])
	director.add("block", "labx_dustfall", {"at": Vector3(0, 1, 28), "radius": 5.0},
		[["drop", func() -> void: _drop_block()]])
	director.add("pond", "labx_splash", {"at": Vector3(0, 1, 16), "radius": 6.0},
		[["rock", func() -> void: _splash(1.2)],
		 ["boulder", func() -> void: _splash(2.2)]])
	director.add("wild", "labx_wildfire", {"at": Vector3(0, 1, 14), "radius": 6.0},
		[["east", func() -> void: _ignite_field(Vector2i(2, 7))],
		 ["south", func() -> void: _ignite_field(Vector2i(4, 12))]])
	director.add("beam", "labx_beam", {"at": Vector3(0, 1, 4), "radius": 6.0},
		[["turn", func() -> void: _beam_on = true]])
	director.add("treb", "labx_shockwave", {"at": Vector3(0, 1, -14), "radius": 6.0},
		[["stone", func() -> void: _launch_stone()]])
	director.add("storm", "labx_sandstorm", {"at": Vector3(0, 1, -34), "radius": 7.0},
		[["gust", func() -> void: _start_sandstorm()]])
	if _perf_case != "":
		_pose_perf.call_deferred()


## Fixed worst-case poses for the perf runner: the player stands facing the fire field.
func _pose_perf() -> void:
	match _perf_case:
		"calm":
			_pose()
		"field400":
			# the FireField alone: 400 cells, no wall fire, no ember weather
			_pose()
			for i in 400:
				field.set_cell(Vector2i(i % FIELD_W, floori(float(i) / FIELD_W)), 0.55 + 0.4 * fmod(i * 0.37, 1.0))
			field.prewarm(9.0)
		"wildfire":
			_pose_wildfire()
			for y in FIELD_H:
				for x in FIELD_W:
					if field.get_cell(Vector2i(x, y)) <= 0.0:
						field.set_cell(Vector2i(x, y), 0.8)
			field.prewarm(9.0)
		_:
			_pose(_perf_case, 1.0)
	print("lab_fx perf case '%s': %d burning cells" % [_perf_case, field.burning_count()])


func _wx(kind: String) -> FxWeather:
	if not _weather.has(kind):
		_weather[kind] = FxKit.weather(self, kind, {"strength": 0.0, "ground": ground_y})
	return _weather[kind]


func _start_weather(kind: String) -> void:
	_wx(kind).fade = 0.5
	_wx(kind).set_strength(0.8)


func _drop_block() -> void:
	_block.position = _block_rest
	var land := on_ground(_block_rest.x, _block_rest.z, 0.5)
	var tw := _block.create_tween()
	tw.tween_property(_block, "position", land, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		var p := land - Vector3(0, 0.45, 0)
		FxKit.dust_puff(self, p, {"size": 2.0})
		FxKit.debris(self, p + Vector3(0, 0.1, 0), {"size": 1.2, "amount": 18})
		camera_rig.add_shake(0.3)
		Sfx.play("step", p)
		mark("fx_dust"))


func _splash(size: float) -> void:
	FxKit.splash(self, Vector3(_pond.x + 1.0, water_level, _pond.z + 1.5), {"size": size})
	mark("fx_splash")


func _launch_stone() -> void:
	_stone_t = 0.0
	_stone.visible = true


func _impact() -> void:
	_stone.visible = false
	var e := FxKit.shockwave(self, _impact_pos, {"size": 6.0})
	e.shook.connect(func(amount: float) -> void: _shook = amount)
	emit_noise(_impact_pos, 40.0, 1.0, "impact")
	mark("fx_shockwave")


func _ignite_field(c: Vector2i) -> void:
	_ca.clear()
	_ca[c] = [1.0, 0.2]
	_ca_running = true
	wall_fire.ignite(1.0, 6.0)


func _start_sandstorm() -> void:
	_sand_phase = 1
	_sand_t = 0.0
	for k in _weather:
		(_weather[k] as FxWeather).set_strength(0.0)
	_wx("sandstorm").fade = 0.45
	_wx("sandstorm").set_strength(0.85)


func _step_fire() -> void:
	# tiny cellular wildfire: heat rises while fuel lasts, spreads downwind first
	var add: Array = []
	for c: Vector2i in _ca.keys():
		var s: Array = _ca[c]
		if s[0] > 0.0:
			s[1] = minf(s[1] + 0.2, 1.0)
			s[0] -= 0.035
			if s[1] > 0.5:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1)]:
					var n := c + d
					if n.x < 0 or n.y < 0 or n.x >= FIELD_W or n.y >= FIELD_H or _ca.has(n):
						continue
					if rng.randf() < (0.42 if d.x > 0 else 0.2):
						add.append(n)
		else:
			s[1] = maxf(s[1] - 0.06, 0.0)
		field.set_cell(c, s[1])
	for n: Vector2i in add:
		if not _ca.has(n):
			_ca[n] = [0.9 + rng.randf() * 0.5, 0.15]


func _era_process(delta: float) -> void:
	var d := wdelta(delta)
	for i in range(_sched.size() - 1, -1, -1):
		_sched[i][0] -= delta
		if _sched[i][0] <= 0.0:
			var fn: Callable = _sched[i][1]
			_sched.remove_at(i)
			fn.call()
	# lamps light up in a wave
	if _lamps_lit < _lamp_target * lamps.count():
		_lamps_lit = minf(_lamps_lit + d * 90.0, lamps.count())
		lamps.set_lit_count(int(_lamps_lit))
		if lamps.lit_count() == lamps.count():
			mark("fx_lamps")
	# beam swings onto the second mirror
	if _beam_on and _beam_k < 1.0:
		_route_beam(minf(_beam_k + d * 0.8, 1.0))
		if _beam_k >= 1.0 and beam.points.size() == 4:
			mark("fx_beam")
	# trebuchet stone
	if _stone_t >= 0.0:
		_stone_t += d / 0.9
		var from := _impact_pos + Vector3(26, 3, 30)
		var k := minf(_stone_t, 1.0)
		_stone.position = from.lerp(_impact_pos, k) + Vector3(0, sin(k * PI) * 12.0, 0)
		_stone.rotation += Vector3(3.0, 1.0, 2.0) * d
		if _stone_t >= 1.0:
			_stone_t = -1.0
			_impact()
	# wildfire
	if _ca_running:
		_ca_t -= d
		if _ca_t <= 0.0:
			_ca_t = 0.2
			_step_fire()
		if field.burning_count() >= 40:
			mark("fx_firefield")
	if brazier.is_burning() and brazier.intensity > 0.5:
		mark("fx_fire_lit")
	for kind in _weather:
		var w: FxWeather = _weather[kind]
		if kind != "sandstorm" and w.get_strength() > 0.5:
			mark("fx_weather")
	# sandstorm gust: up, hold until visibility has really dropped, then clear
	if _sand_phase == 1:
		_sand_t += d
		if _wx("sandstorm").get_strength() > 0.8 and env.fog_density > _base_fog * 4.0:
			mark("fx_sandstorm")
			_sand_phase = 2
			_wx("sandstorm").set_strength(0.0)
	elif _sand_phase == 2 and _wx("sandstorm").get_strength() <= 0.0:
		_sand_phase = 0


func _telemetry_extra() -> Dictionary:
	return {"cells": field.burning_count(), "smoke": snappedf(field.smoke_amount(), 0.01), "fog": snappedf(env.fog_density, 0.0001), "shook": _shook}


func required_mechanics() -> Array:
	return ["fx_lamps", "fx_fire_lit", "fx_dust", "fx_splash", "fx_beam", "fx_firefield", "fx_shockwave",
		"fx_weather", "fx_sandstorm", "glitch:time_stutter", "checkpoint", "event", "portal_entered"]


func autopilot_plan() -> Array:
	var AP := AutoPilot
	if _perf_case != "":
		return [AP.wait(600.0)]
	var go := func(z: float) -> Dictionary: return AP.goto(Vector3(0, 0, z), {"direct": true, "tol": 1.2, "ytol": 20.0})
	return [
		AP.label("lamps"), go.call(54.0),
		AP.until(func() -> bool: return mechanics.has("fx_lamps"), 12.0),
		AP.label("campfire and torches"), go.call(40.0),
		AP.label("falling block"), go.call(26.0),
		AP.until(func() -> bool: return mechanics.has("fx_dust"), 8.0),
		AP.label("pond"), go.call(14.0),
		AP.until(func() -> bool: return mechanics.has("fx_splash"), 6.0),
		AP.run(func() -> void: chrono.trigger_glitch("time_stutter")),
		AP.label("beam"), go.call(2.0),
		AP.until(func() -> bool: return mechanics.has("fx_beam"), 8.0),
		AP.label("shaft and trebuchet"), go.call(-16.0),
		AP.until(func() -> bool: return mechanics.has("fx_shockwave"), 8.0),
		AP.until(func() -> bool: return mechanics.has("fx_firefield"), 40.0),
		AP.label("sandstorm"), go.call(-36.0),
		AP.until(func() -> bool: return mechanics.has("fx_sandstorm"), 25.0),
		AP.label("brazier"),
		AP.use(func() -> Node: return _brazier_use, {"direct": true}),
		AP.until(func() -> bool: return mechanics.has("fx_fire_lit"), 8.0),
		AP.label("portal"),
		AP.goto(func() -> Vector3: return portal.global_position, {"direct": true, "tol": 0.6, "ytol": 20.0}),
	]


# ----------------------------------------------------------------- capture
## Poses the world for one shot: everything calm, lamps lit, then the extras.
func _pose(weather := "", strength := 0.0) -> void:
	director.enabled = false
	_sched.clear()
	_sand_phase = 0
	_ca_running = false
	for k in _weather:
		(_weather[k] as FxWeather).set_strength(0.0, true)
	if field.burning_count() > 0:
		field.clear()
		field.prewarm(0.0)
	wall_fire.set_intensity(0.0, true)
	lamps.set_lit_count(lamps.count())
	_lamps_lit = lamps.count()
	_lamp_target = 1.0
	_block.position = _block_rest
	if weather != "":
		var w := _wx(weather)
		w.set_strength(strength, true)
		w.prewarm()


## Fires `fn` so that both review frames of a shot of length `time` land `lead` seconds after a trigger.
func _on_cue(time: float, lead: float, fn: Callable) -> void:
	for k: float in [0.35, 0.85]:
		_sched.append([maxf(0.05, 10.0 / 12.0 + time * k - lead), fn])


func _pose_wildfire() -> void:
	_pose("embers", 0.8)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var n := FastNoiseLite.new()
	n.seed = 3
	n.frequency = 0.09
	for y in FIELD_H:
		for x in FIELD_W:
			# an organic patch of about 300 cells: hottest at the downwind front, burning low behind it
			var edge := minf(minf(x, FIELD_W - 1 - x), minf(y, FIELD_H - 1 - y)) / 4.0
			if n.get_noise_2d(x, y) + clampf(edge, 0.0, 1.0) * 0.9 < 0.42:
				continue
			var v := clampf(0.3 + 0.7 * float(x) / FIELD_W + r.randf_range(-0.2, 0.25), 0.15, 1.0)
			field.set_cell(Vector2i(x, y), v)
	print("lab_fx: wildfire pose burning cells = ", field.burning_count())
	wall_fire.set_intensity(1.0, true)
	wall_fire.prewarm(8.0)
	field.prewarm(9.0)


func capture_shots() -> Array:
	var g := func(x: float, z: float, lift: float) -> Vector3: return on_ground(x, z, lift)
	var storm_from: Vector3 = g.call(0.5, 49.0, 1.9)
	var storm_to: Vector3 = g.call(-1.0, 30.0, 1.6)
	return [
		{"name": "lamps_dusk", "from": g.call(-1.6, 57.2, 2.0), "to": g.call(-7.0, 52.0, 0.9), "from2": g.call(-2.4, 56.0, 1.7), "time": 2.5,
			"setup": func() -> void: _pose()},
		{"name": "campfire", "from": g.call(2.6, 44.6, 1.3), "to": g.call(6.0, 42.0, 0.9), "time": 2.5,
			"setup": func() -> void:
				_pose()
				campfire.prewarm()},
		{"name": "torches_chimney", "from": g.call(1.5, 40.5, 1.8), "to": g.call(-5.5, 31.0, 4.2), "time": 2.5,
			"setup": func() -> void:
				_pose()
				chimney.prewarm(12.0)},
		{"name": "dust_debris", "from": g.call(2.2, 27.6, 1.5), "to": g.call(6.5, 24.0, 1.0), "time": 2.0,
			"setup": func() -> void:
				_pose()
				_on_cue(2.0, 0.95, _drop_block)},
		{"name": "splash_mist", "from": g.call(-4.6, 18.5, 2.6), "to": Vector3(_pond.x + 0.6, water_level, _pond.z + 1.2), "time": 2.0,
			"setup": func() -> void:
				_pose()
				_on_cue(2.0, 0.4, func() -> void: _splash(1.6))},
		{"name": "beam", "from": g.call(3.0, 2.5, 2.4), "to": g.call(11.0, -1.5, 2.6), "time": 2.5,
			"setup": func() -> void:
				_pose()
				_route_beam(1.0)},
		{"name": "god_rays", "from": g.call(-7.3, -8.2, 1.5), "to": g.call(-10.6, -10.6, 2.0), "fov": 70.0, "time": 2.5,
			"setup": func() -> void: _pose()},
		{"name": "shockwave", "from": g.call(-3.5, -15.5, 2.6), "to": _impact_pos + Vector3(0, 1.2, 0), "time": 2.0,
			"setup": func() -> void:
				_pose()
				_on_cue(2.0, 0.5, _impact)},
		{"name": "wildfire_wide", "from": g.call(2.0, -12.0, 7.0), "to": g.call(50.0, -34.0, 6.0), "time": 3.0,
			"setup": _pose_wildfire},
		{"name": "wildfire_close", "from": g.call(10.0, -40.0, 2.2), "to": g.call(30.0, -36.0, 3.5), "time": 2.5,
			"setup": _pose_wildfire},
		{"name": "sandstorm_0", "from": storm_from, "to": storm_to, "time": 2.0,
			"setup": func() -> void: _pose("sandstorm", 0.0)},
		{"name": "sandstorm_05", "from": storm_from, "to": storm_to, "time": 2.0,
			"setup": func() -> void: _pose("sandstorm", 0.5)},
		{"name": "sandstorm_1", "from": storm_from, "to": storm_to, "time": 2.0,
			"setup": func() -> void: _pose("sandstorm", 1.0)},
		{"name": "blizzard", "from": storm_from, "to": storm_to, "time": 2.0,
			"setup": func() -> void: _pose("blizzard", 1.0)},
		{"name": "snow", "from": storm_from, "to": storm_to, "time": 2.0,
			"setup": func() -> void: _pose("snow", 1.0)},
		{"name": "rain", "from": g.call(0.0, 40.5, 1.7), "to": g.call(-1.5, 33.0, 1.7), "time": 2.0,
			"setup": func() -> void: _pose("rain", 1.0)},
		{"name": "ash", "from": g.call(0.0, 40.5, 1.7), "to": g.call(-1.5, 33.0, 1.7), "time": 2.0,
			"setup": func() -> void: _pose("ash", 1.0)},
		{"name": "portal_brazier", "from": g.call(5.5, -50.0, 2.0), "to": g.call(1.5, -58.0, 1.6), "time": 2.0,
			"setup": func() -> void:
				_pose()
				brazier.set_intensity(1.0, true)
				open_portal()},
	]
