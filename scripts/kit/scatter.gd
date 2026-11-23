class_name Scatter extends RefCounted
## MultiMesh scattering over terrain: rocks, plants, debris, props.
##
## cfg keys (all optional except count):
##   count: int            seed: int
##   center: Vector3 + radius: float      OR  rect: Rect2 (x, z)
##   terrain: Terrain      sample heights / normals; without it y = center.y
##   scale: Vector2(min, max)             stretch_y: Vector2(min, max)
##   min_h, max_h: float                  only place between these heights
##   min_flat: float                      only where terrain normal.y >= this
##   max_flat: float                      only where terrain normal.y <= this (cliffs)
##   accept: Callable(x, z, h) -> float   placement probability 0..1
##   sink: float                          push into the ground (metres, scaled)
##   align: float                         0 = upright, 1 = follow the terrain normal
##   tilt: float                          random lean in radians
##   visibility_end: float                cull beyond this distance
##   shadows: bool (default true)
##   collide: bool                        add colliders (rocks / trunks)
##   collide_radius: float                collider radius per unit scale

## Generates instance transforms.
static func points(cfg: Dictionary) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = cfg.get("seed", 1)
	var count: int = cfg.count
	var terrain: Terrain = cfg.get("terrain", null)
	var center: Vector3 = cfg.get("center", Vector3.ZERO)
	var radius: float = cfg.get("radius", 50.0)
	var has_rect: bool = cfg.has("rect")
	var rect: Rect2 = cfg.get("rect", Rect2())
	var sc: Vector2 = cfg.get("scale", Vector2(0.8, 1.2))
	var sy: Vector2 = cfg.get("stretch_y", Vector2(1, 1))
	var min_h: float = cfg.get("min_h", -1e9)
	var max_h: float = cfg.get("max_h", 1e9)
	var min_flat: float = cfg.get("min_flat", -1.0)
	var max_flat: float = cfg.get("max_flat", 2.0)
	var accept: Callable = cfg.get("accept", Callable())
	var sink: float = cfg.get("sink", 0.0)
	var align: float = cfg.get("align", 0.0)
	var tilt: float = cfg.get("tilt", 0.0)
	var tries := 0
	while out.size() < count and tries < count * 12:
		tries += 1
		var x: float
		var z: float
		if has_rect:
			x = rng.randf_range(rect.position.x, rect.end.x)
			z = rng.randf_range(rect.position.y, rect.end.y)
		else:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * radius
			x = center.x + cos(a) * r
			z = center.z + sin(a) * r
		var h := center.y
		var n := Vector3.UP
		if terrain:
			if not terrain.contains(x, z, 1.0):
				continue
			h = terrain.height_at(x, z)
			n = terrain.normal_at(x, z)
		if h < min_h or h > max_h or n.y < min_flat or n.y > max_flat:
			continue
		if accept.is_valid() and rng.randf() > float(accept.call(x, z, h)):
			continue
		var s := rng.randf_range(sc.x, sc.y)
		var up := Vector3.UP.lerp(n, align).normalized()
		if tilt > 0.0:
			up = (up + Vector3(rng.randf_range(-tilt, tilt), 0, rng.randf_range(-tilt, tilt))).normalized()
		var yaw := rng.randf() * TAU
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var right := up.cross(fwd).normalized()
		fwd = right.cross(up).normalized()
		var basis := Basis(right * s, up * s * rng.randf_range(sy.x, sy.y), fwd * s)
		out.append(Transform3D(basis, Vector3(x, h - sink * s, z)))
	return out


static func multimesh(parent: Node, mesh: Mesh, material: Material, xforms: Array[Transform3D], cfg: Dictionary = {}) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = cfg.get("custom_data", false)
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if material:
		mmi.material_override = material
	if not cfg.get("shadows", true):
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ve: float = cfg.get("visibility_end", 0.0)
	if ve > 0.0:
		mmi.visibility_range_end = ve
		mmi.visibility_range_end_margin = ve * 0.12
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	return mmi


## Procedural chiselled rocks (a few mesh variants), optionally solid.
## Extra cfg: material: Material, variants: int (default 3), squash: Vector3
static func rocks(parent: Node, cfg: Dictionary) -> Array:
	var variants: int = cfg.get("variants", 3)
	var mat: Material = cfg.get("material", MatLib.pbr("rock_face_03", {"scale": 0.2}))
	var base_seed: int = cfg.get("seed", 1)
	var out := []
	var per := int(ceil(float(cfg.count) / variants))
	for v in variants:
		var c := cfg.duplicate()
		c.count = per
		c.seed = base_seed * 31 + v * 7
		var xf := points(c)
		var mesh := MeshKit.rock_mesh(base_seed + v * 13, cfg.get("subdiv", 3), 0.3, cfg.get("squash", Vector3(1, 0.72, 1)))
		out.append(multimesh(parent, mesh, mat, xf, cfg))
		if cfg.get("collide", false):
			_colliders(parent, xf, MeshKit.rock_mesh(base_seed + v * 13, 1, 0.3, cfg.get("squash", Vector3(1, 0.72, 1))).create_convex_shape(true, true), cfg.get("collide_min_scale", 0.0))
	return out


## Scatters a fetched Poly Haven model (all its parts) as MultiMeshes.
## Returns [] if the model is not on disk. Extra cfg: part (name filter), collide_radius.
static func model(parent: Node, model_name: String, cfg: Dictionary) -> Array:
	var parts := MatLib.model_parts(model_name)
	var out := []
	if parts.is_empty():
		return out
	var xf := points(cfg)
	for p in parts:
		if cfg.has("part") and not String(p.name).contains(cfg.part):
			continue
		var local: Transform3D = p.xform
		var arr: Array[Transform3D] = []
		for t in xf:
			arr.append(t * local)
		out.append(multimesh(parent, p.mesh, null, arr, cfg))
	if cfg.get("collide", false):
		var s := SphereShape3D.new()
		s.radius = cfg.get("collide_radius", 0.5)
		_colliders(parent, xf, s, cfg.get("collide_min_scale", 0.0))
	return out


static func _colliders(parent: Node, xf: Array[Transform3D], shape: Shape3D, min_scale: float) -> void:
	var body := StaticBody3D.new()
	var any := false
	for t in xf:
		if t.basis.get_scale().x < min_scale:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = t
		body.add_child(cs)
		any = true
	if any:
		parent.add_child(body)
	else:
		body.free()
