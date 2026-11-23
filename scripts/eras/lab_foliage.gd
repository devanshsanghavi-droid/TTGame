extends EraBase
## Foliage lab. One grove per plant kind, laid out by era along a north-south
## path, so FoliageKit can be judged kind by kind (python3 tools/capture.py lab_foliage).
##
##   z 140 ..  96   Carboniferous   lycopsid, calamites, tree_fern, fern, clubmoss
##   z  94 ..  50   Cretaceous      conifer, ginkgo_broadleaf, cycad, horsetail, berry_bush
##   z  48 ..   4   Ice age         spruce (east side snowed in), dwarf_shrub, dry_grass
##   z   2 .. -42   Indus / Egypt   date_palm, acacia, reed, papyrus, crop, dry_scrub
##   z -44 .. -88   Chola           coconut_palm, banana, banyan_broadleaf
##   z -90 .. -134  Medieval        oak_broadleaf, hedge, grass, wheat
##   x 70 .. 120    burn and snow demo rows

const POND := Vector2(22.0, -12.0)
const BURN_AT := Vector3(92, 0, 104)
const SNOW_AT := Vector3(92, 0, 40)
const GROUND_AT := Vector3(92, 0, 132)

var groups := {}
var _burn_sets: Array = []
var _snow_row: FoliageKit.Group
var _fire_tree := -1
var _fire := 0.0
var _snowing := false
var _snow := 0.0
var _drought := false
var _dry := 0.0
var _gust := 0.0


func _configure() -> void:
	era_id = "lab_foliage"
	spawn_pos = Vector3(0, 7, 139)
	spawn_yaw = 0.0
	time_limit = 300.0
	nav_cell = 0.5


func _height(x: float, z: float) -> float:
	var h := 5.0 + sin(x * 0.045) * 0.6 + cos(z * 0.05 + 1.3) * 0.5 + sin((x + z) * 0.11) * 0.2
	var path := smoothstep(0.0, 1.0, clampf(1.0 - absf(x) / 7.0, 0.0, 1.0))
	h = lerpf(h, 5.0 + cos(z * 0.05 + 1.3) * 0.35, path)
	var pd := Vector2(x - POND.x, z - POND.y).length()
	h -= smoothstep(10.0, 3.5, pd) * 2.6
	return h


func _off_path(x: float, _z: float, _h: float) -> float:
	return 1.0 if absf(x) > 3.2 else 0.0


func _build_world() -> void:
	EnvKit.build(self, {"hdri": "kloofendal_48d_partly_cloudy_puresky", "fog_density": 0.0012, "vol_density": 0.004,
		"sun_energy": 2.6, "grade_shadow": Color(0.012, 0.016, 0.022)})
	terrain = Terrain.create(self, {
		"size": 320.0, "res": 257, "chunks": 8, "height": _height,
		"a": "forest_ground_04", "b": "rock_face_03", "c": "dry_ground_01",
		"a_scale": 0.22, "c_scale": 0.2, "paint_tint": Color(0.80, 0.83, 0.88), "paint_rough": 0.8,
		"color": func(x: float, z: float, _h: float, _s: float) -> Color:
			var sand := smoothstep(8.0, -2.0, z) * smoothstep(-50.0, -40.0, z)
			sand = maxf(sand, smoothstep(5.5, 2.0, absf(x)) * 0.8)
			var damp := smoothstep(13.0, 8.0, Vector2(x - POND.x, z - POND.y).length()) * 0.8
			return Color(sand, damp, 0),
	})
	water_level = 3.3
	WaterKit.plane(self, Vector3(POND.x, water_level, POND.y), Vector2(26, 26))
	var t := terrain
	var off := _off_path

	# ---------------------------------------------------------- Carboniferous
	groups["lycopsid"] = FoliageKit.forest(self, "lycopsid", {"count": 14, "seed": 1, "terrain": t, "center": Vector3(-27, 0, 118), "radius": 21.0, "accept": off})
	groups["calamites"] = FoliageKit.forest(self, "calamites", {"count": 24, "seed": 2, "terrain": t, "center": Vector3(25, 0, 127), "radius": 12.0})
	groups["tree_fern"] = FoliageKit.forest(self, "tree_fern", {"count": 9, "seed": 3, "terrain": t, "center": Vector3(15, 0, 107), "radius": 9.0, "accept": off})
	groups["fern"] = FoliageKit.ground_cover(self, "fern", {"count": 520, "seed": 4, "terrain": t, "rect": Rect2(-46, 96, 92, 46), "accept": off})
	groups["clubmoss"] = FoliageKit.ground_cover(self, "clubmoss", {"count": 420, "seed": 5, "terrain": t, "rect": Rect2(-14, 98, 28, 40), "accept": off, "visibility_end": 45.0})

	# ------------------------------------------------------------- Cretaceous
	groups["conifer"] = FoliageKit.forest(self, "conifer", {"count": 14, "seed": 6, "terrain": t, "center": Vector3(-29, 0, 72), "radius": 21.0})
	groups["ginkgo_broadleaf"] = FoliageKit.forest(self, "ginkgo_broadleaf", {"count": 8, "seed": 7, "terrain": t, "center": Vector3(28, 0, 79), "radius": 15.0})
	groups["cycad"] = FoliageKit.forest(self, "cycad", {"count": 14, "seed": 8, "terrain": t, "rect": Rect2(-15, 52, 30, 40), "accept": off})
	groups["horsetail"] = FoliageKit.ground_cover(self, "horsetail", {"count": 300, "seed": 9, "terrain": t, "center": Vector3(13, 0, 59), "radius": 9.0, "accept": off})
	groups["berry_bush"] = FoliageKit.ground_cover(self, "berry_bush", {"count": 16, "seed": 10, "terrain": t, "center": Vector3(-12, 0, 59), "radius": 8.0, "accept": off, "shadows": true, "spacing": 2.0})
	FoliageKit.ground_cover(self, "fern", {"count": 260, "seed": 11, "terrain": t, "rect": Rect2(-46, 52, 92, 40), "accept": off})

	# ---------------------------------------------------------------- Ice age
	groups["spruce"] = FoliageKit.forest(self, "spruce", {"count": 22, "seed": 12, "terrain": t, "center": Vector3(-27, 0, 26), "radius": 20.0})
	groups["spruce_snow"] = FoliageKit.forest(self, "spruce", {"count": 16, "seed": 13, "terrain": t, "center": Vector3(27, 0, 31), "radius": 16.0, "snow": 0.85})
	groups["dwarf_shrub"] = FoliageKit.ground_cover(self, "dwarf_shrub", {"count": 220, "seed": 14, "terrain": t, "rect": Rect2(-40, 6, 80, 40), "accept": off})
	groups["dry_grass"] = FoliageKit.ground_cover(self, "dry_grass", {"count": 650, "seed": 15, "terrain": t, "rect": Rect2(-44, 6, 88, 40), "accept": off})
	for i in 140:
		var a := i * 2.399963
		var r := sqrt((i + 0.5) / 140.0) * 24.0
		terrain.paint(27.0 + cos(a) * r, 29.0 + sin(a) * r, 4.5, 0.85)

	# ---------------------------------------------------------- Indus / Egypt
	groups["date_palm"] = FoliageKit.forest(self, "date_palm", {"count": 12, "seed": 16, "terrain": t, "center": Vector3(-24, 0, -10), "radius": 15.0})
	groups["acacia"] = FoliageKit.forest(self, "acacia", {"count": 5, "seed": 17, "terrain": t, "center": Vector3(32, 0, -32), "radius": 12.0})
	var shore := func(x: float, z: float, _h: float) -> float:
		var d := Vector2(x - POND.x, z - POND.y).length()
		return 1.0 if d > 6.2 and d < 10.5 else 0.0
	groups["reed"] = FoliageKit.ground_cover(self, "reed", {"count": 130, "seed": 18, "terrain": t, "center": Vector3(POND.x - 3, 0, POND.y), "radius": 11.0, "accept": shore, "shadows": true})
	groups["papyrus"] = FoliageKit.ground_cover(self, "papyrus", {"count": 60, "seed": 19, "terrain": t, "center": Vector3(POND.x + 5, 0, POND.y + 2), "radius": 9.0, "accept": shore, "shadows": true})
	groups["crop"] = FoliageKit.ground_cover(self, "crop", {"seed": 20, "terrain": t, "rect": Rect2(-40, -40, 32, 12), "rows": {"spacing": 0.75, "step": 1.45}, "visibility_end": 90.0})
	groups["dry_scrub"] = FoliageKit.ground_cover(self, "dry_scrub", {"count": 150, "seed": 21, "terrain": t, "rect": Rect2(-44, -42, 88, 42), "accept": func(x: float, z: float, h: float) -> float:
			return 0.0 if absf(x) < 3.2 or h < 4.2 or Rect2(-41, -41, 34, 14).has_point(Vector2(x, z)) else 1.0})

	# ------------------------------------------------------------------ Chola
	groups["coconut_palm"] = FoliageKit.forest(self, "coconut_palm", {"count": 12, "seed": 22, "terrain": t, "center": Vector3(-25, 0, -64), "radius": 18.0})
	groups["banana"] = FoliageKit.forest(self, "banana", {"count": 14, "seed": 23, "terrain": t, "center": Vector3(15, 0, -54), "radius": 8.0, "accept": off})
	groups["banyan_broadleaf"] = FoliageKit.single(self, "banyan_broadleaf", on_ground(27, -74), 1.1, 3, {"collide": true})
	FoliageKit.forest(self, "banyan_broadleaf", {"count": 2, "seed": 24, "terrain": t, "center": Vector3(-52, 0, -78), "radius": 16.0})
	FoliageKit.ground_cover(self, "grass", {"count": 700, "seed": 25, "terrain": t, "rect": Rect2(-44, -88, 88, 42), "accept": off})
	FoliageKit.ground_cover(self, "fern", {"count": 120, "seed": 26, "terrain": t, "center": Vector3(26, 0, -72), "radius": 13.0})

	# --------------------------------------------------------------- Medieval
	groups["oak_broadleaf"] = FoliageKit.forest(self, "oak_broadleaf", {"count": 8, "seed": 27, "terrain": t, "center": Vector3(-34, 0, -103), "radius": 14.0})
	var hedge_pts := FoliageKit.line_points(Vector3(6, 0, -100), Vector3(46, 0, -100), 2.0, t, 0.1, 1)
	hedge_pts.append_array(FoliageKit.line_points(Vector3(6, 0, -102), Vector3(6, 0, -131), 2.0, t, 0.1, 2))
	groups["hedge"] = FoliageKit.ground_cover(self, "hedge", {"points": hedge_pts, "visibility_end": 150.0})
	groups["wheat"] = FoliageKit.ground_cover(self, "wheat", {"seed": 28, "terrain": t, "rect": Rect2(9, -130, 36, 27), "rows": {"spacing": 0.7, "step": 1.45}, "visibility_end": 100.0})
	groups["grass"] = FoliageKit.ground_cover(self, "grass", {"count": 2600, "seed": 29, "terrain": t, "rect": Rect2(-31, -135, 28, 24), "accept": off})

	# ------------------------------------------------- burn / snow demo rows
	# three tree clusters at burn 0, 0.5, 1 and a row of ground plants at 0, 0.25, 0.5, 0.75, 1
	var tree_off := {"oak_broadleaf": Vector3(-6, 0, 0), "spruce": Vector3(1, 0, -10), "date_palm": Vector3(7, 0, 2)}
	for kind: String in tree_off:
		var pts: Array = []
		for col in 3:
			pts.append(BURN_AT + Vector3((col - 1) * 26.0, 0, 0) + tree_off[kind])
		var g := FoliageKit.forest(self, kind, {"points": pts, "terrain": t, "scale": Vector2(0.85, 0.85), "variants": 1, "yaw": 0.7})
		_burn_sets.append([g, [0.0, 0.5, 1.0]])
	var ground_off := {"berry_bush": 0.0, "fern": 2.2, "dry_grass": 3.8, "grass": 5.0}
	for kind: String in ground_off:
		var pts: Array = []
		var amounts: Array = []
		for st in 5:
			for j in 2:
				pts.append(GROUND_AT + Vector3((st - 2) * 4.2 + (j - 0.5) * 1.5, 0, ground_off[kind]))
				amounts.append(st * 0.25)
		var g := FoliageKit.ground_cover(self, kind, {"points": pts, "terrain": t, "scale": Vector2(1.15, 1.15), "shadows": true, "variants": 1})
		_burn_sets.append([g, amounts])
	_set_burn_demo()
	_snow_row = FoliageKit.forest(self, "spruce", {"points": [SNOW_AT + Vector3(-11, 0, 0), SNOW_AT, SNOW_AT + Vector3(11, 0, 0)], "terrain": t, "scale": Vector2(0.8, 0.8), "variants": 1})
	_snow_row.set_snow_at(1, 0.5)
	_snow_row.set_snow_at(2, 1.0)

	portal = Portal.make(self, on_ground(0, -139))
	add_checkpoint(on_ground(0, 72, 1.0), 6.0, 1)
	add_checkpoint(on_ground(0, -20, 1.0), 6.0, 2)
	add_checkpoint(on_ground(0, -100, 1.0), 6.0, 3)


func _set_burn_demo() -> void:
	for row: Array in _burn_sets:
		var g: FoliageKit.Group = row[0]
		var amounts: Array = row[1]
		for i in g.count():
			g.set_burn(i, amounts[i])


func water_height_at(pos: Vector3) -> float:
	return water_level if Vector2(pos.x - POND.x, pos.z - POND.y).length() < 14.0 else -1000.0


func _setup() -> void:
	chrono.glitch_pool = ["gravity_flicker", "era_flash", "time_stutter"]
	chrono.glitch_interval = Vector2(40, 60)
	add_objective("survey", "Walk the groves to the far end")
	director.add("gust", "labf_gust", {"at": Vector3(0, 5, 120), "radius": 8.0},
		[["breeze", func() -> void:
			_gust = 6.0
			chrono.say("Wind. The big scaly ones are Lepidodendron. They are not trees. Nobody has told them.")],
		 ["gale", func() -> void:
			_gust = 9.0
			chrono.say("Gusts rising. If a fern hits you, it was an accident.")]])
	director.add("fire", "labf_fire", {"at": Vector3(0, 5, 74), "radius": 8.0},
		[["a", func() -> void:
			var g: FoliageKit.Group = groups["conifer"]
			_fire_tree = g.nearest(player.global_position)
			chrono.say("That conifer is on fire. Unrelated to my arrival. Probably.")]])
	director.add("snowfall", "labf_snowfall", {"at": Vector3(0, 5, 34), "radius": 8.0},
		[["a", func() -> void:
			_snowing = true
			chrono.say("Snow load increasing on the left. Spruce are built for it. You are not.")]])
	director.add("drought", "labf_drought", {"at": Vector3(0, 5, -14), "radius": 8.0},
		[["a", func() -> void:
			_drought = true
			chrono.say("Dry season. Everything green is reconsidering.")]])
	director.add("timer", "labf_timer", {"time": 5.0},
		[["a", func() -> void: chrono.say("Twenty-six kinds of plant. I have opinions about nine.")],
		 ["b", func() -> void: chrono.say("Botany survey. Try not to eat the berries.")]])
	director.add("harvest", "labf_harvest", {"at": Vector3(0, 5, -104), "radius": 8.0},
		[["a", func() -> void: chrono.say("Wheat, hedges, oak. We are nearly somewhere with bread.")]])


func _era_process(delta: float) -> void:
	var d := wdelta(delta)
	if _gust > 0.0:
		_gust -= d
		FoliageKit.set_wind(Vector2(0.94, 0.34), 2.4 if _gust > 0.0 else 1.0, 1.25 if _gust > 0.0 else 1.0)
		mark("wind_gust")
	if _fire_tree >= 0 and _fire < 1.0:
		_fire = minf(_fire + d * 0.08, 1.0)
		var g: FoliageKit.Group = groups["conifer"]
		g.set_burn(_fire_tree, _fire)
		var ferns: FoliageKit.Group = groups["fern"]
		for i in ferns.within(g.position_of(_fire_tree), 6.0 * _fire):
			ferns.set_burn(i, maxf(ferns.get_burn(i), _fire))
		mark("burn_spread")
	if _snowing and _snow < 0.9:
		_snow = minf(_snow + d * 0.06, 0.9)
		(groups["spruce"] as FoliageKit.Group).set_snow(_snow)
		mark("snow_load")
	if _drought and _dry < 0.7:
		_dry = minf(_dry + d * 0.05, 0.7)
		FoliageKit.set_season(Color(1.0, 0.97, 0.9), _dry)
		mark("drought")
	if player.global_position.z < -98.0 and not objective_is_done("survey"):
		complete_objective("survey")


func required_mechanics() -> Array:
	return ["wind_gust", "burn_spread", "snow_load", "drought", "checkpoint", "event", "portal_entered"]


func autopilot_plan() -> Array:
	var AP := AutoPilot
	return [
		AP.label("carboniferous"),
		AP.goto(on_ground(0, 118), {"sprint": true}),
		AP.label("cretaceous"),
		AP.goto(on_ground(0, 72), {"sprint": true}),
		AP.run(func() -> void: chrono.trigger_glitch("time_stutter")),
		AP.label("ice age"),
		AP.goto(on_ground(0, 30), {"sprint": true}),
		AP.label("indus"),
		AP.goto(on_ground(0, -16), {"sprint": true}),
		AP.label("chola"),
		AP.goto(on_ground(0, -62), {"sprint": true}),
		AP.label("medieval"),
		AP.goto(on_ground(0, -106), {"sprint": true}),
		AP.until(func() -> bool: return portal.is_open, 10.0),
		AP.label("portal"),
		AP.goto(func() -> Vector3: return portal.global_position, {"tol": 0.6}),
	]


func _reset_look() -> void:
	FoliageKit.set_season(Color.WHITE, 0.0)
	FoliageKit.set_wind(Vector2(0.94, 0.34), 1.0, 1.0)
	_gust = 0.0
	_drought = false
	_snowing = false
	_fire_tree = -1
	(groups["conifer"] as FoliageKit.Group).burn_all(0.0)
	(groups["fern"] as FoliageKit.Group).burn_all(0.0)
	(groups["spruce"] as FoliageKit.Group).set_snow(0.0)


func capture_shots() -> Array:
	var g := func(x: float, z: float, lift: float) -> Vector3: return on_ground(x, z, lift)
	return [
		{"name": "carbo_wide", "from": g.call(9, 141, 3.0), "to": Vector3(-16, 15, 112), "from2": g.call(5, 136, 2.4), "time": 0.6, "setup": _reset_look},
		{"name": "snow_trio", "from": g.call(SNOW_AT.x, SNOW_AT.z + 27, 4.0), "to": SNOW_AT + Vector3(0, 12, 0), "time": 0.6},
		{"name": "burn_0_50_100", "from": g.call(BURN_AT.x, BURN_AT.z + 37, 5.0), "to": BURN_AT + Vector3(0, 11, 0), "time": 0.6, "setup": _set_burn_demo},
		{"name": "burn_ground", "from": g.call(GROUND_AT.x, GROUND_AT.z + 14, 3.2), "to": GROUND_AT + Vector3(0, 5.2, 2), "time": 0.6, "fov": 50.0},
		{"name": "far_lod", "from": Vector3(95, 38, 120), "to": Vector3(-25, 8, 60), "time": 0.6, "fov": 50.0},
		{"name": "carbo_floor", "from": g.call(2.5, 111, 1.5), "to": g.call(13, 104, 2.6), "time": 0.6, "fov": 55.0},
		{"name": "calamites", "from": g.call(5, 116, 2.0), "to": Vector3(24, 10, 127), "time": 0.6},
		{"name": "creta_wide", "from": g.call(8, 94, 3.0), "to": Vector3(-18, 17, 70), "from2": g.call(5, 90, 2.5), "time": 0.6},
		{"name": "creta_floor", "from": g.call(-1.5, 66, 1.5), "to": g.call(-10, 58, 0.8), "to2": g.call(9, 58, 0.8), "time": 0.6, "fov": 55.0},
		{"name": "ginkgo", "from": g.call(3, 62, 2.2), "to": Vector3(26, 9, 79), "time": 0.6},
		{"name": "ice_wide", "from": g.call(-3, 50, 3.2), "to": Vector3(6, 7, 24), "time": 0.6},
		{"name": "ice_floor", "from": g.call(-2.5, 20, 1.3), "to": g.call(-12, 12, 0.6), "time": 0.6, "fov": 55.0},
		{"name": "indus_wide", "from": g.call(6, 4, 3.0), "to": Vector3(-22, 9, -18), "time": 0.6},
		{"name": "pond", "from": g.call(5, 0, 5.5), "to": Vector3(POND.x + 1, 3.5, POND.y - 2), "time": 0.6},
		{"name": "crop_scrub", "from": g.call(-3, -24, 1.7), "to": g.call(-22, -34, 0.6), "time": 0.6},
		{"name": "chola_wide", "from": g.call(5, -42, 3.0), "to": Vector3(-20, 13, -64), "time": 0.6},
		{"name": "banana_banyan", "from": g.call(2, -58, 2.2), "to": Vector3(24, 8, -70), "time": 0.6},
		{"name": "medieval_wide", "from": g.call(4, -84, 3.2), "to": Vector3(-26, 9, -104), "time": 0.6},
		{"name": "wheat_hedge", "from": g.call(-4, -95, 5.0), "to": g.call(24, -116, 0.5), "time": 0.6},
		{"name": "meadow", "from": g.call(-2.5, -133, 1.3), "to": g.call(-20, -119, 1.6), "time": 0.6, "fov": 55.0},
	]
