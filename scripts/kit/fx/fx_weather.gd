class_name FxWeather extends Node3D
## Weather that follows the camera. Built by FxKit.weather(parent, kind).
##
##   "snow"       soft flakes drifting down
##   "blizzard"   set piece: driven snow, streaking sheets, white-out
##   "rain"       streaks, ground splashes, dimmed grey light
##   "sandstorm"  set piece: wind-driven grains and sand sheets; visibility really drops
##   "ash"        slow grey flakes from a distant fire
##   "dust_motes" specks that shine only in direct light (interiors, forest)
##   "embers"     drifting sparks downwind of a fire
##
## set_strength(0..1) fades particles AND the Environment (fog, sun, sky) between
## calm and full storm; 0 restores the era's own look exactly.

const LOOKS := {
	"sandstorm": {
		"fog_light_color": Color(0.62, 0.47, 0.3), "fog_density": 0.1, "fog_sky_affect": 1.0,
		"fog_aerial_perspective": 0.0, "fog_sun_scatter": 0.0, "volumetric_fog_density": 0.05,
		"volumetric_fog_albedo": Color(0.74, 0.58, 0.38), "sun_color": Color(1.0, 0.63, 0.36),
		"sun_energy": 0.34, "ambient": 0.85, "sky": 0.8,
	},
	"blizzard": {
		"fog_light_color": Color(0.8, 0.82, 0.86), "fog_density": 0.095, "fog_sky_affect": 1.0,
		"fog_aerial_perspective": 0.0, "fog_sun_scatter": 0.0, "volumetric_fog_density": 0.04,
		"volumetric_fog_albedo": Color(0.9, 0.92, 0.96), "sun_color": Color(0.8, 0.86, 0.95),
		"sun_energy": 0.4, "sky": 0.9,
	},
	"rain": {
		"fog_light_color": Color(0.3, 0.33, 0.37), "fog_density": 0.02, "fog_sky_affect": 0.8,
		"volumetric_fog_density": 0.035, "sun_energy": 0.42, "ambient": 0.8, "sky": 0.6,
	},
	"snow": {
		"fog_light_color": Color(0.64, 0.67, 0.72), "fog_density": 0.013, "fog_sky_affect": 0.7, "sun_energy": 0.72,
	},
	"ash": {
		"fog_light_color": Color(0.3, 0.28, 0.27), "fog_density": 0.018, "fog_sky_affect": 0.75,
		"sun_color": Color(1.0, 0.7, 0.5), "sun_energy": 0.55, "sky": 0.6,
	},
}

var kind := ""
var strength := 1.0             ## target
var fade := 0.3                 ## strength units per second
var wind := Vector3(1.6, 0, 0.7)
var lead := 4.0                 ## metres the volume is pushed ahead of the camera
var ground_fn := Callable()     ## (x, z) -> y for rain splashes

var _cur := -1.0
var _layers: Array = []         # [particles, lo, hi, base speed (0 = fixed), pm]
var _env: Environment
var _sun: DirectionalLight3D
var _look := {}
var _splash: GPUParticles3D
var _stopping := false
var _wdir := Vector3.RIGHT


func build(p_kind: String, o: Dictionary) -> void:
	kind = p_kind
	top_level = true
	wind = o.get("wind", FxKit.wind)
	fade = o.get("fade", 0.3)
	ground_fn = o.get("ground", Callable())
	var flat := Vector3(wind.x, 0, wind.z)
	_wdir = flat.normalized() if flat.length() > 0.05 else Vector3.RIGHT
	match kind:
		"snow":
			_dots({"amount": 1400.0, "life": 5.0, "box": Vector3(10, 4.5, 10), "vel": Vector3(wind.x * 0.5, -1.1, wind.z * 0.5),
				"size": Vector2(0.05, 0.05), "color": Color(0.9, 0.92, 0.96, 0.9), "turb": 0.3, "spread": 14.0, "boost": 1.4, "near": 1.2})
		"blizzard":
			var v := _wdir * 13.0 + Vector3(0, -1.6, 0)
			_dots({"amount": 3200.0, "life": 1.3, "box": Vector3(11, 4.5, 11), "vel": v, "size": Vector2(0.035, 0.1), "near": 0.9,
				"color": Color(0.92, 0.94, 0.97, 0.7), "streak": true, "spread": 5.0, "turb": 0.25, "boost": 1.3})
			_sheets({"amount": 46.0, "life": 2.6, "box": Vector3(22, 3.5, 22), "vel": _wdir * 11.0, "scale": Vector2(5.0, 10.0),
				"color": Color(0.86, 0.88, 0.92), "opacity": 0.2, "lo": 0.15, "y": 1.0})
		"rain":
			var v := Vector3(wind.x * 1.3, -13.5, wind.z * 1.3)
			_dots({"amount": 3600.0, "life": 0.8, "box": Vector3(13, 1.0, 13), "vel": v, "size": Vector2(0.02, 0.42),
				"color": Color(0.74, 0.79, 0.84, 0.4), "streak": true, "spread": 1.5, "hardness": 0.6, "boost": 1.3, "near": 1.6})
			var sm := FxKit.smat("dot", {"hardness": 0.8, "backlight": 0.6, "near_fade": 0.3})
			_splash = FxKit.particles(self, {
				"amount": FxKit.count(260.0), "lifetime": 0.28,
				"pm": FxKit.ppm({
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": Vector3(10, 0.02, 10),
					"direction": Vector3.UP, "spread": 35.0, "initial_velocity_min": 0.5, "initial_velocity_max": 1.3,
					"gravity": Vector3(0, -6.0, 0), "scale_min": 0.6, "scale_max": 1.4,
					"scale_curve": FxKit.curve([0.0, 0.4, 1.0, 1.6]),
					"color_ramp": FxKit.ramp([[0.0, Color(0.78, 0.82, 0.86, 0.5)], [1.0, Color(0.78, 0.82, 0.86, 0.0)]]),
				}),
				"mesh": FxKit.quad(Vector2(0.07, 0.045), sm), "aabb": AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80)),
			})
			_layers.append([_splash, 0.0, 1.0, 0.0, null])
		"sandstorm":
			var v := _wdir * 15.0 + Vector3(0, 0.3, 0)
			_dots({"amount": 2600.0, "life": 1.4, "box": Vector3(15, 4, 15), "vel": v, "size": Vector2(0.024, 0.1),
				"color": Color(0.74, 0.61, 0.44, 0.7), "near": 1.0, "streak": true, "spread": 6.0, "turb": 0.3, "speed_lo": 0.3, "y": -0.5})
			_sheets({"amount": 72.0, "life": 2.8, "box": Vector3(24, 2.4, 24), "vel": _wdir * 12.0, "scale": Vector2(5.0, 11.0),
				"color": Color(0.6, 0.47, 0.31), "opacity": 0.42, "lo": 0.1, "y": 0.2, "speed_lo": 0.35})
			_sheets({"amount": 26.0, "life": 2.2, "box": Vector3(16, 0.5, 16), "vel": _wdir * 9.0, "scale": Vector2(2.5, 5.0),
				"color": Color(0.64, 0.5, 0.34), "opacity": 0.2, "lo": 0.0, "hi": 0.6, "y": -1.3, "speed_lo": 0.4, "ground": true})
		"ash":
			_dots({"amount": 800.0, "life": 7.0, "box": Vector3(9, 4.5, 9), "vel": Vector3(wind.x * 0.3, -0.55, wind.z * 0.3),
				"size": Vector2(0.07, 0.05), "color": Color(0.62, 0.61, 0.6, 0.95), "boost": 1.3, "near": 1.0, "turb": 0.5, "spread": 25.0, "spin": true})
		"dust_motes":
			var p := FxKit.particles(self, {
				"amount": FxKit.count(380.0), "lifetime": 9.0, "preprocess": 9.0,
				"pm": FxKit.motes_pm(Vector3(9, 4, 9), o.get("color", Color(1.0, 0.93, 0.8))), "mesh": FxKit.motes_mesh(),
				"aabb": AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80)),
			})
			_layers.append([p, 0.0, 1.0, 0.0, null])
		"embers":
			var em := FxKit.smat("spark", {"brightness": 3.0})
			var v := Vector3(wind.x * 1.4, 0.9, wind.z * 1.4)
			var p := FxKit.particles(self, {
				"amount": FxKit.count(280.0), "lifetime": 5.0, "randomness": 0.4,
				"pm": FxKit.ppm({
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": Vector3(14, 5, 14),
					"emission_shape_offset": -v * 2.5 + Vector3(0, 1.0, 0),
					"direction": v.normalized(), "spread": 22.0,
					"initial_velocity_min": v.length() * 0.5, "initial_velocity_max": v.length() * 1.5,
					"gravity": Vector3(0, 0.15, 0), "scale_min": 0.5, "scale_max": 1.6,
					"scale_curve": FxKit.curve([0.0, 0.0, 0.1, 1.0, 0.7, 0.8, 1.0, 0.0]),
					"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.4,
					"color_ramp": FxKit.ramp([[0.0, Color(1.0, 0.55, 0.2, 1)], [0.5, Color(1.0, 0.32, 0.07, 1)], [1.0, Color(0.4, 0.05, 0.01, 0)]]),
					"turbulence_enabled": true, "turbulence_noise_strength": 1.8, "turbulence_noise_scale": 3.0,
					"turbulence_influence_min": 0.08, "turbulence_influence_max": 0.25,
				}),
				"mesh": FxKit.quad(Vector2(0.045, 0.045), em), "aabb": AABB(Vector3(-50, -25, -50), Vector3(100, 50, 100)),
			})
			_layers.append([p, 0.0, 1.0, 0.0, null])
		_:
			push_error("FxKit.weather: unknown kind '%s'" % kind)
	# ---- environment
	_look = LOOKS.get(kind, {})
	if o.get("drive_env", true) and not _look.is_empty():
		_env = o.get("env")
		_sun = o.get("sun")
		if _env == null:
			var era: Node = Game.current_era
			if era and is_instance_valid(era) and era.get("env") != null:
				_env = era.get("env")
				_sun = era.get("sun")
		if _env and _sun:
			# airborne dust / snow is only as bright as the daylight on it
			var day := clampf(_sun.light_energy * (_sun.light_color.get_luminance() + 0.2) / 2.4, 0.62, 1.1)
			_look = _look.duplicate()
			_look["fog_light_color"] = (_look["fog_light_color"] as Color) * day
	set_strength(float(o.get("strength", 1.0)), true)
	_follow()


## 0 = clear, 1 = full storm. Fades at `fade` per second unless `instant`.
func set_strength(v: float, instant := false) -> void:
	strength = clampf(v, 0.0, 1.0)
	if instant:
		_cur = strength
		_apply()


func get_strength() -> float:
	return _cur


## Fills the air as if the weather had been running for a while (use after an instant set_strength).
func prewarm() -> void:
	_follow()
	for l in _layers:
		var p: GPUParticles3D = l[0]
		if p.emitting:
			p.preprocess = p.lifetime
			p.restart()


## Fades out, restores the environment and frees the node.
func stop() -> void:
	_stopping = true
	strength = 0.0


func _dots(c: Dictionary) -> void:
	var vel: Vector3 = c["vel"]
	var life: float = c["life"]
	var box: Vector3 = c["box"]
	var col: Color = c["color"]
	var streak: bool = c.get("streak", false)
	var m := FxKit.smat("dot", {"hardness": c.get("hardness", 1.1), "backlight": 0.6, "near_fade": c.get("near", 0.5), "boost": c.get("boost", 1.0)})
	var props := {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": box,
		"emission_shape_offset": -vel * life * 0.5 + Vector3(0, c.get("y", 1.0), 0),
		"direction": vel.normalized(), "spread": c.get("spread", 5.0),
		"initial_velocity_min": vel.length() * 0.8, "initial_velocity_max": vel.length() * 1.2,
		"gravity": Vector3.ZERO, "scale_min": 0.6, "scale_max": 1.4, "color": col,
	}
	if c.has("turb"):
		props.merge({"turbulence_enabled": true, "turbulence_noise_strength": 1.2, "turbulence_noise_scale": 2.5,
			"turbulence_influence_min": float(c["turb"]) * 0.3, "turbulence_influence_max": c["turb"]})
	if c.get("spin", false):
		props.merge({"angle_min": -180.0, "angle_max": 180.0, "angular_velocity_min": -220.0, "angular_velocity_max": 220.0})
	var pm := FxKit.ppm(props)
	var p := FxKit.particles(self, {
		"amount": FxKit.count(c["amount"]), "lifetime": life, "pm": pm, "mesh": FxKit.quad(c["size"], m),
		"align": GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY if streak else GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD,
		"aabb": AABB(Vector3(-60, -30, -60), Vector3(120, 60, 120)), "sort": 2.0,
	})
	_layers.append([p, c.get("lo", 0.0), c.get("hi", 1.0), vel.length() if c.has("speed_lo") else 0.0, pm, c.get("speed_lo", 1.0), vel, life, c.get("y", 1.0)])


func _sheets(c: Dictionary) -> void:
	var vel: Vector3 = c["vel"]
	var life: float = c["life"]
	var col: Color = c["color"]
	var op: float = c["opacity"]
	var sc: Vector2 = c["scale"]
	var ground: bool = c.get("ground", false)
	var m := FxKit.smat("puff", {
		"noise_scale": 0.55, "stretch": Vector2(0.45, 1.5), "scroll": Vector2(0.35, 0.0), "erosion": 0.35, "warp": 0.9,
		"soft_dist": 0.5 if ground else 2.0, "near_fade": 1.5 if ground else 3.5, "backlight": 0.5, "bump": 0.4})
	var pm := FxKit.ppm({
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": c["box"],
		"emission_shape_offset": -vel * life * 0.5 + Vector3(0, c.get("y", 1.0), 0),
		"direction": vel.normalized(), "spread": 4.0,
		"initial_velocity_min": vel.length() * 0.7, "initial_velocity_max": vel.length() * 1.3,
		"gravity": Vector3.ZERO, "scale_min": sc.x, "scale_max": sc.y,
		"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.3,
		"color_ramp": FxKit.ramp([[0.0, Color(col, 0.0)], [0.25, Color(col, op)], [0.75, Color(col, op)], [1.0, Color(col, 0.0)]]),
	})
	var p := FxKit.particles(self, {
		"amount": FxKit.count(c["amount"]), "lifetime": life, "pm": pm, "mesh": FxKit.quad(Vector2(2.2, 0.8) if not ground else Vector2(2.4, 0.5), m),
		"order": GPUParticles3D.DRAW_ORDER_VIEW_DEPTH, "aabb": AABB(Vector3(-70, -30, -70), Vector3(140, 60, 140)), "sort": 1.0,
	})
	_layers.append([p, c.get("lo", 0.0), c.get("hi", 1.0), vel.length() if c.has("speed_lo") else 0.0, pm, c.get("speed_lo", 1.0), vel, life, c.get("y", 1.0)])


func _apply() -> void:
	var s := _cur
	for l in _layers:
		var p: GPUParticles3D = l[0]
		var lo: float = l[1]
		var hi: float = l[2]
		var r := clampf((s - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
		p.amount_ratio = maxf(r, 0.001)
		p.emitting = r > 0.004
		if float(l[3]) > 0.0:
			# wind picks up with the storm
			var pm: ParticleProcessMaterial = l[4]
			var k := lerpf(float(l[5]), 1.0, s)
			var vel: Vector3 = l[6]
			pm.initial_velocity_min = vel.length() * k * 0.75
			pm.initial_velocity_max = vel.length() * k * 1.25
			pm.emission_shape_offset = -vel * k * float(l[7]) * 0.5 + Vector3(0, l[8], 0)
	if _env and not _look.is_empty():
		FxKit.env_layer(_env, _sun, "weather_" + kind, _look, pow(s, 0.75))


func _follow() -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var f := -cam.global_basis.z
	f.y = 0.0
	var pos := cam.global_position + (f.normalized() * lead if f.length() > 0.01 else Vector3.ZERO)
	global_position = pos
	if _splash:
		var gy := pos.y - 1.6
		if ground_fn.is_valid():
			gy = float(ground_fn.call(pos.x, pos.z))
		else:
			var era: Node = Game.current_era
			if era and is_instance_valid(era) and era.has_method("ground_y") and era.get("terrain") != null:
				gy = float(era.call("ground_y", pos.x, pos.z))
		(_splash.process_material as ParticleProcessMaterial).emission_shape_offset = Vector3(0, gy - pos.y + 0.04, 0)


func _process(delta: float) -> void:
	_follow()
	if not is_equal_approx(_cur, strength):
		_cur = move_toward(_cur, strength, delta * fade)
		_apply()
	elif _stopping:
		_stopping = false
		var longest := 0.0
		for l in _layers:
			longest = maxf(longest, (l[0] as GPUParticles3D).lifetime)
		get_tree().create_timer(longest).timeout.connect(queue_free)


func _exit_tree() -> void:
	if _env and not _look.is_empty():
		FxKit.env_layer(_env, _sun, "weather_" + kind, _look, 0.0)
