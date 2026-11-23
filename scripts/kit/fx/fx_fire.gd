class_name FxFire extends Node3D
## A fire of any size: lamp flame (size < 0.3, one steady quad), torch,
## campfire (size 1) or wildfire wall (size 8-12 with a width). Flames are
## alpha-blended noise licks over a standing body, with dark smoke, embers
## and flickering OmniLight3Ds. Built by FxKit.fire().

signal extinguished

const LIGHT_COLOR := Color(1.0, 0.5, 0.2)

var size := 1.0
var width := 0.0
var intensity := 1.0
var target_intensity := 1.0
var fade_rate := 1.2
var light: OmniLight3D
var lights: Array[OmniLight3D] = []
var flickers: Array[FxFlicker] = []
var flames: GPUParticles3D
var smoke: GPUParticles3D
var embers: GPUParticles3D
var body: GeometryInstance3D

var _body_mat: ShaderMaterial
var _burning := true


func build(o: Dictionary) -> void:
	size = clampf(float(o.get("size", 1.0)), 0.03, 14.0)
	width = maxf(float(o.get("width", 0.0)), 0.0)
	var s := size
	var tiny := s < 0.3
	var wind: Vector3 = o.get("wind", FxKit.wind)
	var wf := 1.0 + width / (1.2 * s)
	var half := Vector3(maxf(width * 0.5, s * 0.2), s * 0.05, s * 0.2)
	if tiny:
		_body_mat = FxKit.smat("flame_mm", {"steady": 1.0, "y_lock": 0.0, "halo": 0.55, "flame_frac": 0.36,
			"use_instance": false, "brightness": 1.9, "soft_dist": 0.02, "near_fade": 0.15})
		var q := s / 0.36
		var mi := MeshInstance3D.new()
		mi.mesh = FxKit.quad(Vector2(q, q), _body_mat, true)
		mi.position.y = -0.12 * q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.extra_cull_margin = q
		add_child(mi)
		body = mi
	else:
		# standing body: wild tongues on y-locked quads (one draw call)
		_body_mat = FxKit.smat("flame_mm", {"steady": 0.0, "y_lock": 1.0, "scroll": 0.75 / pow(s, 0.3),
			"noise_scale": 0.9 * pow(s, 0.25), "soft_dist": clampf(s * 0.25, 0.08, 1.5), "near_fade": clampf(s, 0.4, 4.0)})
		var n_body := maxi(1, int(round(width / (0.85 * s))) + 1) if width > 0.0 else 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = FxKit.quad(Vector2(1.05 * s, 1.55 * s), _body_mat, true)
		mm.instance_count = n_body
		for i in n_body:
			var x := 0.0 if n_body == 1 else lerpf(-width * 0.5, width * 0.5, float(i) / float(n_body - 1))
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, -0.06 * s, sin(float(i) * 2.4) * s * 0.12)))
			mm.set_instance_custom_data(i, Color(1.0, fmod(float(i) * 0.37 + 0.11, 1.0), 0, 0))
		mm.custom_aabb = AABB(Vector3(-half.x - s, -0.2, -s), Vector3(half.x * 2.0 + s * 2.0, s * 2.0, s * 2.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mmi)
		body = mmi
		# rising licks
		var life := 0.8 * pow(s, 0.35)
		var up := 1.25 * sqrt(s)
		var fm := FxKit.smat("flame", {"noise_scale": 0.8 * pow(s, 0.2), "scroll": 0.9 / pow(s, 0.3),
			"soft_dist": clampf(s * 0.3, 0.1, 2.0), "near_fade": clampf(s, 0.4, 4.0)})
		flames = FxKit.particles(self, {
			"amount": FxKit.count(minf(15.0 * wf, 130.0)), "lifetime": life,
			"pm": FxKit.ppm({
				"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": half,
				"direction": Vector3.UP, "spread": 7.0,
				"initial_velocity_min": up * 0.6, "initial_velocity_max": up * 1.25,
				"gravity": Vector3(wind.x * 0.3, up * 1.1, wind.z * 0.3),
				"angle_min": -14.0, "angle_max": 14.0,
				"scale_min": 0.55, "scale_max": 1.1, "scale_curve": FxKit.curve([0.0, 0.5, 0.25, 1.0, 1.0, 0.4]),
				"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.3,
				"color_ramp": FxKit.ramp([[0.0, Color(1, 1, 1, 0)], [0.12, Color(1, 1, 1, 1)], [0.65, Color(1, 0.85, 0.7, 0.85)], [1.0, Color(0.9, 0.6, 0.45, 0)]]),
			}),
			"mesh": FxKit.quad(Vector2(0.95 * s, 1.45 * s), fm), "order": GPUParticles3D.DRAW_ORDER_LIFETIME,
			"pos": Vector3(0, 0.55 * s, 0), "sort": 0.25 * s,
			"aabb": AABB(Vector3(-half.x - s * 1.5, -s, -s * 1.5), Vector3(half.x * 2.0 + s * 3.0, s * 5.0, s * 3.0)),
		})
	if o.get("smoke", not tiny):
		var rise := 1.5 * pow(s, 0.45)
		smoke = FxKit.smoke_system(self, {
			"size": 0.5 * s, "rise": rise, "lifetime": 3.6 * pow(s, 0.4),
			"color": Color(0.05, 0.045, 0.04), "opacity": 0.5, "wind": wind,
			"extents": Vector3(half.x * 0.85, 0.05, s * 0.2), "y": 0.95 * s,
			"amount": minf(22.0 * wf, 64.0), "glow": Color(0.3, 0.08, 0.012), "fade": 0.28,
		})
		smoke.sorting_offset = -0.5 * s
	if o.get("embers", not tiny):
		var em := FxKit.smat("spark", {"brightness": 3.2})
		var es := clampf(0.042 * pow(s, 0.4), 0.025, 0.11)
		var eup := 1.7 * sqrt(s)
		embers = FxKit.particles(self, {
			"amount": FxKit.count(minf(16.0 * wf, 140.0)), "lifetime": 2.3 * pow(s, 0.3), "randomness": 0.4,
			"pm": FxKit.ppm({
				"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": half,
				"direction": Vector3.UP, "spread": 24.0,
				"initial_velocity_min": eup * 0.5, "initial_velocity_max": eup * 1.6,
				"gravity": Vector3(wind.x * 0.35, 0.5, wind.z * 0.35), "damping_min": 0.2, "damping_max": 0.6,
				"scale_min": 0.5, "scale_max": 1.5, "scale_curve": FxKit.curve([0.0, 1.0, 0.7, 0.8, 1.0, 0.0]),
				"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.5,
				"color_ramp": FxKit.ramp([[0.0, Color(1.0, 0.62, 0.25, 1)], [0.4, Color(1.0, 0.34, 0.07, 1)], [0.85, Color(0.5, 0.07, 0.01, 0.9)], [1.0, Color(0.2, 0.02, 0.0, 0)]]),
				"turbulence_enabled": true, "turbulence_noise_strength": 1.6, "turbulence_noise_scale": 2.2,
				"turbulence_influence_min": 0.08, "turbulence_influence_max": 0.3,
			}),
			"mesh": FxKit.quad(Vector2(es, es), em), "pos": Vector3(0, 0.6 * s, 0), "sort": 0.5 * s,
			"aabb": AABB(Vector3(-half.x - s * 4.0 - 3.0, -s, -s * 4.0 - 3.0), Vector3(half.x * 2.0 + s * 8.0 + 6.0, s * 9.0 + 3.0, s * 8.0 + 6.0)),
		})
	if o.get("light", true):
		var n_l := clampi(int(width / (2.5 * s)) + 1, 1, 3)
		var energy: float = o.get("energy", (0.45 + s * 3.5) if tiny else 2.6 * pow(s, 0.7))
		var rng: float = o.get("range", (2.4 + s * 9.0) if tiny else 7.5 * pow(s, 0.65))
		for i in n_l:
			var l := OmniLight3D.new()
			l.light_color = LIGHT_COLOR
			l.light_energy = energy
			l.omni_range = rng
			l.omni_attenuation = 1.3
			l.light_specular = 0.35
			l.light_volumetric_fog_energy = 1.2
			l.shadow_enabled = o.get("shadow", false) and i == 0
			l.shadow_bias = 0.06
			l.light_size = 0.05 * s
			var x := 0.0 if n_l == 1 else lerpf(-width * 0.35, width * 0.35, float(i) / float(n_l - 1))
			l.position = Vector3(x, (0.7 * s) if tiny else (0.6 * s + 0.15), 0.0)
			add_child(l)
			lights.append(l)
			flickers.append(FxKit.flicker(l, {
				"amount": 0.07 if tiny else 0.32, "speed": 5.0 if tiny else 9.0 / pow(s, 0.3),
				"move": 0.0 if tiny else 0.035 * s, "energy": energy}))
		light = lights[0]
	if o.get("scorch", false):
		MatLib.decal(self, Vector3.ZERO, Vector3(maxf(width, 0.0) + s * 2.6, 1.5, s * 2.6), "soot", 0.0, 0.85)
	set_intensity(float(o.get("intensity", 1.0)), true)


## 0..1. Scales flame mass, smoke, embers and light together.
func set_intensity(v: float, instant := false) -> void:
	target_intensity = clampf(v, 0.0, 1.0)
	if instant:
		intensity = target_intensity
		_apply()
	else:
		set_process(true)


## Dies down over `fade` seconds; lingering smoke thins out by itself. Relight with ignite().
func extinguish(fade := 1.2) -> void:
	fade_rate = 1.0 / maxf(fade, 0.05)
	set_intensity(0.0)


func ignite(v := 1.0, fade := 1.0) -> void:
	fade_rate = 1.0 / maxf(fade, 0.05)
	set_intensity(v)


func is_burning() -> bool:
	return target_intensity > 0.01


## Starts smoke and embers as if the fire had already burned for `seconds`.
func prewarm(seconds := 5.0) -> void:
	for p: GPUParticles3D in [flames, smoke, embers]:
		if p and p.emitting:
			p.preprocess = minf(seconds, p.lifetime * 1.5)
			p.restart()


func _process(delta: float) -> void:
	intensity = move_toward(intensity, target_intensity, delta * fade_rate)
	_apply()
	if is_equal_approx(intensity, target_intensity):
		set_process(false)


func _apply() -> void:
	var v := intensity
	var on := v > 0.02
	_body_mat.set_shader_parameter("intensity", v)
	body.visible = v > 0.004
	if flames:
		flames.amount_ratio = clampf(v, 0.05, 1.0)
		flames.emitting = on
	if smoke:
		# a dying fire smokes more than it burns
		smoke.amount_ratio = clampf(0.25 + v * 0.75, 0.05, 1.0)
		smoke.emitting = on
	if embers:
		embers.amount_ratio = clampf(v * v, 0.03, 1.0)
		embers.emitting = on
	for f in flickers:
		f.level = v
	for l in lights:
		l.visible = v > 0.004
	if _burning and not on:
		_burning = false
		extinguished.emit()
	elif on:
		_burning = true
