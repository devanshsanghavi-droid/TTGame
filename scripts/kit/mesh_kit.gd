class_name MeshKit extends RefCounted
## Procedural geometry helpers. All meshes are meant to be used with triplanar
## PBR materials from MatLib, so UVs are secondary.

static var _ico_cache := {}
static var _shape_cache := {}
static var _unit_box: BoxMesh


# ---------------------------------------------------------------- core build
## Builds a smooth-shaded ArrayMesh from triangles given with outward (math, CCW)
## winding. Handles Godot's clockwise front faces.
static func mesh_from(verts: PackedVector3Array, idx: PackedInt32Array, uvs := PackedVector2Array(), flat := false) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	if flat:
		var fv := PackedVector3Array()
		var fn := PackedVector3Array()
		var fu := PackedVector2Array()
		for i in range(0, idx.size(), 3):
			var a := verts[idx[i]]
			var b := verts[idx[i + 1]]
			var c := verts[idx[i + 2]]
			var n := (b - a).cross(c - a).normalized()
			fv.append_array([a, c, b])
			fn.append_array([n, n, n])
			if uvs.size() == verts.size():
				fu.append_array([uvs[idx[i]], uvs[idx[i + 2]], uvs[idx[i + 1]]])
		arrays[Mesh.ARRAY_VERTEX] = fv
		arrays[Mesh.ARRAY_NORMAL] = fn
		if fu.size() > 0:
			arrays[Mesh.ARRAY_TEX_UV] = fu
	else:
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		var out_idx := PackedInt32Array()
		out_idx.resize(idx.size())
		for i in range(0, idx.size(), 3):
			var ia := idx[i]
			var ib := idx[i + 1]
			var ic := idx[i + 2]
			var n := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
			normals[ia] += n
			normals[ib] += n
			normals[ic] += n
			out_idx[i] = ia
			out_idx[i + 1] = ic
			out_idx[i + 2] = ib
		for i in normals.size():
			normals[i] = normals[i].normalized() if normals[i].length_squared() > 1e-12 else Vector3.UP
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = out_idx
		if uvs.size() == verts.size():
			arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _ico(subdiv: int) -> Array:
	if _ico_cache.has(subdiv):
		return _ico_cache[subdiv]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var idx := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4,
		11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11,
		6, 2, 10, 8, 6, 7, 9, 8, 1])
	for _s in subdiv:
		var mid := {}
		var nidx := PackedInt32Array()
		for i in range(0, idx.size(), 3):
			var tri := [idx[i], idx[i + 1], idx[i + 2]]
			var m := [0, 0, 0]
			for e in 3:
				var a: int = tri[e]
				var b: int = tri[(e + 1) % 3]
				var key := mini(a, b) * 100000 + maxi(a, b)
				if not mid.has(key):
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
					mid[key] = verts.size() - 1
				m[e] = mid[key]
			nidx.append_array([tri[0], m[0], m[2], tri[1], m[1], m[0], tri[2], m[2], m[1], m[0], m[1], m[2]])
		idx = nidx
	_ico_cache[subdiv] = [verts, idx]
	return _ico_cache[subdiv]


# -------------------------------------------------------------------- shapes
## Smooth ellipsoid (unit radius scaled by `radii`).
static func ellipsoid_mesh(radii: Vector3, subdiv := 2) -> ArrayMesh:
	var ico := _ico(subdiv)
	var src: PackedVector3Array = ico[0]
	var verts := PackedVector3Array()
	verts.resize(src.size())
	for i in src.size():
		verts[i] = src[i] * radii
	return mesh_from(verts, ico[1])


## Chiselled rock: noise-displaced icosphere with random planar cuts.
## Radius is about 1; scale the instance for size.
static func rock_mesh(rock_seed: int, subdiv := 3, rough := 0.28, squash := Vector3(1, 0.72, 1), cuts := 13, flat := true) -> ArrayMesh:
	var ico := _ico(subdiv)
	var src: PackedVector3Array = ico[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed
	var noise := FastNoiseLite.new()
	noise.seed = rock_seed
	noise.frequency = 0.9
	noise.fractal_octaves = 3
	var planes: Array = []
	for _i in cuts:
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		planes.append([n, rng.randf_range(0.46, 0.86)])
	var verts := PackedVector3Array()
	verts.resize(src.size())
	for i in src.size():
		var v := src[i]
		var p := v * (1.0 + noise.get_noise_3dv(v * 1.4) * rough + noise.get_noise_3dv(v * 5.0) * rough * 0.25)
		for pl in planes:
			var d: float = p.dot(pl[0]) - pl[1]
			if d > 0.0:
				p -= pl[0] * d
		if p.y < -0.55:
			p.y = -0.55
		verts[i] = p * squash
	return mesh_from(verts, ico[1], PackedVector2Array(), flat)


## Layered rock stack / sea stack / butte: a faceted column with stepped strata
## ledges and vertical flutes. Base at y = 0, flat top at y = height.
static func strata_mesh(stack_seed: int, height: float, radius: float, top_ratio := 0.7, segs := 26, band := 1.7) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = stack_seed
	noise.frequency = 1.0
	noise.fractal_octaves = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = stack_seed
	var ledges: Array = []
	for _i in 64:
		ledges.append(rng.randf_range(-0.13, 0.13))
	var rings := maxi(4, int(height / 1.25))
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in rings + 1:
		var y := height * j / float(rings)
		var t := y / height
		var prof := lerpf(1.0, top_ratio, pow(t, 1.3)) * (1.0 + 0.16 * noise.get_noise_2d(y * 0.33, 71.0))
		prof *= 1.0 + 0.55 * pow(1.0 - t, 6.0)
		var ledge: float = ledges[int(y / band) % ledges.size()]
		for i in segs:
			var a := TAU * i / float(segs)
			var nx := cos(a)
			var nz := sin(a)
			var flute := noise.get_noise_3d(nx * 1.1, y * 0.07, nz * 1.1)
			var grit := noise.get_noise_3d(nx * 3.4, y * 0.42, nz * 3.4)
			var r := radius * prof * (1.0 + ledge + flute * 0.42 + grit * 0.1)
			verts.append(Vector3(nx * r, y, nz * r))
	for j in rings:
		for i in segs:
			var a := j * segs + i
			var b := j * segs + (i + 1) % segs
			var c := (j + 1) * segs + (i + 1) % segs
			var d := (j + 1) * segs + i
			idx.append_array([a, c, b, a, d, c])
	var top := verts.size()
	verts.append(Vector3(0, height, 0))
	for i in segs:
		idx.append_array([top, rings * segs + (i + 1) % segs, rings * segs + i])
	return mesh_from(verts, idx, PackedVector2Array(), true)


## Tube swept along `points` with per-point radii. `radii` entries may be float
## or Vector2 (ellipse: x = sideways, y = up). Ends are capped.
static func loft_mesh(points: PackedVector3Array, radii: Array, sides := 10, up_hint := Vector3.UP) -> ArrayMesh:
	var n := points.size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var up := up_hint
	var dist := 0.0
	for i in n:
		var t: Vector3
		if i == 0:
			t = points[1] - points[0]
		elif i == n - 1:
			t = points[n - 1] - points[n - 2]
		else:
			t = points[i + 1] - points[i - 1]
		t = t.normalized()
		if absf(up.dot(t)) > 0.98:
			up = Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD
		var r := up.cross(t).normalized()
		up = t.cross(r).normalized()
		var rad: Variant = radii[mini(i, radii.size() - 1)]
		var rx: float = rad.x if rad is Vector2 else float(rad)
		var ry: float = rad.y if rad is Vector2 else float(rad)
		if i > 0:
			dist += points[i].distance_to(points[i - 1])
		for j in sides + 1:
			var a := float(j) / sides * TAU
			verts.append(points[i] + r * cos(a) * rx + up * sin(a) * ry)
			uvs.append(Vector2(float(j) / sides, dist))
	var ring := sides + 1
	for i in n - 1:
		for j in sides:
			var a := i * ring + j
			var b := a + 1
			var c := a + ring + 1
			var d := a + ring
			idx.append_array([a, b, c, a, c, d])
	# caps
	var c0 := verts.size()
	verts.append(points[0])
	uvs.append(Vector2(0.5, 0))
	var c1 := verts.size()
	verts.append(points[n - 1])
	uvs.append(Vector2(0.5, dist))
	for j in sides:
		idx.append_array([c0, j + 1, j])
		var e := (n - 1) * ring + j
		idx.append_array([c1, e, e + 1])
	return mesh_from(verts, idx, uvs)


## Merges several meshes into one (one draw call). parts: Array of [Mesh, Transform3D].
static func merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		st.append_from(p[0], 0, p[1])
	return st.commit()


static func unit_box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _unit_box


static func box_shape(size: Vector3) -> BoxShape3D:
	var key := Vector3i(size * 100.0)
	if not _shape_cache.has(key):
		var s := BoxShape3D.new()
		s.size = size
		_shape_cache[key] = s
	return _shape_cache[key]


# ------------------------------------------------------------- node builders
static func mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	if parent:
		parent.add_child(m)
	return m


static func box(size: Vector3, mat: Material, pos := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return mi(bm, mat, pos, parent)


static func cyl(r_top: float, r_bot: float, h: float, mat: Material, pos := Vector3.ZERO, parent: Node = null, sides := 16) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	cm.rings = 1
	return mi(cm, mat, pos, parent)


static func ellipsoid(radii: Vector3, mat: Material, pos := Vector3.ZERO, parent: Node = null, subdiv := 2) -> MeshInstance3D:
	return mi(ellipsoid_mesh(radii, subdiv), mat, pos, parent)


## For vertical lofts pass up_hint = Vector3.BACK: radii are then Vector2(width X, depth Z).
static func loft(points: Array, radii: Array, mat: Material, parent: Node = null, sides := 10, up_hint := Vector3.UP) -> MeshInstance3D:
	return mi(loft_mesh(PackedVector3Array(points), radii, sides, up_hint), mat, Vector3.ZERO, parent)


## Solid box: StaticBody3D with a collider and a visible mesh.
static func solid_box(parent: Node, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	var cs := CollisionShape3D.new()
	cs.shape = box_shape(size)
	body.add_child(cs)
	box(size, mat, Vector3.ZERO, body)
	parent.add_child(body)
	return body


## Invisible collider.
static func collider_box(parent: Node, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	var cs := CollisionShape3D.new()
	cs.shape = box_shape(size)
	body.add_child(cs)
	parent.add_child(body)
	return body


## Solid rock: displaced-sphere visual with a convex collider.
static func solid_rock(parent: Node, pos: Vector3, scale: Vector3, mat: Material, rock_seed := 0, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var mesh := rock_mesh(rock_seed)
	var m := mi(mesh, mat, Vector3.ZERO, body)
	m.scale = scale
	var cs := CollisionShape3D.new()
	var key := "rockshape%d" % rock_seed
	if not _shape_cache.has(key):
		_shape_cache[key] = rock_mesh(rock_seed, 1).create_convex_shape(true, true)
	cs.shape = _shape_cache[key]
	cs.scale = scale
	body.add_child(cs)
	parent.add_child(body)
	return body


static func occluder_box(parent: Node, pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> OccluderInstance3D:
	var o := OccluderInstance3D.new()
	var bo := BoxOccluder3D.new()
	bo.size = size
	o.occluder = bo
	o.position = pos
	o.rotation = rot
	parent.add_child(o)
	return o


static func area_box(parent: Node, pos: Vector3, size: Vector3, mask := 2) -> Area3D:
	var a := Area3D.new()
	a.position = pos
	a.collision_layer = 0
	a.collision_mask = mask
	a.monitorable = false
	var cs := CollisionShape3D.new()
	cs.shape = box_shape(size)
	a.add_child(cs)
	parent.add_child(a)
	return a


static func area_sphere(parent: Node, pos: Vector3, radius: float, mask := 2) -> Area3D:
	var a := Area3D.new()
	a.position = pos
	a.collision_layer = 0
	a.collision_mask = mask
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	a.add_child(cs)
	parent.add_child(a)
	return a
