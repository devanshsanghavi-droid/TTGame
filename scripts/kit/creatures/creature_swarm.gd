class_name CreatureSwarm extends Creature
## Meganeura: griffinfly with a 70 cm wingspan. One node is a whole swarm
## (count 1..40) orbiting the node's position: two MultiMeshes (bodies + blurred
## wings), so any swarm size is two draw calls. set_path / move_to move the centre.

const WING_SHADER := "
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
uniform sampler2D vein : repeat_enable, filter_linear_mipmap;
void vertex() {
	float ph = TIME * 173.0 + float(INSTANCE_ID) * 1.7 + UV2.x * 2.2;
	VERTEX.y += abs(VERTEX.x) * sin(ph) * 0.22;
}
void fragment() {
	float v = texture(vein, UV * vec2(5.0, 1.5)).r;
	ALBEDO = mix(vec3(0.62, 0.55, 0.38), vec3(0.2, 0.16, 0.1), smoothstep(0.5, 0.62, v));
	ALPHA = (0.2 + 0.3 * smoothstep(0.46, 0.6, v)) * smoothstep(0.0, 0.12, UV.x) * UV2.y;
	ROUGHNESS = 0.18;
	SPECULAR = 0.7;
}
"

static var _body_mesh: ArrayMesh
static var _wing_mesh: ArrayMesh
static var _wing_mat: ShaderMaterial

var count := 8
var radius := 5.0                    ## orbit radius around the node
var hover := 1.8                     ## centre height above the ground
var spread_y := 1.2

var _mm_body: MultiMesh
var _mm_wing: MultiMesh
var _ang := PackedFloat32Array()
var _rad := PackedFloat32Array()
var _w := PackedFloat32Array()
var _h := PackedFloat32Array()
var _ph := PackedFloat32Array()
var _t := 0.0
var _acc_dt := 0.0


static func create(opts: Dictionary = {}) -> CreatureSwarm:
	var c := CreatureSwarm.new()
	c.kind = "meganeura"
	c.cfg = opts
	c._setup()
	return c


func _setup() -> void:
	if _body_mesh == null:
		_build_meshes()
	count = clampi(int(cfg.get("count", 8)), 1, 40)
	radius = cfg.get("radius", 5.0 if count > 1 else 1.5)
	hover = cfg.get("hover", 1.8)
	size_scale = cfg.get("scale", 1.0)
	era = cfg.get("era", null)
	if cfg.has("ground"):
		ground = cfg.ground
	speed = cfg.get("speed", 2.5)
	turn_rate = 2.0
	accel = 3.0
	weight = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 0)) + 77
	for i in count:
		_ang.append(rng.randf() * TAU)
		_rad.append(radius * rng.randf_range(0.35, 1.0))
		_w.append(rng.randf_range(0.5, 1.3) * (1.0 if rng.randf() > 0.4 else -1.0) * 3.0 / maxf(radius, 1.0))
		_h.append(rng.randf_range(-1.0, 1.0) * spread_y)
		_ph.append(rng.randf() * TAU)
	_mm_body = MultiMesh.new()
	_mm_body.transform_format = MultiMesh.TRANSFORM_3D
	_mm_body.mesh = _body_mesh
	_mm_body.instance_count = count
	_mm_wing = MultiMesh.new()
	_mm_wing.transform_format = MultiMesh.TRANSFORM_3D
	_mm_wing.mesh = _wing_mesh
	_mm_wing.instance_count = count
	var ext := AABB(Vector3(-radius - 1.0, -spread_y - 1.5, -radius - 1.0), Vector3(radius * 2.0 + 2.0, spread_y * 2.0 + 3.0, radius * 2.0 + 2.0))
	for mm: MultiMesh in [_mm_body, _mm_wing]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.custom_aabb = ext
		if mm == _mm_wing:
			mi.material_override = _wing_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_add_notifier(ext)
	anim_distance = 120.0
	lod_near = 40.0
	name = "Meganeura"
	_update_instances(0.0)


func _place(p: Vector3, _delta: float) -> void:
	p.y = ground_at(p.x, p.z) + hover
	global_position = p


func _animate(delta: float) -> void:
	if _lod == 2:
		return
	_acc_dt += delta
	if _lod == 1 and (_frame & 1) == 1:
		return
	var dt := _acc_dt
	_acc_dt = 0.0
	_t += dt
	_update_instances(dt)


func _update_instances(dt: float) -> void:
	var s := size_scale
	for i in count:
		var ph := _ph[i]
		var wv := _w[i] * (0.55 + 0.45 * sin(_t * 0.7 + ph))
		_ang[i] += wv * dt
		var a := _ang[i]
		var r := _rad[i] * (1.0 + 0.25 * sin(_t * 0.45 + ph * 2.0))
		var pos := Vector3(cos(a) * r, _h[i] + sin(_t * 1.3 + ph) * 0.35, sin(a) * r)
		var dirn := 1.0 if wv >= 0.0 else -1.0
		var tangent := Vector3(-sin(a), 0.0, cos(a)) * dirn
		var yaw := atan2(-tangent.x, -tangent.z)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.12 + cos(_t * 1.3 + ph) * 0.1) * Basis(Vector3.BACK, -0.35 * dirn * clampf(absf(wv), 0.0, 1.0))
		var xf := Transform3D(b.scaled(Vector3(s, s, s)), pos)
		_mm_body.set_instance_transform(i, xf)
		_mm_wing.set_instance_transform(i, xf)


## World positions of every dragonfly (for scans, hazards, sounds).
func positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		out.append(global_transform * _mm_body.get_instance_transform(i).origin)
	return out


func telemetry() -> Dictionary:
	var d := super.telemetry()
	d["count"] = count
	return d


static func _build_meshes() -> void:
	var cm := CreatureMesh.new()
	var green := Color(0.2, 0.26, 0.12)
	var amber := Color(0.55, 0.4, 0.14)
	var dark := Color(0.07, 0.06, 0.05)
	cm.shade(green, amber, dark, 0.7, 0.55)
	cm.ellipsoid(Vector3(0.036, 0.04, 0.07), Vector3(0, 0, -0.03), 0, 1)
	cm.paint(Color(0.1, 0.16, 0.12), 0.1, 0.2)
	cm.ellipsoid(Vector3(0.032, 0.028, 0.026), Vector3(0, 0.004, -0.105), 0, 1)
	for sgn: float in [-1.0, 1.0]:
		cm.ellipsoid(Vector3(0.02, 0.022, 0.022), Vector3(0.022 * sgn, 0.01, -0.112), 0, 1)
	for k in 7:
		cm.shade(dark if k % 2 == 0 else amber, null, null, 0.5, 0.5)
		var z0 := 0.03 + k * 0.047
		var r0 := lerpf(0.02, 0.01, k / 6.0)
		cm.loft([Vector3(0, 0, z0), Vector3(0, -0.004, z0 + 0.05)], [r0, r0 * 0.9], 0, 6)
	cm.paint(dark, 0.1, 0.5)
	for sgn: float in [-1.0, 1.0]:
		for k in 3:
			var z := -0.07 + k * 0.03
			cm.loft([Vector3(0.02 * sgn, -0.02, z), Vector3(0.06 * sgn, -0.05, z - 0.02), Vector3(0.05 * sgn, -0.1, z - 0.04)], [0.005, 0.004, 0.003], 0, 4)
	cm.commit({"hide": CreatureMesh.material("pine_bark", {"scale": 9.0, "contrast": 0.5, "rough": 0.7})})
	_body_mesh = cm.mesh
	# wings: each wing is a fan of three blades (the blur of the beat)
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var nr := PackedVector3Array()
	var ix := PackedInt32Array()
	for sgn: float in [-1.0, 1.0]:
		for pair in 2:
			var z := -0.05 + pair * 0.065
			var span := 0.35 - pair * 0.02
			for blade in 3:
				var tilt := (blade - 1) * 0.42
				var alpha := 1.0 if blade == 1 else 0.55
				var base := v.size()
				var up := Vector3(cos(tilt) * sgn, sin(tilt), 0.0)
				for k in 4:
					var t := k / 3.0
					var chord := 0.012 + 0.04 * sin(pow(t, 0.7) * PI * 0.92)
					var c := Vector3(0.012 * sgn, 0.03, z + (0.02 if pair == 1 else -0.02) * t) + up * span * t
					v.append(c + Vector3(0, 0, -chord))
					v.append(c + Vector3(0, 0, chord))
					uv.append(Vector2(t, 0.0))
					uv.append(Vector2(t, 1.0))
					uv2.append(Vector2(float(pair), alpha))
					uv2.append(Vector2(float(pair), alpha))
					nr.append(Vector3.UP)
					nr.append(Vector3.UP)
				for k in 3:
					var a := base + k * 2
					ix.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = ix
	_wing_mesh = ArrayMesh.new()
	_wing_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sh := Shader.new()
	sh.code = WING_SHADER
	_wing_mat = ShaderMaterial.new()
	_wing_mat.shader = sh
	_wing_mat.set_shader_parameter("vein", MatLib.noise_tex(31, 0.06, false))
