class_name FoliageKit extends RefCounted
## Vegetation for every era: procedural leaf textures, plant / tree meshes,
## wind + burn + snow shaders and one-call MultiMesh placement.
##
##   var woods := FoliageKit.forest(self, "lycopsid", {"count": 60, "seed": 3, "terrain": terrain,
##       "center": Vector3(0, 0, -40), "radius": 70.0, "accept": func(x, z, h): return 1.0})
##   FoliageKit.ground_cover(self, "fern", {"count": 900, "terrain": terrain, "rect": Rect2(-80, -80, 160, 160)})
##   var hero := FoliageKit.single(self, "banyan_broadleaf", on_ground(10, 4), 1.2, 7)
##   woods.set_burn(woods.nearest(player.global_position), 0.6)     # 0 green .. 0.5 charred .. 1 gone
##   woods.set_snow(0.8)
##   FoliageKit.set_season(Color(1.0, 0.95, 0.8), 0.4)              # global tint + dryness
##   FoliageKit.set_wind(Vector2(1, 0.3), 1.5)                      # global wind
##
## Placement cfg (all optional): count, seed, terrain, center + radius | rect | points
## (Array of Vector3 / Transform3D), accept: Callable(x, z, h) -> 0..1, scale: Vector2,
## collide: bool, visibility_end, lod_distance, spacing, shadows, variants, cell, yaw,
## snow / burn (initial 0..1), min_h / max_h / min_flat / sink / tilt / align (as in
## Scatter), rows: {"spacing", "step", "angle"} to plant in rows (crop, wheat), exact: true
## to ignore the Game.quality().foliage density multiplier.
##
## forest() / ground_cover() / single() return a FoliageKit.Group (Node3D):
##   count(), positions(), position_of(i), scale_of(i), radius_of(i), height_of(i),
##   set_burn(i, amount), get_burn(i), burn_all(amount), set_snow(amount), set_snow_at(i, amount),
##   nearest(world_pos, max_dist) -> index, within(world_pos, radius) -> indices,
##   .mmis (MultiMeshInstance3Ds), .xforms (per-plant transforms), .body (trunk colliders)
## kinds(): every plant name. triangle_report(): triangles per kind. line_points(): hedge rows.
## Never load shaders/foliage*.gdshader directly: their global uniforms are registered here.

const LEAF_SHADER := "res://shaders/foliage.gdshader"
const TRUNK_SHADER := "res://shaders/foliage_trunk.gdshader"
const GOLDEN := 2.399963

## sway = Vector3(height the sway is normalised to, metres of sway at that height, leaf flutter)
const SPECS := {
	# ---- Carboniferous
	"lycopsid": {"gen": "lycopsid", "tree": true, "leaf": "tuft", "bark": "proc_scales", "bark_uv": Vector2(5.0, 1.15), "bark_tint": Color(0.80, 0.80, 0.66), "scale": Vector2(0.8, 1.3), "sway": Vector3(27.0, 0.55, 0.09), "lod": 95.0, "spacing": 5.0, "backlight": Color(0.20, 0.27, 0.07), "moss": 0.5},
	"calamites": {"gen": "calamites", "tree": true, "leaf": "whorl", "bark": "proc_ribs", "bark_uv": Vector2(3.0, 0.5), "bark_tint": Color(0.74, 0.80, 0.52), "scale": Vector2(0.7, 1.35), "sway": Vector3(14.0, 0.7, 0.07), "lod": 80.0, "spacing": 2.2, "backlight": Color(0.24, 0.32, 0.09)},
	"tree_fern": {"gen": "tree_fern", "tree": true, "leaf": "fern", "bark": "palm_tree_bark", "bark_scale": 0.9, "bark_tint": Color(0.42, 0.34, 0.27), "scale": Vector2(0.7, 1.5), "sway": Vector3(6.0, 0.22, 0.07), "lod": 70.0, "spacing": 3.0, "backlight": Color(0.30, 0.38, 0.10), "moss": 0.6},
	"fern": {"gen": "fern", "leaf": "fern", "scale": Vector2(0.7, 1.5), "sway": Vector3(1.0, 0.06, 0.035), "backlight": Color(0.30, 0.38, 0.10)},
	"clubmoss": {"gen": "clubmoss", "leaf": "clubmoss", "scale": Vector2(0.8, 1.6), "sway": Vector3(0.4, 0.02, 0.012), "backlight": Color(0.22, 0.30, 0.08)},
	# ---- Cretaceous
	"conifer": {"gen": "conifer", "tree": true, "leaf": "needle", "bark": "metasequoia_bark", "bark_scale": 0.28, "bark_tint": Color(0.92, 0.80, 0.70), "scale": Vector2(0.75, 1.3), "sway": Vector3(34.0, 0.5, 0.05), "lod": 100.0, "spacing": 5.5, "backlight": Color(0.10, 0.14, 0.04), "rough": 0.72, "moss": 0.35},
	"cycad": {"gen": "cycad", "tree": true, "leaf": "cycad", "bark": "palm_tree_bark", "bark_scale": 1.1, "bark_tint": Color(0.55, 0.47, 0.38), "scale": Vector2(0.75, 1.4), "sway": Vector3(3.0, 0.05, 0.03), "lod": 60.0, "spacing": 2.2, "backlight": Color(0.18, 0.26, 0.07), "rough": 0.55},
	"ginkgo_broadleaf": {"gen": "ginkgo", "tree": true, "leaf": "ginkgo", "bark": "bark_brown_02", "bark_scale": 0.4, "bark_tint": Color(0.80, 0.78, 0.74), "scale": Vector2(0.8, 1.3), "sway": Vector3(15.0, 0.35, 0.10), "lod": 90.0, "spacing": 5.0, "backlight": Color(0.36, 0.42, 0.10)},
	"horsetail": {"gen": "horsetail", "leaf": "horsetail", "scale": Vector2(0.7, 1.5), "sway": Vector3(1.0, 0.07, 0.03), "backlight": Color(0.26, 0.34, 0.09)},
	"berry_bush": {"gen": "berry_bush", "leaf": "berry", "bark": "bark_brown_02", "bark_scale": 1.2, "bark_tint": Color(0.6, 0.5, 0.42), "scale": Vector2(0.8, 1.3), "sway": Vector3(1.6, 0.05, 0.035), "backlight": Color(0.28, 0.34, 0.09), "collide_r": 0.0},
	# ---- Ice age
	"spruce": {"gen": "spruce", "tree": true, "leaf": "spruce", "bark": "pine_bark", "bark_scale": 0.45, "bark_tint": Color(0.72, 0.66, 0.62), "scale": Vector2(0.7, 1.3), "sway": Vector3(17.0, 0.3, 0.04), "lod": 90.0, "spacing": 3.6, "backlight": Color(0.07, 0.11, 0.05), "rough": 0.74},
	"dwarf_shrub": {"gen": "dwarf_shrub", "leaf": "dwarf", "scale": Vector2(0.7, 1.5), "sway": Vector3(0.6, 0.02, 0.02), "backlight": Color(0.26, 0.22, 0.08)},
	"dry_grass": {"gen": "dry_grass", "leaf": "dry_grass", "scale": Vector2(0.7, 1.4), "sway": Vector3(0.8, 0.10, 0.03), "backlight": Color(0.40, 0.32, 0.14), "rough": 0.8},
	# ---- Indus / Egypt
	"date_palm": {"gen": "date_palm", "tree": true, "leaf": "palm", "bark": "palm_tree_bark", "bark_scale": 0.55, "bark_tint": Color(0.80, 0.72, 0.62), "scale": Vector2(0.8, 1.25), "sway": Vector3(13.0, 0.45, 0.08), "lod": 95.0, "spacing": 4.0, "backlight": Color(0.24, 0.28, 0.10), "rough": 0.58},
	"acacia": {"gen": "acacia", "tree": true, "leaf": "acacia", "bark": "bark_willow_02", "bark_scale": 0.5, "bark_tint": Color(0.74, 0.68, 0.60), "scale": Vector2(0.8, 1.3), "sway": Vector3(7.0, 0.18, 0.06), "lod": 85.0, "spacing": 6.0, "backlight": Color(0.28, 0.30, 0.11)},
	"reed": {"gen": "reed", "leaf": "reed", "scale": Vector2(0.75, 1.3), "sway": Vector3(2.6, 0.30, 0.03), "backlight": Color(0.34, 0.36, 0.12)},
	"papyrus": {"gen": "papyrus", "leaf": "papyrus", "scale": Vector2(0.8, 1.3), "sway": Vector3(2.8, 0.28, 0.03), "backlight": Color(0.30, 0.38, 0.11)},
	"crop": {"gen": "crop", "leaf": "wheat", "tint": Color(0.80, 0.98, 0.62), "scale": Vector2(0.9, 1.1), "sway": Vector3(1.0, 0.12, 0.025), "backlight": Color(0.36, 0.38, 0.12), "rough": 0.75},
	"dry_scrub": {"gen": "dry_scrub", "leaf": "scrub", "scale": Vector2(0.7, 1.5), "sway": Vector3(1.0, 0.03, 0.02), "backlight": Color(0.30, 0.26, 0.12), "rough": 0.8},
	# ---- Chola
	"coconut_palm": {"gen": "coconut_palm", "tree": true, "leaf": "coco", "bark": "palm_tree_bark", "bark_scale": 0.7, "bark_tint": Color(0.92, 0.88, 0.80), "scale": Vector2(0.8, 1.25), "sway": Vector3(17.0, 0.8, 0.09), "lod": 100.0, "spacing": 4.0, "backlight": Color(0.32, 0.38, 0.10), "rough": 0.55},
	"banana": {"gen": "banana", "tree": true, "leaf": "banana", "bark": "palm_tree_bark", "bark_scale": 1.3, "bark_tint": Color(0.62, 0.66, 0.36), "scale": Vector2(0.8, 1.3), "sway": Vector3(4.5, 0.14, 0.06), "lod": 65.0, "spacing": 2.2, "backlight": Color(0.36, 0.46, 0.12), "rough": 0.5, "collide_r": 0.2},
	"banyan_broadleaf": {"gen": "banyan", "tree": true, "leaf": "banyan", "bark": "bark_willow_02", "bark_scale": 0.3, "bark_tint": Color(0.80, 0.76, 0.70), "scale": Vector2(0.85, 1.25), "sway": Vector3(17.0, 0.2, 0.09), "lod": 110.0, "spacing": 16.0, "backlight": Color(0.22, 0.30, 0.08), "rough": 0.5, "moss": 0.3},
	# ---- Medieval
	"oak_broadleaf": {"gen": "oak", "tree": true, "leaf": "oak", "bark": "bark_brown_02", "bark_scale": 0.3, "bark_tint": Color(0.70, 0.66, 0.60), "scale": Vector2(0.8, 1.3), "sway": Vector3(13.0, 0.25, 0.10), "lod": 95.0, "spacing": 7.0, "backlight": Color(0.28, 0.36, 0.09), "moss": 0.55},
	"hedge": {"gen": "hedge", "leaf": "hedge", "bark": "bark_brown_02", "bark_scale": 1.0, "bark_tint": Color(0.6, 0.52, 0.45), "scale": Vector2(0.9, 1.15), "sway": Vector3(1.8, 0.03, 0.03), "backlight": Color(0.22, 0.30, 0.08), "collide_r": 0.7, "shadows": true},
	"grass": {"gen": "grass", "leaf": "grass", "scale": Vector2(0.7, 1.5), "sway": Vector3(0.5, 0.06, 0.02), "backlight": Color(0.32, 0.38, 0.10)},
	"wheat": {"gen": "crop", "leaf": "wheat", "scale": Vector2(0.9, 1.15), "sway": Vector3(1.0, 0.14, 0.025), "backlight": Color(0.42, 0.34, 0.13), "rough": 0.78},
}

static var _tex := {}
static var _mats := {}
static var _plants := {}
static var _globals_ready := false
static var _era_id := 0
static var _season := Color(1, 1, 1, 0)
static var _wind := Vector4(0.94, 0.34, 1.0, 1.0)


# =================================================================== globals
static func kinds() -> Array:
	return SPECS.keys()


static func has_kind(kind: String) -> bool:
	return SPECS.has(kind)


## Global tint multiplier and dryness (0 lush .. 1 parched) for every FoliageKit plant.
## Resets to neutral when a new era is loaded.
static func set_season(tint: Color, dryness := 0.0) -> void:
	_ensure_globals()
	_season = Color(tint.r, tint.g, tint.b, clampf(dryness, 0.0, 1.0))
	RenderingServer.global_shader_parameter_set(&"foliage_season", _season)


## Global wind: direction in world xz, strength (1 = breeze, 3 = gale), speed multiplier.
static func set_wind(dir: Vector2, strength := 1.0, speed := 1.0) -> void:
	_ensure_globals()
	var d := dir.normalized() if dir.length_squared() > 0.0001 else Vector2(1, 0)
	_wind = Vector4(d.x, d.y, strength, speed)
	RenderingServer.global_shader_parameter_set(&"foliage_wind", _wind)


static func _ensure_globals() -> void:
	if not _globals_ready:
		_globals_ready = true
		# registered at runtime so project.godot does not need a [shader_globals] entry
		if not ProjectSettings.has_setting("shader_globals/foliage_season"):
			RenderingServer.global_shader_parameter_add(&"foliage_season", RenderingServer.GLOBAL_VAR_TYPE_COLOR, _season)
		if not ProjectSettings.has_setting("shader_globals/foliage_wind"):
			RenderingServer.global_shader_parameter_add(&"foliage_wind", RenderingServer.GLOBAL_VAR_TYPE_VEC4, _wind)
	var game := _game()
	var era: Variant = game.get("current_era") if game else null
	var id: int = (era as Node).get_instance_id() if era is Node and is_instance_valid(era) else 0
	if id != _era_id:
		_era_id = id
		_season = Color(1, 1, 1, 0)
		_wind = Vector4(0.94, 0.34, 1.0, 1.0)
		RenderingServer.global_shader_parameter_set(&"foliage_season", _season)
		RenderingServer.global_shader_parameter_set(&"foliage_wind", _wind)


## The Game autoload, looked up at runtime so this script also compiles before autoloads exist.
static func _game() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(^"Game") if tree else null


static func _density() -> float:
	var game := _game()
	if game and game.has_method(&"quality"):
		return clampf(float((game.call(&"quality") as Dictionary).get("foliage", 1.0)), 0.1, 2.0)
	return 1.0


static func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


static func _shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), 1.0)


# ================================================================== textures
## Scanline polygon rasteriser over Image.fill_rect: fast enough to draw leaf
## atlases at load. Coordinates are in canvas widths (x 0..1, y 0..h/w, y down).
## Drawn at 2x and downsampled, which antialiases the alpha edge.
class Canvas:
	var w: int
	var h: int
	var img: Image
	var bump: Image
	var _xs := PackedFloat32Array()

	func _init(pw: int, ph: int, bg: Color, opaque := false) -> void:
		w = pw
		h = ph
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(bg.r, bg.g, bg.b, 1.0 if opaque else 0.0))
		bump = Image.create(w, h, false, Image.FORMAT_L8)

	func poly(pts: PackedVector2Array, col: Color, hgt := 0.5) -> void:
		var n := pts.size()
		var fw := float(w)
		var ymin := 1e9
		var ymax := -1e9
		var px := PackedFloat32Array()
		var py := PackedFloat32Array()
		px.resize(n)
		py.resize(n)
		for i in n:
			px[i] = pts[i].x * fw
			py[i] = pts[i].y * fw
			ymin = minf(ymin, py[i])
			ymax = maxf(ymax, py[i])
		var y0 := maxi(int(ceil(ymin - 0.5)), 0)
		var y1 := mini(int(floor(ymax - 0.5)), h - 1)
		var hc := Color(hgt, hgt, hgt)
		for y in range(y0, y1 + 1):
			var yc := y + 0.5
			_xs.clear()
			var j := n - 1
			for i in n:
				var ay := py[j]
				var by := py[i]
				if (ay <= yc) != (by <= yc):
					_xs.append(px[j] + (yc - ay) / (by - ay) * (px[i] - px[j]))
				j = i
			if _xs.size() < 2:
				continue
			_xs.sort()
			for k in range(0, _xs.size() - 1, 2):
				var xa := int(ceil(_xs[k] - 0.5))
				var xb := int(floor(_xs[k + 1] - 0.5))
				if xb >= xa:
					var r := Rect2i(xa, y, xb - xa + 1, 1)
					img.fill_rect(r, col)
					bump.fill_rect(r, hc)

	func line(a: Vector2, b: Vector2, wa: float, wb: float, col: Color, hgt := 0.5) -> void:
		var d := b - a
		if d.length_squared() < 1e-10:
			return
		var p := Vector2(-d.y, d.x).normalized() * 0.5
		poly(PackedVector2Array([a - p * wa, b - p * wb, b + p * wb, a + p * wa]), col, hgt)

	## Leaf from `base`, pointing `ang` radians clockwise from straight up.
	## shape: 0 lanceolate, 1 ovate, 2 lobed (oak), 3 strap, 4 fan (ginkgo), 5 serrated
	func leaf(base: Vector2, ang: float, length: float, width: float, col: Color, shape := 0, hgt := 0.6, simple := false) -> void:
		var d := Vector2(sin(ang), -cos(ang))
		var p := Vector2(-d.y, d.x)
		var n := 9 if shape == 2 else (4 if simple and shape != 5 else 6)
		var left := PackedVector2Array([base])
		var right := PackedVector2Array([base])
		for i in range(1, n):
			var t := float(i) / n
			var k: float
			match shape:
				1:
					k = pow(sin(PI * pow(t, 0.6)), 0.8)
				2:
					k = pow(sin(PI * pow(t, 0.7)), 0.7) * (1.0 if i % 2 == 1 else 0.68)
				3:
					k = minf(1.0, t * 6.0) * minf(1.0, (1.0 - t) * 4.0)
				4:
					k = minf(t * 1.3, 1.0)
				5:
					k = sin(PI * pow(t, 0.8)) * (1.0 if i % 2 == 1 else 0.7)
				_:
					k = sin(PI * pow(t, 0.8))
			var c := base + d * (length * t)
			left.append(c - p * (k * width * 0.5))
			right.append(c + p * (k * width * 0.5))
		var tip := base + d * length
		if shape == 4:
			left.append(tip - p * (width * 0.36))
			right.append(tip + p * (width * 0.36))
			tip = base + d * (length * 0.86)
		left.append(tip)
		right.append(tip)
		poly(left, col, hgt)
		poly(right, FoliageKit._shade(col, 0.82), hgt * 0.75)
		if not simple:
			line(base, tip, width * 0.07, width * 0.02, FoliageKit._shade(col, 1.28), 1.0)

	## Tapered quadratic curve (grass blade, stalk).
	func blade(a: Vector2, c: Vector2, b: Vector2, w0: float, col: Color, hgt := 0.6, w1 := 0.0) -> void:
		var n := 6
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in n + 1:
			var t := float(i) / n
			var q := a.lerp(c, t).lerp(c.lerp(b, t), t)
			var tg := (c - a).lerp(b - c, t)
			if tg.length_squared() < 1e-10:
				tg = b - a
			var pp := Vector2(-tg.y, tg.x).normalized()
			var wv := lerpf(w0, w1, pow(t, 1.3)) * 0.5
			left.append(q - pp * wv)
			right.append(q + pp * wv)
		right.reverse()
		left.append_array(right)
		poly(left, col, hgt)

	func disc(c: Vector2, r: float, col: Color, hgt := 0.9) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := TAU * i / 10.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		poly(pts, col, hgt)
		var hl := PackedVector2Array()
		for i in 6:
			var a := TAU * i / 6.0
			hl.append(c + Vector2(-0.3, -0.35) * r + Vector2(cos(a), sin(a)) * r * 0.32)
		poly(hl, FoliageKit._shade(col, 1.7), 1.0)

	func finish(bump_scale := 6.0) -> Dictionary:
		@warning_ignore("integer_division")
		var fw := w / 2
		@warning_ignore("integer_division")
		var fh := h / 2
		img.resize(fw, fh, Image.INTERPOLATE_BILINEAR)
		img.generate_mipmaps()
		@warning_ignore("integer_division")
		bump.resize(fw / 2, fh / 2, Image.INTERPOLATE_BILINEAR)
		bump.resize(fw, fh, Image.INTERPOLATE_CUBIC)
		bump.bump_map_to_normal_map(bump_scale)
		bump.generate_mipmaps(true)
		return {"albedo": ImageTexture.create_from_image(img), "normal": ImageTexture.create_from_image(bump)}


static func _leaf_tex(tex_name: String) -> Dictionary:
	if _tex.has(tex_name):
		return _tex[tex_name]
	var d: Dictionary
	match tex_name:
		"fern":
			d = _tex_frond({"seed": 11, "pairs": 17, "len": 0.44, "w": 0.105, "angle": 68.0, "shape": 5, "stalk": 0.10,
				"col": Color(0.15, 0.26, 0.10), "col2": Color(0.23, 0.32, 0.13), "rachis": Color(0.22, 0.21, 0.10)})
		"cycad":
			d = _tex_frond({"seed": 12, "pairs": 26, "len": 0.46, "w": 0.045, "angle": 62.0, "shape": 0, "stalk": 0.07, "profile": 1,
				"col": Color(0.12, 0.24, 0.10), "col2": Color(0.19, 0.30, 0.12), "rachis": Color(0.30, 0.29, 0.14)})
		"palm":
			d = _tex_frond({"seed": 13, "pairs": 24, "len": 0.50, "w": 0.048, "angle": 52.0, "shape": 0, "stalk": 0.10, "profile": 1,
				"col": Color(0.25, 0.33, 0.19), "col2": Color(0.33, 0.39, 0.22), "rachis": Color(0.42, 0.40, 0.23)})
		"coco":
			d = _tex_frond({"seed": 14, "pairs": 28, "len": 0.52, "w": 0.042, "angle": 58.0, "shape": 0, "stalk": 0.06, "profile": 1, "sag": 0.18,
				"col": Color(0.23, 0.35, 0.12), "col2": Color(0.36, 0.42, 0.15), "rachis": Color(0.44, 0.44, 0.21)})
		"banana":
			d = _tex_banana()
		"tuft":
			d = _tex_blades({"seed": 21, "n": 60, "px": 512, "spread": 0.48, "base": 0.04, "w": 0.022, "hmin": 0.55, "hmax": 0.98,
				"col": Color(0.15, 0.27, 0.11), "col2": Color(0.24, 0.34, 0.14), "stem": Color(0.22, 0.20, 0.12)})
		"grass":
			d = _tex_blades({"seed": 22, "n": 30, "px": 512, "spread": 0.30, "base": 0.22, "w": 0.034, "hmin": 0.45, "hmax": 0.97,
				"col": Color(0.19, 0.28, 0.11), "col2": Color(0.30, 0.34, 0.15)})
		"dry_grass":
			d = _tex_blades({"seed": 23, "n": 32, "px": 512, "spread": 0.32, "base": 0.16, "w": 0.026, "hmin": 0.5, "hmax": 0.97,
				"col": Color(0.52, 0.45, 0.25), "col2": Color(0.68, 0.60, 0.37), "heads": 0.35, "head_col": Color(0.60, 0.50, 0.30)})
		"needle":
			d = _tex_bough({"seed": 31, "feather": true, "sec": 11, "sec_len": 0.40, "sec_angle": 56.0, "leaf": 0.075, "lw": 0.019, "shape": 5, "step": 0.023, "leaf_angle": 50.0,
				"col": Color(0.11, 0.21, 0.10), "col2": Color(0.18, 0.27, 0.13), "twig": Color(0.24, 0.16, 0.10)})
		"spruce":
			d = _tex_bough({"seed": 32, "feather": true, "sec": 12, "sec_len": 0.41, "sec_angle": 50.0, "leaf": 0.066, "lw": 0.018, "shape": 5, "step": 0.020, "leaf_angle": 46.0,
				"col": Color(0.08, 0.17, 0.11), "col2": Color(0.14, 0.23, 0.15), "twig": Color(0.20, 0.15, 0.11)})
		"whorl":
			d = _tex_needles({"seed": 33, "twigs": 0, "reach": 0.0, "angle": 50.0, "step": 0.075, "nlen": 0.30, "nw": 0.016, "whorl": 3,
				"col": Color(0.19, 0.32, 0.13), "col2": Color(0.27, 0.38, 0.16), "twig": Color(0.30, 0.34, 0.16)})
		"clubmoss":
			d = _tex_needles({"seed": 34, "twigs": 0, "reach": 0.0, "angle": 38.0, "step": 0.022, "nlen": 0.07, "nw": 0.018, "stems": 6,
				"col": Color(0.15, 0.26, 0.10), "col2": Color(0.23, 0.32, 0.13), "twig": Color(0.20, 0.23, 0.10)})
		"ginkgo":
			d = _tex_bough({"seed": 41, "prim": 7, "sec": 7, "sec_len": 0.21, "leaf": 0.072, "lw": 0.070, "shape": 4, "spread": 64.0,
				"col": Color(0.27, 0.37, 0.12), "col2": Color(0.37, 0.43, 0.16), "twig": Color(0.24, 0.19, 0.14)})
		"oak":
			d = _tex_bough({"seed": 42, "prim": 7, "sec": 8, "sec_len": 0.22, "leaf": 0.082, "lw": 0.048, "shape": 2, "spread": 66.0,
				"col": Color(0.16, 0.27, 0.09), "col2": Color(0.25, 0.33, 0.12), "twig": Color(0.21, 0.16, 0.11)})
		"banyan":
			d = _tex_bough({"seed": 43, "prim": 7, "sec": 7, "sec_len": 0.22, "leaf": 0.088, "lw": 0.046, "shape": 1, "spread": 66.0,
				"col": Color(0.10, 0.22, 0.09), "col2": Color(0.17, 0.29, 0.12), "twig": Color(0.26, 0.22, 0.17)})
		"acacia":
			d = _tex_bough({"seed": 44, "prim": 8, "sec": 8, "sec_len": 0.20, "leaf": 0.050, "lw": 0.020, "shape": 0, "spread": 74.0, "step": 0.018, "leaf_angle": 60.0,
				"col": Color(0.26, 0.32, 0.15), "col2": Color(0.34, 0.38, 0.19), "twig": Color(0.27, 0.22, 0.16)})
		"berry":
			d = _tex_cluster({"fill": 3, "seed": 45, "twigs": 6, "per": 7, "leaf": 0.165, "lw": 0.100, "shape": 1, "spread": 70.0, "berries": 16,
				"col": Color(0.19, 0.31, 0.11), "col2": Color(0.28, 0.37, 0.14), "twig": Color(0.25, 0.18, 0.13), "berry_col": Color(0.50, 0.07, 0.09)})
		"dwarf":
			d = _tex_cluster({"fill": 3, "seed": 46, "px": 512, "twigs": 7, "per": 8, "leaf": 0.085, "lw": 0.070, "shape": 1, "spread": 78.0,
				"col": Color(0.29, 0.31, 0.13), "col2": Color(0.44, 0.27, 0.12), "twig": Color(0.25, 0.19, 0.15)})
		"hedge":
			d = _tex_bough({"seed": 47, "prim": 8, "sec": 7, "sec_len": 0.22, "leaf": 0.085, "lw": 0.055, "shape": 1, "spread": 78.0,
				"col": Color(0.13, 0.24, 0.09), "col2": Color(0.21, 0.30, 0.12), "twig": Color(0.20, 0.16, 0.11)})
		"scrub":
			d = _tex_cluster({"seed": 48, "px": 512, "twigs": 7, "per": 6, "leaf": 0.070, "lw": 0.030, "shape": 0, "spread": 76.0, "sparse": 0.4, "twig_w": 0.016,
				"col": Color(0.38, 0.37, 0.22), "col2": Color(0.48, 0.42, 0.25), "twig": Color(0.32, 0.25, 0.18)})
		"reed":
			d = _tex_stalks({"seed": 51, "n": 7, "head": "plume", "leafy": true, "hmin": 0.6, "hmax": 0.95, "w": 0.016,
				"col": Color(0.33, 0.40, 0.17), "col2": Color(0.47, 0.46, 0.24), "head_col": Color(0.46, 0.36, 0.26)})
		"papyrus":
			d = _tex_stalks({"seed": 52, "n": 5, "head": "umbel", "leafy": false, "hmin": 0.55, "hmax": 0.84, "w": 0.018,
				"col": Color(0.24, 0.38, 0.14), "col2": Color(0.33, 0.44, 0.18), "head_col": Color(0.36, 0.44, 0.18)})
		"horsetail":
			d = _tex_stalks({"seed": 53, "n": 5, "px": 512, "head": "whorl", "leafy": false, "hmin": 0.6, "hmax": 0.96, "w": 0.022,
				"col": Color(0.17, 0.29, 0.14), "col2": Color(0.24, 0.34, 0.17), "head_col": Color(0.30, 0.26, 0.12)})
		"wheat":
			d = _tex_stalks({"seed": 54, "n": 13, "px": 512, "head": "ear", "leafy": true, "hmin": 0.66, "hmax": 0.88, "w": 0.012, "spread": 0.44,
				"col": Color(0.58, 0.51, 0.25), "col2": Color(0.66, 0.57, 0.30), "head_col": Color(0.74, 0.61, 0.31)})
		_:
			push_error("FoliageKit: unknown leaf texture '%s'" % tex_name)
			d = _tex_blades({"seed": 1, "n": 20, "px": 512, "spread": 0.3, "base": 0.2, "w": 0.03, "hmin": 0.4, "hmax": 0.9,
				"col": Color(0.2, 0.3, 0.1), "col2": Color(0.3, 0.4, 0.15)})
	_tex[tex_name] = d
	return d


## Pinnate frond (fern, palm, cycad, banana): root at the bottom centre, 1:2 aspect.
static func _tex_frond(p: Dictionary) -> Dictionary:
	var rng := _rng(p.seed)
	var col: Color = p.col
	var col2: Color = p.col2
	var cv := Canvas.new(512, 1024, col.lerp(col2, 0.5))
	var asp := 2.0
	var pairs: int = p.pairs
	var stalk: float = p.get("stalk", 0.1)
	var ang: float = deg_to_rad(p.angle)
	var plen: float = p.len
	var pw: float = p.w
	var shape: int = p.shape
	var style: int = p.get("profile", 0)
	var gap: float = p.get("gap", 0.0)
	var sag: float = p.get("sag", 0.0)
	cv.line(Vector2(0.5, asp - 0.004), Vector2(0.5, 0.05), 0.026, 0.008, p.rachis, 0.95)
	for i in pairs:
		var t := (i + 0.5) / pairs
		var y := lerpf(asp * (1.0 - stalk), 0.09, t)
		var k: float
		match style:
			1:
				k = (0.70 + 0.30 * sin(PI * t)) * smoothstep(1.03, 0.82, t)
			2:
				k = (0.88 + 0.12 * sin(PI * t)) * minf(1.0, (1.0 - t) * 7.0) * minf(1.0, t * 9.0 + 0.35)
			_:
				k = pow(sin(PI * pow(t * 0.9 + 0.1, 0.62)), 0.85)
		for side: float in [-1.0, 1.0]:
			if rng.randf() < gap:
				continue
			var a := side * (ang * (1.0 - 0.28 * t) + sag * rng.randf()) + rng.randf_range(-0.05, 0.05)
			var c := _shade(col.lerp(col2, rng.randf()), rng.randf_range(0.88, 1.1))
			cv.leaf(Vector2(0.5, y + rng.randf_range(-0.004, 0.004)), a, plen * k * rng.randf_range(0.92, 1.05), pw, c, shape, rng.randf_range(0.45, 0.7))
	cv.leaf(Vector2(0.5, 0.11), 0.0, 0.10, pw * 0.9, col2, shape)
	return cv.finish()


## Fan of blades from the bottom centre (grass, straw, lycopsid leaf tufts).
static func _tex_blades(p: Dictionary) -> Dictionary:
	var rng := _rng(p.seed)
	var col: Color = p.col
	var col2: Color = p.col2
	var px: int = p.get("px", 512)
	var cv := Canvas.new(px, px, col.lerp(col2, 0.5))
	var n: int = p.n
	var heads: float = p.get("heads", 0.0)
	if p.has("stem"):
		cv.line(Vector2(0.5, 1.0), Vector2(0.5, 0.72), 0.03, 0.012, p.stem, 0.9)
	for i in n:
		var bx := 0.5 + rng.randf_range(-1.0, 1.0) * float(p.base)
		var hgt := rng.randf_range(p.hmin, p.hmax)
		var lean := rng.randf_range(-1.0, 1.0)
		lean = signf(lean) * pow(absf(lean), 0.75) * float(p.spread)
		var tip := Vector2(clampf(bx + lean, 0.03, 0.97), 1.0 - hgt * (1.0 - absf(lean) * 0.5))
		var ctrl := Vector2(bx + lean * 0.12, 1.0 - hgt * 0.7)
		var c := _shade(col.lerp(col2, rng.randf()), rng.randf_range(0.8, 1.12))
		cv.blade(Vector2(bx, 1.0), ctrl, tip, float(p.w) * rng.randf_range(0.7, 1.2), c, rng.randf_range(0.35, 0.9), float(p.w) * 0.12)
		if rng.randf() < heads:
			var hd := (tip - ctrl).normalized()
			cv.leaf(tip - hd * 0.02, atan2(hd.x, -hd.y), 0.10, 0.034, _shade(p.head_col, rng.randf_range(0.85, 1.15)), 5, 0.9)
	return cv.finish()


## Spray of leafy twigs fanning out from the bottom centre (broadleaf crowns, bushes).
static func _tex_cluster(p: Dictionary) -> Dictionary:
	var rng := _rng(p.seed)
	var col: Color = p.col
	var col2: Color = p.col2
	var px: int = p.get("px", 1024)
	var cv := Canvas.new(px, px, col.lerp(col2, 0.5))
	var twigs: int = p.twigs
	var per: int = p.per
	var spread: float = deg_to_rad(p.spread)
	var ll: float = p.leaf
	var lw: float = p.lw
	var shape: int = p.shape
	var sparse: float = p.get("sparse", 0.0)
	var tw_w: float = p.get("twig_w", 0.012)
	var origin := Vector2(0.5, 0.99)
	var leaves: Array = []
	var mids: Array = []
	var fill: int = p.get("fill", 0)
	for i in twigs + fill:
		var inner := i >= twigs
		var a := lerpf(-spread, spread, (i + 0.5) / twigs) + rng.randf_range(-0.08, 0.08)
		if inner:
			a = lerpf(-spread, spread, (i - twigs + rng.randf()) / fill) * 0.85
		var d := Vector2(sin(a), -cos(a))
		# longest reach that keeps the twig and its leaves on the canvas
		var reach := 0.93 - ll * 0.6
		if absf(d.x) > 0.01:
			reach = minf(reach, (0.46 - ll * 0.35) / absf(d.x))
		reach *= rng.randf_range(0.5, 0.66) if inner else rng.randf_range(0.82, 1.0)
		var bend := rng.randf_range(-0.05, 0.05)
		var e := origin + d * reach + Vector2(-d.y, d.x) * bend
		cv.line(origin, e, tw_w, tw_w * 0.35, p.twig, 0.85)
		mids.append(origin.lerp(e, rng.randf_range(0.45, 0.8)))
		for j in per:
			if rng.randf() < sparse:
				continue
			var t := (j + 1.0) / (per + 0.3)
			t = 0.16 + 0.84 * t
			var q := origin.lerp(e, t)
			var sgn := 1.0 if j % 2 == 0 else -1.0
			var la := a + sgn * rng.randf_range(0.6, 1.1)
			var sz := ll * rng.randf_range(0.75, 1.15) * (0.72 + 0.28 * sin(PI * t))
			leaves.append([q, la, sz, _shade(col.lerp(col2, rng.randf()), rng.randf_range(0.82, 1.12))])
		leaves.append([e, a + rng.randf_range(-0.2, 0.2), ll, _shade(col.lerp(col2, rng.randf()), 1.05)])
	for i in range(leaves.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Array = leaves[i]
		leaves[i] = leaves[j]
		leaves[j] = tmp
	for l: Array in leaves:
		cv.leaf(l[0], l[1], l[2], lw * (float(l[2]) / ll), l[3], shape, rng.randf_range(0.4, 0.8))
	var berries: int = p.get("berries", 0)
	if berries > 0:
		var bc: Color = p.berry_col
		for i in berries:
			var m: Vector2 = mids[i % mids.size()]
			var c := m + Vector2(rng.randf_range(-0.07, 0.07), rng.randf_range(-0.07, 0.07))
			for k in rng.randi_range(2, 4):
				var o := Vector2(rng.randf_range(-0.035, 0.035), rng.randf_range(-0.035, 0.035))
				var cc := _shade(bc, rng.randf_range(0.7, 1.2)) if rng.randf() > 0.25 else Color(0.22, 0.06, 0.16)
				cv.disc(c + o, rng.randf_range(0.019, 0.026), cc)
	return cv.finish()


## Bough with two levels of twigs and many small leaves, so a 3 m crown card reads as
## foliage instead of a few giant leaves. Fan layout: primaries spread from the bottom
## centre (broadleaf). Feather layout: one axis with side twigs (conifer boughs).
static func _tex_bough(p: Dictionary) -> Dictionary:
	var rng := _rng(p.seed)
	var col: Color = p.col
	var col2: Color = p.col2
	var cv := Canvas.new(1024, 1024, col.lerp(col2, 0.5))
	var feather: bool = p.get("feather", false)
	var prim: int = 1 if feather else int(p.prim)
	var spread := deg_to_rad(p.get("spread", 62.0))
	var sec_n: int = p.sec
	var sec_len: float = p.sec_len
	var sec_ang := deg_to_rad(p.get("sec_angle", 50.0))
	var ll: float = p.leaf
	var lw: float = p.lw
	var shape: int = p.shape
	var step: float = p.get("step", ll * 0.5)
	var leaf_ang := deg_to_rad(p.get("leaf_angle", 50.0))
	var origin := Vector2(0.5, 0.995)
	var leaves: Array = []
	var twigs: Array = []
	for i in prim:
		var a := 0.0
		if not feather:
			a = lerpf(-spread, spread, (i + 0.5) / prim) + rng.randf_range(-0.07, 0.07)
		var d := Vector2(sin(a), -cos(a))
		var reach := 0.95 - ll
		if absf(d.x) > 0.01:
			reach = minf(reach, (0.47 - sec_len * 0.45) / absf(d.x))
		reach *= rng.randf_range(0.86, 1.0)
		var e := origin + d * reach
		twigs.append([origin, e, 0.016])
		for j in sec_n:
			var t := (j + 0.8) / (sec_n + 0.6)
			var env: float
			if feather:
				env = minf(t * 5.0, 1.0) * pow(1.0 - t, 0.8) + 0.07
			else:
				t = 0.2 + 0.8 * t
				env = 0.62 + 0.38 * sin(PI * t)
			var q := origin.lerp(e, t)
			var sides: Array = [-1.0, 1.0] if feather else [1.0 if (i + j) % 2 == 0 else -1.0]
			for sd: float in sides:
				var sa := a + sd * sec_ang * rng.randf_range(0.85, 1.15)
				var sl := sec_len * env * rng.randf_range(0.85, 1.1)
				var se := q + Vector2(sin(sa), -cos(sa)) * sl
				twigs.append([q, se, 0.009])
				var n := maxi(int(sl / step), 1)
				for k in n:
					var lq := q.lerp(se, (k + 0.7) / (n + 0.2))
					var lsides: Array = [-1.0, 1.0] if feather else [1.0 if k % 2 == 0 else -1.0]
					for ls: float in lsides:
						leaves.append([lq, sa + ls * leaf_ang * rng.randf_range(0.8, 1.2), ll * rng.randf_range(0.78, 1.15),
							_shade(col.lerp(col2, rng.randf()), rng.randf_range(0.8, 1.14))])
				leaves.append([se, sa + rng.randf_range(-0.25, 0.25), ll, _shade(col.lerp(col2, rng.randf()), 1.06)])
		leaves.append([e, a, ll * 1.1, _shade(col2, 1.05)])
	for tw: Array in twigs:
		cv.line(tw[0], tw[1], tw[2], float(tw[2]) * 0.4, p.twig, 0.85)
	for i in range(leaves.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Array = leaves[i]
		leaves[i] = leaves[j]
		leaves[j] = tmp
	for l: Array in leaves:
		cv.leaf(l[0], l[1], l[2], lw * (float(l[2]) / ll), l[3], shape, rng.randf_range(0.4, 0.85), true)
	return cv.finish()


## One broad banana blade with a pale midrib, side veins and wind tears.
static func _tex_banana() -> Dictionary:
	var rng := _rng(15)
	var col := Color(0.22, 0.36, 0.13)
	var cv := Canvas.new(512, 1024, col)
	var y0 := 1.86
	var y1 := 0.05
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array([Vector2(0.5, y0)])
		var steps := 14
		for i in range(1, steps):
			var t := float(i) / steps
			var hw := 0.43 * pow(sin(PI * pow(t, 0.8)), 0.45) * (1.0 + 0.05 * sin(t * 37.0 + side))
			pts.append(Vector2(0.5 + side * hw, lerpf(y0, y1, t)))
		pts.append(Vector2(0.5, y1))
		cv.poly(pts, _shade(col, 1.0 if side < 0.0 else 0.86), 0.6 if side < 0.0 else 0.45)
		for i in 46:
			var t := (i + 0.5) / 46.0
			var y := lerpf(y0, y1, t)
			var hw := 0.42 * pow(sin(PI * pow(t, 0.8)), 0.45)
			cv.line(Vector2(0.5, y), Vector2(0.5 + side * hw, y - 0.035), 0.006, 0.003, _shade(col, rng.randf_range(0.78, 1.2)), 0.7)
		for i in 7:
			var t := rng.randf_range(0.12, 0.92)
			var y := lerpf(y0, y1, t)
			var hw := 0.46 * pow(sin(PI * pow(t, 0.8)), 0.45)
			var inner := 0.5 + side * hw * rng.randf_range(0.2, 0.6)
			var gap := rng.randf_range(0.008, 0.02)
			cv.poly(PackedVector2Array([Vector2(0.5 + side * hw, y - 0.035 - gap), Vector2(0.5 + side * hw, y - 0.035 + gap), Vector2(inner, y - 0.012)]), Color(col.r, col.g, col.b, 0.0), 0.0)
	cv.line(Vector2(0.5, 1.995), Vector2(0.5, y1), 0.034, 0.008, Color(0.50, 0.55, 0.28), 1.0)
	return cv.finish()


## Conifer bough (spray of twigs lined with needles), calamites whorl branch, clubmoss shoots.
static func _tex_needles(p: Dictionary) -> Dictionary:
	var rng := _rng(p.seed)
	var col: Color = p.col
	var col2: Color = p.col2
	var cv := Canvas.new(512, 512, col.lerp(col2, 0.5))
	var twigs: Array = []
	var root := Vector2(0.5, 1.0)
	var top := Vector2(0.5, 0.06)
	var stems: int = p.get("stems", 0)
	var whorl: int = p.get("whorl", 0)
	var n: int = p.twigs
	if stems > 0:
		for i in stems:
			var a := lerpf(-0.5, 0.5, (i + 0.5) / stems) + rng.randf_range(-0.1, 0.1)
			var l := rng.randf_range(0.5, 0.9)
			var b := Vector2(0.5 + (i + 0.5 - stems * 0.5) * 0.09, 1.0)
			var e := b + Vector2(sin(a), -cos(a)) * l
			twigs.append([b, e])
			if rng.randf() < 0.6:
				var m := b.lerp(e, rng.randf_range(0.4, 0.6))
				var a2 := a + (0.5 if rng.randf() < 0.5 else -0.5)
				twigs.append([m, m + Vector2(sin(a2), -cos(a2)) * l * 0.45])
	else:
		twigs.append([root, top])
		for i in n:
			var t := (i + 0.7) / (n + 0.7)
			var o := root.lerp(top, t)
			var l := float(p.reach) * sin(PI * pow(lerpf(0.10, 1.0, t), 0.72)) + 0.04
			for side: float in [-1.0, 1.0]:
				var a := side * deg_to_rad(p.angle) * rng.randf_range(0.9, 1.1)
				twigs.append([o, o + Vector2(sin(a), -cos(a)) * l * rng.randf_range(0.85, 1.08)])
	for tw: Array in twigs:
		cv.line(tw[0], tw[1], 0.016, 0.006, p.twig, 0.9)
	var na := deg_to_rad(float(p.angle) + 8.0)
	for tw: Array in twigs:
		var a: Vector2 = tw[0]
		var b: Vector2 = tw[1]
		var ln := a.distance_to(b)
		var d := (b - a) / ln
		var steps := maxi(int(ln / float(p.step)), 1)
		for s in steps:
			var f := (s + 0.5) / steps
			var q := a + d * (ln * f)
			var taper := 1.0 - 0.55 * f if whorl > 0 else 1.0
			for side: float in [-1.0, 1.0]:
				for wi in maxi(whorl, 1):
					var ang := side * (na * (1.0 - 0.25 * wi) + rng.randf_range(-0.12, 0.12))
					var nd := d.rotated(ang)
					var c := _shade(col.lerp(col2, rng.randf()), rng.randf_range(0.8, 1.15))
					cv.line(q, q + nd * float(p.nlen) * taper * rng.randf_range(0.8, 1.1), float(p.nw), float(p.nw) * 0.3, c, rng.randf_range(0.4, 0.8))
	return cv.finish()


## Upright stalks with seed heads: reeds (plume), papyrus (umbel), wheat (ear), horsetail (whorls).
static func _tex_stalks(p: Dictionary) -> Dictionary:
	var rng := _rng(p.seed)
	var col: Color = p.col
	var col2: Color = p.col2
	var px: int = p.get("px", 1024)
	var cv := Canvas.new(px, px, col.lerp(col2, 0.5))
	var n: int = p.n
	var head: String = p.head
	var hc: Color = p.head_col
	var sw: float = p.w
	var spread: float = p.get("spread", 0.36)
	var order: Array = range(n)
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	for oi: int in order:
		var bx := 0.5 + ((oi + 0.5) / n - 0.5) * 2.0 * spread + rng.randf_range(-0.02, 0.02)
		var hgt := rng.randf_range(p.hmin, p.hmax)
		var lean := rng.randf_range(-0.07, 0.07)
		var a := Vector2(bx, 1.0)
		var b := Vector2(clampf(bx + lean, 0.05, 0.95), 1.0 - hgt)
		var c := Vector2(bx + lean * 0.2, 1.0 - hgt * 0.55)
		var sc := _shade(col.lerp(col2, rng.randf()), rng.randf_range(0.85, 1.1))
		if p.leafy:
			for k in rng.randi_range(2, 3):
				var t := rng.randf_range(0.15, 0.7)
				var q := a.lerp(c, t).lerp(c.lerp(b, t), t)
				var sgn := 1.0 if rng.randf() < 0.5 else -1.0
				var ll := rng.randf_range(0.22, 0.36)
				var tip := q + Vector2(sgn * ll * 0.55, -ll * 0.75)
				tip.x = clampf(tip.x, 0.02, 0.98)
				cv.blade(q, q + Vector2(sgn * ll * 0.12, -ll * 0.6), tip, sw * 2.0, _shade(sc, rng.randf_range(0.85, 1.1)), 0.5, sw * 0.2)
		cv.blade(a, c, b, sw, sc, 0.8, sw * 0.6)
		var up := (b - c).normalized()
		match head:
			"plume":
				var sgn := 1.0 if lean >= 0.0 else -1.0
				for k in 5:
					var ang := atan2(up.x, -up.y) + sgn * (0.1 + 0.16 * k) + rng.randf_range(-0.08, 0.08)
					cv.leaf(b + up * (0.012 * k), ang, rng.randf_range(0.11, 0.17), 0.034, _shade(hc, rng.randf_range(0.8, 1.2)), 5, 0.9)
			"umbel":
				var rays := 30
				var cen := b
				for k in rays:
					var ang := lerpf(-2.0, 2.0, (k + rng.randf()) / rays)
					var rl := rng.randf_range(0.10, 0.155)
					var e := cen + Vector2(sin(ang), -cos(ang)) * rl
					cv.line(cen, e, 0.0075, 0.0045, _shade(hc, rng.randf_range(0.8, 1.2)), 0.6)
					cv.leaf(e - Vector2(sin(ang), -cos(ang)) * 0.012, ang, 0.035, 0.014, Color(0.48, 0.44, 0.24), 0, 0.9)
			"ear":
				var ang := atan2(up.x, -up.y) + rng.randf_range(-0.25, 0.25)
				var dir := Vector2(sin(ang), -cos(ang))
				for k in 7:
					var q := b + dir * (0.018 * k)
					for side: float in [-1.0, 1.0]:
						cv.line(q, q + dir.rotated(side * 0.32) * rng.randf_range(0.07, 0.11), 0.006, 0.003, _shade(hc, 1.12), 0.5)
				cv.leaf(b, ang, 0.15, 0.046, _shade(hc, rng.randf_range(0.9, 1.1)), 5, 1.0)
			"whorl":
				var nodes := int(hgt / 0.062)
				for k in range(1, nodes):
					var t := float(k) / nodes
					var q := a.lerp(c, t).lerp(c.lerp(b, t), t)
					var rl := 0.16 * sin(PI * pow(t, 0.7)) * rng.randf_range(0.85, 1.1) + 0.02
					for side: float in [-1.0, 1.0]:
						for wi in 2:
							var ang := side * (0.75 - 0.3 * wi) + rng.randf_range(-0.08, 0.08)
							cv.line(q, q + Vector2(sin(ang), -cos(ang)) * rl * (1.0 - 0.3 * wi), 0.011, 0.005, _shade(sc, rng.randf_range(0.9, 1.15)), 0.5)
					cv.line(q - Vector2(sw * 0.7, 0), q + Vector2(sw * 0.7, 0), 0.008, 0.008, _shade(hc, 0.8), 1.0)
				cv.leaf(b - up * 0.01, atan2(up.x, -up.y), 0.05, 0.026, hc, 1, 1.0)
	return cv.finish()


## Tileable bark for cylindrical UV mapping: Lepidodendron leaf-cushion diamonds.
static func _bark_scales() -> Dictionary:
	var cv := Canvas.new(512, 512, Color(0.15, 0.14, 0.105), true)
	var rng := _rng(77)
	var nx := 4
	var ny := 4
	for row in range(-1, ny * 2 + 2):
		for cx in range(-1, nx + 1):
			var c := Vector2((cx + (0.5 if posmod(row, 2) == 1 else 0.0)) / nx, row * 0.5 / ny)
			var hw := 0.5 / nx * 0.84
			var hh := 0.5 / ny * 0.88
			var base := _shade(Color(0.31, 0.29, 0.22), 0.88 + 0.22 * absf(sin(c.x * 37.0 + c.y * 91.0)))
			cv.poly(PackedVector2Array([c + Vector2(0, -hh), c + Vector2(hw, 0), c + Vector2(0, hh), c + Vector2(-hw, 0)]), base, 0.55)
			cv.poly(PackedVector2Array([c + Vector2(0, -hh * 0.62), c + Vector2(hw * 0.62, 0), c + Vector2(0, hh * 0.62), c + Vector2(-hw * 0.62, 0)]), _shade(base, 1.10), 0.8)
			var s := c + Vector2(0, -hh * 0.12)
			cv.poly(PackedVector2Array([s + Vector2(0, -hh * 0.24), s + Vector2(hw * 0.26, 0), s + Vector2(0, hh * 0.2), s + Vector2(-hw * 0.26, 0)]), _shade(base, 0.74 + rng.randf() * 0.1), 0.35)
	return cv.finish(9.0)


## Tileable bark for cylindrical UV mapping: Calamites vertical ribs.
static func _bark_ribs() -> Dictionary:
	var cv := Canvas.new(512, 512, Color(0.12, 0.13, 0.08), true)
	var ribs := 10
	for i in ribs:
		var x0 := (i + 0.12) / ribs
		var x1 := (i + 0.88) / ribs
		var k := 0.9 + 0.2 * absf(sin(i * 12.7))
		cv.poly(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, 1), Vector2(x0, 1)]), _shade(Color(0.30, 0.33, 0.19), k), 0.6)
		var m0 := (i + 0.32) / ribs
		var m1 := (i + 0.68) / ribs
		cv.poly(PackedVector2Array([Vector2(m0, 0), Vector2(m1, 0), Vector2(m1, 1), Vector2(m0, 1)]), _shade(Color(0.36, 0.38, 0.22), k), 1.0)
	return cv.finish(7.0)


# ================================================================= materials
static func _leaf_material(kind: String, fade_end := 0.0) -> ShaderMaterial:
	var key := "leaf:%s:%d" % [kind, int(fade_end)]
	if _mats.has(key):
		return _mats[key]
	_ensure_globals()
	var spec: Dictionary = SPECS[kind]
	var tx := _leaf_tex(spec.leaf)
	var m := ShaderMaterial.new()
	m.shader = load(LEAF_SHADER)
	m.set_shader_parameter("albedo_tex", tx.albedo)
	m.set_shader_parameter("normal_tex", tx.normal)
	m.set_shader_parameter("use_normal_map", true)
	m.set_shader_parameter("normal_strength", 0.7)
	m.set_shader_parameter("noise_tex", MatLib.noise_tex(41, 0.02, false))
	var tint: Color = spec.get("tint", Color.WHITE)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	var bl: Color = spec.get("backlight", Color(0.3, 0.36, 0.1))
	m.set_shader_parameter("backlight", Vector3(bl.r, bl.g, bl.b))
	m.set_shader_parameter("roughness", spec.get("rough", 0.64))
	var sway: Vector3 = spec.sway
	m.set_shader_parameter("sway_height", sway.x)
	m.set_shader_parameter("sway_amount", sway.y)
	m.set_shader_parameter("flutter", sway.z)
	if fade_end > 0.0:
		m.set_shader_parameter("fade_start", fade_end * 0.72)
		m.set_shader_parameter("fade_end", fade_end)
	_mats[key] = m
	return m


static func _bark_material(kind: String) -> ShaderMaterial:
	var key := "bark:" + kind
	if _mats.has(key):
		return _mats[key]
	_ensure_globals()
	var spec: Dictionary = SPECS[kind]
	var bark: String = spec.get("bark", "bark_brown_02")
	var m := ShaderMaterial.new()
	m.shader = load(TRUNK_SHADER)
	if bark.begins_with("proc_"):
		if not _tex.has(bark):
			_tex[bark] = _bark_scales() if bark == "proc_scales" else _bark_ribs()
		m.set_shader_parameter("albedo_tex", _tex[bark].albedo)
		m.set_shader_parameter("normal_tex", _tex[bark].normal)
		m.set_shader_parameter("use_uv", true)
		m.set_shader_parameter("uv_scale", spec.get("bark_uv", Vector2(6, 1)))
		m.set_shader_parameter("rough_mul", 0.82)
		m.set_shader_parameter("normal_strength", 1.3)
	else:
		var alb := MatLib.tex(bark, "diff")
		if alb:
			m.set_shader_parameter("albedo_tex", alb)
			var nor := MatLib.tex(bark, "nor")
			if nor:
				m.set_shader_parameter("normal_tex", nor)
			var arm := MatLib.tex(bark, "arm")
			if arm:
				m.set_shader_parameter("arm_tex", arm)
		else:
			m.set_shader_parameter("albedo_tex", MatLib.noise_tex(61, 0.05, false, Color(0.16, 0.12, 0.09), Color(0.40, 0.32, 0.25)))
			m.set_shader_parameter("normal_tex", MatLib.noise_tex(62, 0.08, true))
			m.set_shader_parameter("rough_mul", 0.88)
		m.set_shader_parameter("tex_scale", spec.get("bark_scale", 0.4))
	m.set_shader_parameter("noise_tex", MatLib.noise_tex(41, 0.02, false))
	var tint: Color = spec.get("bark_tint", Color.WHITE)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("moss", spec.get("moss", 0.0))
	var sway: Vector3 = spec.sway
	m.set_shader_parameter("sway_height", sway.x)
	m.set_shader_parameter("sway_amount", sway.y)
	_mats[key] = m
	return m


# ============================================================== mesh builder
class MB:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var t := PackedFloat32Array()
	var idx := PackedInt32Array()
	var leafy := false

	func _init(p_leafy: bool) -> void:
		leafy = p_leafy

	func tris() -> int:
		@warning_ignore("integer_division")
		return idx.size() / 3

	## Leaf card: a strip from `root` along `dir`, `width` wide across `side`.
	## o: segs, droop (radians the strip bends toward the ground over its length; negative
	## curls up), fold (radians, V section), nbias + nblend (bent shading normal), ao0 / ao1
	## (occlusion at root / tip), live (0 = dead frond), phase, wind0 (flutter at the root).
	func card(root: Vector3, dir: Vector3, side: Vector3, length: float, width: float, o: Dictionary = {}) -> void:
		var segs: int = o.get("segs", 1)
		var droop: float = o.get("droop", 0.0)
		var fold: float = o.get("fold", 0.0)
		var nbias: Vector3 = o.get("nbias", Vector3.UP)
		var nblend: float = o.get("nblend", 0.6)
		var ao0: float = o.get("ao0", 0.6)
		var ao1: float = o.get("ao1", 1.0)
		var live: float = o.get("live", 1.0)
		var phase: float = o.get("phase", 0.0)
		var w0: float = o.get("wind0", 0.0)
		var d := dir.normalized()
		var s := side - d * side.dot(d)
		if s.length_squared() < 1e-8:
			s = d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT)
		s = s.normalized()
		var sgn := 1.0
		if droop != 0.0 and d.rotated(s, 0.05).y > d.y:
			sgn = -1.0
		var pos := root
		var cols := 3 if fold > 0.0 else 2
		var base := v.size()
		var step := length / segs
		var hw := width * 0.5
		for k in segs + 1:
			var tt := float(k) / segs
			var nc := s.cross(d).normalized()
			if nc.dot(nbias) < 0.0:
				nc = -nc
			var nn := nc.lerp(nbias, nblend).normalized()
			for ci in cols:
				var u := float(ci) / (cols - 1)
				var p := pos + s * ((u - 0.5) * 2.0 * hw * cos(fold))
				if fold > 0.0 and ci != 1:
					p += nc * (sin(fold) * hw)
				v.append(p)
				n.append(nn)
				uv.append(Vector2(u, 1.0 - tt))
				c.append(Color(lerpf(w0, 1.0, tt), phase, lerpf(ao0, ao1, tt), live))
				t.append_array([s.x, s.y, s.z, 1.0])
			pos += d * step
			if droop != 0.0:
				d = d.rotated(s, sgn * droop / segs)
		for k in segs:
			for ci in cols - 1:
				var a := base + k * cols + ci
				var e := a + cols
				idx.append_array([a, e, a + 1, a + 1, e, e + 1])

	func add_mesh(m: ArrayMesh, xf := Transform3D.IDENTITY) -> void:
		var arr := m.surface_get_arrays(0)
		var base := v.size()
		var mv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var mn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var has_uv: bool = arr[Mesh.ARRAY_TEX_UV] != null
		var mu: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if has_uv else PackedVector2Array()
		var indexed: bool = arr[Mesh.ARRAY_INDEX] != null
		var mi: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if indexed else PackedInt32Array()
		var ident := xf == Transform3D.IDENTITY
		for i in mv.size():
			v.append(mv[i] if ident else xf * mv[i])
			n.append(mn[i] if ident else (xf.basis * mn[i]).normalized())
			uv.append(mu[i] if has_uv else Vector2.ZERO)
		if indexed:
			for i in mi:
				idx.append(base + i)
		else:
			for i in mv.size():
				idx.append(base + i)

	## Tapered tube along `points` (trunks, branches, roots).
	func limb(points: Array, radii: Array, sides: int) -> void:
		add_mesh(MeshKit.loft_mesh(PackedVector3Array(points), radii, sides))

	func blob(center: Vector3, radii: Vector3, subdiv := 0) -> void:
		add_mesh(MeshKit.ellipsoid_mesh(radii, subdiv), Transform3D(Basis.IDENTITY, center))

	func mesh() -> ArrayMesh:
		if v.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = idx
		if leafy:
			arrays[Mesh.ARRAY_COLOR] = c
			arrays[Mesh.ARRAY_TANGENT] = t
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


# ========================================================== plant generators
## Meshes for one variant of a kind (cached): {trunk, crown, trunk_far, crown_far,
## height, radius, tris, tris_far}. Origin at the base, y up. Entries may be null.
static func plant(kind: String, variant := 0) -> Dictionary:
	var key := "%s#%d" % [kind, variant]
	if _plants.has(key):
		return _plants[key]
	if not SPECS.has(kind):
		push_error("FoliageKit: unknown plant kind '%s'" % kind)
		kind = "fern"
	var spec: Dictionary = SPECS[kind]
	var near := _gen(spec.gen, kind.hash() % 1000 + variant * 131 + 7, false)
	var d := {"trunk": (near.t as MB).mesh(), "crown": (near.c as MB).mesh(), "trunk_far": null, "crown_far": null,
		"height": near.h, "radius": near.r, "tris": (near.t as MB).tris() + (near.c as MB).tris(), "tris_far": 0}
	if float(spec.get("lod", 0.0)) > 0.0:
		var far := _gen(spec.gen, kind.hash() % 1000 + variant * 131 + 7, true)
		d.trunk_far = (far.t as MB).mesh()
		d.crown_far = (far.c as MB).mesh()
		d.tris_far = (far.t as MB).tris() + (far.c as MB).tris()
	_plants[key] = d
	return d


static func _gen(gen: String, s: int, far: bool) -> Dictionary:
	var t := MB.new(false)
	var c := MB.new(true)
	var rng := _rng(s)
	var hr := Vector2(1, 0)
	match gen:
		"lycopsid":
			hr = _g_lycopsid(t, c, rng, far)
		"calamites":
			hr = _g_calamites(t, c, rng, far)
		"tree_fern":
			hr = _g_palmlike(t, c, rng, far, {"h": Vector2(4.0, 5.2), "r0": 0.24, "r1": 0.2, "flare": 1.35, "lean": 0.9, "sides": 7,
				"fronds": 13, "flen": 3.1, "fwid": 1.25, "el_top": 1.05, "el_bot": -0.05, "droop": Vector2(0.9, 1.5), "segs": 4, "dead": 6, "bulge": 0.0})
		"fern":
			hr = _g_palmlike(t, c, rng, far, {"h": Vector2.ZERO, "fronds": 9, "flen": 1.05, "fwid": 0.42, "el_top": 1.35, "el_bot": 0.6,
				"droop": Vector2(0.75, 1.15), "segs": 3, "dead": 0})
		"cycad":
			hr = _g_palmlike(t, c, rng, far, {"h": Vector2(0.9, 1.5), "r0": 0.34, "r1": 0.30, "flare": 1.1, "lean": 0.15, "sides": 8,
				"fronds": 17, "flen": 2.0, "fwid": 0.56, "el_top": 1.3, "el_bot": 0.12, "droop": Vector2(0.35, 0.7), "segs": 3, "fold": 0.3, "dead": 0, "bulge": 0.36})
		"date_palm":
			hr = _g_palmlike(t, c, rng, far, {"h": Vector2(10.0, 13.0), "r0": 0.33, "r1": 0.27, "flare": 1.5, "lean": 1.6, "sides": 8,
				"fronds": 23, "flen": 4.2, "fwid": 1.35, "el_top": 1.35, "el_bot": -0.55, "droop": Vector2(0.45, 0.95), "segs": 4, "fold": 0.3, "dead": 7, "bulge": 0.5})
		"coconut_palm":
			hr = _g_palmlike(t, c, rng, far, {"h": Vector2(14.0, 18.0), "r0": 0.24, "r1": 0.17, "flare": 1.9, "lean": 4.2, "sides": 8,
				"fronds": 18, "flen": 5.4, "fwid": 1.6, "el_top": 1.25, "el_bot": -0.7, "droop": Vector2(0.9, 1.35), "segs": 5, "fold": 0.32, "dead": 2, "bulge": 0.34, "nuts": 5})
		"banana":
			hr = _g_palmlike(t, c, rng, far, {"h": Vector2(2.3, 3.0), "r0": 0.2, "r1": 0.12, "flare": 1.2, "lean": 0.35, "sides": 7,
				"fronds": 9, "flen": 2.5, "fwid": 0.95, "el_top": 1.3, "el_bot": 0.1, "droop": Vector2(0.7, 1.4), "segs": 4, "fold": 0.14, "dead": 2, "bulge": 0.0})
		"conifer":
			hr = _g_conifer(t, c, rng, far, {"h": Vector2(31.0, 37.0), "r0": 0.95, "bare": 0.40, "tiers": 12, "per": 5, "len0": 6.8, "len1": 1.6,
				"el0": -0.14, "el1": 0.45, "droop": 0.3, "wk": 0.62, "branches": true, "curtain": true, "pw": 1.1})
		"spruce":
			hr = _g_conifer(t, c, rng, far, {"h": Vector2(15.0, 19.0), "r0": 0.36, "bare": 0.06, "tiers": 16, "per": 7, "len0": 4.6, "len1": 0.7,
				"el0": -0.25, "el1": 0.45, "droop": 0.6, "wk": 0.5, "branches": false, "curtain": true, "hang": 0.16, "cw": 0.42, "pw": 0.85})
		"ginkgo":
			hr = _g_tree(t, c, rng, far, {"trunk": Vector2(5.0, 6.5), "r": 0.42, "levels": 2, "kids": [5, 3], "spread": [0.85, 0.6], "len": 5.2, "ratio": 0.62,
				"up": [0.0, 0.22, 0.3], "gnarl": 0.10, "leader": true, "from": 0.35, "limb_levels": 2, "puff": 4, "size": 2.5, "style": "ball"})
		"oak":
			hr = _g_tree(t, c, rng, far, {"trunk": Vector2(3.2, 4.2), "r": 0.62, "levels": 2, "kids": [5, 3], "spread": [1.0, 0.7], "len": 5.6, "ratio": 0.66,
				"up": [0.0, 0.16, 0.2], "gnarl": 0.24, "leader": false, "from": 0.8, "limb_levels": 2, "puff": 5, "size": 3.0, "style": "ball"})
		"banyan":
			hr = _g_tree(t, c, rng, far, {"trunk": Vector2(3.4, 4.4), "r": 1.25, "levels": 2, "kids": [6, 3], "spread": [1.22, 0.6], "len": 9.0, "ratio": 0.6,
				"up": [0.0, 0.14, 0.2], "gnarl": 0.16, "leader": false, "from": 0.7, "limb_levels": 2, "puff": 6, "size": 3.6, "style": "ball", "roots": 10, "fused": 5})
		"acacia":
			hr = _g_tree(t, c, rng, far, {"trunk": Vector2(2.2, 3.0), "r": 0.3, "levels": 2, "kids": [3, 4], "spread": [0.75, 0.95], "len": 3.6, "ratio": 0.8,
				"up": [0.0, 0.05, -0.12], "gnarl": 0.18, "leader": false, "from": 0.85, "limb_levels": 2, "puff": 4, "size": 2.3, "style": "flat", "tilt": 0.5})
		"berry_bush":
			hr = _g_bush(t, c, rng, far, {"rx": 0.85, "ry": 0.62, "cy": 0.72, "cards": 18, "size": 0.95, "stems": 4})
		"dwarf_shrub":
			hr = _g_bush(t, c, rng, far, {"rx": 0.6, "ry": 0.24, "cy": 0.2, "cards": 9, "size": 0.6, "stems": 0})
		"dry_scrub":
			hr = _g_bush(t, c, rng, far, {"rx": 0.6, "ry": 0.42, "cy": 0.42, "cards": 10, "size": 0.85, "stems": 0})
		"hedge":
			hr = _g_bush(t, c, rng, far, {"rx": 1.15, "ry": 0.8, "rz": 0.55, "cy": 0.85, "cards": 30, "size": 1.05, "stems": 3, "box": true})
		"clubmoss":
			hr = _g_tuft(c, rng, {"cards": 3, "h": 0.30, "w": 0.55, "clumps": 3, "spread": 0.42, "lean": 0.25})
		"horsetail":
			hr = _g_tuft(c, rng, {"cards": 3, "h": 0.95, "w": 0.62, "clumps": 0, "spread": 0.0, "lean": 0.08})
		"dry_grass":
			hr = _g_tuft(c, rng, {"cards": 3, "h": 0.78, "w": 0.85, "clumps": 1, "spread": 0.3, "lean": 0.22})
		"grass":
			hr = _g_tuft(c, rng, {"cards": 3, "h": 0.46, "w": 0.9, "clumps": 3, "spread": 0.55, "lean": 0.28})
		"reed":
			hr = _g_tuft(c, rng, {"cards": 3, "h": 2.6, "w": 1.5, "clumps": 1, "spread": 0.4, "lean": 0.07, "segs": 2, "droop": 0.12})
		"papyrus":
			hr = _g_tuft(c, rng, {"cards": 4, "h": 2.9, "w": 1.7, "clumps": 0, "spread": 0.0, "lean": 0.10, "segs": 2, "droop": 0.1})
		"crop":
			hr = _g_crop(c, rng)
		_:
			push_error("FoliageKit: unknown generator '%s'" % gen)
	return {"t": t, "c": c, "h": hr.x, "r": hr.y}


static func _g_lycopsid(t: MB, c: MB, rng: RandomNumberGenerator, far: bool) -> Vector2:
	var hf := rng.randf_range(16.5, 19.0)
	var lean := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
	var ys := [-0.3, 0.6, 3.0, 8.0, 13.0, hf]
	var rs := [1.08, 0.74, 0.6, 0.52, 0.44, 0.36]
	var pts: Array = []
	for i in ys.size():
		var k: float = maxf(ys[i], 0.0) / hf
		pts.append(Vector3(lean.x * k * k, ys[i], lean.z * k * k))
	t.limb(pts, rs, 5 if far else 9)
	var tips: Array = []
	_fork(t, rng, pts[pts.size() - 1], Vector3.UP, 4.5, 0.34, 0, 3 if far else 4, far, tips)
	var center: Vector3 = pts[pts.size() - 1] + Vector3(0, 5.5, 0)
	var top := hf
	for tip: Array in tips:
		var pos: Vector3 = tip[0]
		var dir: Vector3 = tip[1]
		var big: bool = tip[2]
		top = maxf(top, pos.y)
		var n := 3 if far else (6 if big else 4)
		var ln := (4.6 if far else (3.4 if big else 2.7)) * rng.randf_range(0.85, 1.1)
		var az0 := rng.randf() * TAU
		var outw := (pos - center).normalized()
		for i in n:
			var az := az0 + TAU * i / n + rng.randf_range(-0.3, 0.3)
			var o := Vector3(cos(az), 0, sin(az))
			var cd := (o * 0.9 + dir * 0.55 + Vector3.DOWN * (0.45 if far else 0.1)).normalized()
			c.card(pos, cd, Vector3(-sin(az), 0, cos(az)), ln, ln * (1.05 if far else 0.78), {"segs": 1 if far else 2, "droop": 0.0 if far else 1.1,
				"nbias": (outw * 0.6 + Vector3.UP * 0.7 + o * 0.3).normalized(), "nblend": 0.55, "ao0": 0.4, "ao1": 1.0, "phase": rng.randf()})
	return Vector2(top + 1.5, 0.62)


static func _fork(t: MB, rng: RandomNumberGenerator, pos: Vector3, dir: Vector3, length: float, radius: float, level: int, levels: int, far: bool, tips: Array) -> void:
	if level >= levels:
		tips.append([pos, dir, true])
		return
	var perp := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.8 else Vector3.BACK).normalized().rotated(dir, rng.randf() * TAU)
	for sgn: float in [-1.0, 1.0]:
		var d := dir.rotated(perp, sgn * rng.randf_range(0.40, 0.60))
		d = (d + Vector3.UP * 0.2).normalized()
		var mid := pos + d * (length * 0.5)
		var d2 := (d + Vector3.UP * 0.16 + Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))).normalized()
		var end := mid + d2 * (length * 0.5)
		if far:
			t.limb([pos, end], [radius, radius * 0.68], 3)
		elif level >= 3:
			t.limb([pos, end], [radius, radius * 0.6], 3)
			tips.append([mid, d, false])
		else:
			t.limb([pos, mid, end], [radius, radius * 0.84, radius * 0.68], 5 if level == 0 else 4)
			if level == 2:
				tips.append([mid, d, false])
		_fork(t, rng, end, d2, length * 0.74, radius * 0.68, level + 1, levels, far, tips)


static func _g_calamites(t: MB, c: MB, rng: RandomNumberGenerator, far: bool) -> Vector2:
	var hgt := rng.randf_range(12.0, 15.0)
	var nodes := 15
	var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
	var pts: Array = [Vector3(0, -0.3, 0)]
	var rs: Array = [0.36]
	var az0 := rng.randf() * TAU
	for i in range(0, nodes + 1):
		var k := float(i) / nodes
		var y := hgt * (1.0 - pow(1.0 - k, 1.3))
		var r := lerpf(0.33, 0.045, pow(k, 0.9))
		var p := Vector3(lean.x * k * k, y, lean.z * k * k)
		if far:
			if i % 3 == 0 or i == nodes:
				pts.append(p)
				rs.append(r)
		else:
			if i > 0:
				pts.append(p - Vector3(0, 0.07, 0))
				rs.append(r * 1.24)
			pts.append(p + Vector3(0, 0.05, 0))
			rs.append(r)
		if k < 0.26 or i == nodes or (far and i % 2 == 1):
			continue
		var u := (k - 0.26) / 0.74
		var ln := lerpf(2.5, 0.6, pow(u, 0.8)) * rng.randf_range(0.9, 1.1)
		var n := 4 if far else 7
		for j in n:
			var az := az0 + i * 0.9 + TAU * j / n + rng.randf_range(-0.15, 0.15)
			var o := Vector3(cos(az), 0, sin(az))
			var el := 0.55 + rng.randf_range(-0.1, 0.1)
			c.card(p + o * r * 0.6, o * cos(el) + Vector3.UP * sin(el), Vector3(-sin(az), 0, cos(az)), ln, ln * (0.9 if far else 0.6),
				{"segs": 1, "nbias": (Vector3.UP * 0.75 + o * 0.5).normalized(), "nblend": 0.6, "ao0": 0.35, "ao1": 1.0, "phase": rng.randf()})
	var top: Vector3 = pts[pts.size() - 1]
	for j in 2:
		c.card(top - Vector3(0, 0.5, 0), Vector3.UP, Vector3(cos(j * PI * 0.5), 0, sin(j * PI * 0.5)), 1.5, 0.8, {"nbias": Vector3.UP, "nblend": 0.5, "ao0": 0.7})
	t.limb(pts, rs, 4 if far else 6)
	return Vector2(hgt + 1.0, 0.3)


## Trunk with a rosette of fronds: palms, tree ferns, cycads, bananas, ground ferns.
static func _g_palmlike(t: MB, c: MB, rng: RandomNumberGenerator, far: bool, p: Dictionary) -> Vector2:
	var hrange: Vector2 = p.h
	var hgt := rng.randf_range(hrange.x, hrange.y)
	var top := Vector3.ZERO
	var r1 := 0.0
	var r_chest := 0.0
	if hgt > 0.0:
		var la := rng.randf() * TAU
		var lean := Vector3(cos(la), 0, sin(la)) * (rng.randf_range(0.3, 1.0) * float(p.lean))
		var r0: float = p.r0
		r1 = p.r1
		r_chest = r0
		var pts: Array = []
		var rs: Array = []
		var ks := [-0.03, 0.05, 0.28, 0.55, 0.8, 1.0]
		for k: float in ks:
			var kk := maxf(k, 0.0)
			pts.append(lean * pow(kk, 1.7) + Vector3(0, hgt * k, 0))
			rs.append(lerpf(r0, r1, kk) * (float(p.flare) if k < 0.0 else (lerpf(float(p.flare), 1.0, 0.6) if k < 0.1 else 1.0)))
		t.limb(pts, rs, 5 if far else int(p.sides))
		top = pts[pts.size() - 1]
		var bulge: float = p.get("bulge", 0.0)
		if bulge > 0.0 and not far:
			t.blob(top - Vector3(0, bulge * 0.3, 0), Vector3(bulge, bulge * 1.15, bulge))
		if not far:
			for i in int(p.get("nuts", 0)):
				var a := TAU * i / 5.0 + rng.randf()
				t.blob(top + Vector3(cos(a) * 0.3, -0.42 - rng.randf() * 0.15, sin(a) * 0.3), Vector3(0.16, 0.19, 0.16))
	var n: int = p.fronds
	if far:
		n = ceili(n * 0.5)
	var flen: float = p.flen
	var fwid: float = float(p.fwid) * (1.5 if far else 1.0)
	var droop: Vector2 = p.droop
	var az0 := rng.randf() * TAU
	for i in n:
		var u := (i + 0.5) / n
		var az := az0 + i * GOLDEN
		var el := lerpf(p.el_top, p.el_bot, pow(u, 0.85)) + rng.randf_range(-0.1, 0.1)
		var o := Vector3(cos(az), 0, sin(az))
		var dir := o * cos(el) + Vector3.UP * sin(el)
		c.card(top + o * (r1 * 0.5) + Vector3(0, lerpf(0.2, -0.1, u) * minf(hgt, 1.0), 0), dir, Vector3(-sin(az), 0, cos(az)),
			flen * rng.randf_range(0.82, 1.1), fwid, {"segs": 2 if far else int(p.segs), "droop": lerpf(droop.x, droop.y, u) * rng.randf_range(0.85, 1.15),
			"fold": 0.0 if far else float(p.get("fold", 0.0)), "nbias": (Vector3.UP * 0.8 + o * 0.45).normalized(), "nblend": 0.5,
			"ao0": 0.3, "ao1": 1.0, "phase": rng.randf()})
	var dead: int = p.get("dead", 0)
	if far:
		@warning_ignore("integer_division")
		dead = dead / 2
	for i in dead:
		var az := az0 + 1.3 + i * GOLDEN
		var o := Vector3(cos(az), 0, sin(az))
		var el := -1.05 + rng.randf_range(-0.15, 0.2)
		c.card(top + o * (r1 * 0.6) - Vector3(0, 0.15, 0), o * cos(el) + Vector3.UP * sin(el), Vector3(-sin(az), 0, cos(az)),
			flen * rng.randf_range(0.5, 0.75), fwid * 0.8, {"segs": 2, "droop": 0.3, "nbias": (o + Vector3.UP * 0.2).normalized(), "nblend": 0.5,
			"ao0": 0.3, "ao1": 0.75, "live": 0.0, "phase": rng.randf()})
	return Vector2(hgt + flen * 0.7, r_chest)


## Excurrent conifer: one straight trunk with tiers of boughs.
static func _g_conifer(t: MB, c: MB, rng: RandomNumberGenerator, far: bool, p: Dictionary) -> Vector2:
	var hrange: Vector2 = p.h
	var hgt := rng.randf_range(hrange.x, hrange.y)
	var r0: float = p.r0
	var lean := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
	var pts: Array = []
	var rs: Array = []
	for k: float in [-0.012, 0.03, 0.2, 0.45, 0.72, 1.0]:
		var kk := maxf(k, 0.0)
		pts.append(lean * (kk * kk) + Vector3(0, hgt * k, 0))
		rs.append(lerpf(r0, 0.05, pow(kk, 0.85)) * (1.45 if k < 0.0 else 1.0))
	t.limb(pts, rs, 5 if far else 9)
	var boughs: int = int(p.tiers) * int(p.per)
	if far:
		boughs = ceili(boughs * 0.42)
	var wk: float = float(p.wk) * (2.0 if far else 1.0)
	var az0 := rng.randf() * TAU
	for bi in boughs:
		var k := (bi + rng.randf() * 0.8) / boughs
		var y := hgt * lerpf(p.bare, 0.955, k)
		var ln := lerpf(p.len0, p.len1, pow(k, p.pw)) * rng.randf_range(0.88, 1.1)
		var el := lerpf(p.el0, p.el1, k) + rng.randf_range(-0.08, 0.08)
		var kk := y / hgt
		var axis := lean * (kk * kk) + Vector3(0, y, 0)
		var rt := lerpf(r0, 0.05, pow(kk, 0.85))
		var az := az0 + bi * GOLDEN + rng.randf_range(-0.2, 0.2)
		var o := Vector3(cos(az), 0, sin(az))
		var side := Vector3(-sin(az), 0, cos(az))
		var dir := o * cos(el) + Vector3.UP * sin(el)
		var root := axis + o * (rt * 0.5)
		var bl := ln * rng.randf_range(0.85, 1.1)
		if p.branches and not far and k < 0.78:
			var rb := 0.045 + rt * 0.14
			t.limb([root, root + dir * (bl * 0.5) - Vector3(0, bl * 0.04, 0), root + dir * (bl * 0.95) - Vector3(0, bl * 0.08, 0)], [rb, rb * 0.6, rb * 0.2], 3)
		var bias := (Vector3.UP * 0.8 + o * 0.5).normalized()
		c.card(root + dir * (bl * 0.06), dir, side, bl, bl * wk, {"segs": 1 if far else 2, "droop": p.droop, "nbias": bias, "nblend": 0.55,
			"ao0": 0.25, "ao1": 1.0, "phase": rng.randf(), "wind0": 0.1})
		if p.curtain and not far:
			c.card(root + dir * (bl * 0.12) - Vector3(0, bl * float(p.get("hang", 0.14)), 0), dir, Vector3.DOWN + side * rng.randf_range(-0.3, 0.3), bl * 0.85, bl * float(p.get("cw", 0.5)),
				{"segs": 1, "droop": float(p.droop) * 0.7, "nbias": (o * 0.7 + Vector3.UP * 0.5).normalized(), "nblend": 0.6, "ao0": 0.25, "ao1": 0.9, "phase": rng.randf(), "wind0": 0.1})
	var tip: Vector3 = pts[pts.size() - 1]
	var tl := float(p.len1) * 2.6 + hgt * 0.04
	for j in 2:
		c.card(tip - Vector3(0, tl * 0.78, 0), Vector3.UP, Vector3(cos(j * PI * 0.5 + 0.4), 0, sin(j * PI * 0.5 + 0.4)), tl, float(p.len1) * 1.7,
			{"nbias": Vector3.UP, "nblend": 0.45, "ao0": 0.6, "ao1": 1.0, "wind0": 0.3})
	return Vector2(hgt, r0 * 0.85)


static func _grow(sk: Dictionary, rng: RandomNumberGenerator, pos: Vector3, dir: Vector3, length: float, radius: float, depth: int, p: Dictionary) -> void:
	var segs := 4 if depth == 0 else (3 if depth == 1 else 2)
	var pts: Array = [pos]
	var rs: Array = [radius]
	var d := dir
	var gn: float = p.gnarl
	var up: float = (p.up as Array)[mini(depth, (p.up as Array).size() - 1)]
	var end_r := radius * (0.72 if depth == 0 else 0.42)
	var cur := pos
	for i in segs:
		d = (d + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)) * gn + Vector3.UP * up).normalized()
		cur += d * (length / segs)
		pts.append(cur)
		rs.append(lerpf(radius, end_r, (i + 1.0) / segs))
	sk.limbs.append({"pts": pts, "rs": rs, "depth": depth})
	var levels: int = p.levels
	if depth >= 1:
		sk.tips.append({"pos": (pts[segs - 1] as Vector3).lerp(pts[segs], 0.3), "depth": depth, "end": false})
	if depth >= levels:
		sk.tips.append({"pos": cur, "depth": depth, "end": true})
		return
	var kids: int = (p.kids as Array)[depth]
	var spin := rng.randf() * TAU
	var leader: bool = p.leader and depth == 0
	for k in kids:
		var spread: float = (p.spread as Array)[depth] * rng.randf_range(0.82, 1.18)
		var perp := d.cross(Vector3.RIGHT if absf(d.x) < 0.8 else Vector3.BACK).normalized().rotated(d, spin + TAU * k / kids + rng.randf_range(-0.25, 0.25))
		var cd := d.rotated(perp, spread)
		var at := 1.0
		var ln := length * float(p.ratio)
		if depth == 0:
			ln = p.len
			at = lerpf(p.from, 1.0, float(k) / maxi(kids - 1, 1))
			if leader and k == kids - 1:
				cd = (d + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))).normalized()
			elif leader:
				ln *= lerpf(1.0, 0.7, float(k) / kids)
		else:
			at = rng.randf_range(float(p.from) * 0.8, 1.0) if k > 0 else 1.0
		var f := at * segs
		var si := mini(int(f), segs - 1)
		var start := (pts[si] as Vector3).lerp(pts[si + 1], f - si)
		var sr := lerpf(rs[si], rs[si + 1], f - si)
		_grow(sk, rng, start, cd, ln * rng.randf_range(0.82, 1.12), sr * (0.62 if depth == 0 else 0.7), depth + 1, p)


## Broadleaf tree: recursive limbs, leaf-cluster cards around the branch tips.
static func _g_tree(t: MB, c: MB, rng: RandomNumberGenerator, far: bool, p: Dictionary) -> Vector2:
	var tr: Vector2 = p.trunk
	var th := rng.randf_range(tr.x, tr.y)
	var r: float = p.r
	var sk := {"limbs": [], "tips": []}
	var tilt: float = p.get("tilt", 0.12)
	var d0 := (Vector3.UP + Vector3(rng.randf_range(-tilt, tilt), 0, rng.randf_range(-tilt, tilt))).normalized()
	_grow(sk, rng, Vector3(0, -0.3, 0), d0, th + 0.3, r, 0, p)
	var limb_levels: int = p.limb_levels
	for l: Dictionary in sk.limbs:
		var depth: int = l.depth
		var rs: Array = l.rs
		var pts: Array = l.pts
		if depth == 0:
			rs[0] = r * 1.55
			rs[1] = r * 1.08
			t.limb(pts, rs, 5 if far else 9)
		elif depth <= limb_levels and not (far and depth > 1):
			if far:
				t.limb([pts[0], pts[pts.size() - 1]], [rs[0], rs[rs.size() - 1]], 3)
			else:
				t.limb(pts, rs, 6 if depth == 1 else 4)
	# fused secondary stems (banyan)
	if not far:
		for i in int(p.get("fused", 0)):
			var a := TAU * i / float(p.fused) + rng.randf_range(-0.3, 0.3)
			var o := Vector3(cos(a), 0, sin(a))
			var rr := r * rng.randf_range(0.28, 0.42)
			t.limb([o * (r * 1.25) + Vector3(0, -0.3, 0), o * (r * 0.95) + Vector3(0, th * 0.45, 0), o * (r * 0.6) + d0 * (th * 0.95)], [rr * 1.3, rr, rr * 0.8], 5)
	# aerial prop roots (banyan)
	var roots: int = p.get("roots", 0)
	if roots > 0:
		var firsts: Array = []
		for l: Dictionary in sk.limbs:
			if l.depth == 1:
				firsts.append(l)
		for i in (roots if not far else ceili(roots * 0.4)):
			var l: Dictionary = firsts[i % firsts.size()]
			var pts: Array = l.pts
			var f := rng.randf_range(0.45, 0.95) * (pts.size() - 1)
			var si := mini(int(f), pts.size() - 2)
			var a := (pts[si] as Vector3).lerp(pts[si + 1], f - si)
			var rr := rng.randf_range(0.06, 0.13)
			var wob := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
			t.limb([a, Vector3(a.x, a.y * 0.5, a.z) + wob, Vector3(a.x, -0.8, a.z)], [rr, rr * 0.8, rr * 1.5], 3 if far else 4)
	# crown
	var center := Vector3.ZERO
	for tip: Dictionary in sk.tips:
		center += tip.pos
	center /= maxf(sk.tips.size(), 1.0)
	var rad := 0.1
	var top := 0.0
	for tip: Dictionary in sk.tips:
		rad = maxf(rad, (tip.pos as Vector3).distance_to(center))
		top = maxf(top, (tip.pos as Vector3).y)
	var per: int = p.puff
	var size: float = p.size
	var flat: bool = p.style == "flat"
	var ti := 0
	for tip: Dictionary in sk.tips:
		ti += 1
		if far and ti % 2 == 0:
			continue
		var n := 3 if far else (per if tip.end else per - 2)
		var sz := size * (1.75 if far else 1.0)
		for j in n:
			var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.9), rng.randf_range(-1, 1)) * (size * 0.5)
			if flat:
				off.y *= 0.25
			var pos: Vector3 = tip.pos + off
			var outw := pos - center
			var dist := outw.length()
			outw = outw / maxf(dist, 0.001)
			var ao := lerpf(0.3, 1.0, clampf(inverse_lerp(0.25 * rad, 0.95 * rad, dist), 0.0, 1.0))
			ao *= lerpf(0.72, 1.0, smoothstep(-0.6 * rad, 0.2 * rad, pos.y - center.y))
			var rv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var dir: Vector3
			var side: Vector3
			if flat:
				dir = (Vector3(outw.x, 0, outw.z) + Vector3(rv.x, rv.y * 0.15, rv.z) * 0.7).normalized()
				side = dir.cross(Vector3.UP)
			else:
				dir = (outw * 0.75 + rv * 0.85 + Vector3.UP * 0.3).normalized()
				side = dir.cross(outw + rv * 0.6)
			var s1 := sz * rng.randf_range(0.8, 1.2)
			c.card(pos - dir * (s1 * 0.5), dir, side, s1, sz * rng.randf_range(0.8, 1.2), {"segs": 1,
				"nbias": (outw * 0.8 + Vector3.UP * 0.55).normalized(), "nblend": 0.82, "ao0": ao * 0.85, "ao1": minf(ao + 0.2, 1.0),
				"phase": rng.randf(), "wind0": 0.35})
	return Vector2(top + size * 0.6, r)


## Shrub: leaf cards on an ellipsoid (or box) shell, optional woody stems.
static func _g_bush(t: MB, c: MB, rng: RandomNumberGenerator, _far: bool, p: Dictionary) -> Vector2:
	var rx: float = p.rx
	var ry: float = p.ry
	var rz: float = p.get("rz", rx)
	var cy: float = p.cy
	var n: int = p.cards
	var size: float = p.size
	var box: bool = p.get("box", false)
	var center := Vector3(0, cy, 0)
	for i in int(p.stems):
		var a := TAU * i / float(p.stems) + rng.randf()
		var o := Vector3(cos(a), 0, sin(a))
		t.limb([Vector3(0, -0.1, 0) + o * 0.05, o * (rx * 0.35) + Vector3(0, cy * 0.7, 0), o * (rx * 0.6) + Vector3(0, cy * 1.25, 0)], [0.045, 0.03, 0.012], 3)
	for i in n:
		var y := 1.0 - (i + 0.5) / n * 1.45
		var rr := sqrt(maxf(1.0 - y * y, 0.0))
		var az := i * GOLDEN + rng.randf_range(-0.2, 0.2)
		var dv := Vector3(cos(az) * rr, y, sin(az) * rr)
		if box:
			var m := maxf(absf(dv.x), maxf(absf(dv.y) * 0.9, absf(dv.z)))
			dv /= m
			dv.y = clampf(dv.y, -0.6, 1.0)
		var shell := rng.randf_range(0.72, 1.0)
		var pos := center + Vector3(dv.x * rx, dv.y * ry, dv.z * rz) * shell
		pos.y = maxf(pos.y, size * 0.2)
		var outw := Vector3(dv.x, dv.y * 0.8, dv.z).normalized()
		var rv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var dir := (outw * 0.6 + Vector3.UP * 0.6 + rv * 0.5).normalized()
		var ao := lerpf(0.4, 1.0, clampf(pos.y / (cy + ry), 0.0, 1.0)) * lerpf(0.75, 1.0, (shell - 0.72) / 0.28)
		var s1 := size * rng.randf_range(0.8, 1.2)
		c.card(pos - dir * (s1 * 0.5), dir, dir.cross(outw + rv * 0.5), s1, size * rng.randf_range(0.8, 1.2), {"segs": 1,
			"nbias": (outw + Vector3.UP * 0.7).normalized(), "nblend": 0.68, "ao0": ao * 0.8, "ao1": minf(ao + 0.2, 1.0), "phase": rng.randf(), "wind0": 0.3})
	if box:
		# dark core so the hedge is not see-through
		for i in 4:
			var x := lerpf(-rx * 0.6, rx * 0.6, i / 3.0)
			c.card(Vector3(x, 0.0, 0), Vector3.UP, Vector3(rng.randf_range(-0.4, 0.4), 0, 1), cy + ry * 0.8, rz * 2.2, {"nbias": Vector3.UP, "nblend": 0.7, "ao0": 0.25, "ao1": 0.5, "wind0": 0.0})
		c.card(Vector3(-rx * 0.95, 0.0, 0), Vector3.UP, Vector3(1, 0, 0), cy + ry * 0.7, rx * 1.9, {"nbias": Vector3.UP, "nblend": 0.7, "ao0": 0.25, "ao1": 0.5})
	return Vector2(cy + ry + size * 0.4, 0.0)


## Crossed upright cards: grasses, reeds, horsetails, clubmoss mats.
static func _g_tuft(c: MB, rng: RandomNumberGenerator, p: Dictionary) -> Vector2:
	var hgt: float = p.h
	var wid: float = p.w
	var lean: float = p.lean
	var segs: int = p.get("segs", 1)
	var centers: Array = [[Vector3.ZERO, 1.0, int(p.cards)]]
	for i in int(p.clumps):
		var a := TAU * i / maxf(float(p.clumps), 1.0) + rng.randf() * 2.0
		centers.append([Vector3(cos(a), 0, sin(a)) * (float(p.spread) * rng.randf_range(0.7, 1.2)), rng.randf_range(0.6, 0.85), 2])
	for ce: Array in centers:
		var n: int = ce[2]
		var k: float = ce[1]
		var yaw0 := rng.randf() * PI
		for i in n:
			var yaw := yaw0 + PI * i / n + rng.randf_range(-0.2, 0.2)
			var side := Vector3(cos(yaw), 0, sin(yaw))
			var nrm := Vector3(-sin(yaw), 0, cos(yaw))
			var dir := (Vector3.UP + nrm * rng.randf_range(-lean, lean)).normalized()
			c.card((ce[0] as Vector3) - Vector3(0, 0.03, 0), dir, side, hgt * k * rng.randf_range(0.85, 1.1), wid * k, {"segs": segs, "droop": p.get("droop", 0.0),
				"nbias": Vector3.UP, "nblend": 0.78, "ao0": 0.45, "ao1": 1.0, "phase": rng.randf()})
	return Vector2(hgt, 0.0)


## One 1.5 m stretch of a cereal row (plant with cfg.rows).
static func _g_crop(c: MB, rng: RandomNumberGenerator) -> Vector2:
	for z: float in [-0.13, 0.13]:
		c.card(Vector3(rng.randf_range(-0.1, 0.1), -0.03, z), (Vector3.UP + Vector3(0, 0, z * 0.9)).normalized(), Vector3.RIGHT, 1.05 * rng.randf_range(0.92, 1.06), 1.7,
			{"nbias": Vector3.UP, "nblend": 0.78, "ao0": 0.4, "ao1": 1.0, "phase": rng.randf()})
	for x: float in [-0.45, 0.4]:
		c.card(Vector3(x, -0.03, 0), Vector3.UP, Vector3(rng.randf_range(-0.4, 0.4), 0, 1), 1.0, 0.9, {"nbias": Vector3.UP, "nblend": 0.78, "ao0": 0.4, "ao1": 1.0, "phase": rng.randf()})
	return Vector2(1.05, 0.0)


# ================================================================= placement
## A planted batch: MultiMeshInstance3Ds chunked into cells, with per-plant
## burn / snow state. Indices are stable for the lifetime of the node.
class Group extends Node3D:
	var kind := ""
	var xforms: Array[Transform3D] = []			## per-plant transform, local to this node
	var mmis: Array[MultiMeshInstance3D] = []
	var burn := PackedFloat32Array()
	var snow := PackedFloat32Array()
	var trunk_radius := 0.0						## at scale 1; multiply by scale_of(i)
	var plant_height := 0.0						## at scale 1
	var body: StaticBody3D						## trunk colliders (null without collide)
	var _cell := PackedInt32Array()
	var _local := PackedInt32Array()
	var _cells: Array = []

	func count() -> int:
		return xforms.size()

	## World-space base position of every plant.
	func positions() -> PackedVector3Array:
		var out := PackedVector3Array()
		out.resize(xforms.size())
		var g := global_transform if is_inside_tree() else transform
		for i in xforms.size():
			out[i] = g * xforms[i].origin
		return out

	func position_of(i: int) -> Vector3:
		return (global_transform if is_inside_tree() else transform) * xforms[i].origin

	func scale_of(i: int) -> float:
		return xforms[i].basis.get_scale().y

	func radius_of(i: int) -> float:
		return trunk_radius * scale_of(i)

	func height_of(i: int) -> float:
		return plant_height * scale_of(i)

	## 0 = untouched, 0.5 = charred black, 1 = leaves gone (trunks stay, blackened).
	func set_burn(i: int, amount: float) -> void:
		if i < 0 or i >= xforms.size():
			return
		burn[i] = clampf(amount, 0.0, 1.0)
		_push(i)

	func get_burn(i: int) -> float:
		return burn[i]

	func burn_all(amount: float) -> void:
		for i in xforms.size():
			burn[i] = clampf(amount, 0.0, 1.0)
			_push(i)

	## Snow cover 0..1 on every plant.
	func set_snow(amount: float) -> void:
		for i in xforms.size():
			snow[i] = clampf(amount, 0.0, 1.0)
			_push(i)

	func set_snow_at(i: int, amount: float) -> void:
		if i < 0 or i >= xforms.size():
			return
		snow[i] = clampf(amount, 0.0, 1.0)
		_push(i)

	## Index of the plant closest to a world position (-1 if none within max_dist).
	func nearest(pos: Vector3, max_dist := 1e9) -> int:
		var lp := (global_transform.affine_inverse() if is_inside_tree() else transform.affine_inverse()) * pos
		var best := -1
		var bd := max_dist * max_dist
		for i in xforms.size():
			var o := xforms[i].origin
			var d := (o.x - lp.x) * (o.x - lp.x) + (o.z - lp.z) * (o.z - lp.z)
			if d < bd:
				bd = d
				best = i
		return best

	## Indices of plants within `radius` (horizontal) of a world position.
	func within(pos: Vector3, radius: float) -> PackedInt32Array:
		var lp := (global_transform.affine_inverse() if is_inside_tree() else transform.affine_inverse()) * pos
		var out := PackedInt32Array()
		var r2 := radius * radius
		for i in xforms.size():
			var o := xforms[i].origin
			if (o.x - lp.x) * (o.x - lp.x) + (o.z - lp.z) * (o.z - lp.z) <= r2:
				out.append(i)
		return out

	func _push(i: int) -> void:
		var col := Color(burn[i], snow[i], 0.0, 0.0)
		var li := _local[i]
		for mm: MultiMesh in _cells[_cell[i]]:
			mm.set_instance_custom_data(li, col)


## Trees: trunk + crown MultiMeshes with a cheap far LOD and trunk colliders.
static func forest(parent: Node, kind: String, cfg: Dictionary = {}) -> Group:
	return _place(parent, kind, cfg, false)


## Dense low plants: no shadows or colliders by default, shrink-fade at visibility_end (default 70 m).
static func ground_cover(parent: Node, kind: String, cfg: Dictionary = {}) -> Group:
	return _place(parent, kind, cfg, true)


## One hero plant as its own node at `pos` (full detail at any distance, no collider
## unless cfg.collide). Metadata: kind, trunk_radius, height (both already scaled).
static func single(parent: Node, kind: String, pos: Vector3, scale := 1.0, plant_seed := 0, cfg: Dictionary = {}) -> Group:
	var c := cfg.duplicate()
	var rng := _rng(plant_seed * 977 + 5)
	c["points"] = [Transform3D(Basis(Vector3.UP, c.get("yaw", rng.randf() * TAU)).scaled(Vector3.ONE * scale), Vector3.ZERO)]
	c["variant"] = plant_seed
	c["lod_distance"] = c.get("lod_distance", 0.0)
	c["collide"] = c.get("collide", false)
	c.erase("terrain")
	var g := _place(parent, kind, c, false, pos)
	g.set_meta("kind", kind)
	g.set_meta("trunk_radius", g.trunk_radius * scale)
	g.set_meta("height", g.plant_height * scale)
	return g


## Evenly spaced transforms from a to b, facing along the line (hedges, avenues).
static func line_points(a: Vector3, b: Vector3, spacing: float, terrain: Terrain = null, jitter := 0.0, line_seed := 1) -> Array:
	var out: Array = []
	var rng := _rng(line_seed)
	var d := b - a
	var n := maxi(int(round(Vector2(d.x, d.z).length() / spacing)), 1)
	var yaw := atan2(-d.z, d.x)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n) + Vector3(rng.randf_range(-jitter, jitter), 0, rng.randf_range(-jitter, jitter))
		if terrain:
			p.y = terrain.height_at(p.x, p.z)
		out.append(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.08, 0.08)).scaled(Vector3.ONE * rng.randf_range(0.92, 1.1)), p))
	return out


## Triangles per kind: {kind: {"near": n, "far": n}} (variant 0).
static func triangle_report() -> Dictionary:
	var out := {}
	for kind: String in SPECS:
		var pl := plant(kind, 0)
		out[kind] = {"near": pl.tris, "far": pl.tris_far}
	return out


static func _transforms(cfg: Dictionary, spec: Dictionary, ground: bool) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var rng := _rng(int(cfg.get("seed", 1)) * 7919 + 13)
	var terrain: Terrain = cfg.get("terrain", null)
	var sc: Vector2 = cfg.get("scale", spec.scale)
	var accept: Callable = cfg.get("accept", Callable())
	if cfg.has("points"):
		for p: Variant in cfg.points:
			if p is Transform3D:
				out.append(p)
				continue
			var pos: Vector3 = p
			if terrain:
				pos.y = terrain.height_at(pos.x, pos.z)
			var yaw: float = cfg.get("yaw", rng.randf() * TAU)
			out.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(sc.x, sc.y)), pos))
		return out
	if cfg.has("rows"):
		var rows: Dictionary = cfg.rows
		var gap: float = rows.get("spacing", 0.7)
		var step: float = rows.get("step", 1.4)
		var ang: float = rows.get("angle", 0.0)
		var rect: Rect2 = cfg.get("rect", Rect2(-10, -10, 20, 20))
		var cen := rect.get_center()
		var half := rect.size.length() * 0.5
		var along := Vector2(cos(ang), -sin(ang))
		var across := Vector2(sin(ang), cos(ang))
		var nr := int(half / gap)
		var ns := int(half / step)
		for ri in range(-nr, nr + 1):
			for si in range(-ns, ns + 1):
				var q := cen + across * (ri * gap + rng.randf_range(-0.04, 0.04)) + along * (si * step + rng.randf_range(-0.15, 0.15))
				if not rect.has_point(q):
					continue
				var y := terrain.height_at(q.x, q.y) if terrain else float(cfg.get("center", Vector3.ZERO).y)
				if accept.is_valid() and rng.randf() > float(accept.call(q.x, q.y, y)):
					continue
				out.append(Transform3D(Basis(Vector3.UP, ang).scaled(Vector3.ONE * rng.randf_range(sc.x, sc.y)), Vector3(q.x, y, q.y)))
		return out
	var c := cfg.duplicate()
	var want := int(cfg.get("count", 20))
	if not cfg.get("exact", false):
		want = maxi(int(round(want * _density())), 1)
	var spacing: float = cfg.get("spacing", spec.get("spacing", 0.0))
	c["count"] = want if spacing <= 0.0 else int(want * 1.6) + 6
	c["scale"] = sc
	if not c.has("sink"):
		c["sink"] = 0.0 if ground else 0.1
	if not c.has("align"):
		c["align"] = 0.55 if ground else 0.0
	if not c.has("tilt"):
		c["tilt"] = 0.04 if ground else 0.025
	if not c.has("min_flat") and not ground:
		c["min_flat"] = 0.7
	var pts := Scatter.points(c)
	if spacing <= 0.0:
		return pts
	var grid := {}
	for xf in pts:
		if out.size() >= want:
			break
		var o := xf.origin
		var key := Vector2i(floori(o.x / spacing), floori(o.z / spacing))
		var ok := true
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var k2 := key + Vector2i(dx, dz)
				if grid.has(k2):
					for q: Vector3 in grid[k2]:
						if Vector2(q.x - o.x, q.z - o.z).length_squared() < spacing * spacing:
							ok = false
		if not ok:
			continue
		if not grid.has(key):
			grid[key] = []
		grid[key].append(o)
		out.append(xf)
	return out


static func _place(parent: Node, kind: String, cfg: Dictionary, ground: bool, at := Vector3.ZERO) -> Group:
	_ensure_globals()
	if not SPECS.has(kind):
		push_error("FoliageKit: unknown plant kind '%s'" % kind)
		kind = "fern"
	var spec: Dictionary = SPECS[kind]
	var g := Group.new()
	g.name = "Foliage_" + kind
	g.kind = kind
	g.position = at
	parent.add_child(g)
	var xforms := _transforms(cfg, spec, ground)
	g.xforms = xforms
	var n := xforms.size()
	g.burn.resize(n)
	g.snow.resize(n)
	g._cell.resize(n)
	g._local.resize(n)
	var init_snow: float = cfg.get("snow", 0.0)
	var init_burn: float = cfg.get("burn", 0.0)
	for i in n:
		g.burn[i] = init_burn
		g.snow[i] = init_snow
	var is_tree: bool = spec.get("tree", false)
	var nvar: int = clampi(int(cfg.get("variants", 3 if is_tree else 2)), 1, maxi(n, 1))
	var base_var: int = cfg.get("variant", 0)
	var lod: float = cfg.get("lod_distance", spec.get("lod", 0.0))
	var ve: float = cfg.get("visibility_end", 70.0 if ground else 0.0)
	var cell: float = cfg.get("cell", 48.0 if not ground else clampf(ve * 0.4, 16.0, 40.0))
	var shadows: bool = cfg.get("shadows", spec.get("shadows", not ground))
	var fade := ve if ground else 0.0
	var leaf_mat := _leaf_material(kind, fade)
	var bark_mat: ShaderMaterial = _bark_material(kind) if spec.has("bark") else null
	var first := plant(kind, base_var)
	g.trunk_radius = first.radius
	g.plant_height = first.height
	# bucket by cell and variant
	var buckets := {}
	for i in n:
		var o := xforms[i].origin
		var key := Vector3i(floori(o.x / cell), floori(o.z / cell), base_var + (i * 7 + int(absf(o.x) * 3.1)) % nvar)
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(i)
	for key: Vector3i in buckets:
		var ids := PackedInt32Array(buckets[key] as Array)
		var pl := plant(kind, key.z)
		var mms: Array[MultiMesh] = []
		var has_far: bool = lod > 0.0 and (pl.crown_far != null or pl.trunk_far != null)
		var near_end := lod if has_far else ve
		if pl.trunk and bark_mat:
			mms.append(_mmi(g, pl.trunk, bark_mat, ids, shadows, 0.0, near_end, has_far, ground))
		if pl.crown:
			mms.append(_mmi(g, pl.crown, leaf_mat, ids, shadows, 0.0, near_end, has_far, ground))
		if has_far:
			if pl.trunk_far and bark_mat:
				mms.append(_mmi(g, pl.trunk_far, bark_mat, ids, shadows, lod, ve, false, ground))
			if pl.crown_far:
				mms.append(_mmi(g, pl.crown_far, leaf_mat, ids, shadows, lod, ve, false, ground))
		var ci := g._cells.size()
		g._cells.append(mms)
		for li in ids.size():
			g._cell[ids[li]] = ci
			g._local[ids[li]] = li
	# trunk colliders
	var cr: float = spec.get("collide_r", first.radius)
	if cfg.get("collide", is_tree) and cr > 0.0 and n > 0:
		var body := StaticBody3D.new()
		body.name = "Trunks"
		body.collision_layer = 1
		body.collision_mask = 0
		g.add_child(body)
		g.body = body
		var shapes := {}
		for i in n:
			var s := xforms[i].basis.get_scale().y
			var rq := maxf(snappedf(cr * s, 0.05), 0.05)
			var hq := clampf(snappedf(float(first.height) * s * 0.8, 0.5), 1.0, 9.0)
			var sk := Vector2(rq, hq)
			if not shapes.has(sk):
				var sh := CylinderShape3D.new()
				sh.radius = rq
				sh.height = hq
				shapes[sk] = sh
			var cs := CollisionShape3D.new()
			cs.shape = shapes[sk]
			cs.position = xforms[i].origin + Vector3(0, hq * 0.5 - 0.2, 0)
			body.add_child(cs)
	return g


static func _mmi(g: Group, mesh: Mesh, mat: Material, ids: PackedInt32Array, shadows: bool, begin: float, end: float, lod_near: bool, ground: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = ids.size()
	for li in ids.size():
		var i := ids[li]
		mm.set_instance_transform(li, g.xforms[i])
		mm.set_instance_custom_data(li, Color(g.burn[i], g.snow[i], 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.extra_cull_margin = 2.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if begin > 0.0:
		mmi.visibility_range_begin = begin
		mmi.visibility_range_begin_margin = 6.0
	if end > 0.0:
		if ground:
			# plants shrink away in the shader before this; the range only culls the chunk
			mmi.visibility_range_end = end + mm.get_aabb().size.length() * 0.5 + 6.0
		else:
			mmi.visibility_range_end = end
			mmi.visibility_range_end_margin = 6.0 if lod_near else end * 0.1
	g.add_child(mmi)
	g.mmis.append(mmi)
	return mm
