class_name MatLib extends RefCounted
## PBR material library over the fetched CC0 textures (assets/manifest.json).
## Every material is real PBR (albedo + normal + AO/roughness). If an asset is
## missing, a procedural noise-based PBR fallback is used so nothing is ever
## default grey.

static var _manifest := {}
static var _manifest_loaded := false
static var _cache := {}
static var _noise_cache := {}


static func manifest() -> Dictionary:
	if not _manifest_loaded:
		_manifest_loaded = true
		var txt := FileAccess.get_file_as_string("res://assets/manifest.json") if FileAccess.file_exists("res://assets/manifest.json") else ""
		if txt != "":
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				_manifest = parsed
	return _manifest


static func has_tex(name: String) -> bool:
	var t: Dictionary = manifest().get("textures", {})
	return t.has(name) and ResourceLoader.exists(t[name].get("diff", ""))


static func tex(name: String, kind: String) -> Texture2D:
	var t: Dictionary = manifest().get("textures", {})
	if not t.has(name):
		return null
	var p: String = t[name].get(kind, "")
	if p == "" or not ResourceLoader.exists(p):
		return null
	return load(p)


## Triplanar PBR material.
## opts: scale (float, tiles per metre; default 0.35), tint (Color), world (bool, default true:
## world-space projection for static geometry; pass false for anything that moves),
## rough (roughness multiplier), metallic, normal (normal strength), sharp (blend sharpness),
## triplanar (default true), emission (Color), emission_energy, cull_off (bool)
static func pbr(name: String, opts: Dictionary = {}) -> StandardMaterial3D:
	var key := name + str(opts)
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var scale: float = opts.get("scale", 0.35)
	var tri: bool = opts.get("triplanar", true)
	m.uv1_triplanar = tri
	m.uv1_world_triplanar = tri and opts.get("world", true)
	m.uv1_triplanar_sharpness = opts.get("sharp", 4.0)
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var tint: Color = opts.get("tint", Color.WHITE)
	var diff := tex(name, "diff")
	if diff:
		m.albedo_texture = diff
		m.albedo_color = tint
		var nor := tex(name, "nor")
		if nor:
			m.normal_enabled = true
			m.normal_texture = nor
			m.normal_scale = opts.get("normal", 1.0)
		var arm := tex(name, "arm")
		if arm:
			m.ao_enabled = true
			m.ao_texture = arm
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.ao_light_affect = 0.35
			m.roughness_texture = arm
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			m.roughness = opts.get("rough", 1.0)
		else:
			m.roughness = 0.85 * float(opts.get("rough", 1.0))
	else:
		# Procedural fallback: still albedo variation + normal detail.
		m.albedo_texture = noise_tex(name.hash() % 1000, 0.02, false, Color(0.55, 0.55, 0.55), Color(1, 1, 1))
		m.albedo_color = opts.get("fallback", Color(0.45, 0.42, 0.38)) * tint
		m.normal_enabled = true
		m.normal_texture = noise_tex(name.hash() % 1000 + 1, 0.05, true)
		m.normal_scale = 1.2
		m.roughness = 0.9 * float(opts.get("rough", 1.0))
	m.metallic = opts.get("metallic", 0.0)
	if opts.has("emission"):
		m.emission_enabled = true
		m.emission = opts.emission
		m.emission_energy_multiplier = opts.get("emission_energy", 1.0)
	if opts.get("cull_off", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## Bare-metal style material built on a PBR set (bronze, iron, gold leaf).
static func metal(name: String, tint: Color, rough := 0.45, scale := 1.0, world := false) -> StandardMaterial3D:
	return pbr(name, {"tint": tint, "metallic": 0.9, "rough": rough, "scale": scale, "world": world})


## Skin / hide / chitin: a rock or bark set recoloured, object-space triplanar.
static func hide(name: String, tint: Color, scale := 0.8, rough := 0.9) -> StandardMaterial3D:
	return pbr(name, {"tint": tint, "scale": scale, "world": false, "rough": rough, "sharp": 2.0})


static func noise_tex(noise_seed: int, freq: float, as_normal: bool, lo := Color.BLACK, hi := Color.WHITE) -> NoiseTexture2D:
	var key := "%d_%f_%s_%s_%s" % [noise_seed, freq, as_normal, lo, hi]
	if _noise_cache.has(key):
		return _noise_cache[key]
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.frequency = freq
	n.fractal_octaves = 5
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if as_normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	else:
		var g := Gradient.new()
		g.set_color(0, lo)
		g.set_color(1, hi)
		t.color_ramp = g
	_noise_cache[key] = t
	return t


# ------------------------------------------------------------------- models
static func has_model(name: String) -> bool:
	var m: Dictionary = manifest().get("models", {})
	return m.has(name) and ResourceLoader.exists(m[name])


static func model_scene(name: String) -> PackedScene:
	if not has_model(name):
		return null
	return load(manifest().models[name])


## Instantiates a fetched model. Returns null if it is not available.
static func model(name: String) -> Node3D:
	var ps := model_scene(name)
	return ps.instantiate() if ps else null


## All (mesh, local transform) pairs in a fetched model, for MultiMesh scattering.
static func model_parts(name: String) -> Array:
	var key := "parts_" + name
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var root := model(name)
	if root:
		_collect(root, Transform3D.IDENTITY, out)
		root.free()
	_cache[key] = out
	return out


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var local := xf
	if n is Node3D:
		local = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append({"mesh": (n as MeshInstance3D).mesh, "xform": local, "name": String(n.name)})
	for c in n.get_children():
		_collect(c, local, out)


# --------------------------------------------------------------------- skies
static func hdri(name: String) -> Dictionary:
	var h: Dictionary = manifest().get("hdris", {})
	if not h.has(name) or not ResourceLoader.exists(h[name].path):
		return {}
	var s: Array = h[name].sun
	return {"tex": load(h[name].path), "sun": Vector3(s[0], s[1], s[2]).normalized()}


# -------------------------------------------------------------------- decals
static var _decal_tex := {}


## Soft-edged procedural decal (grime, moss, sand drift, soot, damp).
## kind: "grime" | "moss" | "sand" | "soot" | "damp" | "lichen"
static func decal(parent: Node, pos: Vector3, size: Vector3, kind := "grime", rot_y := 0.0, strength := 1.0) -> Decal:
	var cols := {
		"grime": Color(0.10, 0.085, 0.07), "moss": Color(0.16, 0.22, 0.08),
		"sand": Color(0.62, 0.52, 0.38), "soot": Color(0.03, 0.03, 0.03),
		"damp": Color(0.07, 0.07, 0.065), "lichen": Color(0.45, 0.47, 0.32),
		"snow": Color(0.85, 0.88, 0.92), "ash": Color(0.35, 0.34, 0.33),
	}
	var d := Decal.new()
	d.texture_albedo = _decal_texture(kind.hash() % 7)
	d.modulate = Color(cols.get(kind, cols.grime), 1.0)
	d.albedo_mix = clampf(strength, 0.0, 1.0)
	d.size = size
	d.position = pos
	d.rotation.y = rot_y
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.distance_fade_enabled = true
	d.distance_fade_begin = 60.0
	d.distance_fade_length = 20.0
	d.cull_mask = 1
	parent.add_child(d)
	return d


static func _decal_texture(variant: int) -> Texture2D:
	if _decal_tex.has(variant):
		return _decal_tex[variant]
	var n := FastNoiseLite.new()
	n.seed = 77 + variant * 13
	n.frequency = 0.012
	n.fractal_octaves = 5
	var size := 192
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (x + 0.5) / size * 2.0 - 1.0
			var v := (y + 0.5) / size * 2.0 - 1.0
			var edge := clampf(1.0 - sqrt(u * u + v * v), 0.0, 1.0)
			var nv := n.get_noise_2d(x * 3.0, y * 3.0) * 0.5 + 0.5
			var a := clampf((edge * 1.6 + nv * 1.1 - 1.0) * 2.2, 0.0, 1.0)
			var shade := 0.75 + 0.25 * (n.get_noise_2d(x * 9.0 + 500.0, y * 9.0) * 0.5 + 0.5)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_decal_tex[variant] = t
	return t
