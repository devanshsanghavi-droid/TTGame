class_name FxLamps extends Node3D
## Hundreds of oil-lamp flames (a temple festival) for the price of one draw
## call, plus a small pool of real lights that settles on the lamp clusters
## nearest the camera. Built by FxKit.lamps(parent, positions).

var size := 0.09
var max_lights := 8
var light_energy := 0.8
var light_range := 6.0
var cluster := 5.0
var intensity := 1.0

var _positions := PackedVector3Array()
var _lit := PackedByteArray()
var _lit_count := 0
var _mm: MultiMesh
var _mat: ShaderMaterial
var _pool := FxLightPool.new()
var _clusters := {}
var _dirty := true
var _timer := 0.0


func build(positions: PackedVector3Array, o: Dictionary) -> void:
	size = o.get("size", 0.09)
	max_lights = o.get("max_lights", 8)
	light_energy = o.get("energy", 0.8)
	light_range = o.get("range", 6.0)
	cluster = o.get("cluster", 5.0)
	_positions = positions
	var start_lit: bool = o.get("lit", true)
	_lit.resize(positions.size())
	_lit.fill(1 if start_lit else 0)
	_lit_count = positions.size() if start_lit else 0
	_mat = FxKit.smat("flame_mm", {"steady": 1.0, "y_lock": 0.0, "halo": 0.55, "flame_frac": 0.36,
		"brightness": 1.9, "soft_dist": 0.02, "near_fade": 0.15})
	var q := size / 0.36
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = FxKit.quad(Vector2(q, q), _mat, true)
	_mm.instance_count = positions.size()
	var box := AABB(positions[0] if positions.size() > 0 else Vector3.ZERO, Vector3.ZERO)
	for i in positions.size():
		var sc := 0.85 + 0.3 * fmod(float(i) * 0.618, 1.0)
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), positions[i] - Vector3(0, 0.12 * q * sc, 0)))
		_mm.set_instance_custom_data(i, Color(1.0 if start_lit else 0.0, fmod(float(i) * 0.7548, 1.0), 0, 0))
		box = box.expand(positions[i])
	_mm.custom_aabb = box.grow(q * 2.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	_pool.setup(self, mini(max_lights, maxi(1, positions.size())), FxFire.LIGHT_COLOR, 0.8)
	_pool.flicker = 0.1
	_pool.speed = 4.5


func count() -> int:
	return _positions.size()


func lit_count() -> int:
	return _lit_count


func set_lit(index: int, on: bool) -> void:
	if index < 0 or index >= _positions.size() or (_lit[index] == 1) == on:
		return
	_lit[index] = 1 if on else 0
	_lit_count += 1 if on else -1
	_mm.set_instance_custom_data(index, Color(1.0 if on else 0.0, fmod(float(index) * 0.7548, 1.0), 0, 0))
	_dirty = true


## Lights the first `n` lamps and puts out the rest (for lighting a festival row by row).
func set_lit_count(n: int) -> void:
	for i in _positions.size():
		set_lit(i, i < n)


## 0..1 for every flame and light at once.
func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)
	_mat.set_shader_parameter("intensity", intensity)
	_pool.level = intensity


func extinguish() -> void:
	set_lit_count(0)


func _rebuild_clusters() -> void:
	_clusters.clear()
	for i in _positions.size():
		if _lit[i] == 0:
			continue
		var p := _positions[i]
		var key := Vector3i((p / cluster).floor())
		var c: Array = _clusters.get(key, [Vector3.ZERO, 0])
		c[0] += p
		c[1] += 1
		_clusters[key] = c


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.4
		if _dirty:
			_dirty = false
			_rebuild_clusters()
		var cam := get_viewport().get_camera_3d()
		var cp := to_local(cam.global_position) if cam else Vector3.ZERO
		var cands: Array = []
		for key in _clusters:
			var c: Array = _clusters[key]
			var n: int = c[1]
			var pos: Vector3 = c[0] / float(n) + Vector3(0, 0.3, 0)
			var e := light_energy * clampf(sqrt(float(n)) * 0.45, 0.5, 2.6)
			cands.append([key, pos, e, light_range + cluster * 0.6, float(n) / (36.0 + cp.distance_squared_to(pos))])
		_pool.assign(cands)
	_pool.process(delta)
