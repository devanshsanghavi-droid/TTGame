extends EraBase
## ERA 1: CAMBRIAN TIDAL FLATS, 510 million years ago.
## Bare rock, no life on land, thin air. Gather trilobites from tide pools to
## recharge CHRONO while the tide comes in, then reach the portal on the rock
## spire before the causeway drowns.
##
## New mechanics: OXYGEN meter, rising TIDE that floods the route, creature
## that blocks water routes (Anomalocaris), gas vents.
## Set-piece: the drowning causeway and the spire climb.

const POOLS := [
	{"c": Vector2(-28, 104), "r": 7.0, "depth": 1.0, "n": 2},
	{"c": Vector2(34, 76), "r": 8.0, "depth": 1.1, "n": 2},
	{"c": Vector2(-50, 22), "r": 9.0, "depth": 1.2, "n": 2},
	{"c": Vector2(22, 6), "r": 7.0, "depth": 1.0, "n": 2},
	{"c": Vector2(-14, -50), "r": 8.0, "depth": 1.1, "n": 2},
]
const CAUSEWAY := [Vector2(30, -62), Vector2(50, -86), Vector2(36, -110), Vector2(44, -137)]
const SPIRE := Vector2(44, -148)
const SPIRE_TOP := 30.0
const RIDGE_X := 72.0
const VENTS := [Vector2(2, 90), Vector2(-20, 44), Vector2(46, 30), Vector2(6, -6)]
const NEED := 5

var tide := -1.0
var tide_rate := 0.0
var surge := false
var trilobites_got := 0

var _n_big := FastNoiseLite.new()
var _n_det := FastNoiseLite.new()
var _water: MeshInstance3D
var _pool_levels: Array = []
var _pool_nodes: Array = []
var _trilobites: Array = []
var _anomalo: CambrianFauna.Anomalocaris
var _vent_nodes: Array = []
var _vents_awake := false
var _vent_pattern := 0
var _wave_t := -1.0
var _wave_len := 6.0
var _wave_count := 0
var _wave_amp := 0.0
var _hiccup := false
var _tide_started := false
var _base_rate := 0.008
var _in_vent := false
var _stampede_nodes: Array = []
var _pool_h0: Array = []


func _configure() -> void:
	era_id = "cambrian"
	spawn_pos = Vector3(0, 12, 142)
	spawn_yaw = 0.0
	time_limit = 420.0
	flash_tint = Color(0.95, 0.8, 0.6)
	nav_bounds = AABB(Vector3(-110, -6, -165), Vector3(220, 50, 330))
	_n_big.seed = 510
	_n_big.frequency = 0.007
	_n_big.fractal_octaves = 4
	_n_det.seed = 77
	_n_det.frequency = 0.035
	_n_det.fractal_octaves = 3
	for p in POOLS:
		_pool_h0.append(_height_base(p.c.x, p.c.y))


# ------------------------------------------------------------------ terrain
func _channel2(x: float) -> float:
	return -22.0 + sin(x * 0.025 + 1.0) * 9.0


func _dist_causeway(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	for i in CAUSEWAY.size() - 1:
		var a: Vector2 = CAUSEWAY[i]
		var b: Vector2 = CAUSEWAY[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _height(x: float, z: float) -> float:
	var h := _height_base(x, z)
	var n2 := _n_det.get_noise_2d(x, z)
	# tide pools: a levelled apron, a bowl, and a low rim
	for i in POOLS.size():
		var p: Dictionary = POOLS[i]
		var d := Vector2(x - p.c.x, z - p.c.y).length()
		var r: float = p.r
		if d < r * 1.9:
			h = lerpf(h, float(_pool_h0[i]) + n2 * 0.04, 1.0 - smoothstep(r * 1.3, r * 1.9, d))
			h -= float(p.depth) * (1.0 - smoothstep(r * 0.35, r, d))
			h += 0.2 * exp(-pow((d - r * 1.12) / (r * 0.16), 2.0))
	# rock causeway to the spire
	var dc := _dist_causeway(x, z)
	if dc < 7.0:
		var k := 1.0 - smoothstep(2.4, 7.0, dc)
		h = lerpf(h, maxf(h, 1.75 + n2 * 0.45), k)
	var ds := Vector2(x - SPIRE.x, z - SPIRE.y).length()
	if ds < 18.0:
		h = lerpf(h, maxf(h, 3.0), 1.0 - smoothstep(8.0, 18.0, ds))
	return h


func _height_base(x: float, z: float) -> float:
	var h: float
	if z >= 118.0:
		h = 2.7 + smoothstep(118.0, 150.0, z) * 5.5 + smoothstep(168.0, 208.0, z) * 30.0
	elif z >= -70.0:
		h = lerpf(-0.5, 2.7, (z + 70.0) / 188.0)
	else:
		var t := clampf((-70.0 - z) / 75.0, 0.0, 1.0)
		h = -0.5 - t * t * (3.0 - 2.0 * t) * 9.5
	var n1 := _n_big.get_noise_2d(x, z)
	var n2 := _n_det.get_noise_2d(x, z)
	var land := smoothstep(150.0, 185.0, z)
	var head := smoothstep(150.0, 200.0, absf(x)) * smoothstep(-90.0, -30.0, z)
	h += n1 * (0.5 + land * 9.0 + head * 6.0) + n2 * (0.1 + land * 1.6 + head * 1.5)
	h += head * 24.0
	h += sin(z * 0.11 + n1 * 3.0) * 0.15 * (1.0 - land) * (1.0 - head)
	# tidal channels
	var c1 := 52.0 + sin(x * 0.03) * 10.0
	h -= 1.2 * exp(-pow((z - c1) / 7.0, 2.0)) * (1.0 - head)
	var c2 := _channel2(x)
	var ridge := exp(-pow((x - RIDGE_X) / 10.0, 2.0))
	h -= 3.1 * exp(-pow((z - c2) / 9.5, 2.0)) * (1.0 - ridge) * (1.0 - head)
	h += ridge * exp(-pow((z - c2) / 15.0, 2.0)) * 0.95
	return h


func _vcolor(x: float, z: float, h: float, flat: float) -> Color:
	var n := _n_det.get_noise_2d(x * 0.6 + 300.0, z * 0.6)
	var rocky := clampf(n * 1.6 + 0.15, 0.0, 1.0)
	var dc := _dist_causeway(x, z)
	rocky = maxf(rocky, 1.0 - smoothstep(3.0, 8.0, dc))
	rocky = maxf(rocky, smoothstep(125.0, 140.0, z))
	rocky = maxf(rocky, exp(-pow((x - RIDGE_X) / 12.0, 2.0)) * exp(-pow((z - _channel2(x)) / 16.0, 2.0)))
	var damp := 0.0
	for p in POOLS:
		var d := Vector2(x - p.c.x, z - p.c.y).length()
		damp = maxf(damp, 1.0 - smoothstep(p.r * 0.8, p.r * 1.5, d))
	# shallow hollows on the flats keep a film of water
	if z < 118.0 and flat > 0.97:
		damp = maxf(damp, clampf((-_n_big.get_noise_2d(x * 3.0, z * 3.0) - 0.25) * 2.2, 0.0, 0.75))
	return Color(rocky, damp, 0.0)


# -------------------------------------------------------------------- world
func _build_world() -> void:
	EnvKit.build(self, {
		"hdri": "qwantani_dusk_2_puresky", "sky_yaw": -1.65, "sky_energy": 0.8,
		"sun_energy": 2.4, "sun_color": Color(1.0, 0.82, 0.62), "sun_angular": 1.6,
		"fog_color": Color(0.4, 0.4, 0.43), "fog_density": 0.0009, "fog_aerial": 0.9, "fog_sun_scatter": 0.08, "fog_sky_affect": 0.0,
		"vol_density": 0.003, "vol_albedo": Color(0.85, 0.83, 0.82), "vol_anisotropy": 0.75, "vol_length": 140.0, "vol_sun": 1.2, "vol_ambient": 0.15,
		"exposure": 0.72, "white": 8.0, "contrast": 1.16, "saturation": 0.86,
		"grade_shadow": Color(0.008, 0.016, 0.026), "grade_mid": Color(0.485, 0.48, 0.468), "grade_high": Color(1.0, 0.95, 0.87),
		"shadow_distance": 260.0, "sdfgi_energy": 0.7, "ambient_energy": 0.75,
	})
	terrain = Terrain.create(self, {
		"size": 420.0, "res": 281, "chunks": 8, "height": _height, "color": _vcolor,
		"a": "damp_beach_sand", "b": "rock_face_04", "c": "low_tide_rocks",
		"a_scale": 0.22, "b_scale": 0.1, "c_scale": 0.2,
		"a_tint": Color(0.84, 0.78, 0.7), "b_tint": Color(0.78, 0.72, 0.68), "c_tint": Color(0.62, 0.58, 0.54),
		"slope": Vector2(0.74, 0.9), "macro": 0.32, "lod_distance": 190.0,
	})
	water_level = tide
	_water = WaterKit.plane(self, Vector3(0, tide, -40), Vector2(1600, 1600), {
		"shallow": Color(0.2, 0.25, 0.2), "deep": Color(0.025, 0.05, 0.055), "clarity": 2.4,
		"wave_scale": 0.05, "wave_strength": 0.5, "swell": 0.05, "foam_width": 0.3, "roughness": 0.2, "subdiv": 96})
	_water.add_to_group("flash_hidden")
	terrain.set_wet_level(tide + 0.3, 0.5)
	_build_pools()
	_build_spire()
	_build_rocks()
	_build_vents()
	_build_flash_ruins()
	# Anomalocaris patrols the deep channel
	var path: Array = []
	for x in [-62.0, -40.0, -15.0, 10.0, 34.0, 52.0, 34.0, 10.0, -15.0, -40.0]:
		path.append(Vector3(x, -1.5, _channel2(x)))
	_anomalo = CambrianFauna.Anomalocaris.new()
	add_child(_anomalo)
	_anomalo.setup(self, path, 1.15)
	_anomalo.add_to_group("flash_hidden")
	_anomalo.bumped.connect(_on_bumped)
	portal = Portal.make(self, Vector3(SPIRE.x, SPIRE_TOP, SPIRE.y - 0.8))
	Sfx.set_ambience({"wind": 0.55, "surf": 0.85})


func _build_pools() -> void:
	for i in POOLS.size():
		var p: Dictionary = POOLS[i]
		var level: float = float(_pool_h0[i]) + 0.07
		_pool_levels.append(level)
		var disc := WaterKit.plane(self, Vector3(p.c.x, level, p.c.y), Vector2(p.r * 2.8, p.r * 2.8), {
			"shallow": Color(0.2, 0.26, 0.2), "deep": Color(0.03, 0.065, 0.055), "clarity": 1.5,
			"wave_strength": 0.16, "swell": 0.0, "foam_width": 0.05, "roughness": 0.08, "subdiv": 2, "wave_speed": 0.006,
			"disc_radius": p.r * 1.22})
		disc.add_to_group("flash_hidden")
		_pool_nodes.append(disc)
		# microbial film around the rim: the only "life" on land
		MatLib.decal(self, Vector3(p.c.x, level, p.c.y), Vector3(p.r * 3.4, 3.0, p.r * 3.4), "damp", i * 1.3, 0.6)
		for k in int(p.n):
			var a := rng.randf() * TAU
			var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, p.r * 0.42)
			var pos := Vector3(p.c.x + off.x, 0, p.c.y + off.z)
			pos.y = terrain.height_at(pos.x, pos.z)
			var t := CambrianFauna.Trilobite.new()
			add_child(t)
			t.setup(self, pos, p.r * 0.5, rng.randf_range(0.95, 1.35), Color(0.17, 0.11, 0.08).lerp(Color(0.12, 0.11, 0.1), rng.randf()))
			t.handle = Interactable.make(t, Vector3(0, 0.1, 0), "Gather trilobite", _gather.bind(t), 2.0, true)
			add_poi(t, "Trilobite")
			_trilobites.append(t)


func _build_spire() -> void:
	var banded := MatLib.pbr("cliff_side", {"scale": 0.09, "tint": Color(0.6, 0.5, 0.46)})
	var core_h := SPIRE_TOP - 2.0
	MeshKit.collider_box(self, Vector3(SPIRE.x, 2.0 + core_h * 0.5, SPIRE.y), Vector3(8.0, core_h, 8.0))
	MeshKit.occluder_box(self, Vector3(SPIRE.x, 2.0 + core_h * 0.5, SPIRE.y), Vector3(6.0, core_h, 6.0))
	var holder := Node3D.new()
	holder.name = "Spire"
	add_child(holder)
	MeshKit.mi(MeshKit.strata_mesh(510, SPIRE_TOP - 1.0, 4.5, 0.82, 44, 1.9), banded, Vector3(SPIRE.x, 1.0, SPIRE.y), holder)
	# fallen blocks at the foot (the south face, the climb, stays clear)
	for k in 8:
		var a := k / 8.0 * TAU + 0.4
		if a > 0.8 and a < 2.4:
			continue
		var r := 7.5 + sin(k * 2.7) * 1.5
		var pos := Vector3(SPIRE.x + cos(a) * r, 0, SPIRE.y + sin(a) * r)
		pos.y = terrain.height_at(pos.x, pos.z) + 0.8
		MeshKit.solid_rock(self, pos, Vector3(2.6, 2.4 + sin(k) * 0.8, 2.6), banded, 80 + k, k * 1.1)
	ClimbSurface.make(self, Vector3(SPIRE.x, 2.0 + core_h * 0.5, SPIRE.y + 4.0), 5.0, core_h, 0.0, true, 1.1)
	MatLib.decal(self, Vector3(SPIRE.x, 12.0, SPIRE.y + 4.6), Vector3(3.0, 22.0, 3.5), "damp", 0.0, 0.7)
	# smaller stacks on the flats: scale references and cover from the glare
	var near := [[-72, 62, 13, 4.2], [90, 98, 17, 5.2], [-98, -8, 22, 6.5], [106, 18, 15, 5.0], [-66, 124, 11, 4.6], [-6, 40, 7, 2.8]]
	for n in near.size():
		var st: Array = near[n]
		var base := Vector3(st[0], terrain.height_at(st[0], st[1]) - 1.2, st[1])
		MeshKit.mi(MeshKit.strata_mesh(300 + n, st[2], st[3], 0.7, 22, 1.6), banded, base, holder).rotation.y = n * 1.4
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = st[3] * 0.92
		cyl.height = st[2]
		cs.shape = cyl
		body.add_child(cs)
		body.position = base + Vector3.UP * st[2] * 0.5
		add_child(body)
	# distant sea stacks: the huge things on the horizon
	var far_rock := MatLib.pbr("cliff_side", {"scale": 0.035, "tint": Color(0.5, 0.44, 0.42)})
	var stacks := [[-150, -270, 52, 20], [140, -330, 70, 26], [-30, -410, 96, 34], [270, -230, 58, 24], [-300, -200, 64, 28], [60, -540, 130, 44], [-210, -360, 44, 16]]
	for s in stacks.size():
		var st: Array = stacks[s]
		var m := MeshKit.mi(MeshKit.strata_mesh(120 + s * 5, st[2] + 8.0, st[3], 0.5 + 0.25 * absf(sin(s * 2.0)), 30, 5.0 + s * 1.7), far_rock, Vector3(st[0], -8.0, st[1]), holder)
		m.scale = Vector3(1.0 + 0.5 * absf(sin(s * 1.1)), 1.0, 1.0)
		m.rotation.y = s * 1.3
		m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _build_rocks() -> void:
	var dark := MatLib.pbr("rock_face_04", {"scale": 0.28, "tint": Color(0.8, 0.76, 0.72)})
	var pale := MatLib.pbr("cliff_side", {"scale": 0.16, "tint": Color(0.62, 0.52, 0.48)})
	var on_flats := func(x: float, z: float, _h: float) -> float:
		for p in POOLS:
			if Vector2(x - p.c.x, z - p.c.y).length() < p.r * 1.05:
				return 0.0
		return 1.0
	Scatter.rocks(self, {"count": 420, "seed": 3, "terrain": terrain, "rect": Rect2(-150, -68, 300, 205), "scale": Vector2(0.1, 0.45),
		"material": dark, "sink": 0.3, "align": 0.6, "accept": on_flats, "visibility_end": 110.0, "subdiv": 2, "shadows": false})
	Scatter.rocks(self, {"count": 70, "seed": 9, "terrain": terrain, "rect": Rect2(-150, -60, 300, 195), "scale": Vector2(0.6, 1.7),
		"material": dark, "sink": 0.35, "align": 0.4, "accept": on_flats, "collide": true, "visibility_end": 240.0})
	Scatter.rocks(self, {"count": 34, "seed": 14, "terrain": terrain, "rect": Rect2(-150, 118, 300, 60), "scale": Vector2(1.6, 4.6),
		"material": pale, "sink": 0.4, "collide": true, "stretch_y": Vector2(0.8, 1.5)})
	# big slabs marking the causeway and the ridge crossing
	Scatter.rocks(self, {"count": 16, "seed": 21, "terrain": terrain, "center": Vector3(RIDGE_X, 0, _channel2(RIDGE_X)), "radius": 17.0,
		"scale": Vector2(1.2, 2.6), "material": pale, "sink": 0.55, "collide": true, "stretch_y": Vector2(0.5, 0.8),
		"accept": func(x: float, _z: float, _h: float) -> float: return 1.0 if absf(x - RIDGE_X) > 3.5 else 0.0})
	for i in CAUSEWAY.size() - 1:
		var a: Vector2 = CAUSEWAY[i]
		var b: Vector2 = CAUSEWAY[i + 1]
		for k in 7:
			var t := (k + 0.5) / 7.0
			var c := a.lerp(b, t)
			var side := (b - a).orthogonal().normalized() * (4.6 + sin(i * 7 + k * 2.0) * 1.0) * (1.0 if k % 2 == 0 else -1.0)
			var pos := Vector3(c.x + side.x, 0, c.y + side.y)
			pos.y = terrain.height_at(pos.x, pos.z) + 0.3
			MeshKit.solid_rock(self, pos, Vector3(1.9, 2.2 + sin(k * 1.7) * 0.8, 1.9), pale, 200 + i * 10 + k, k * 0.9)


func _build_vents() -> void:
	for i in VENTS.size():
		var v: Vector2 = VENTS[i]
		var pos := Vector3(v.x, terrain.height_at(v.x, v.y), v.y)
		var holder := Node3D.new()
		holder.position = pos
		add_child(holder)
		MatLib.decal(holder, Vector3.ZERO, Vector3(7, 2, 7), "soot", i * 0.9, 0.6)
		MatLib.decal(holder, Vector3.ZERO, Vector3(11, 2, 11), "sand", i * 2.1, 0.3)
		var gp := GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 1.6
		pm.direction = Vector3(0.25, 1, 0.1)
		pm.spread = 22.0
		pm.initial_velocity_min = 0.7
		pm.initial_velocity_max = 1.7
		pm.gravity = Vector3(0.35, 0.25, 0.1)
		pm.scale_min = 1.6
		pm.scale_max = 3.6
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.74, 0.7, 0.5, 0.0))
		ramp.add_point(0.2, Color(0.72, 0.68, 0.5, 0.34))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.58, 0.5, 0.0))
		var rt := GradientTexture1D.new()
		rt.gradient = ramp
		pm.color_ramp = rt
		gp.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1.4, 1.4)
		var qm := StandardMaterial3D.new()
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.vertex_color_use_as_albedo = true
		qm.albedo_texture = MatLib._decal_texture(3)
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		qm.proximity_fade_enabled = true
		qm.proximity_fade_distance = 0.8
		qm.disable_receive_shadows = false
		q.material = qm
		gp.draw_pass_1 = q
		gp.amount = 28
		gp.lifetime = 4.5
		gp.emitting = false
		gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gp.visibility_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 14, 16))
		holder.add_child(gp)
		_vent_nodes.append({"pos": pos, "fx": gp, "active": false, "phase": i * 2.7})


## Weathered pillars from some other age: only visible during an era-flash glitch.
func _build_flash_ruins() -> void:
	var b := BlockBatch.new()
	b.material = MatLib.pbr("sandstone_blocks_08", {"scale": 0.35, "tint": Color(0.85, 0.78, 0.66)})
	b.collide = false
	add_child(b)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for i in 16:
		var x := r.randf_range(-80, 90)
		var z := r.randf_range(-55, 110)
		var y := terrain.height_at(x, z)
		var hgt := r.randf_range(2.0, 7.0)
		b.add(Vector3(x, y + hgt * 0.5 - 0.4, z), Vector3(1.3, hgt, 1.3), r.randf() * 3.0, false, Vector3(r.randf_range(-0.12, 0.12), 0, r.randf_range(-0.12, 0.12)))
		if i % 3 == 0:
			b.add(Vector3(x + 1.6, y + 0.3, z + 0.8), Vector3(2.6, 0.7, 1.2), r.randf() * 3.0, false, Vector3(0.1, 0, 0.3))
	b.commit()
	b.visible = false
	b.add_to_group("flash_only")


# -------------------------------------------------------------------- setup
func _setup() -> void:
	add_meter("oxygen", "Oxygen", 1.0, Color(0.8, 0.86, 0.84))
	add_meter("charge", "CHRONO charge", 0.2, Color(0.86, 0.78, 0.55))
	add_objective("trilobites", "Recharge CHRONO: gather trilobites from tide pools (0/%d)" % NEED)
	add_objective("spire", "Reach the portal on the rock spire", true, true)
	chrono.glitch_pool = ["gravity_flicker", "era_flash", "time_stutter", "yell"]
	chrono.glitch_interval = Vector2(42, 70)
	chrono.register_glitch("concentrator_hiccup", 7.0,
		func() -> void: _hiccup = true,
		func() -> void: _hiccup = false,
		["Oxygen concentrator is rebooting. Breathe slowly. Or not at all, that also works.",
		 "Concentrator fault. For the next few seconds the air is entirely your problem."])
	chrono.glitch_lines["era_flash"] = [
		"Temporal bleed. Same beach, a few hundred million years on. The sea has stepped out.",
		"We are briefly in the wrong epoch. Nobody is home. Walk on the sea floor while it lasts."]
	chrono.glitch_started.connect(func(kind: String) -> void:
		if kind == "yell":
			for t in _trilobites:
				if not t.collected:
					t.startle(player.global_position, 4.0))
	add_checkpoint(on_ground(34, 66, 1.0), 9.0, 1)
	add_checkpoint(on_ground(26, 14, 1.0), 9.0, 2)
	add_checkpoint(on_ground(RIDGE_X, -40, 1.0), 9.0, 3)
	add_checkpoint(on_ground(30, -60, 1.0), 7.0, 4)

	director.add("air_briefing", "cam_air_briefing", {"time": 2.5}, [
		["thin", func() -> void:
			chrono.say("Welcome to the Cambrian. Oxygen is about a third of what your lungs signed up for.")
			chrono.say("I am concentrating air for you. Walk and I keep up. Sprint and I do not.")],
		["blunt", func() -> void:
			chrono.say("Five hundred and ten million years ago. No plants on land. No animals on land. Just you, and I have notes.")
			chrono.say("The air is thin. Walking is fine. Sprinting is a short conversation with your lungs.")]])
	director.add("charge_briefing", "cam_charge_briefing", {"time": 11.0}, [
		["a", func() -> void:
			chrono.say("I am at twenty percent. Trilobites carry a usable bioelectric field. Gather five from the tide pools.")
			chrono.say("They will be fine. They will be annoyed. The portal opens on that spire once I am charged.")]])
	director.add("tide_turns", "cam_tide_turn", {"time": 38.0}, [
		["slow", func() -> void:
			_begin_tide(0.0075)
			chrono.say("The tide has turned. The Moon is closer in this era, so the sea is rather keen.")],
		["brisk", func() -> void:
			_begin_tide(0.0105)
			chrono.say("Tide is coming in. Days are twenty-one hours long here and the ocean is in a hurry.")]])
	director.add("vents_wake", "cam_gas_vents", {"at": on_ground(2, 100), "radius": 16.0}, [
		["pattern_a", func() -> void: _wake_vents(0)],
		["pattern_b", func() -> void: _wake_vents(1)]])
	director.add("stampede", "cam_trilobite_stampede", {"at": on_ground(-50, 22), "radius": 15.0}, [
		["from_west", func() -> void: _stampede(-1.0)],
		["from_east", func() -> void: _stampede(1.0)]])
	director.add("predator_reveal", "cam_predator_reveal", {"when": func() -> bool:
		return player.global_position.z < 2.0 and absf(player.global_position.z - _channel2(player.global_position.x)) < 30.0}, [
		["surfaces_left", func() -> void: _reveal_predator(-18.0)],
		["surfaces_right", func() -> void: _reveal_predator(18.0)]])
	director.add("rogue_wave", "cam_rogue_wave", {"when": func() -> bool: return _tide_started and tide > -0.72 and player.global_position.z < 70.0}, [
		["single", func() -> void: _start_wave(1, 0.85)],
		["double", func() -> void: _start_wave(2, 0.65)]], {"delay": 2.0})
	director.add("drowning_causeway", "cam_drowning_causeway", {"when": func() -> bool: return trilobites_got >= NEED}, [
		["a", func() -> void: _begin_surge()]])
	director.add("spire_commentary", "cam_spire_commentary", {"at": on_ground(30, -60), "radius": 9.0}, [
		["a", func() -> void: chrono.say("That spire is the tallest thing on this continent. Admittedly the competition is gravel.")],
		["b", func() -> void: chrono.say("Portal is at the top. The climb is thirty metres. I will be very encouraging from your wrist.")]])


func _begin_tide(rate: float) -> void:
	_tide_started = true
	_base_rate = rate


func _begin_surge() -> void:
	surge = true
	mark("tide_surge")
	reveal_objective("spire")
	chrono.say("Fully charged. Portal is forming on the spire. Also, the tide has noticed.", true)
	chrono.say("The causeway goes under in about a minute. I would not stop to admire anything.")
	hud.toast("The tide is surging")
	camera_rig.add_shake(0.5)
	Sfx.play("roar", player.global_position + Vector3(0, 0, -40), -6.0, 0.5)


func _wake_vents(pattern: int) -> void:
	_vents_awake = true
	_vent_pattern = pattern
	chrono.say("Gas vents. Mostly carbon dioxide and hydrogen sulphide. The yellow haze is not a suggestion.")


func _start_wave(count: int, amp: float) -> void:
	_wave_count = count
	_wave_amp = amp
	_wave_t = 0.0
	mark("rogue_wave")
	chrono.say("Wave. A big one." if count == 1 else "Waves. Plural. Brace.", true)


func _stampede(side: float) -> void:
	mark("stampede")
	chrono.say("They have seen you. Trilobite eyes are made of calcite crystal. Literal stone-cold stares.")
	var p: Dictionary = POOLS[2]
	for i in 12:
		var t := CambrianFauna.Trilobite.new()
		add_child(t)
		var start := Vector3(p.c.x + side * (11.0 + i * 0.5), 0, p.c.y - 7.0 + i * 1.2)
		start.y = terrain.height_at(start.x, start.z)
		t.setup(self, start, 60.0, rng.randf_range(0.7, 1.1))
		t.home = Vector3(p.c.x - side * 30.0, 0, p.c.y + rng.randf_range(-14, 14))
		t.roam = 4.0
		t._target = t.home
		t._flee = 14.0
		_stampede_nodes.append(t)
	for t in _trilobites:
		if not t.collected:
			t.startle(player.global_position, 3.0)


func _reveal_predator(dx: float) -> void:
	var x := clampf(player.global_position.x + dx, -58.0, 54.0)
	_anomalo.global_position = Vector3(x, tide - 0.2, _channel2(x))
	_anomalo.state = "investigate"
	_anomalo._investigate_pos = Vector3(player.global_position.x, tide, _channel2(player.global_position.x))
	_anomalo._investigate_t = 7.0
	camera_rig.add_shake(0.35)
	Sfx.play("splash", _anomalo.global_position)
	chrono.say("Anomalocaris. Records say one metre long. Records were written by people who were not here.", true)
	chrono.say("It will not eat you. It will, however, object to you being in its channel.")


func _on_bumped(_p: Player) -> void:
	mark("anomalocaris_block")
	set_meter("oxygen", meter("oxygen") - 0.12)
	camera_rig.add_shake(0.8)
	chrono.say_once("bump", "It has reviewed your application to cross and declined. Try the rock ridge to the east.")
	hud.toast("Shoved back by Anomalocaris")


func _gather(_p: Player, t: CambrianFauna.Trilobite) -> void:
	if t.collected:
		return
	t.collected = true
	t.visible = false
	remove_poi(t)
	trilobites_got += 1
	mark("trilobite_gather")
	mark("chrono_recharge")
	set_meter("charge", 0.2 + 0.16 * mini(trilobites_got, NEED))
	set_objective_text("trilobites", "Recharge CHRONO: gather trilobites from tide pools (%d/%d)" % [mini(trilobites_got, NEED), NEED])
	Sfx.play("pickup", t.global_position)
	match trilobites_got:
		1: chrono.say("Absorbing bioelectric field. It tastes like a battery that has opinions.")
		3: chrono.say("Three. Their species lasts another two hundred and seventy million years. They will get over this.")
	if trilobites_got >= NEED:
		complete_objective("trilobites")


# ------------------------------------------------------------------ process
func water_height_at(pos: Vector3) -> float:
	if era_flash_active:
		return -1000.0
	var w := water_level
	for i in POOLS.size():
		var p: Dictionary = POOLS[i]
		if Vector2(pos.x - p.c.x, pos.z - p.c.y).length() < p.r * 1.1:
			w = maxf(w, _pool_levels[i])
	return w


func _update_tide(d: float) -> void:
	tide_rate = 0.0
	if _tide_started:
		tide_rate = _base_rate
	if surge:
		tide_rate = 0.036 if tide < 2.4 else 0.012
	tide = minf(tide + tide_rate * d, 4.4)
	if tide_rate > 0.0:
		mark("tide_rise")
	var wave := 0.0
	if _wave_t >= 0.0:
		_wave_t += d
		var k := _wave_t / _wave_len
		wave = sin(clampf(k, 0.0, 1.0) * PI) * _wave_amp
		if k >= 1.0:
			_wave_count -= 1
			_wave_t = 0.0 if _wave_count > 0 else -1.0
	water_level = tide + wave
	_water.position.y = water_level
	terrain.set_wet_level(water_level + 0.3, 0.5)
	for i in _pool_nodes.size():
		(_pool_nodes[i] as Node3D).visible = (water_level < _pool_levels[i] - 0.03) and not era_flash_active


func _era_process(delta: float) -> void:
	var d := wdelta(delta)
	_update_tide(d)
	# vents cycle on and off
	_in_vent = false
	for v in _vent_nodes:
		var on := false
		if _vents_awake:
			var cyc := fmod(elapsed + float(v.phase) + (3.0 if _vent_pattern == 1 else 0.0), 11.0)
			on = cyc < 5.0 and water_level < float(v.pos.y) + 0.4
		v.active = on
		(v.fx as GPUParticles3D).emitting = on
		if on and player.global_position.distance_to(v.pos) < 4.2:
			_in_vent = true
	# oxygen
	var o2 := meter("oxygen")
	var charge := meter("charge")
	var rate := 0.0
	if player.is_sprinting:
		rate = -0.055
		mark("oxygen_sprint_drain")
	elif player.state == Player.State.SWIM:
		rate = -0.018
		mark("swim")
	elif player.horizontal_speed() > 0.6 and not player.crouching:
		rate = -0.005
	else:
		rate = 0.014 + 0.035 * charge
	if _in_vent:
		rate -= 0.13
		mark("vent_gas")
		chrono.say_once("vent", "You are standing in the haze. The haze is the bad part.")
	if _hiccup:
		rate -= 0.045
	if rate < 0.0:
		mark("oxygen_drain")
	o2 = clampf(o2 + rate * delta, 0.0, 1.0)
	set_meter("oxygen", o2)
	player.sprint_allowed = o2 > 0.1
	player.speed_scale = 1.0 if o2 > 0.25 else lerpf(0.62, 1.0, o2 / 0.25)
	if o2 < 0.3:
		chrono.say_once("low_o2", "Oxygen is low. Stand still for a moment. I recommend it medically and personally.")
	if o2 <= 0.0 and player.alive:
		player.kill("oxygen")
	if player.state == Player.State.CLIMB and player.global_position.distance_to(Vector3(SPIRE.x, player.global_position.y, SPIRE.y)) < 9.0:
		mark("climb_spire")
	if player.global_position.y > SPIRE_TOP - 0.5 and not objective_is_done("spire") and objective_is_done("trilobites"):
		complete_objective("spire")
	# stampede extras leave once they have crossed
	for i in range(_stampede_nodes.size() - 1, -1, -1):
		var t: CambrianFauna.Trilobite = _stampede_nodes[i]
		if t._flee <= 0.5:
			t.queue_free()
			_stampede_nodes.remove_at(i)


func _on_era_flash(active: bool) -> void:
	if active:
		mark("flash_dry_seabed")
	for n in _pool_nodes:
		(n as Node3D).visible = not active


func _on_respawn() -> void:
	set_meter("oxygen", 0.85)


func _telemetry_extra() -> Dictionary:
	return {"tide": tide, "rate": tide_rate, "surge": surge, "trilobites": trilobites_got, "in_vent": _in_vent}


func required_mechanics() -> Array:
	return ["oxygen_drain", "oxygen_sprint_drain", "tide_rise", "tide_surge", "trilobite_gather", "chrono_recharge",
		"anomalocaris_block", "vent_gas", "rogue_wave", "stampede", "climb_spire", "checkpoint", "portal_entered"]


# ---------------------------------------------------------------- autopilot
func _nearest_trilobite() -> Node:
	var best: Node = null
	var bd := 1e9
	for t in _trilobites:
		if t.collected:
			continue
		var d: float = t.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = t
	return best


func autopilot_plan() -> Array:
	var AP := AutoPilot
	var gather := func() -> Node: return _nearest_trilobite()
	var rest := AP.until(func() -> bool: return meter("oxygen") > 0.8, 40.0)
	var plan: Array = [
		AP.label("down to the flats"),
		AP.goto(on_ground(-10, 122), {"direct": true}),
		AP.label("vent"),
		AP.goto(on_ground(2, 100), {"direct": true}),
		AP.drive(func(bot: AutoPilot, _d: float) -> bool:
			# stand in the haze once to prove it hurts, then step out
			var v: Dictionary = _vent_nodes[0]
			var to: Vector3 = v.pos - bot.player.global_position
			to.y = 0.0
			if to.length() > 1.5:
				bot.player.input.world_move = to.normalized()
			return int(mechanics.get("vent_gas", 0)) > 20 or bot.step_time > 14.0, 20.0),
		AP.label("pool 1"),
		AP.goto(on_ground(-24, 106), {"direct": true}),
		AP.use(gather, {"skip_if": func() -> bool: return trilobites_got >= 1}),
		AP.use(gather, {"skip_if": func() -> bool: return trilobites_got >= 2}),
		AP.label("pool 2"),
		AP.goto(on_ground(10, 92), {"direct": true}),
		AP.goto(on_ground(30, 78), {"direct": true}),
		AP.use(gather, {"skip_if": func() -> bool: return trilobites_got >= 3}),
		AP.use(gather, {"skip_if": func() -> bool: return trilobites_got >= 4}),
		rest,
		AP.label("pool 3 and the stampede"),
		AP.goto(on_ground(0, 58), {"direct": true}),
		AP.goto(on_ground(-42, 26), {"direct": true}),
		AP.until(func() -> bool: return director.has_fired("stampede"), 10.0),
		AP.label("pool 4"),
		AP.goto(on_ground(16, 10), {"direct": true}),
		AP.use(gather, {"skip_if": func() -> bool: return trilobites_got >= NEED}),
		AP.until(func() -> bool: return surge, 10.0),
		AP.label("try the channel"),
		AP.drive(func(bot: AutoPilot, _d: float) -> bool:
			# wade straight into Anomalocaris territory and get refused
			var px := bot.player.global_position.x
			var goal := Vector3(px, 0, _channel2(px) + 1.0)
			var to := goal - bot.player.global_position
			to.y = 0.0
			if to.length() > 1.0 and bot.player.water_depth < 1.1:
				bot.player.input.world_move = to.normalized()
			return int(mechanics.get("anomalocaris_block", 0)) > 0, 60.0),
		AP.label("ridge crossing"),
		AP.goto(on_ground(46, 2), {"direct": true}),
		AP.goto(on_ground(RIDGE_X, -6), {"direct": true}),
		AP.goto(on_ground(RIDGE_X, -40), {"direct": true, "timeout": 60.0}),
		rest,
		AP.label("causeway"),
		AP.goto(on_ground(34, -58), {"direct": true, "timeout": 60.0}),
		AP.goto(on_ground(50, -86), {"direct": true, "sprint": true}),
		AP.goto(on_ground(36, -110), {"direct": true}),
		AP.goto(on_ground(44, -134), {"direct": true, "sprint": true}),
		AP.label("spire"),
		AP.goto(Vector3(SPIRE.x, 3, SPIRE.y + 4.8), {"direct": true, "tol": 0.7, "ytol": 6.0}),
		AP.climb(SPIRE_TOP - 0.3, 60.0),
		AP.goto(func() -> Vector3: return portal.global_position, {"direct": true, "tol": 0.7}),
	]
	return plan


# ------------------------------------------------------------------ capture
func debug_set_tide(v: float) -> void:
	tide = v
	_tide_started = true
	_update_tide(0.0)


func capture_shots() -> Array:
	return [

		{"name": "establishing", "from": Vector3(-34, 13, 134), "to": Vector3(30, 6, -60), "from2": Vector3(-28, 11, 124), "to2": Vector3(36, 8, -80), "time": 3.5, "fov": 52,
			"setup": func() -> void: debug_set_tide(-0.9)},
		{"name": "tide pool", "from": Vector3(-21.5, 3.6, 110.5), "to": Vector3(-29, 2.2, 103), "from2": Vector3(-22.5, 3.3, 109.5), "time": 3.0, "fov": 50},
		{"name": "anomalocaris", "from": Vector3(15, 1.6, -11), "to": Vector3(9.5, -0.4, -18.5), "from2": Vector3(14, 1.4, -11.5), "to2": Vector3(7, -0.4, -19.5), "time": 3.0, "fov": 44,
			"setup": func() -> void:
				debug_set_tide(-0.55)
				_anomalo.global_position = Vector3(10, -0.8, _channel2(10) + 1.0)
				_anomalo.state = "investigate"
				_anomalo._investigate_pos = Vector3(-4, 0, _channel2(-4))
				_anomalo._investigate_t = 30.0
				player.teleport(on_ground(13, -9, 0.2))},
		{"name": "causeway surge", "from": Vector3(27, 4.6, -55), "to": Vector3(44, 14, -148), "from2": Vector3(30, 4.0, -60), "time": 3.0, "fov": 50,
			"setup": func() -> void:
				debug_set_tide(1.35)
				player.teleport(on_ground(34, -66, 0.2))},
		{"name": "spire summit", "from": Vector3(54, 35, -138), "to": Vector3(44, 31.2, -149), "from2": Vector3(52, 34, -139.5), "time": 3.0, "fov": 55,
			"setup": func() -> void:
				debug_set_tide(2.6)
				open_portal()
				player.teleport(Vector3(SPIRE.x + 1.5, SPIRE_TOP + 0.2, SPIRE.y + 1.8))},
		{"name": "flooded flats", "from": Vector3(60, 15, 150), "to": Vector3(10, 0, 20), "from2": Vector3(50, 13, 144), "time": 3.0, "fov": 60,
			"setup": func() -> void: debug_set_tide(2.3)},
	]
