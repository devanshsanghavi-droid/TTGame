class_name FxFireField extends Node3D
## Renderer for a GRID of burning cells (cellular wildfire). The era owns the
## simulation and just calls set_cell(); this draws it cheaply:
##   - every flame in ONE MultiMesh (flames_per_cell billboards per burning cell)
##   - a capped pool of real lights on the brightest clusters near the camera
##   - one smoke system and one ember system fed by the burning cells
##   - scorch + ember-glow decals per cluster
##   - optional Environment tint toward smoke as the fire grows
##
##   var field := FxKit.fire_field(self, {"cell_size": 3.0, "height": ground_y})
##   field.bind_environment(env, sun)
##   field.set_cell(Vector2i(3, 5), 0.8)       # or a world position
##
## Cells are Vector2i grid coordinates in this node's local XZ plane (cell_of()
## converts a world position). Cost is flat: 3 draw calls + max_lights lights +
## up to 48 decals however many of the max_cells are burning; what you pay for is
## fill rate: the smoke (about 90 large lit puffs) and the flame quads.

const SMOKE_LOOK := {
	"fog_light_color": Color(0.36, 0.26, 0.18), "fog_density": 0.012, "fog_sky_affect": 0.7,
	"fog_aerial_perspective": 0.0, "volumetric_fog_density": 0.035,
	"volumetric_fog_albedo": Color(0.5, 0.42, 0.36), "sun_color": Color(1.0, 0.45, 0.22),
	"sun_energy": 0.32, "sky": 0.6, "ambient": 0.75,
}
const BUCKET := 4               # cells per light / decal cluster side
const POINTS := 1024            # emission points fed to smoke and embers

var cell_size := 3.0
var max_cells := 600
var flame_height := 4.0
var max_lights := 6
var flames_per_cell := 2          ## 1 halves the flame fill cost (fine for distant fires)
var light_energy := 5.0
var light_range := 26.0
var smoke_full := 220.0          ## total intensity at which the environment is fully smoked out
var height_fn := Callable()      ## (world x, world z) -> ground y
var cells := {}                  ## Vector2i -> [intensity, slot, local position]
var total := 0.0

var smoke: GPUParticles3D
var embers: GPUParticles3D

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _free: Array[int] = []
var _buckets := {}               # Vector2i -> [sum, local centre, decal or null]
var _pool := FxLightPool.new()
var _bounds := AABB()
var _has_bounds := false
var _dirty := false
var _light_t := 0.0
var _points_t := 0.0
var _points_img: Image
var _points_tex: ImageTexture
var _env: Environment
var _sun: DirectionalLight3D
var _smoke_amt := 0.0
var _decals := 0
var _max_decals := 48


func build(o: Dictionary) -> void:
	cell_size = o.get("cell_size", 3.0)
	max_cells = o.get("max_cells", 600)
	flame_height = o.get("flame_height", 4.0)
	max_lights = o.get("max_lights", 6)
	flames_per_cell = clampi(int(o.get("flames_per_cell", 2)), 1, 3)
	light_energy = o.get("light_energy", 5.0)
	light_range = o.get("light_range", cell_size * BUCKET * 2.2)
	smoke_full = o.get("smoke_full", 220.0)
	height_fn = o.get("height", Callable())
	_max_decals = o.get("max_decals", 48)
	var wind: Vector3 = o.get("wind", FxKit.wind)
	# ---- flames
	var mat := FxKit.smat("flame_mm", {"steady": 0.0, "y_lock": 1.0,
		"scroll": 0.75 / pow(flame_height, 0.3), "noise_scale": 0.5 * pow(flame_height, 0.25),
		"soft_dist": 0.8, "near_fade": 2.5, "tongues": 1.3, "height_gain": 1.6})
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = FxKit.quad(Vector2(cell_size * (2.1 if flames_per_cell == 1 else 1.7), flame_height * 1.7), mat, true)
	_mm.instance_count = max_cells * flames_per_cell
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	for i in max_cells * flames_per_cell:
		_mm.set_instance_transform(i, hidden)
		_mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	for i in max_cells:
		_free.append(max_cells - 1 - i)
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mmi.sorting_offset = flame_height
	add_child(_mmi)
	# ---- lights
	_pool.setup(self, max_lights, FxFire.LIGHT_COLOR, 1.4)
	_pool.flicker = 0.3
	_pool.speed = 6.0
	for l in _pool.lights:
		l.omni_attenuation = 1.2
	# ---- smoke + embers, emitted from the burning cells
	_points_img = Image.create(32, 32, false, Image.FORMAT_RGBF)
	_points_tex = ImageTexture.create_from_image(_points_img)
	var pts := {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_POINTS,
		"emission_point_texture": _points_tex, "emission_point_count": POINTS,
	}
	if o.get("smoke", true):
		var big := cell_size * 1.5
		smoke = FxKit.smoke_system(self, {
			"size": big, "rise": 3.4, "lifetime": 10.0, "color": Color(0.045, 0.04, 0.035), "opacity": 0.68,
			"wind": wind, "y": flame_height * 0.7, "amount": 90.0, "glow": Color(0.3, 0.08, 0.015), "fade": 0.22,
			"pm": pts,
		})
		smoke.emitting = false
		smoke.sorting_offset = -flame_height
	if o.get("embers", true):
		var em := FxKit.smat("spark", {"brightness": 3.2})
		embers = FxKit.particles(self, {
			"amount": FxKit.count(220.0), "lifetime": 4.5, "randomness": 0.5, "emitting": false,
			"pm": FxKit.ppm(pts.merged({
				"direction": Vector3.UP, "spread": 30.0,
				"initial_velocity_min": 2.0, "initial_velocity_max": 7.5,
				"gravity": Vector3(wind.x * 0.5, 0.4, wind.z * 0.5), "damping_min": 0.2, "damping_max": 0.5,
				"scale_min": 0.5, "scale_max": 1.6, "scale_curve": FxKit.curve([0.0, 1.0, 0.7, 0.8, 1.0, 0.0]),
				"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.5,
				"color_ramp": FxKit.ramp([[0.0, Color(1.0, 0.62, 0.25, 1)], [0.4, Color(1.0, 0.34, 0.07, 1)], [0.85, Color(0.5, 0.07, 0.01, 0.9)], [1.0, Color(0.2, 0.02, 0.0, 0)]]),
				"turbulence_enabled": true, "turbulence_noise_strength": 2.2, "turbulence_noise_scale": 3.0,
				"turbulence_influence_min": 0.1, "turbulence_influence_max": 0.3,
			})),
			"mesh": FxKit.quad(Vector2(0.07, 0.07), em), "pos": Vector3(0, flame_height * 0.4, 0), "sort": flame_height * 2.0,
		})
	if o.has("env"):
		bind_environment(o["env"], o.get("sun"))


# ------------------------------------------------------------------ cells
## Grid cell under a world position.
func cell_of(world_pos: Vector3) -> Vector2i:
	var l := to_local(world_pos)
	return Vector2i(floori(l.x / cell_size), floori(l.z / cell_size))


## World position of a cell's centre on the ground.
func cell_pos(cell: Vector2i) -> Vector3:
	return to_global(_cell_local(cell))


func _cell_local(cell: Vector2i) -> Vector3:
	var l := Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)
	if height_fn.is_valid():
		var w := to_global(l)
		l.y = float(height_fn.call(w.x, w.z)) - global_position.y
	return l


## Sets how hard a cell burns (0 = out, 1 = fully ablaze). `cell` is a Vector2i
## grid coordinate or a world-space Vector3. Cheap: call it as often as the
## simulation changes.
func set_cell(cell: Variant, value: float) -> void:
	var c: Vector2i = cell if cell is Vector2i else cell_of(cell as Vector3)
	value = clampf(value, 0.0, 1.0)
	var e: Array = cells.get(c, [])
	if e.is_empty():
		if value <= 0.0 or _free.is_empty():
			return
		e = [0.0, _free.pop_back(), _cell_local(c)]
		cells[c] = e
		var p: Vector3 = e[2]
		if _has_bounds:
			_bounds = _bounds.expand(p)
		else:
			_bounds = AABB(p, Vector3.ZERO)
			_has_bounds = true
	var old: float = e[0]
	if absf(old - value) < 0.004 and value > 0.0:
		return
	total += value - old
	e[0] = value
	_bucket_add(c, value - old)
	_write(c, e)
	if value <= 0.0:
		_free.append(e[1])
		cells.erase(c)
	_dirty = true


func get_cell(cell: Variant) -> float:
	var c: Vector2i = cell if cell is Vector2i else cell_of(cell as Vector3)
	return cells[c][0] if cells.has(c) else 0.0


func burning_count() -> int:
	return cells.size()


## 0..1: how smoked-out the bound environment currently is.
func smoke_amount() -> float:
	return _smoke_amt


func clear() -> void:
	for c in cells.keys():
		set_cell(c, 0.0)


## Tints `env` (fog, sun, sky) toward wildfire smoke as the total fire grows.
func bind_environment(env: Environment, sun: DirectionalLight3D = null) -> void:
	_env = env
	_sun = sun


## Starts smoke and embers as if the current fire had already burned for `seconds`,
## and jumps the environment tint to its settled value.
func prewarm(seconds := 8.0) -> void:
	_update_points()
	_points_t = 0.5
	for p: GPUParticles3D in [smoke, embers]:
		if p and p.emitting:
			p.preprocess = minf(seconds, p.lifetime * 1.2)
			p.restart()
	_smoke_amt = clampf(total / smoke_full, 0.0, 1.0)
	if _env:
		FxKit.env_layer(_env, _sun, "wildfire", SMOKE_LOOK, _smoke_amt)
	_light_t = 0.0


func _write(c: Vector2i, e: Array) -> void:
	var v: float = e[0]
	var slot: int = e[1]
	var p: Vector3 = e[2]
	var h := float(hash(c) % 1000) / 1000.0
	for k in flames_per_cell:
		var seed_f := fmod(h + 0.41 * k, 1.0)
		var xf: Transform3D
		if v <= 0.0:
			xf = Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), p)
		else:
			var off := Vector3(seed_f - 0.5, 0.0, fmod(seed_f * 7.3, 1.0) - 0.5) * cell_size * 0.8
			xf = Transform3D(Basis.IDENTITY.scaled(Vector3(0.85 + seed_f * 0.4, 0.7 + 0.5 * fmod(seed_f * 3.7, 1.0), 1.0)), p + off - Vector3(0, 0.25, 0))
		_mm.set_instance_transform(slot * flames_per_cell + k, xf)
		_mm.set_instance_custom_data(slot * flames_per_cell + k, Color(v, seed_f, 0, 0))


func _bucket_add(c: Vector2i, dv: float) -> void:
	var key := Vector2i(floori(float(c.x) / BUCKET), floori(float(c.y) / BUCKET))
	var b: Array = _buckets.get(key, [])
	if b.is_empty():
		var centre := Vector3((key.x + 0.5) * BUCKET * cell_size, 0.0, (key.y + 0.5) * BUCKET * cell_size)
		if height_fn.is_valid():
			var w := to_global(centre)
			centre.y = float(height_fn.call(w.x, w.z)) - global_position.y
		b = [0.0, centre, null]
		_buckets[key] = b
		if _decals < _max_decals:
			_decals += 1
			var d := Decal.new()
			var side := cell_size * BUCKET * 1.5
			d.size = Vector3(side, maxf(6.0, cell_size * 2.0), side)
			d.position = centre
			d.rotation.y = float(hash(key) % 628) / 100.0
			d.texture_albedo = FxKit.decal_tex("soot")
			d.texture_emission = FxKit.decal_tex("ember")
			d.albedo_mix = 0.0
			d.emission_energy = 0.0
			d.upper_fade = 0.4
			d.lower_fade = 0.4
			d.cull_mask = 1
			add_child(d)
			b[2] = d
	b[0] = maxf(float(b[0]) + dv, 0.0)


func _update_points() -> void:
	var keys: Array = cells.keys()
	var n := keys.size()
	if n == 0:
		return
	var data := PackedFloat32Array()
	data.resize(POINTS * 3)
	var jitter := cell_size * 0.5
	for i in POINTS:
		var e: Array = cells[keys[(i * 7919) % n]]
		var p: Vector3 = e[2]
		var r := float((i * 2654435761) % 1000) / 1000.0
		var r2 := float((i * 40503) % 1000) / 1000.0
		data[i * 3] = p.x + (r - 0.5) * 2.0 * jitter
		data[i * 3 + 1] = p.y
		data[i * 3 + 2] = p.z + (r2 - 0.5) * 2.0 * jitter
	_points_img.set_data(32, 32, false, Image.FORMAT_RGBF, data.to_byte_array())
	_points_tex.update(_points_img)
	if _has_bounds:
		var box := _bounds.grow(cell_size * 2.0 + 30.0)
		box.size.y += 60.0
		box.position.y -= 4.0
		if smoke:
			smoke.visibility_aabb = AABB(box.position - smoke.position, box.size)
		if embers:
			embers.visibility_aabb = AABB(box.position - embers.position, box.size)
		_mmi.custom_aabb = _bounds.grow(cell_size * 2.0 + flame_height * 2.0)


func _process(delta: float) -> void:
	var n := cells.size()
	# ---- smoke / ember emission follows the burning set
	_points_t -= delta
	if _dirty and _points_t <= 0.0:
		_points_t = 0.5
		_dirty = false
		_update_points()
	var burn := clampf(total / 60.0, 0.0, 1.0)
	if smoke:
		smoke.emitting = n > 0
		smoke.amount_ratio = clampf(0.12 + burn * 0.88, 0.05, 1.0)
	if embers:
		embers.emitting = n > 0
		embers.amount_ratio = clampf(0.1 + burn * 0.9, 0.05, 1.0)
	# ---- lights + decals on the hottest clusters near the camera
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.35
		var cam := get_viewport().get_camera_3d()
		var cp := to_local(cam.global_position) if cam else Vector3.ZERO
		var cands: Array = []
		for key in _buckets:
			var b: Array = _buckets[key]
			var sum: float = b[0]
			var heat := clampf(sum / (BUCKET * BUCKET * 0.5), 0.0, 1.0)
			var d: Decal = b[2]
			if d:
				d.albedo_mix = maxf(d.albedo_mix, heat * 0.92)       # scorch stays
				d.emission_energy = heat * 0.45
			if sum < 0.1:
				continue
			var pos: Vector3 = b[1] + Vector3(0, flame_height * 0.45, 0)
			cands.append([key, pos, light_energy * (0.35 + 0.65 * heat), light_range, sum / (1.0 + cp.distance_squared_to(pos) / 1600.0)])
		_pool.assign(cands)
	_pool.process(delta)
	# ---- environment
	if _env:
		var want := clampf(total / smoke_full, 0.0, 1.0)
		if not is_equal_approx(want, _smoke_amt):
			_smoke_amt = move_toward(_smoke_amt, want, delta * 0.12)
			FxKit.env_layer(_env, _sun, "wildfire", SMOKE_LOOK, _smoke_amt)


func _exit_tree() -> void:
	if _env and _smoke_amt > 0.0:
		FxKit.env_layer(_env, _sun, "wildfire", SMOKE_LOOK, 0.0)
