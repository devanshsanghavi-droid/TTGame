class_name Crowd extends Node3D
## Many low-cost people (60 to 150): festival crowds, markets, work gangs.
## Each outfit variant is baked from a Humanoid into ONE mesh and drawn with a
## MultiMesh; limbs swing in the vertex shader, so the CPU only moves instance
## transforms (throttled by camera distance). A crowd is a handful of draw calls.
##
##   # people milling about inside a rectangle
##   var c := Crowd.make(self, {"center": on_ground(0, 20), "size": Vector2(14, 14), "count": 80,
##       "outfits": ["chola_devotee", "chola_artisan"], "seed": 4})
##   c.add_cover()                         # CoverZone over the crowd: the player hides in it
##   # a work gang / procession walking a closed loop
##   Crowd.make(self, {"loop": [a, b, c, d], "count": 24, "outfits": ["egypt_worker"], "speed": 1.1, "spread": 0.8})
##
## cfg: center (Vector3), size (Vector2, metres), rot_y | loop (Array of Vector3), spread (lane half-width)
##      count (60), outfits (Array of Outfits names or Humanoid cfg dictionaries), variants (bodies to bake, default 8),
##      seed, speed (0.9), work (0..1 share of standing people doing a work motion), ground (Callable (x, z) -> y),
##      era, draw_distance (220), shadows (true)

const MAX_VARIANTS := 12

var era: Node
var count := 0
var center := Vector3.ZERO
var size := Vector2(12, 12)
var rot_y := 0.0
var speed := 0.9
var looping := false
var ground_fn := Callable()

var _rng := RandomNumberGenerator.new()
var _mm: Array[MultiMesh] = []
var _buf: Array[PackedFloat32Array] = []
var _dirty: Array[bool] = []
var _variant := PackedInt32Array()
var _slot := PackedInt32Array()
var _pos := PackedVector3Array()
var _target := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _want_yaw := PackedFloat32Array()
var _state := PackedInt32Array()          # 0 standing, 1 walking
var _timer := PackedFloat32Array()
var _pace := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _stride := PackedFloat32Array()
var _shade := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _mode := PackedFloat32Array()         # 1 = work motion while standing
var _every := PackedInt32Array()
var _loop_s := PackedFloat32Array()
var _loop_off := PackedFloat32Array()
var _loop_pts: Array = []
var _loop_len := PackedFloat32Array()
var _loop_total := 0.0
var _spread := 0.8
var _work_share := 0.0
var _frame := 0
var _grid := {}
var _basis := Basis.IDENTITY

static var _shader: Shader
static var _material: ShaderMaterial
static var _bake_cache := {}


static func make(parent: Node, cfg: Dictionary) -> Crowd:
	var c := Crowd.new()
	c.era = cfg.get("era", parent if parent is EraBase else Game.current_era)
	parent.add_child(c)
	c._build(cfg)
	return c


## Drops a CoverZone over the crowd area (the player counts as hidden inside it).
func add_cover(height := 2.2, margin := 0.0) -> CoverZone:
	if looping:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p: Vector3 in _loop_pts:
			lo = lo.min(p)
			hi = hi.max(p)
		var mid := (lo + hi) * 0.5
		return CoverZone.make(self, Vector3(mid.x, lo.y + height * 0.5, mid.z),
			Vector3(hi.x - lo.x + (_spread + margin) * 2.0, height + (hi.y - lo.y), hi.z - lo.z + (_spread + margin) * 2.0))
	return CoverZone.make(self, center + Vector3.UP * height * 0.5, Vector3(size.x + margin * 2.0, height + 1.0, size.y + margin * 2.0), rot_y)


## World positions of everyone (for era logic: "is the player inside the crowd?").
func positions() -> PackedVector3Array:
	return _pos


## Distance from `pos` to the nearest crowd member.
func nearest_distance(pos: Vector3) -> float:
	var best := INF
	for p in _pos:
		best = minf(best, p.distance_squared_to(pos))
	return sqrt(best)


func contains(pos: Vector3, margin := 0.0) -> bool:
	if looping:
		return nearest_distance(pos) < 2.0 + margin
	var l := _basis.inverse() * (pos - center)
	return absf(l.x) < size.x * 0.5 + margin and absf(l.z) < size.y * 0.5 + margin


# ---------------------------------------------------------------------- build
func _build(cfg: Dictionary) -> void:
	count = cfg.get("count", 60)
	speed = cfg.get("speed", 0.9)
	_rng.seed = int(cfg.get("seed", 0)) * 977 + 3
	_work_share = cfg.get("work", 0.0)
	_spread = cfg.get("spread", 0.8)
	if cfg.has("ground"):
		ground_fn = cfg.ground
	if cfg.has("loop"):
		looping = true
		_loop_pts = (cfg.loop as Array).duplicate()
		for i in _loop_pts.size():
			var a: Vector3 = _loop_pts[i]
			var b: Vector3 = _loop_pts[(i + 1) % _loop_pts.size()]
			_loop_len.append(Vector2(b.x - a.x, b.z - a.z).length())
			_loop_total += _loop_len[i]
			center += a / _loop_pts.size()
	else:
		center = cfg.get("center", Vector3.ZERO)
		size = cfg.get("size", Vector2(12, 12))
		rot_y = cfg.get("rot_y", 0.0)
	_basis = Basis(Vector3.UP, rot_y)
	var outfits: Array = cfg.get("outfits", ["medieval_peasant"])
	var n_var: int = clampi(cfg.get("variants", 8), 1, MAX_VARIANTS)
	n_var = mini(n_var, count)
	var seed0: int = cfg.get("seed", 0)
	var per := PackedInt32Array()
	per.resize(n_var)
	for i in count:
		per[i % n_var] += 1
	for v in n_var:
		var o: Variant = outfits[v % outfits.size()]
		var mesh: ArrayMesh
		if o is Dictionary:
			mesh = bake_cfg(o)
		else:
			mesh = bake_outfit(String(o), seed0 + v)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = per[v]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material()
		mmi.visibility_range_end = cfg.get("draw_distance", 220.0)
		if not cfg.get("shadows", true):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mm.append(mm)
		var buf := PackedFloat32Array()
		buf.resize(per[v] * 16)
		_buf.append(buf)
		_dirty.append(true)
	# people
	_variant.resize(count)
	_slot.resize(count)
	_state.resize(count)
	_every.resize(count)
	_yaw.resize(count)
	_want_yaw.resize(count)
	_timer.resize(count)
	_pace.resize(count)
	_phase.resize(count)
	_stride.resize(count)
	_shade.resize(count)
	_scale.resize(count)
	_mode.resize(count)
	_loop_s.resize(count)
	_loop_off.resize(count)
	_pos.resize(count)
	_target.resize(count)
	var used := PackedInt32Array()
	used.resize(n_var)
	for i in count:
		var v := i % n_var
		_variant[i] = v
		_slot[i] = used[v]
		used[v] += 1
		_every[i] = 1
		_pace[i] = speed * _rng.randf_range(0.8, 1.2)
		_phase[i] = _rng.randf() * TAU
		_shade[i] = _rng.randf_range(0.82, 1.12)
		_scale[i] = _rng.randf_range(0.96, 1.04)
		_yaw[i] = _rng.randf() * TAU
		_want_yaw[i] = _yaw[i]
		if looping:
			_loop_s[i] = _loop_total * (float(i) + _rng.randf_range(-0.2, 0.2)) / count
			_loop_off[i] = _rng.randf_range(-_spread, _spread)
			_state[i] = 1
			_pace[i] = speed * _rng.randf_range(0.97, 1.03)
			_place_on_loop(i)
		else:
			_pos[i] = _random_point()
			_target[i] = _pos[i]
			_state[i] = 0
			_timer[i] = _rng.randf_range(0.0, 7.0)
			_mode[i] = 1.0 if _rng.randf() < _work_share else 0.0
		_pos[i].y = _ground(_pos[i])
		_write(i)
	_flush()
	# fixed bounds: the area never moves, and vertex animation stays inside the margin
	var ext := Vector3(size.x, 0, size.y).length() * 0.5 + 2.0
	if looping:
		ext = 2.0 + _spread
		for p: Vector3 in _loop_pts:
			ext = maxf(ext, Vector2(p.x - center.x, p.z - center.z).length() + 2.0 + _spread)
	for mm in _mm:
		mm.custom_aabb = AABB(center - Vector3(ext, 30.0, ext), Vector3(ext * 2.0, 60.0, ext * 2.0))


func _random_point() -> Vector3:
	return center + _basis * Vector3(_rng.randf_range(-0.5, 0.5) * (size.x - 0.8), 0.0, _rng.randf_range(-0.5, 0.5) * (size.y - 0.8))


func _ground(p: Vector3) -> float:
	if ground_fn.is_valid():
		return ground_fn.call(p.x, p.z)
	if era and era.has_method("ground_y"):
		return era.ground_y(p.x, p.z)
	return center.y


func _place_on_loop(i: int) -> void:
	var s := fposmod(_loop_s[i], _loop_total)
	var seg := 0
	while seg < _loop_len.size() - 1 and s > _loop_len[seg]:
		s -= _loop_len[seg]
		seg += 1
	var a: Vector3 = _loop_pts[seg]
	var b: Vector3 = _loop_pts[(seg + 1) % _loop_pts.size()]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var l := dir.length()
	dir = dir / l if l > 0.001 else Vector3.FORWARD
	var p := a + dir * s + dir.cross(Vector3.UP) * _loop_off[i]
	# round the corners a little so the file does not snap direction
	_want_yaw[i] = atan2(-dir.x, -dir.z)
	p.y = _pos[i].y
	_pos[i] = p


# --------------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	var dt: float = era.wdelta(delta) if era and era.has_method("wdelta") else delta
	if dt <= 0.0 or count == 0:
		return
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	var pl: Node3D = era.get("player") if era and "player" in era else null
	var ref := cam.global_position if cam else (pl.global_position if pl else center)
	var ppos := pl.global_position if pl else Vector3(1e9, 0, 0)
	# refresh LOD buckets now and then
	if _frame % 24 == 1:
		for i in count:
			var d2 := ref.distance_squared_to(_pos[i])
			_every[i] = 1 if d2 < 900.0 else (2 if d2 < 3600.0 else (4 if d2 < 14400.0 else 8))
	if not looping and _frame % 4 == 0:
		_grid.clear()
		for i in count:
			var key := int(floorf(_pos[i].x)) * 4096 + int(floorf(_pos[i].z))
			if _grid.has(key):
				(_grid[key] as PackedInt32Array).append(i)
			else:
				_grid[key] = PackedInt32Array([i])
	for i in count:
		var ev := _every[i]
		if (_frame + i) % ev != 0:
			continue
		var d := dt * ev
		if looping:
			_loop_s[i] += _pace[i] * d
			_place_on_loop(i)
			_stride[i] = move_toward(_stride[i], _pace[i] * 2.0 / 5.0, d * 2.0)
			_phase[i] += d * (2.0 + _pace[i] * 2.0 * 1.55)
		else:
			_mill(i, d)
		# the player shoulders through: people step aside
		var off := _pos[i] - ppos
		off.y = 0.0
		var pd2 := off.length_squared()
		if pd2 < 0.72 and pd2 > 0.0001 and absf(_pos[i].y - ppos.y) < 2.0:
			var pd := sqrt(pd2)
			_pos[i] += off / pd * (0.85 - pd) * minf(1.0, d * 8.0)
		_yaw[i] = lerp_angle(_yaw[i], _want_yaw[i], 1.0 - exp(-d * 6.0))
		var gy := _ground(_pos[i])
		_pos[i].y = lerpf(_pos[i].y, gy, 1.0 - exp(-d * 12.0))
		_write(i)
	_flush()


func _mill(i: int, d: float) -> void:
	if _state[i] == 0:
		_timer[i] -= d
		_stride[i] = move_toward(_stride[i], 0.0, d * 2.5)
		if _mode[i] > 0.5:
			_phase[i] += d * 8.0
		if _timer[i] <= 0.0:
			# usually drift toward another knot of people, sometimes strike out alone
			var t := _random_point()
			if _rng.randf() < 0.55:
				var j := _rng.randi() % count
				var a := _rng.randf() * TAU
				t = _target[j] + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.7, 1.1)
				var l := _basis.inverse() * (t - center)
				l.x = clampf(l.x, -size.x * 0.5 + 0.4, size.x * 0.5 - 0.4)
				l.z = clampf(l.z, -size.y * 0.5 + 0.4, size.y * 0.5 - 0.4)
				t = center + _basis * l
			_target[i] = t
			_state[i] = 1
		return
	var to := _target[i] - _pos[i]
	to.y = 0.0
	var dist := to.length()
	if dist < 0.3:
		_state[i] = 0
		_timer[i] = _rng.randf_range(2.5, 10.0)
		_mode[i] = 1.0 if _rng.randf() < _work_share else 0.0
		_face_neighbour(i)
		return
	var dir := to / dist
	# separation from neighbours in the 3x3 cells around
	var cx := int(floorf(_pos[i].x))
	var cz := int(floorf(_pos[i].z))
	var push := Vector3.ZERO
	for gx in range(cx - 1, cx + 2):
		for gz in range(cz - 1, cz + 2):
			var cell: Variant = _grid.get(gx * 4096 + gz)
			if cell == null:
				continue
			for j: int in cell:
				if j == i:
					continue
				var off := _pos[i] - _pos[j]
				off.y = 0.0
				var o2 := off.length_squared()
				if o2 < 0.42 and o2 > 0.0001:
					push += off / o2 * 0.22
	var v := dir + push.limit_length(1.5)
	if v.length_squared() > 0.0001:
		v = v.normalized()
	_pos[i] += v * _pace[i] * d
	_want_yaw[i] = atan2(-v.x, -v.z)
	_stride[i] = move_toward(_stride[i], _pace[i] * 2.0 / 5.0, d * 2.0)
	_phase[i] += d * (2.0 + _pace[i] * 2.0 * 1.55)
	_timer[i] -= d
	if _timer[i] < -14.0:      # blocked for too long: settle where we are
		_target[i] = _pos[i]


func _face_neighbour(i: int) -> void:
	var best := 4.0
	var cx := int(floorf(_pos[i].x))
	var cz := int(floorf(_pos[i].z))
	for gx in range(cx - 1, cx + 2):
		for gz in range(cz - 1, cz + 2):
			var cell: Variant = _grid.get(gx * 4096 + gz)
			if cell == null:
				continue
			for j: int in cell:
				if j == i:
					continue
				var off := _pos[j] - _pos[i]
				off.y = 0.0
				var o2 := off.length_squared()
				if o2 < best and o2 > 0.01:
					best = o2
					_want_yaw[i] = atan2(-off.x, -off.z)


func _write(i: int) -> void:
	var v := _variant[i]
	var o := _slot[i] * 16
	var buf := _buf[v]
	var c := cos(_yaw[i]) * _scale[i]
	var s := sin(_yaw[i]) * _scale[i]
	var p := _pos[i]
	buf[o] = c
	buf[o + 1] = 0.0
	buf[o + 2] = s
	buf[o + 3] = p.x
	buf[o + 4] = 0.0
	buf[o + 5] = _scale[i]
	buf[o + 6] = 0.0
	buf[o + 7] = p.y
	buf[o + 8] = -s
	buf[o + 9] = 0.0
	buf[o + 10] = c
	buf[o + 11] = p.z
	buf[o + 12] = _phase[i]
	buf[o + 13] = _stride[i]
	buf[o + 14] = _shade[i]
	buf[o + 15] = _mode[i]
	_buf[v] = buf
	_dirty[v] = true


func _flush() -> void:
	for v in _mm.size():
		if _dirty[v]:
			_dirty[v] = false
			_mm[v].buffer = _buf[v]


# ----------------------------------------------------------------------- bake
static func bake_outfit(outfit: String, p_seed := 0) -> ArrayMesh:
	var key := "%s#%d" % [outfit, p_seed]
	if not _bake_cache.has(key):
		_bake_cache[key] = bake_cfg(Outfits.cfg(outfit, p_seed))
	return _bake_cache[key]


## Bakes a Humanoid into one mesh: vertex colour = cloth / skin colour, CUSTOM0 = joint
## pivot + part id, CUSTOM1 = thigh length, skin flag, metal flag, arm swing scale.
static func bake_cfg(cfg: Dictionary) -> ArrayMesh:
	var c := cfg.duplicate()
	c.erase("merge")
	c["face"] = false       # crowd bodies are seen from a distance: drop the small pieces
	c["lod"] = true
	var h := Humanoid.create(c)
	h.arm_l.rotation.z = -0.1 + h._relax
	h.arm_r.rotation.z = 0.1 - h._relax
	h.elbow_l.rotation.x = 0.3
	h.elbow_r.rotation.x = 0.3
	var out := {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
		"c0": PackedFloat32Array(), "c1": PackedFloat32Array(), "i": PackedInt32Array()}
	var held: String = c.get("prop", "")
	var swing_r := 0.2 if held in ["spear", "staff", "torch", "hoe", "oar"] else 1.0
	var swing_l := 0.25 if c.has("shield") else 1.0
	var thigh := 0.44 * h.scale.y
	_bake_node(h, h, Transform3D(Basis.from_scale(h.scale), Vector3.ZERO), 0, Vector3.ZERO, thigh, swing_l, swing_r, out)
	h.free()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out.v
	arrays[Mesh.ARRAY_NORMAL] = out.n
	arrays[Mesh.ARRAY_COLOR] = out.c
	arrays[Mesh.ARRAY_CUSTOM0] = out.c0
	arrays[Mesh.ARRAY_CUSTOM1] = out.c1
	arrays[Mesh.ARRAY_INDEX] = out.i
	var mesh := ArrayMesh.new()
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


static func _bake_node(h: Humanoid, n: Node, xf: Transform3D, part: int, pivot: Vector3, thigh: float, swing_l: float, swing_r: float, out: Dictionary) -> void:
	if n is Node3D and n != h:
		xf = xf * (n as Node3D).transform
	if n == h.leg_l:
		part = 1
		pivot = xf.origin
	elif n == h.knee_l:
		part = 2
		pivot = xf.origin
	elif n == h.leg_r:
		part = 3
		pivot = xf.origin
	elif n == h.knee_r:
		part = 4
		pivot = xf.origin
	elif n == h.arm_l:
		part = 5
		pivot = xf.origin
	elif n == h.arm_r:
		part = 6
		pivot = xf.origin
	var m := n as MeshInstance3D
	if m and m.mesh and m.mesh.get_surface_count() > 0:
		var arr := m.mesh.surface_get_arrays(0)
		var av: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var an: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var nb := xf.basis.inverse().transposed()
		var col := Color(0.5, 0.5, 0.5)
		var skin := 0.0
		var metal := 0.0
		var sm := m.material_override as StandardMaterial3D
		if sm:
			var lin := sm.albedo_color.srgb_to_linear()
			if sm.albedo_texture and not (sm.albedo_texture is NoiseTexture2D):
				var avg := Color(0.2, 0.2, 0.2)
				var path := sm.albedo_texture.resource_path
				for k: String in Humanoid.TEX_AVG:
					if path.contains("/" + k + "/"):
						avg = Humanoid.TEX_AVG[k]
						break
				lin = Color(lin.r * avg.r, lin.g * avg.g, lin.b * avg.b)
			col = Color(clampf(lin.r, 0.0, 1.0), clampf(lin.g, 0.0, 1.0), clampf(lin.b, 0.0, 1.0)).linear_to_srgb()
			skin = 1.0 if sm.subsurf_scatter_enabled else 0.0
			metal = 1.0 if sm.metallic > 0.5 else 0.0
			if sm.emission_enabled:
				col = sm.emission
		var swing := swing_l if part == 5 else (swing_r if part == 6 else 1.0)
		var base := (out.v as PackedVector3Array).size()
		var ov: PackedVector3Array = out.v
		var on: PackedVector3Array = out.n
		var oc: PackedColorArray = out.c
		var o0: PackedFloat32Array = out.c0
		var o1: PackedFloat32Array = out.c1
		var oi: PackedInt32Array = out.i
		for i in av.size():
			ov.append(xf * av[i])
			on.append((nb * an[i]).normalized())
			oc.append(col)
			o0.append_array([pivot.x, pivot.y, pivot.z, float(part)])
			o1.append_array([thigh, skin, metal, swing])
		if arr[Mesh.ARRAY_INDEX] == null:
			for i in av.size():
				oi.append(base + i)
		else:
			var ai: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for i in ai.size():
				oi.append(base + ai[i])
		out.v = ov
		out.n = on
		out.c = oc
		out.c0 = o0
		out.c1 = o1
		out.i = oi
	for ch in n.get_children():
		_bake_node(h, ch, xf, part, pivot, thigh, swing_l, swing_r, out)


static func material() -> ShaderMaterial:
	if _material == null:
		_shader = Shader.new()
		_shader.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = _shader
		var det := MatLib.tex("acg_fabric", "diff")
		if det == null:
			det = MatLib.noise_tex(3, 0.08, false, Color(0.25, 0.25, 0.25), Color(0.42, 0.42, 0.42))
			_material.set_shader_parameter("detail_avg", 0.09)
		_material.set_shader_parameter("detail", det)
	return _material


const SHADER := "
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 2.4;
uniform float detail_avg = 0.104;

varying vec3 opos;
varying vec3 onrm;
varying vec3 flags;

vec3 rx(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	float ph = INSTANCE_CUSTOM.x;
	float stride = INSTANCE_CUSTOM.y;
	float work = INSTANCE_CUSTOM.w;
	flags = vec3(CUSTOM1.y, CUSTOM1.z, INSTANCE_CUSTOM.z);
	float s = sin(ph);
	float c = cos(ph);
	float id = CUSTOM0.w;
	vec3 piv = CUSTOM0.xyz;
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	if (id > 0.5 && id < 4.5) {
		float side = id < 2.5 ? 1.0 : -1.0;
		float hip_a = side * s * 0.75 * stride;
		vec3 hip = piv;
		if (abs(id - 2.0) < 0.5 || id > 3.5) {
			float knee_a = -(max(-side * c, 0.0) * stride) - 0.08;
			p = rx(p - piv, knee_a) + piv;
			n = rx(n, knee_a);
			hip = piv + vec3(0.0, CUSTOM1.x, 0.0);
		}
		p = rx(p - hip, hip_a) + hip;
		n = rx(n, hip_a);
	} else if (id > 4.5) {
		float side = id < 5.5 ? -1.0 : 1.0;
		float a = side * s * 0.6 * stride * CUSTOM1.w;
		if (id > 5.5) {
			a += work * (1.15 + sin(ph) * 0.8);
		}
		p = rx(p - piv, a) + piv;
		n = rx(n, a);
	} else {
		// torso: a little lean and counter-sway so the body is not a statue
		p.x += s * 0.012 * stride * (p.y - 0.9);
		p.z -= 0.03 * stride * max(p.y - 0.9, 0.0) + work * sin(ph) * 0.04 * max(p.y - 0.9, 0.0);
	}
	p.y += abs(s) * 0.035 * stride;
	VERTEX = p;
	NORMAL = n;
}

void fragment() {
	vec3 w = pow(abs(normalize(onrm)), vec3(3.0));
	w /= (w.x + w.y + w.z);
	vec3 q = opos * detail_scale;
	vec3 d = texture(detail, q.zy).rgb * w.x + texture(detail, q.xz).rgb * w.y + texture(detail, q.xy).rgb * w.z;
	float lum = clamp(dot(d, vec3(0.3333)) / detail_avg, 0.4, 1.8);
	float skin = flags.x;
	float metal = flags.y;
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = base * mix(lum, 1.0, skin * 0.85) * mix(flags.z, 1.0, skin);
	ROUGHNESS = mix(mix(0.92, 0.62, skin), 0.5, metal);
	METALLIC = metal * 0.8;
	SPECULAR = 0.4;
}
"
