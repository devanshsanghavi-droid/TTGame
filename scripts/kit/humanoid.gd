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
##
## Period dress (used by Outfits; every key optional, defaults keep the old look):
##   female: bool           narrower shoulders, wider hips
##   sleeves: "long"|"none" long = forearms clothed, none = upper arms bare
##   tunic: float           hem of the `top` garment below the waist (legs keep `bottom`)
##   skirt_flare: float     1 = bell, 0.4 = straight wrap (kilt, veshti)
##   skirt_border: Color    woven border band at the skirt hem
##   drape: [texture, tint] wrap over the LEFT shoulder, right shoulder bare
##   drape_style: "one_shoulder"|"sari" (adds the tail down the back)|"stole" (folded cloth on the shoulder)
##   drape_arm: bool        the drape also covers the left upper arm
##   cowl: [texture, tint]  short cape over both shoulders (hood cape, mantle, fur wrap)
##   belt: [texture, tint]  narrow waist belt        band: [texture, tint] diagonal chest band
##   necklace: Color        string of beads          collar: Color  broad bead collar
##   bangles: Color         wrist rings              armband: Color upper-arm ring
##   mail: bool             mail on arms and legs    face: bool  ears, brows, mouth
##   head (more): "bun"|"headband"|"wig"|"shaved"|"headcloth"|"tonsure"|"great_helm"|
##                "kettle_helm"|"mail_coif"|"veil"|"circlet"|"braid"|"straw_hat"|"linen_coif"
##   flowers: Color (on a bun)   head_color: Color (cloth / metal of the headwear)
##   prop / props (more): "sword" (scabbard at the hip)|"hammer"|"oar"|"scroll"|"sack"|"pot"|"head_basket"|"drum"|"hoe"
##   shield: "round"|"kite"|"hide"   shield_color: Color
##   shape: bool            rounder anatomy (shoulders, forearms, calves, fingers) and relaxed arms
##   cowl_ragged: bool      uneven lower edge on the cowl (fur)
##   lod: bool              with shape: skip the small anatomy pieces (Crowd bakes use this)
##   merge: bool            merge same-material meshes per bone (fewer draw calls)
## animate() modes (more): "talk", "drum", "sit_ground"

const TORSO_Y: Array[float] = [-0.08, 0.02, 0.22, 0.44, 0.53]

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
var _blend := {"crouch": 0.0, "climb": 0.0, "swim": 0.0, "carry": 0.0, "work": 0.0, "sit": 0.0,
	"talk": 0.0, "drum": 0.0, "sit_ground": 0.0}
var _t := 0.0
var _relax := 0.0
var _skirt_parts: Array[MeshInstance3D] = []
var _skirt_folded := false
var _relax_phase := randf() * TAU


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
		return MatLib.pbr(spec[0], {"tint": spec[1], "scale": 6.0, "world": false, "sharp": 2.0})
	return MatLib.pbr("rough_linen", {"tint": fallback, "scale": 6.0, "world": false, "sharp": 2.0})


func _build() -> void:
	var bulk: float = cfg.get("bulk", 1.0)
	var skin := skin_mat(cfg.get("skin", Color(0.62, 0.45, 0.34)))
	var top := _cloth(cfg.get("top", null), Color(0.42, 0.38, 0.32))
	var bottom := _cloth(cfg.get("bottom", null), Color(0.25, 0.22, 0.2))
	var bare: bool = cfg.get("bare_chest", false)
	var torso_mat: Material = skin if bare else top
	var skirt: float = cfg.get("skirt", 0.0)
	var up := Vector3.BACK
	var female: bool = cfg.get("female", false)
	var prof := _torso_profile()
	var sh := 0.9 if female else 1.0          # shoulder width
	var hipf := 1.07 if female else 1.0       # hip width
	var limb := 0.88 if female else 1.0       # arm thickness
	var shape: bool = cfg.get("shape", false)
	if shape:
		limb *= 1.12
		_relax = 0.085
	scale = Vector3.ONE * (float(cfg.get("height", 1.78)) / 1.78)

	hips = Node3D.new()
	hips.position.y = _hips_y
	add_child(hips)
	# torso
	MeshKit.loft([Vector3(0, -0.08, 0), Vector3(0, 0.02, 0), Vector3(0, 0.22, 0), Vector3(0, 0.44, 0), Vector3(0, 0.53, 0)],
		prof, torso_mat, hips, 12, up)
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
	var sleeves: String = cfg.get("sleeves", "")
	var upper_mat: Material = torso_mat
	var fore_mat: Material = skin
	if sleeves == "long" and not bare:
		fore_mat = top
	elif sleeves == "none":
		upper_mat = skin
	var mail_mat: Material = null
	if cfg.get("mail", false):
		mail_mat = _mail()
		upper_mat = mail_mat
		fore_mat = mail_mat
	var upper_l: Material = upper_mat
	if cfg.has("drape") and cfg.get("drape_arm", false):
		upper_l = _cloth(cfg.drape, Color(0.6, 0.55, 0.45))
	arm_l = _limb(chest, Vector3(-0.215 * bulk * sh, -0.02, 0), 0.29, [0.058 * bulk * limb, 0.046 * bulk * limb], upper_l)
	arm_r = _limb(chest, Vector3(0.215 * bulk * sh, -0.02, 0), 0.29, [0.058 * bulk * limb, 0.046 * bulk * limb], upper_mat)
	elbow_l = _limb(arm_l, Vector3(0, -0.29, 0), 0.27, [0.045 * bulk * limb, 0.036 * limb], fore_mat)
	elbow_r = _limb(arm_r, Vector3(0, -0.29, 0), 0.27, [0.045 * bulk * limb, 0.036 * limb], fore_mat)
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
	if mail_mat:
		leg_mat = mail_mat
	leg_l = _limb(hips, Vector3(-0.09 * bulk, -0.05, 0), 0.44, [0.085 * bulk, 0.066 * bulk], leg_mat)
	leg_r = _limb(hips, Vector3(0.09 * bulk, -0.05, 0), 0.44, [0.085 * bulk, 0.066 * bulk], leg_mat)
	knee_l = _limb(leg_l, Vector3(0, -0.44, 0), 0.42, [0.064 * bulk, 0.045], leg_mat)
	knee_r = _limb(leg_r, Vector3(0, -0.44, 0), 0.42, [0.064 * bulk, 0.045], leg_mat)
	var shoe := MatLib.pbr("brown_leather", {"tint": cfg.get("shoe", Color(0.3, 0.22, 0.16)), "scale": 3.0, "world": false})
	for k in [knee_l, knee_r]:
		MeshKit.ellipsoid(Vector3(0.05, 0.04, 0.11), shoe if not cfg.get("barefoot", false) else skin, Vector3(0, -0.43, -0.04), k, 1)
	if shape:
		# rounder anatomy: shoulders, forearms, hands with fingers, calves, longer feet
		var dl := Vector3(0.064, 0.074, 0.067) * bulk * limb
		MeshKit.ellipsoid(dl, upper_l, Vector3(0.02, -0.03, 0), arm_l, 1)
		MeshKit.ellipsoid(dl, upper_mat, Vector3(-0.02, -0.03, 0), arm_r, 1)
		if not cfg.get("lod", false):
			for e: Node3D in [elbow_l, elbow_r]:
				MeshKit.ellipsoid(Vector3(0.046, 0.1, 0.048) * bulk * limb, fore_mat, Vector3(0, -0.085, 0), e, 1)
			for hn: Node3D in [hand_l, hand_r]:
				MeshKit.ellipsoid(Vector3(0.034, 0.052, 0.021), skin, Vector3(0, -0.056, -0.008), hn, 1)
			for k: Node3D in [knee_l, knee_r]:
				MeshKit.ellipsoid(Vector3(0.058, 0.125, 0.062) * bulk, leg_mat, Vector3(0, -0.15, 0.02), k, 1)
				MeshKit.ellipsoid(Vector3(0.047, 0.03, 0.075), shoe if not cfg.get("barefoot", false) else skin, Vector3(0, -0.442, -0.1), k, 1)
			MeshKit.ellipsoid(Vector3(0.115, 0.045, 0.07) * bulk, torso_mat, Vector3(0, 0.035, 0.012), chest, 1)
	# skirt / kilt / tunic hem
	var flare: float = cfg.get("skirt_flare", 1.0)
	if skirt > 0.0:
		var hem := Vector2(0.2 + skirt * 0.16 * flare, 0.16 + skirt * 0.14 * flare) * bulk * hipf
		_skirt_part(MeshKit.loft([Vector3(0, 0.06, 0), Vector3(0, -0.05, 0), Vector3(0, -skirt, 0)],
			[Vector2(0.165, 0.118) * bulk * hipf, Vector2(0.19, 0.14) * bulk * hipf, hem],
			bottom, hips, 12, up))
		if cfg.has("skirt_border"):
			var bm := MatLib.pbr("acg_fabric", {"tint": cfg.skirt_border, "scale": 3.0, "world": false, "sharp": 2.0})
			_skirt_part(MeshKit.loft([Vector3(0, -skirt + 0.07, 0), Vector3(0, -skirt - 0.004, 0)],
				[hem.lerp(Vector2(0.19, 0.14) * bulk * hipf, 0.07 / maxf(skirt - 0.05, 0.08)) + Vector2(0.004, 0.004), hem + Vector2(0.005, 0.005)], bm, hips, 12, up))
	else:
		MeshKit.loft([Vector3(0, 0.05, 0), Vector3(0, -0.12, 0)], [Vector2(0.172, 0.12) * bulk * hipf, Vector2(0.18, 0.13) * bulk * hipf], bottom, hips, 12, up)
	var tunic: float = cfg.get("tunic", 0.0)
	if tunic > 0.0 and not bare:
		_skirt_part(MeshKit.loft([Vector3(0, 0.07, 0), Vector3(0, -0.05, 0), Vector3(0, -tunic, 0)],
			[Vector2(0.174, 0.126) * bulk * hipf, Vector2(0.198, 0.148) * bulk * hipf,
			Vector2(0.21 + tunic * 0.16 * flare, 0.17 + tunic * 0.14 * flare) * bulk * hipf], top, hips, 12, up))
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
	_build_dress()
	_build_prop()
	if cfg.get("merge", false):
		_merge_static()


func _skirt_part(m: MeshInstance3D) -> void:
	m.name = "Skirt%d" % _skirt_parts.size()
	_skirt_parts.append(m)


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
	if cfg.get("shape", false):
		hair = _dyed(hair_c, "thatch_roof_angled", 5.0)
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
		_:
			_build_headwear_more(kind, hair)
	if cfg.get("beard", false):
		MeshKit.ellipsoid(Vector3(0.075, 0.07, 0.05), hair, Vector3(0, -0.085, -0.06), head, 1)
	elif cfg.get("short_beard", false):
		MeshKit.ellipsoid(Vector3(0.066, 0.05, 0.042), hair, Vector3(0, -0.082, -0.06), head, 1)
	if cfg.get("face", false):
		var lip := skin_mat((cfg.get("skin", Color(0.62, 0.45, 0.34)) as Color) * Color(0.68, 0.52, 0.52))
		MeshKit.ellipsoid(Vector3(0.027, 0.0065, 0.012), lip, Vector3(0, -0.058, -0.091), head, 1)
		for sx in [-1.0, 1.0]:
			MeshKit.ellipsoid(Vector3(0.012, 0.027, 0.018), skin, Vector3(0.093 * sx, -0.002, 0.012), head, 1)
			MeshKit.ellipsoid(Vector3(0.023, 0.0055, 0.009), hair, Vector3(0.037 * sx, 0.037, -0.097), head, 1)
	if cfg.get("brow", false):
		MeshKit.ellipsoid(Vector3(0.085, 0.018, 0.03), skin, Vector3(0, 0.045, -0.09), head, 1)


func _build_prop() -> void:
	var list: Array = (cfg.get("props", []) as Array).duplicate()
	if String(cfg.get("prop", "")) != "":
		list.push_front(cfg.prop)
	for p in list:
		_one_prop(String(p))
	if cfg.has("shield"):
		_build_shield()


func _one_prop(prop: String) -> void:
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
		_:
			_one_prop_more(prop, wood)


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
	if _relax > 0.0:
		arm_l.rotation.z += _relax
		arm_r.rotation.z -= _relax
		hips.rotation.z = sin(_t * 0.37 + _relax_phase) * 0.018 * (1.0 - clampf(stride * 3.0, 0.0, 1.0))
	# ---- extra modes, layered on the base pose
	var tk: float = _blend.talk
	var dr: float = _blend.drum
	var sg: float = _blend.sit_ground
	if tk > 0.001:
		var g := sin(_t * 2.3) * 0.5 + sin(_t * 3.7 + 1.3) * 0.5
		var g2 := 0.5 + 0.5 * sin(_t * 1.7 + 2.0)
		arm_l.rotation.x += (0.3 + 0.22 * g) * tk
		elbow_l.rotation.x += (0.95 + 0.35 * sin(_t * 3.1)) * tk
		arm_r.rotation.x += 0.12 * g2 * tk
		elbow_r.rotation.x += 0.4 * g2 * tk
		head.rotation.x += sin(_t * 2.9) * 0.05 * tk
		chest.rotation.x += sin(_t * 1.1) * 0.03 * tk
	if dr > 0.001:
		var b := _t * 10.0
		arm_l.rotation.x += 0.12 * dr
		arm_r.rotation.x += 0.12 * dr
		elbow_l.rotation.x += (0.55 + maxf(sin(b), 0.0) * 0.5) * dr
		elbow_r.rotation.x += (0.55 + maxf(sin(b + PI), 0.0) * 0.5) * dr
		chest.rotation.x += (0.06 + sin(b * 0.5) * 0.03) * dr
		head.rotation.x += sin(b * 0.5) * 0.05 * dr
	if not _skirt_parts.is_empty() and _relax > 0.0 and (st > 0.001 or sg > 0.001 or stride > 0.001 or _skirt_folded):
		# skirts fold over the thighs when sitting and open front-to-back with the stride
		_skirt_folded = st > 0.001 or sg > 0.001 or stride > 0.001
		for m in _skirt_parts:
			m.rotation.x = 1.3 * st + 0.45 * sg
			m.scale = Vector3(1.0 + 0.1 * st + 0.12 * sg, 1.0 - 0.3 * st - 0.72 * sg, 1.0 - 0.15 * st + 0.2 * sg + minf(stride * 0.7, 0.5))
	if sg > 0.001:
		hips.position.y -= 0.766 * sg
		hips.rotation.x += 0.12 * sg
		chest.rotation.x += 0.3 * sg
		head.rotation.x -= 0.2 * sg
		leg_l.rotation.x += 2.3 * sg
		leg_r.rotation.x += 2.3 * sg
		knee_l.rotation.x -= 2.65 * sg
		knee_r.rotation.x -= 2.65 * sg
		arm_l.rotation.x += 0.95 * sg
		arm_r.rotation.x += 0.95 * sg
		elbow_l.rotation.x += 0.25 * sg
		elbow_r.rotation.x += 0.25 * sg


# ====================================================================== period dress
## Linear-space average colour of the cloth textures, so a wanted colour can be
## turned into the tint that produces it (the base textures are not white).
const TEX_AVG := {
	"acg_fabric": Color(0.104, 0.103, 0.104), "rough_linen": Color(0.29, 0.415, 0.621),
	"wool_boucle": Color(0.205, 0.171, 0.135), "fabric_leather_02": Color(0.224, 0.074, 0.007),
	"brown_leather": Color(0.08, 0.022, 0.002), "thatch_roof_angled": Color(0.088, 0.078, 0.065),
	"rough_wood": Color(0.149, 0.124, 0.096), "rusty_metal_02": Color(0.42, 0.29, 0.127),
	"acg_bronze": Color(0.415, 0.231, 0.134), "wood_planks": Color(0.194, 0.098, 0.037), "clay_plaster": Color(0.171, 0.101, 0.041),
}


## Cloth spec [texture, tint] whose average colour comes out as `c` (sRGB).
static func dye(c: Color, tex := "acg_fabric") -> Array:
	return [tex, tint_for(tex, c)]


static func tint_for(tex: String, c: Color) -> Color:
	var avg: Color = TEX_AVG.get(tex, Color(0.2, 0.2, 0.2))
	var lin := c.srgb_to_linear()
	var t := Color(minf(lin.r / maxf(avg.r, 0.02), 12.0), minf(lin.g / maxf(avg.g, 0.02), 12.0), minf(lin.b / maxf(avg.b, 0.02), 12.0))
	return t.linear_to_srgb()


func _dyed(c: Color, tex := "acg_fabric", scale := 3.0, cull_off := false) -> Material:
	return MatLib.pbr(tex, {"tint": tint_for(tex, c), "scale": scale, "world": false, "sharp": 2.0, "cull_off": cull_off})


func _cloth2(spec: Variant, fallback: Color) -> Material:
	if spec is Array and spec.size() >= 2:
		return MatLib.pbr(spec[0], {"tint": spec[1], "scale": 2.2, "world": false, "sharp": 2.0, "cull_off": true})
	return _dyed(fallback, "acg_fabric", 2.2, true)


## Plain metal: the neutral weave at a fine scale reads as hammered / brushed plate.
func _metal(c: Color, rough := 0.5) -> Material:
	return MatLib.pbr("acg_fabric", {"tint": tint_for("acg_fabric", c), "metallic": 0.85, "rough": rough, "scale": 14.0, "world": false, "sharp": 2.0})


## Mail: the same weave, coarse, so the links show.
func _mail() -> Material:
	return MatLib.pbr("acg_fabric", {"tint": tint_for("acg_fabric", Color(0.58, 0.6, 0.64)), "metallic": 0.7, "rough": 0.6, "scale": 5.0, "world": false, "sharp": 2.0, "normal": 1.6})


func _torso_profile() -> Array:
	var bulk: float = cfg.get("bulk", 1.0)
	if cfg.get("female", false):
		return [Vector2(0.15, 0.104) * bulk, Vector2(0.182, 0.122) * bulk, Vector2(0.138, 0.098) * bulk, Vector2(0.178, 0.117) * bulk, Vector2(0.064, 0.06)]
	return [Vector2(0.14, 0.1) * bulk, Vector2(0.17, 0.115) * bulk, Vector2(0.155, 0.105) * bulk, Vector2(0.2, 0.12) * bulk, Vector2(0.07, 0.065)]


## Torso half-extents (x sideways, y depth) at a height in hips space.
func torso_radius(y: float) -> Vector2:
	var prof := _torso_profile()
	if y <= TORSO_Y[0]:
		return prof[0]
	for i in range(1, TORSO_Y.size()):
		if y <= TORSO_Y[i]:
			return (prof[i - 1] as Vector2).lerp(prof[i], (y - TORSO_Y[i - 1]) / (TORSO_Y[i] - TORSO_Y[i - 1]))
	return prof[TORSO_Y.size() - 1]


## Closed loop of tube. Points are center + ax*cos(a) + ay*sin(a); `radii` cycles
## per point (alternating sizes read as beads). Vector2 radii: x radial, y along the ring normal.
func _ring(parent: Node3D, center: Vector3, ax: Vector3, ay: Vector3, radii: Array, mat: Material, n := 16, sides := 5) -> MeshInstance3D:
	var pts: Array = []
	var rr: Array = []
	for i in n + 1:
		var a := float(i % n) / n * TAU
		pts.append(center + ax * cos(a) + ay * sin(a))
		rr.append(radii[(i % n) % radii.size()])
	return MeshKit.loft(pts, rr, mat, parent, sides, ax.cross(ay).normalized())


## Loop lying on the torso surface (hips space). y_fn(cx, sz) gives the height at each
## angle: cx = -1 is the wearer's left, sz = -1 the front.
func _surface_ring(y_fn: Callable, offset: float, radii: Array, mat: Material, up_hint: Vector3, n := 28, sides := 5) -> MeshInstance3D:
	var pts: Array = []
	var rr: Array = []
	for i in n + 1:
		var a := float(i % n) / n * TAU
		var cx := -cos(a)
		var sz := sin(a)
		var y: float = y_fn.call(cx, sz)
		var r := torso_radius(y) + Vector2(offset, offset)
		pts.append(Vector3(cx * r.x, y, sz * r.y))
		rr.append(radii[(i % n) % radii.size()])
	return MeshKit.loft(pts, rr, mat, hips, sides, up_hint)


## Cloth shell wrapped on the torso between two height curves (hips space), with rolled edges.
## flare widens the lower edge (capes). The material should be double sided.
func _shell(y_bot: Callable, y_top: Callable, mat: Material, offset := 0.013, cape := Vector2.ZERO, roll := 0.009) -> void:
	var sides := 18
	var rows := 5 if cape == Vector2.ZERO else 8
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var top_edge: Array = []
	var bot_edge: Array = []
	for i in rows + 1:
		var v := float(i) / rows
		if cape != Vector2.ZERO:
			v = 1.0 - (1.0 - v) * (1.0 - v)      # more rows where the cape domes over the shoulders
		for j in sides + 1:
			var a := float(j % sides) / sides * TAU
			var cx := -cos(a)
			var sz := sin(a)
			var yt: float = y_top.call(cx, sz)
			var y := lerpf(y_bot.call(cx, sz), yt, v)
			var r := torso_radius(y) + Vector2(offset, offset)
			if cape != Vector2.ZERO:
				# a cape hangs from the shoulder line (y = 0.44) and domes in to the neck above it
				var k := clampf((y - 0.44) / (yt - 0.44 + 0.006), 0.0, 1.0)
				var c := cape * pow(1.0 - k, 0.6)
				c.y *= 1.0 - maxf(0.44 - y, 0.0) * 0.5      # hangs in toward the body front and back
				r = Vector2(maxf(r.x, c.x), maxf(r.y, c.y))
			var p := Vector3(cx * r.x, y, sz * r.y)
			verts.append(p)
			if i == 0:
				bot_edge.append(p)
			elif i == rows:
				top_edge.append(p)
	var ring := sides + 1
	for i in rows:
		for j in sides:
			var a := i * ring + j
			idx.append_array([a, a + 1, a + ring + 1, a, a + ring + 1, a + ring])
	MeshKit.mi(MeshKit.mesh_from(verts, idx), mat, Vector3.ZERO, hips)
	if roll > 0.0:
		MeshKit.loft(top_edge, [roll], mat, hips, 5)
		MeshKit.loft(bot_edge, [roll], mat, hips, 5)


func _build_dress() -> void:
	var bulk: float = cfg.get("bulk", 1.0)
	var hipf := 1.07 if cfg.get("female", false) else 1.0
	var sh := 0.9 if cfg.get("female", false) else 1.0
	if cfg.has("drape"):
		var dm := _cloth2(cfg.drape, Color(0.75, 0.7, 0.6))
		var style: String = cfg.get("drape_style", "one_shoulder")
		var lx := -0.118 * bulk * sh
		if style == "stole":
			var pts: Array = []
			for y: float in [0.06, 0.2, 0.34, 0.45]:
				pts.append(Vector3(lx, y, -(torso_radius(y).y * sqrt(maxf(1.0 - pow(lx / torso_radius(y).x, 2.0), 0.0)) + 0.02)))
			pts.append(Vector3(lx, 0.518, 0.0))
			for y: float in [0.45, 0.34, 0.2, 0.1]:
				pts.append(Vector3(lx, y, torso_radius(y).y * sqrt(maxf(1.0 - pow(lx / torso_radius(y).x, 2.0), 0.0)) + 0.02))
			MeshKit.loft(pts, [Vector2(0.05, 0.011)], dm, hips, 8, Vector3.BACK)
		else:
			_shell(func(_cx: float, _sz: float) -> float: return 0.03,
				func(cx: float, _sz: float) -> float: return lerpf(0.505, 0.27, smoothstep(-0.52, 0.5, cx)), dm)
			if style == "sari":
				MeshKit.loft([Vector3(lx, 0.515, -0.01), Vector3(lx, 0.5, 0.07), Vector3(lx - 0.01, 0.36, 0.137), Vector3(lx - 0.01, 0.05, 0.16), Vector3(lx, -0.3, 0.18)],
					[Vector2(0.06, 0.012), Vector2(0.075, 0.012), Vector2(0.085, 0.011), Vector2(0.09, 0.01), Vector2(0.095, 0.008)], dm, hips, 8, Vector3.BACK)
	if cfg.has("cowl"):
		var cw := _cloth2(cfg.cowl, Color(0.3, 0.26, 0.22))
		var ragged: float = 0.016 if cfg.get("cowl_ragged", false) else 0.0
		_shell(func(cx: float, sz: float) -> float: return 0.21 - 0.05 * maxf(sz, 0.0) + 0.03 * absf(cx) + sin(atan2(sz, cx) * 7.0) * ragged,
			func(_cx: float, _sz: float) -> float: return 0.558, cw, 0.02, Vector2(0.215 * sh + 0.088, 0.16) * bulk, 0.01)
	if cfg.has("collar"):
		var cm := _dyed(cfg.collar, "acg_fabric", 9.0, true)
		_shell(func(_cx: float, sz: float) -> float: return 0.452 - 0.03 * maxf(-sz, 0.0),
			func(_cx: float, _sz: float) -> float: return 0.527, cm, 0.008, Vector2.ZERO, 0.006)
	if cfg.has("necklace"):
		var nm := _dyed(cfg.necklace, "acg_fabric", 12.0)
		_surface_ring(func(_cx: float, sz: float) -> float: return 0.522 - 0.07 * pow(maxf(-sz, 0.0), 1.3) - 0.02 * maxf(sz, 0.0),
			0.024 if cfg.has("drape") and String(cfg.get("drape_style", "")) != "stole" else 0.007, [0.0105, 0.006], nm, Vector3.UP, 36, 5)
	if cfg.has("band"):
		var bm := _cloth(cfg.band, Color(0.3, 0.2, 0.12))
		_surface_ring(func(cx: float, _sz: float) -> float: return 0.3 - 0.2 * cx, 0.016, [Vector2(0.007, 0.028)], bm, Vector3(0.78, 0.62, 0.0), 28, 6)
	if cfg.has("belt"):
		var blt := _cloth(cfg.belt, Color(0.25, 0.17, 0.1))
		MeshKit.loft([Vector3(0, -0.03, 0), Vector3(0, 0.0, 0), Vector3(0, 0.035, 0)],
			[Vector2(0.198, 0.148) * bulk * hipf, Vector2(0.2, 0.15) * bulk * hipf, Vector2(0.19, 0.138) * bulk * hipf], blt, hips, 12, Vector3.BACK)
	if cfg.has("bangles"):
		var gm := _metal(cfg.bangles, 0.4) if cfg.get("bangles_metal", true) else _dyed(cfg.bangles)
		for e: Node3D in [elbow_l, elbow_r]:
			_ring(e, Vector3(0, -0.235, 0), Vector3(0.041, 0, 0), Vector3(0, 0, 0.041), [0.0085], gm, 10, 5)
	if cfg.has("armband"):
		var am := _metal(cfg.armband, 0.4)
		_ring(arm_r, Vector3(0, -0.13, 0), Vector3(0.056 * bulk, 0, 0), Vector3(0, 0, 0.056 * bulk), [Vector2(0.006, 0.014)], am, 10, 5)


func _build_headwear_more(kind: String, hair: Material) -> void:
	var hc: Color = cfg.get("head_color", Color(0.85, 0.82, 0.74))
	match kind:
		"shaved":
			pass
		"bun":
			MeshKit.ellipsoid(Vector3(0.102, 0.1, 0.112), hair, Vector3(0, 0.035, 0.015), head)
			MeshKit.ellipsoid(Vector3(0.054, 0.052, 0.048), hair, Vector3(0, 0.0, 0.122), head, 1)
			if cfg.has("flowers"):
				_ring(head, Vector3(0, 0.0, 0.13), Vector3(0.05, 0, 0), Vector3(0, 0.048, 0), [0.014, 0.009], _dyed(cfg.flowers, "acg_fabric", 9.0), 14, 5)
		"headband":
			MeshKit.ellipsoid(Vector3(0.102, 0.1, 0.112), hair, Vector3(0, 0.035, 0.015), head)
			MeshKit.ellipsoid(Vector3(0.046, 0.042, 0.04), hair, Vector3(0, -0.03, 0.118), head, 1)
			_ring(head, Vector3(0, 0.052, 0.014), Vector3(0.104, 0, 0), Vector3(0, 0, 0.115), [Vector2(0.006, 0.012)], _dyed(hc, "acg_fabric", 6.0), 18, 6)
		"wig":
			MeshKit.ellipsoid(Vector3(0.112, 0.1, 0.113), hair, Vector3(0, 0.036, 0.018), head)
			MeshKit.ellipsoid(Vector3(0.115, 0.085, 0.076), hair, Vector3(0, -0.04, 0.056), head)
		"headcloth":
			var cm := _dyed(hc, "acg_fabric", 4.0)
			MeshKit.ellipsoid(Vector3(0.107, 0.096, 0.117), cm, Vector3(0, 0.042, 0.016), head)
			MeshKit.ellipsoid(Vector3(0.075, 0.085, 0.04), cm, Vector3(0, -0.05, 0.098), head, 1)
		"tonsure":
			_ring(head, Vector3(0, 0.058, 0.006), Vector3(0.084, 0, 0), Vector3(0, 0, 0.093), [Vector2(0.013, 0.021)], hair, 16, 6)
		"great_helm":
			var mm := _metal(cfg.get("head_color", Color(0.5, 0.5, 0.53)))
			MeshKit.loft([Vector3(0, -0.15, 0.005), Vector3(0, -0.02, 0.005), Vector3(0, 0.11, 0.005), Vector3(0, 0.132, 0.005)],
				[Vector2(0.116, 0.128), Vector2(0.121, 0.133), Vector2(0.117, 0.129), Vector2(0.085, 0.095)], mm, head, 12, Vector3.BACK)
			var dark := MatLib.pbr("dark_rock", {"scale": 4.0, "world": false, "tint": Color(0.25, 0.25, 0.25)})
			MeshKit.box(Vector3(0.15, 0.011, 0.02), dark, Vector3(0, 0.022, -0.123), head)
			MeshKit.box(Vector3(0.012, 0.15, 0.012), mm, Vector3(0, -0.02, -0.131), head)
		"kettle_helm":
			var km := _metal(cfg.get("head_color", Color(0.5, 0.5, 0.53)))
			MeshKit.ellipsoid(Vector3(0.104, 0.108, 0.113), _dyed(Color(0.62, 0.56, 0.45), "acg_fabric", 5.0), Vector3(0, 0.012, 0.02), head)
			MeshKit.ellipsoid(Vector3(0.11, 0.085, 0.119), km, Vector3(0, 0.062, 0.01), head)
			MeshKit.cyl(0.165, 0.185, 0.02, km, Vector3(0, 0.05, 0.01), head, 14)
		"mail_coif":
			var mail := _mail()
			MeshKit.ellipsoid(Vector3(0.108, 0.122, 0.117), mail, Vector3(0, 0.012, 0.022), head)
			MeshKit.loft([Vector3(0, -0.07, 0.012), Vector3(0, -0.175, 0.01)], [Vector2(0.082, 0.086), Vector2(0.15, 0.105)], mail, head, 10, Vector3.BACK)
		"linen_coif":
			var lc := _dyed(hc, "acg_fabric", 5.0)
			MeshKit.ellipsoid(Vector3(0.105, 0.102, 0.114), lc, Vector3(0, 0.036, 0.016), head)
			MeshKit.ellipsoid(Vector3(0.1, 0.07, 0.07), lc, Vector3(0, -0.04, 0.045), head, 1)
		"veil":
			var vm := _dyed(hc, "acg_fabric", 4.0)
			MeshKit.ellipsoid(Vector3(0.11, 0.105, 0.118), vm, Vector3(0, 0.037, 0.02), head)
			MeshKit.ellipsoid(Vector3(0.124, 0.19, 0.07), vm, Vector3(0, -0.1, 0.066), head)
			MeshKit.ellipsoid(Vector3(0.08, 0.075, 0.068), _dyed(cfg.get("wimple_color", hc), "acg_fabric", 4.0), Vector3(0, -0.118, -0.006), head, 1)
		"circlet":
			MeshKit.ellipsoid(Vector3(0.103, 0.1, 0.113), hair, Vector3(0, 0.035, 0.015), head)
			if cfg.get("female", false):
				MeshKit.ellipsoid(Vector3(0.1, 0.18, 0.058), hair, Vector3(0, -0.11, 0.082), head)
			_ring(head, Vector3(0, 0.058, 0.014), Vector3(0.104, 0, 0), Vector3(0, 0, 0.114), [Vector2(0.005, 0.008)], _metal(cfg.get("head_color", Color(0.9, 0.7, 0.3)), 0.35), 18, 5)
		"braid":
			MeshKit.ellipsoid(Vector3(0.103, 0.1, 0.113), hair, Vector3(0, 0.035, 0.015), head)
			MeshKit.loft([Vector3(0, 0.0, 0.11), Vector3(0, -0.1, 0.125), Vector3(0, -0.2, 0.12), Vector3(0, -0.3, 0.125), Vector3(0, -0.4, 0.13), Vector3(0, -0.47, 0.13)],
				[0.036, 0.03, 0.033, 0.027, 0.028, 0.012], hair, head, 7, Vector3.BACK)
		"straw_hat":
			var sm := _dyed(Color(0.72, 0.6, 0.36), "thatch_roof_angled", 5.0)
			MeshKit.ellipsoid(Vector3(0.1, 0.09, 0.11), hair, Vector3(0, 0.03, 0.02), head, 1)
			MeshKit.cyl(0.2, 0.215, 0.014, sm, Vector3(0, 0.072, 0.01), head, 14)
			MeshKit.ellipsoid(Vector3(0.105, 0.075, 0.112), sm, Vector3(0, 0.085, 0.01), head, 1)
		_:
			MeshKit.ellipsoid(Vector3(0.102, 0.1, 0.112), hair, Vector3(0, 0.035, 0.015), head)


func _one_prop_more(prop: String, wood: Material) -> void:
	var bulk: float = cfg.get("bulk", 1.0)
	match prop:
		"sword":
			var n := Node3D.new()
			n.name = "Sword"
			n.position = Vector3(-0.2 * bulk, -0.02, -0.03)
			n.rotation = Vector3(-0.38, 0.0, -0.13)
			hips.add_child(n)
			var leather := MatLib.pbr("brown_leather", {"tint": Color(0.9, 0.8, 0.7), "scale": 3.0, "world": false})
			var steel := _metal(Color(0.55, 0.55, 0.58), 0.4)
			MeshKit.loft([Vector3(0, 0.0, 0), Vector3(0, -0.74, 0), Vector3(0, -0.8, 0)], [Vector2(0.01, 0.026), Vector2(0.008, 0.017), Vector2(0.004, 0.006)], leather, n, 6, Vector3.BACK)
			MeshKit.box(Vector3(0.02, 0.018, 0.17), steel, Vector3(0, 0.012, 0), n)
			MeshKit.cyl(0.013, 0.013, 0.11, leather, Vector3(0, 0.075, 0), n, 6)
			MeshKit.ellipsoid(Vector3(0.022, 0.022, 0.022), steel, Vector3(0, 0.14, 0), n, 1)
		"hammer":
			MeshKit.cyl(0.013, 0.015, 0.36, wood, Vector3(0, -0.02, -0.14), hand_r, 6).rotation.x = PI / 2
			MeshKit.cyl(0.045, 0.045, 0.13, wood, Vector3(0, -0.02, -0.3), hand_r, 8)
		"hoe":
			MeshKit.cyl(0.015, 0.018, 1.5, wood, Vector3(0, 0.4, -0.03), hand_r, 6)
			MeshKit.box(Vector3(0.11, 0.02, 0.2), _metal(Color(0.35, 0.33, 0.32), 0.7), Vector3(0, 1.14, -0.12), hand_r).rotation.x = -0.5
		"oar":
			MeshKit.cyl(0.016, 0.019, 1.9, wood, Vector3(0, 0.5, -0.03), hand_r, 6)
			MeshKit.loft([Vector3(0, 1.2, -0.03), Vector3(0, 1.35, -0.03), Vector3(0, 1.75, -0.03), Vector3(0, 1.82, -0.03)],
				[Vector2(0.02, 0.016), Vector2(0.075, 0.012), Vector2(0.085, 0.01), Vector2(0.03, 0.008)], wood, hand_r, 6, Vector3.BACK)
		"scroll":
			MeshKit.cyl(0.02, 0.02, 0.26, _dyed(Color(0.82, 0.74, 0.55), "acg_fabric", 8.0), Vector3(0, -0.01, -0.035), hand_r, 8).rotation.x = PI / 2
		"sack":
			MeshKit.ellipsoid(Vector3(0.16, 0.2, 0.125), _dyed(Color(0.5, 0.42, 0.3), "acg_fabric", 2.5), Vector3(0.02, -0.1, 0.2), chest)
		"head_basket":
			var wk := _dyed(Color(0.62, 0.5, 0.3), "thatch_roof_angled", 6.0)
			MeshKit.loft([Vector3(0, 0.1, 0), Vector3(0, 0.13, 0), Vector3(0, 0.27, 0), Vector3(0, 0.285, 0)],
				[Vector2(0.09, 0.09), Vector2(0.13, 0.13), Vector2(0.2, 0.2), Vector2(0.19, 0.19)], wk, head, 12, Vector3.BACK)
		"pot":
			var clay := _dyed(Color(0.62, 0.36, 0.25), "clay_plaster", 2.0)
			MeshKit.ellipsoid(Vector3(0.135, 0.115, 0.135), clay, Vector3(0, 0.215, 0.0), head)
			MeshKit.cyl(0.07, 0.05, 0.06, clay, Vector3(0, 0.335, 0.0), head, 10)
		"drum":
			var dn := Node3D.new()
			dn.name = "Drum"
			dn.position = Vector3(0.0, 0.0, -0.25)
			dn.rotation.z = 0.12
			hips.add_child(dn)
			MeshKit.loft([Vector3(-0.2, 0, 0), Vector3(-0.1, 0, 0), Vector3(0.1, 0, 0), Vector3(0.2, 0, 0)], [0.09, 0.12, 0.12, 0.09], wood, dn, 12)
			var skin_m := MatLib.pbr("fabric_leather_02", {"tint": Color(1.5, 1.6, 2.4), "scale": 3.0, "world": false})
			for sx in [-1.0, 1.0]:
				MeshKit.cyl(0.094, 0.094, 0.014, skin_m, Vector3(0.203 * sx, 0, 0), dn, 12).rotation.z = PI / 2


func _build_shield() -> void:
	var kind: String = cfg.shield
	var col: Color = cfg.get("shield_color", Color(0.5, 0.2, 0.15))
	var n := Node3D.new()
	n.name = "Shield"
	n.position = Vector3(-0.08, -0.14, 0.0)
	elbow_l.add_child(n)
	match kind:
		"round":
			var face := _dyed(col, "wood_planks", 2.0)
			MeshKit.cyl(0.31, 0.31, 0.028, face, Vector3.ZERO, n, 16).rotation.z = PI / 2
			MeshKit.ellipsoid(Vector3(0.035, 0.07, 0.07), MatLib.metal("acg_bronze", Color(0.9, 0.8, 0.6), 0.4, 3.0), Vector3(-0.02, 0, 0), n, 1)
		"kite":
			var face := _dyed(col, "acg_fabric", 2.0)
			MeshKit.loft([Vector3(0, 0.46, 0), Vector3(0, 0.4, 0), Vector3(0, 0.15, 0), Vector3(0, -0.3, 0), Vector3(0, -0.62, 0)],
				[Vector2(0.012, 0.1), Vector2(0.018, 0.24), Vector2(0.02, 0.25), Vector2(0.018, 0.15), Vector2(0.008, 0.015)], face, n, 10, Vector3.BACK)
			MeshKit.ellipsoid(Vector3(0.03, 0.05, 0.05), _metal(Color(0.55, 0.55, 0.58), 0.4), Vector3(-0.022, 0.12, 0), n, 1)
		_:
			var hide := MatLib.pbr("fabric_leather_02", {"tint": tint_for("fabric_leather_02", col), "scale": 1.6, "world": false, "sharp": 2.0})
			MeshKit.loft([Vector3(0, 0.52, 0), Vector3(0, 0.46, 0), Vector3(0, 0.3, 0), Vector3(0, -0.36, 0), Vector3(0, -0.42, 0)],
				[Vector2(0.01, 0.07), Vector2(0.016, 0.17), Vector2(0.018, 0.22), Vector2(0.018, 0.22), Vector2(0.01, 0.2)], hide, n, 10, Vector3.BACK)


## Merges meshes that share a bone and a material into one mesh (fewer draw calls).
func _merge_static() -> void:
	for bone: Node3D in [hips, chest, head, arm_l, arm_r, elbow_l, elbow_r, hand_l, hand_r, leg_l, leg_r, knee_l, knee_r]:
		var groups := {}
		for c in bone.get_children():
			var m := c as MeshInstance3D
			if m == null or m.mesh == null or m.material_override == null or m.get_child_count() > 0:
				continue
			if String(m.name) in ["Cloak", "Tip"] or String(m.name).begins_with("Skirt"):
				continue
			if not groups.has(m.material_override):
				groups[m.material_override] = []
			groups[m.material_override].append(m)
		for mat: Material in groups:
			var list: Array = groups[mat]
			if list.size() < 2:
				continue
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var idx := PackedInt32Array()
			for m: MeshInstance3D in list:
				var arr := m.mesh.surface_get_arrays(0)
				var xf := m.transform
				var nb := xf.basis.inverse().transposed()
				var base := verts.size()
				var av: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var an: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i in av.size():
					verts.append(xf * av[i])
					norms.append((nb * an[i]).normalized())
				if arr[Mesh.ARRAY_INDEX] == null:
					for i in av.size():
						idx.append(base + i)
				else:
					var ai: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					for i in ai.size():
						idx.append(base + ai[i])
				bone.remove_child(m)
				m.free()
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			MeshKit.mi(mesh, mat, Vector3.ZERO, bone)
