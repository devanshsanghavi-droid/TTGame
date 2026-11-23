class_name Humanoid extends Node3D
## Procedural person: lofted limbs, cloth layers, procedural animation.
## Faces -Z, feet at y = 0. Build with Humanoid.create(cfg).
##
## cfg keys (all optional):
##   skin: Color            top: [texture, tint]      bottom: [texture, tint]
##   bare_chest: bool       skirt: float (0 = trousers, else hem length in m)
##   cloak: [texture, tint] head: "hair"|"hood"|"turban"|"bald"|"helmet"|"nemes"|"cap"|"coif"
##   hair: Color            beard: bool               bulk: float (1 = average)
##   height: float          device: bool (CHRONO on the wrist)
##   prop: "spear"|"staff"|"basket"|"torch"|"" (held in right hand)
##   sash: Color (cloth band across the chest or waist)

var cfg := {}
var hips: Node3D
var chest: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var hand_r: Node3D
var hand_l: Node3D
var device_light: OmniLight3D

var _phase := 0.0
var _hips_y := 0.95
var _blend := {"crouch": 0.0, "climb": 0.0, "swim": 0.0, "carry": 0.0, "work": 0.0, "sit": 0.0}
var _t := 0.0


static func create(config: Dictionary = {}) -> Humanoid:
	var h := Humanoid.new()
	h.cfg = config
	h._build()
	return h


static func skin_mat(c: Color) -> StandardMaterial3D:
	var key := "skin" + str(c)
	if MatLib._cache.has(key):
		return MatLib._cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.62
	m.normal_enabled = true
	m.normal_texture = MatLib.noise_tex(41, 0.09, true)
	m.normal_scale = 0.35
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(3, 3, 3)
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.25
	m.rim_enabled = true
	m.rim = 0.15
	MatLib._cache[key] = m
	return m


func _cloth(spec: Variant, fallback: Color) -> Material:
	if spec is Array and spec.size() >= 2:
		return MatLib.pbr(spec[0], {"tint": spec[1], "scale": 2.2, "world": false, "sharp": 2.0})
	return MatLib.pbr("rough_linen", {"tint": fallback, "scale": 2.2, "world": false, "sharp": 2.0})


func _build() -> void:
	var bulk: float = cfg.get("bulk", 1.0)
	var skin := skin_mat(cfg.get("skin", Color(0.62, 0.45, 0.34)))
	var top := _cloth(cfg.get("top", null), Color(0.42, 0.38, 0.32))
	var bottom := _cloth(cfg.get("bottom", null), Color(0.25, 0.22, 0.2))
	var bare: bool = cfg.get("bare_chest", false)
	var torso_mat: Material = skin if bare else top
	var skirt: float = cfg.get("skirt", 0.0)
	var up := Vector3.BACK
	scale = Vector3.ONE * (float(cfg.get("height", 1.78)) / 1.78)

	hips = Node3D.new()
	hips.position.y = _hips_y
	add_child(hips)
	# torso
	MeshKit.loft([Vector3(0, -0.08, 0), Vector3(0, 0.02, 0), Vector3(0, 0.22, 0), Vector3(0, 0.44, 0), Vector3(0, 0.53, 0)],
		[Vector2(0.14, 0.1) * bulk, Vector2(0.17, 0.115) * bulk, Vector2(0.155, 0.105) * bulk, Vector2(0.2, 0.12) * bulk, Vector2(0.07, 0.065)],
		torso_mat, hips, 12, up)
	chest = Node3D.new()
	chest.position.y = 0.46
	hips.add_child(chest)
	# neck + head
	MeshKit.loft([Vector3(0, 0.02, 0), Vector3(0, 0.14, 0)], [0.05, 0.048], skin, chest, 8, up)
	head = Node3D.new()
	head.position.y = 0.22
	chest.add_child(head)
	MeshKit.ellipsoid(Vector3(0.095, 0.115, 0.105), skin, Vector3.ZERO, head)
	MeshKit.ellipsoid(Vector3(0.022, 0.03, 0.03), skin, Vector3(0, -0.01, -0.105), head, 1)  # nose
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(0.04, 0.035, 0.03)
	eye.roughness = 0.25
	for sx in [-1.0, 1.0]:
		MeshKit.ellipsoid(Vector3(0.014, 0.01, 0.008), eye, Vector3(0.036 * sx, 0.018, -0.096), head, 1)
	_build_headwear(skin)
	# arms
	arm_l = _limb(chest, Vector3(-0.215 * bulk, -0.02, 0), 0.29, [0.058 * bulk, 0.046 * bulk], torso_mat)
	arm_r = _limb(chest, Vector3(0.215 * bulk, -0.02, 0), 0.29, [0.058 * bulk, 0.046 * bulk], torso_mat)
	elbow_l = _limb(arm_l, Vector3(0, -0.29, 0), 0.27, [0.045 * bulk, 0.036], skin)
	elbow_r = _limb(arm_r, Vector3(0, -0.29, 0), 0.27, [0.045 * bulk, 0.036], skin)
	hand_l = Node3D.new()
	hand_l.position.y = -0.3
	elbow_l.add_child(hand_l)
	MeshKit.ellipsoid(Vector3(0.04, 0.055, 0.03), skin, Vector3.ZERO, hand_l, 1)
	hand_r = Node3D.new()
	hand_r.position.y = -0.3
	elbow_r.add_child(hand_r)
	MeshKit.ellipsoid(Vector3(0.04, 0.055, 0.03), skin, Vector3.ZERO, hand_r, 1)
	# legs
	var leg_mat: Material = skin if skirt > 0.0 else bottom
	leg_l = _limb(hips, Vector3(-0.09 * bulk, -0.05, 0), 0.44, [0.085 * bulk, 0.066 * bulk], leg_mat)
	leg_r = _limb(hips, Vector3(0.09 * bulk, -0.05, 0), 0.44, [0.085 * bulk, 0.066 * bulk], leg_mat)
	knee_l = _limb(leg_l, Vector3(0, -0.44, 0), 0.42, [0.064 * bulk, 0.045], leg_mat)
	knee_r = _limb(leg_r, Vector3(0, -0.44, 0), 0.42, [0.064 * bulk, 0.045], leg_mat)
	var shoe := MatLib.pbr("brown_leather", {"tint": cfg.get("shoe", Color(0.3, 0.22, 0.16)), "scale": 3.0, "world": false})
	for k in [knee_l, knee_r]:
		MeshKit.ellipsoid(Vector3(0.05, 0.04, 0.11), shoe if not cfg.get("barefoot", false) else skin, Vector3(0, -0.43, -0.04), k, 1)
	# skirt / kilt / tunic hem
	if skirt > 0.0:
		MeshKit.loft([Vector3(0, 0.06, 0), Vector3(0, -0.05, 0), Vector3(0, -skirt, 0)],
			[Vector2(0.165, 0.118) * bulk, Vector2(0.19, 0.14) * bulk, Vector2(0.2 + skirt * 0.16, 0.16 + skirt * 0.14) * bulk],
			bottom, hips, 12, up)
	else:
		MeshKit.loft([Vector3(0, 0.05, 0), Vector3(0, -0.12, 0)], [Vector2(0.172, 0.12) * bulk, Vector2(0.18, 0.13) * bulk], bottom, hips, 12, up)
	if cfg.has("sash"):
		var sm := MatLib.pbr("rough_linen", {"tint": cfg.sash, "scale": 3.0, "world": false})
		MeshKit.loft([Vector3(0, 0.0, 0), Vector3(0, 0.09, 0)], [Vector2(0.178, 0.125) * bulk, Vector2(0.172, 0.12) * bulk], sm, hips, 12, up)
	if cfg.has("cloak"):
		var cm := _cloth(cfg.cloak, Color(0.2, 0.2, 0.2))
		var cloak := MeshKit.loft([Vector3(0, 0.04, 0.02), Vector3(0, -0.3, 0.1), Vector3(0, -0.85, 0.16)],
			[Vector2(0.21, 0.07) * bulk, Vector2(0.25, 0.06) * bulk, Vector2(0.3, 0.04) * bulk], cm, chest, 10, up)
		cloak.name = "Cloak"
	if cfg.get("device", false):
		var dm := MatLib.metal("rusty_metal_02", Color(0.55, 0.5, 0.42), 0.5, 4.0)
		MeshKit.box(Vector3(0.075, 0.05, 0.085), dm, Vector3(-0.012, -0.2, 0), elbow_l)
		var screen := StandardMaterial3D.new()
		screen.albedo_color = Color(0.02, 0.02, 0.02)
		screen.emission_enabled = true
		screen.emission = Color(0.75, 0.9, 0.82)
		screen.emission_energy_multiplier = 1.2
		MeshKit.box(Vector3(0.005, 0.035, 0.06), screen, Vector3(-0.051, -0.2, 0), elbow_l)
		device_light = OmniLight3D.new()
		device_light.light_color = Color(0.75, 0.9, 0.82)
		device_light.light_energy = 0.25
		device_light.omni_range = 1.6
		device_light.position = Vector3(-0.1, -0.2, 0)
		elbow_l.add_child(device_light)
	_build_prop()


func _limb(parent: Node3D, pos: Vector3, length: float, radii: Array, mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	MeshKit.loft([Vector3(0, 0.02, 0), Vector3(0, -length * 0.5, 0), Vector3(0, -length - 0.01, 0)],
		[radii[0], (radii[0] + radii[1]) * 0.52, radii[1]], mat, pivot, 8, Vector3.BACK)
	return pivot


func _build_headwear(skin: Material) -> void:
	var kind: String = cfg.get("head", "hair")
	var hair_c: Color = cfg.get("hair", Color(0.08, 0.06, 0.05))
	var hair := MatLib.pbr("wool_boucle", {"tint": hair_c, "scale": 5.0, "world": false, "rough": 1.0})
	match kind:
		"hair":
			MeshKit.ellipsoid(Vector3(0.102, 0.1, 0.112), hair, Vector3(0, 0.035, 0.015), head)
		"long_hair":
			MeshKit.ellipsoid(Vector3(0.105, 0.1, 0.115), hair, Vector3(0, 0.035, 0.015), head)
			MeshKit.ellipsoid(Vector3(0.1, 0.17, 0.06), hair, Vector3(0, -0.1, 0.08), head)
		"topknot":
			MeshKit.ellipsoid(Vector3(0.1, 0.09, 0.11), hair, Vector3(0, 0.04, 0.015), head)
			MeshKit.ellipsoid(Vector3(0.045, 0.05, 0.045), hair, Vector3(0, 0.13, 0.05), head, 1)
		"hood":
			var hm := _cloth(cfg.get("cloak", cfg.get("top", null)), Color(0.25, 0.23, 0.2))
			MeshKit.ellipsoid(Vector3(0.125, 0.135, 0.135), hm, Vector3(0, 0.02, 0.03), head)
		"turban":
			var tm := MatLib.pbr("rough_linen", {"tint": cfg.get("head_color", Color(0.85, 0.8, 0.7)), "scale": 4.0, "world": false})
			MeshKit.ellipsoid(Vector3(0.125, 0.075, 0.13), tm, Vector3(0, 0.075, 0.01), head)
		"nemes":
			var nm := MatLib.pbr("rough_linen", {"tint": cfg.get("head_color", Color(0.88, 0.84, 0.72)), "scale": 4.0, "world": false})
			MeshKit.ellipsoid(Vector3(0.115, 0.09, 0.12), nm, Vector3(0, 0.05, 0.015), head)
			MeshKit.box(Vector3(0.21, 0.2, 0.03), nm, Vector3(0, -0.08, 0.09), head)
		"helmet":
			var mm := MatLib.metal("rusty_metal_02", cfg.get("head_color", Color(0.6, 0.6, 0.62)), 0.45, 3.0)
			MeshKit.ellipsoid(Vector3(0.112, 0.115, 0.12), mm, Vector3(0, 0.03, 0.005), head)
			MeshKit.box(Vector3(0.02, 0.1, 0.02), mm, Vector3(0, -0.01, -0.115), head)
		"coif", "cap":
			var cm := MatLib.pbr("wool_boucle", {"tint": cfg.get("head_color", Color(0.5, 0.42, 0.3)), "scale": 4.0, "world": false})
			MeshKit.ellipsoid(Vector3(0.108, 0.1, 0.115), cm, Vector3(0, 0.04, 0.012), head)
		"bald":
			pass
	if cfg.get("beard", false):
		MeshKit.ellipsoid(Vector3(0.075, 0.07, 0.05), hair, Vector3(0, -0.085, -0.06), head, 1)
	if cfg.get("brow", false):
		MeshKit.ellipsoid(Vector3(0.085, 0.018, 0.03), skin, Vector3(0, 0.045, -0.09), head, 1)


func _build_prop() -> void:
	var prop: String = cfg.get("prop", "")
	if prop == "":
		return
	var wood := MatLib.pbr("rough_wood", {"tint": Color(0.55, 0.42, 0.3), "scale": 2.0, "world": false})
	match prop:
		"spear":
			var shaft := MeshKit.cyl(0.014, 0.016, 2.1, wood, Vector3(0, 0.55, -0.03), hand_r, 6)
			shaft.rotation.x = 0.0
			var tip := MeshKit.cyl(0.0, 0.03, 0.2, MatLib.pbr("dark_rock", {"scale": 3.0, "world": false, "tint": Color(0.5, 0.5, 0.5)}), Vector3(0, 1.7, -0.03), hand_r, 6)
			tip.name = "Tip"
		"staff":
			MeshKit.cyl(0.016, 0.02, 1.7, wood, Vector3(0, 0.45, -0.03), hand_r, 6)
		"torch":
			MeshKit.cyl(0.02, 0.016, 0.6, wood, Vector3(0, 0.2, -0.03), hand_r, 6)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.6, 0.25)
			l.light_energy = 1.6
			l.omni_range = 9.0
			l.shadow_enabled = true
			l.position = Vector3(0, 0.55, -0.03)
			l.name = "TorchLight"
			hand_r.add_child(l)
		"basket":
			var bm := MatLib.pbr("rough_wood", {"tint": Color(0.6, 0.5, 0.32), "scale": 5.0, "world": false})
			MeshKit.cyl(0.19, 0.14, 0.2, bm, Vector3(0, 0.28, 0.0), head, 10)


## Drives the pose. `speed` is horizontal speed in m/s.
## mode: "walk" | "crouch" | "climb" | "swim" | "carry" | "work" | "sit"
func animate(delta: float, speed: float, mode := "walk", climb_speed := 0.0) -> void:
	_t += delta
	for k in _blend:
		var target := 1.0 if (mode == k) else 0.0
		_blend[k] = move_toward(_blend[k], target, delta * 5.0)
	var cr: float = _blend.crouch
	var cl: float = _blend.climb
	var sw: float = _blend.swim
	var ca: float = _blend.carry
	var wk: float = _blend.work
	var st: float = _blend.sit
	var stride := clampf(speed / 5.0, 0.0, 1.5)
	_phase += delta * (2.0 + speed * 1.55) * (1.0 if speed > 0.05 else 0.0)
	_phase += delta * absf(climb_speed) * 3.0 * cl
	var s := sin(_phase)
	var c := cos(_phase)
	var breathe := sin(_t * 1.6) * 0.012
	# hips
	hips.position.y = _hips_y - 0.3 * cr - 0.42 * st + absf(s) * 0.035 * stride + breathe * 0.5
	hips.rotation.x = -0.1 * stride - 0.45 * cr - 1.15 * sw + 0.12 * cl
	hips.rotation.y = s * 0.12 * stride
	chest.rotation.x = 0.2 * cr + 0.25 * sw + sin(_t * 9.0) * 0.25 * wk
	chest.scale = Vector3.ONE * (1.0 + breathe)
	head.rotation.x = 0.15 * cr + 0.75 * sw - 0.2 * cl
	# legs
	var amp := 0.75 * stride * (1.0 - cl) * (1.0 - sw * 0.6)
	var base := 0.75 * cr + 1.45 * st
	leg_l.rotation.x = s * amp + base + (maxf(s, 0.0)) * 0.7 * cl
	leg_r.rotation.x = -s * amp + base + (maxf(-s, 0.0)) * 0.7 * cl
	knee_l.rotation.x = -(maxf(-c, 0.0) * 1.0 * stride + 1.25 * cr + 1.4 * st + maxf(s, 0.0) * 0.9 * cl) - 0.08
	knee_r.rotation.x = -(maxf(c, 0.0) * 1.0 * stride + 1.25 * cr + 1.4 * st + maxf(-s, 0.0) * 0.9 * cl) - 0.08
	# arms
	var aamp := 0.6 * stride * (1.0 - ca) * (1.0 - cl)
	var reach := 2.4 * cl + 1.3 * ca * 0.0
	arm_l.rotation.x = -s * aamp + (reach + s * 0.5) * cl + sin(_phase) * 1.4 * sw + 1.7 * sw
	arm_r.rotation.x = s * aamp + (reach - s * 0.5) * cl - sin(_phase) * 1.4 * sw + 1.7 * sw + 0.9 * ca + (1.2 + sin(_t * 9.0) * 0.9) * wk
	arm_l.rotation.z = -0.1 - 0.15 * ca
	arm_r.rotation.z = 0.1 + 0.15 * ca
	elbow_l.rotation.x = 0.25 + 0.35 * stride + 0.5 * cr + 0.6 * cl
	elbow_r.rotation.x = 0.25 + 0.35 * stride + 0.5 * cr + 0.6 * cl + 0.9 * ca + 0.5 * wk
