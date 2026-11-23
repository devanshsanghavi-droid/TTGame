class_name FxBeam extends Node3D
## A soft shaft of warm sunlight routed between points (mirror puzzles).
## Reads as lit haze, not a laser: a cylinder that is densest through its
## middle with dust drifting in it, a small glint at each bounce, and a warm
## glow (decal + light) where it lands. Built by FxKit.beam(parent).
##
##   beam.set_points([source, mirror_a, mirror_b, target])    # world space
##   beam.set_strength(0.5); beam.clear()

var radius := 0.22
var color := Color(1.0, 0.8, 0.54)
var energy := 1.3
var strength := 1.0
var glow := true
var points := PackedVector3Array()

var _mat: ShaderMaterial
var _mesh: CylinderMesh
var _glint_mesh: QuadMesh
var _segs: Array[MeshInstance3D] = []
var _glints: Array[MeshInstance3D] = []
var _decal: Decal
var _light: OmniLight3D


func build(o: Dictionary) -> void:
	radius = o.get("radius", 0.22)
	color = o.get("color", color)
	energy = o.get("energy", 1.3)
	glow = o.get("glow", true)
	_mat = FxKit.smat("beam", {"color": Vector3(color.r, color.g, color.b), "energy": energy,
		"opacity": o.get("opacity", 0.22), "soft_dist": radius * 1.5})
	_mesh = CylinderMesh.new()
	_mesh.top_radius = 1.0
	_mesh.bottom_radius = 1.0
	_mesh.height = 1.0
	_mesh.radial_segments = 20
	_mesh.rings = 1
	_mesh.cap_top = false
	_mesh.cap_bottom = false
	_mesh.material = _mat
	var gm := FxKit.smat("spark", {"brightness": 1.6, "tint": Vector3(color.r, color.g, color.b)})
	_glint_mesh = FxKit.quad(Vector2.ONE, gm)
	if glow:
		_decal = Decal.new()
		_decal.texture_albedo = FxKit.radial()
		_decal.texture_emission = FxKit.radial()
		_decal.albedo_mix = 0.0
		_decal.modulate = color
		_decal.emission_energy = 0.0
		_decal.upper_fade = 0.05
		_decal.lower_fade = 0.05
		_decal.cull_mask = 1
		_decal.visible = false
		add_child(_decal)
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.light_energy = 0.0
		_light.omni_range = maxf(radius * 16.0, 3.0)
		_light.omni_attenuation = 1.4
		_light.shadow_enabled = false
		_light.visible = false
		add_child(_light)


## Routes the beam through `pts` (world space). Fewer than two points hides it.
func set_points(pts: Variant) -> void:
	points = PackedVector3Array(pts)
	var n := maxi(points.size() - 1, 0)
	while _segs.size() < n:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
		_segs.append(mi)
		var g := MeshInstance3D.new()
		g.mesh = _glint_mesh
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		g.sorting_offset = 0.5
		add_child(g)
		_glints.append(g)
	var inv := global_transform.affine_inverse()
	for i in _segs.size():
		var on := i < n
		_segs[i].visible = on
		_glints[i].visible = on and i > 0
		if not on:
			continue
		var a := inv * points[i]
		var b := inv * points[i + 1]
		var d := b - a
		var length := d.length()
		if length < 0.01:
			_segs[i].visible = false
			continue
		var y := d / length
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		_segs[i].transform = Transform3D(Basis(x * radius, y * length, z * radius), (a + b) * 0.5)
		# glint where the beam bounces: a small billboard facing along the bisector
		_glints[i].transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius * 2.6), a)
	if _decal:
		var show := n > 0 and strength > 0.01
		_decal.visible = show
		_light.visible = show
		if show:
			var a := inv * points[n - 1]
			var b := inv * points[n]
			var dir := (b - a).normalized()
			var y := -dir
			var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
			var z := x.cross(y)
			var side := radius * 4.2
			_decal.transform = Transform3D(Basis(x, y, z), b)
			_decal.size = Vector3(side, 1.4, side)
			_light.position = b - dir * 0.35
	_apply()


func set_strength(v: float) -> void:
	strength = clampf(v, 0.0, 1.0)
	_apply()


func clear() -> void:
	set_points(PackedVector3Array())


func _apply() -> void:
	_mat.set_shader_parameter("strength", strength)
	visible = strength > 0.004
	if _decal:
		_decal.emission_energy = 2.2 * energy * strength
		_light.light_energy = 0.9 * energy * strength
