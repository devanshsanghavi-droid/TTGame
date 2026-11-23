class_name Terrain extends StaticBody3D
## Heightmap terrain: chunked mesh with distance LODs, HeightMapShape3D
## collider, 3-layer triplanar splat material, runtime paint mask.
##
##   terrain = Terrain.create(self, {
##       "size": 384.0, "res": 257,
##       "height": func(x, z): return ...,                 # metres
##       "color": func(x, z, h, slope_y): return Color(c_weight, damp, 0),   # optional
##       "a": "damp_beach_sand", "b": "rock_face_03", "c": "coast_sand_rocks_02",
##       "a_scale": 0.3, "b_scale": 0.16, "c_scale": 0.25,
##       "a_tint": Color.WHITE, ... , "slope": Vector2(0.70, 0.86)})

var size := 384.0
var res := 257
var cell := 1.5
var heights := PackedFloat32Array()
var material: ShaderMaterial
var paint_image: Image
var paint_texture: ImageTexture
var paint_res := 256

var _paint_dirty := false
var _half := 192.0


static func create(parent: Node, cfg: Dictionary) -> Terrain:
	var t := Terrain.new()
	t.name = "Terrain"
	parent.add_child(t)
	t._build(cfg)
	return t


func _build(cfg: Dictionary) -> void:
	size = cfg.get("size", 384.0)
	res = cfg.get("res", 257)
	cell = size / float(res - 1)
	_half = size * 0.5
	var hf: Callable = cfg.height
	heights.resize(res * res)
	for j in res:
		var z := -_half + j * cell
		for i in res:
			heights[j * res + i] = hf.call(-_half + i * cell, z)
	# normals
	var normals := PackedVector3Array()
	normals.resize(res * res)
	for j in res:
		for i in res:
			var hl := heights[j * res + maxi(i - 1, 0)]
			var hr := heights[j * res + mini(i + 1, res - 1)]
			var hd := heights[maxi(j - 1, 0) * res + i]
			var hu := heights[mini(j + 1, res - 1) * res + i]
			normals[j * res + i] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
	# vertex colours
	var colors := PackedColorArray()
	colors.resize(res * res)
	var has_color: bool = cfg.has("color")
	var cf: Callable = cfg.get("color", Callable())
	for j in res:
		for i in res:
			var idx := j * res + i
			colors[idx] = cf.call(-_half + i * cell, -_half + j * cell, heights[idx], normals[idx].y) if has_color else Color(0, 0, 0, 1)
	_make_material(cfg)
	# chunks
	var chunks: int = cfg.get("chunks", 8)
	var per := (res - 1) / chunks
	var lod_dist: float = cfg.get("lod_distance", 170.0)
	for cj in chunks:
		for ci in chunks:
			var i0 := ci * per
			var j0 := cj * per
			var hi := _chunk_mesh(i0, j0, per, 1, normals, colors)
			var m_hi := MeshInstance3D.new()
			m_hi.mesh = hi
			m_hi.material_override = material
			m_hi.visibility_range_end = lod_dist
			m_hi.visibility_range_end_margin = 12.0
			add_child(m_hi)
			var stride := 4 if per % 4 == 0 else (2 if per % 2 == 0 else 1)
			var lo := _chunk_mesh(i0, j0, per, stride, normals, colors)
			var m_lo := MeshInstance3D.new()
			m_lo.mesh = lo
			m_lo.material_override = material
			m_lo.visibility_range_begin = lod_dist
			m_lo.visibility_range_begin_margin = 12.0
			add_child(m_lo)
	# collider
	var shape := HeightMapShape3D.new()
	shape.map_width = res
	shape.map_depth = res
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(cell, 1.0, cell)
	add_child(cs)


func _chunk_mesh(i0: int, j0: int, per: int, stride: int, normals: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var n := per / stride + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	for j in n:
		for i in n:
			var gi := i0 + i * stride
			var gj := j0 + j * stride
			var g := gj * res + gi
			var k := j * n + i
			verts[k] = Vector3(-_half + gi * cell, heights[g], -_half + gj * cell)
			norms[k] = normals[g]
			cols[k] = colors[g]
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# skirt hides cracks between LODs
	var base := verts.size()
	var edge: Array[int] = []
	for i in n:
		edge.append(i)
	for j in range(1, n):
		edge.append(j * n + n - 1)
	for i in range(n - 2, -1, -1):
		edge.append((n - 1) * n + i)
	for j in range(n - 2, 0, -1):
		edge.append(j * n)
	for e in edge.size():
		var k: int = edge[e]
		verts.append(verts[k] - Vector3(0, 2.5 * stride, 0))
		norms.append(norms[k])
		cols.append(cols[k])
	for e in edge.size():
		var e2 := (e + 1) % edge.size()
		var a: int = edge[e]
		var b: int = edge[e2]
		var c := base + e
		var d := base + e2
		idx.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_material(cfg: Dictionary) -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	for layer in ["a", "b", "c"]:
		var tex_name: String = cfg.get(layer, cfg.get("a", ""))
		var alb := MatLib.tex(tex_name, "diff")
		if alb:
			material.set_shader_parameter(layer + "_alb", alb)
			var nor := MatLib.tex(tex_name, "nor")
			if nor:
				material.set_shader_parameter(layer + "_nrm", nor)
			var arm := MatLib.tex(tex_name, "arm")
			if arm:
				material.set_shader_parameter(layer + "_arm", arm)
		else:
			var base: Color = [Color(0.42, 0.38, 0.32), Color(0.3, 0.3, 0.3), Color(0.36, 0.33, 0.27)][["a", "b", "c"].find(layer)]
			material.set_shader_parameter(layer + "_alb", MatLib.noise_tex(11 + layer.hash() % 50, 0.03, false, base * 0.7, base * 1.3))
			material.set_shader_parameter(layer + "_nrm", MatLib.noise_tex(12 + layer.hash() % 50, 0.06, true))
		material.set_shader_parameter(layer + "_scale", cfg.get(layer + "_scale", 0.3 if layer != "b" else 0.18))
		var tint: Color = cfg.get(layer + "_tint", Color.WHITE)
		material.set_shader_parameter(layer + "_tint", Vector3(tint.r, tint.g, tint.b))
	var slope: Vector2 = cfg.get("slope", Vector2(0.70, 0.86))
	material.set_shader_parameter("slope_lo", slope.x)
	material.set_shader_parameter("slope_hi", slope.y)
	material.set_shader_parameter("macro_noise", MatLib.noise_tex(5, 0.012, false))
	material.set_shader_parameter("macro_strength", cfg.get("macro", 0.28))
	material.set_shader_parameter("terrain_size", size)
	material.set_shader_parameter("rough_mul", cfg.get("rough", 1.0))
	material.set_shader_parameter("normal_strength", cfg.get("normal", 1.0))
	paint_res = cfg.get("paint_res", 256)
	paint_image = Image.create(paint_res, paint_res, false, Image.FORMAT_R8)
	paint_texture = ImageTexture.create_from_image(paint_image)
	material.set_shader_parameter("paint_tex", paint_texture)
	var pt: Color = cfg.get("paint_tint", Color(0.04, 0.035, 0.03))
	material.set_shader_parameter("paint_tint", Vector3(pt.r, pt.g, pt.b))
	material.set_shader_parameter("paint_rough", cfg.get("paint_rough", 0.95))


# ------------------------------------------------------------------ queries
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + _half) / cell, 0.0, res - 1.001)
	var fz := clampf((z + _half) / cell, 0.0, res - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[j * res + i]
	var h10 := heights[j * res + i + 1]
	var h01 := heights[(j + 1) * res + i]
	var h11 := heights[(j + 1) * res + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := cell
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


func contains(x: float, z: float, margin := 0.0) -> bool:
	return absf(x) < _half - margin and absf(z) < _half - margin


# -------------------------------------------------------------------- paint
## Paints the runtime mask (0..1) in a soft disc. Call flush_paint() or let
## _process upload it (once per frame at most).
func paint(x: float, z: float, radius: float, value := 1.0, additive := true) -> void:
	var px := (x + _half) / size * paint_res
	var pz := (z + _half) / size * paint_res
	var pr := maxf(radius / size * paint_res, 0.75)
	var x0 := maxi(int(px - pr), 0)
	var x1 := mini(int(px + pr) + 1, paint_res - 1)
	var z0 := maxi(int(pz - pr), 0)
	var z1 := mini(int(pz + pr) + 1, paint_res - 1)
	for zz in range(z0, z1 + 1):
		for xx in range(x0, x1 + 1):
			var d := Vector2(xx + 0.5 - px, zz + 0.5 - pz).length() / pr
			if d >= 1.0:
				continue
			var cur := paint_image.get_pixel(xx, zz).r
			var v := value * (1.0 - d * d)
			paint_image.set_pixel(xx, zz, Color(maxf(cur, v) if additive else lerpf(cur, value, 1.0 - d), 0, 0))
	_paint_dirty = true


func paint_value_at(x: float, z: float) -> float:
	var px := clampi(int((x + _half) / size * paint_res), 0, paint_res - 1)
	var pz := clampi(int((z + _half) / size * paint_res), 0, paint_res - 1)
	return paint_image.get_pixel(px, pz).r


func _process(_delta: float) -> void:
	if _paint_dirty:
		_paint_dirty = false
		paint_texture.update(paint_image)


func set_wet_level(y: float, band := 0.45) -> void:
	material.set_shader_parameter("wet_level", y)
	material.set_shader_parameter("wet_band", band)
