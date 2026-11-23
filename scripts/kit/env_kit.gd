class_name EnvKit extends RefCounted
## Lighting rig: HDRI sky, sun matched to the HDRI, SDFGI, volumetric fog,
## SSAO/SSIL/SSR, AgX tonemapping and per-era colour grading.
##
##   EnvKit.build(self, {"hdri": "kloofendal_misty_morning_puresky", "sun_energy": 2.2,
##       "fog_color": Color(...), "fog_density": 0.006, "vol_density": 0.03,
##       "grade_shadow": Color(...), "grade_high": Color(...)})
##
## Every key is optional. See DEFAULTS.

const DEFAULTS := {
	"hdri": "kloofendal_48d_partly_cloudy_puresky",
	"sky_energy": 1.0,
	"sky_yaw": 0.0,                      # rotates sky and sun together (radians)
	"sun_energy": 2.4,
	"sun_color": Color(1.0, 0.95, 0.88),
	"sun_angular": 1.4,                  # soft shadow penumbra
	"sun_min_elevation": 0.14,           # keep shadows readable when the HDRI sun is at the horizon
	"shadow_distance": 220.0,
	"ambient_energy": 1.0,
	"fog_color": Color(0.62, 0.66, 0.7),
	"fog_density": 0.004,
	"fog_sky_affect": 0.35,
	"fog_aerial": 0.6,
	"fog_height": 0.0,
	"fog_height_density": 0.0,
	"fog_sun_scatter": 0.25,
	"vol_density": 0.018,
	"vol_albedo": Color(0.9, 0.92, 0.95),
	"vol_anisotropy": 0.72,
	"vol_length": 180.0,
	"vol_sun": 1.6,                      # sun contribution to volumetric fog (god rays)
	"vol_ambient": 0.35,
	"exposure": 1.0,
	"white": 6.0,
	"contrast": 1.08,
	"saturation": 0.94,
	"brightness": 1.0,
	"grade_shadow": Color(0.0, 0.0, 0.0),   # colour that pure black maps to
	"grade_mid": Color(0.5, 0.5, 0.5),
	"grade_high": Color(1.0, 1.0, 1.0),     # colour that pure white maps to
	"glow": 0.22,
	"ssr": true,
	"sdfgi": true,
	"sdfgi_energy": 1.0,
	"sdfgi_cell": 0.4,
}


static func build(era: Node, overrides: Dictionary = {}) -> void:
	var c := DEFAULTS.duplicate()
	c.merge(overrides, true)
	var q: Dictionary = Game.quality()
	var env := Environment.new()

	# ---- sky
	var sun_dir := Vector3(-0.4, 0.75, 0.5).normalized()
	var h := MatLib.hdri(c.hdri)
	var sky := Sky.new()
	if not h.is_empty():
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = h.tex
		pm.energy_multiplier = c.sky_energy
		sky.sky_material = pm
		sun_dir = h.sun
	else:
		var ps := PhysicalSkyMaterial.new()
		ps.energy_multiplier = c.sky_energy
		sky.sky_material = ps
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if c.get("sky_realtime", false) else Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, c.sky_yaw, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = c.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# ---- tonemap + grade
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = c.exposure
	env.tonemap_white = c.white
	env.adjustment_enabled = true
	env.adjustment_contrast = c.contrast
	env.adjustment_saturation = c.saturation
	env.adjustment_brightness = c.brightness
	var grad := Gradient.new()
	grad.set_color(0, c.grade_shadow)
	grad.set_color(1, c.grade_high)
	grad.add_point(0.5, c.grade_mid)
	var lut := GradientTexture1D.new()
	lut.gradient = grad
	lut.width = 256
	env.adjustment_color_correction = lut

	# ---- fog
	env.fog_enabled = true
	env.fog_light_color = c.fog_color
	env.fog_density = c.fog_density
	env.fog_sky_affect = c.fog_sky_affect
	env.fog_aerial_perspective = c.fog_aerial
	env.fog_sun_scatter = c.fog_sun_scatter
	env.fog_height = c.fog_height
	env.fog_height_density = c.fog_height_density
	env.volumetric_fog_enabled = q.vol_fog and c.vol_density > 0.0
	env.volumetric_fog_density = c.vol_density
	env.volumetric_fog_albedo = c.vol_albedo
	env.volumetric_fog_anisotropy = c.vol_anisotropy
	env.volumetric_fog_length = c.vol_length
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = c.vol_ambient
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.92
	env.volumetric_fog_gi_inject = 0.6

	# ---- screen-space + GI
	env.ssao_enabled = q.ssao
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_enabled = q.ssil
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.9
	env.ssr_enabled = q.ssr and c.ssr
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.5
	env.sdfgi_enabled = q.sdfgi and c.sdfgi
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = c.sdfgi_cell
	env.sdfgi_energy = c.sdfgi_energy
	env.sdfgi_read_sky_light = true
	env.sdfgi_bounce_feedback = 0.45
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.glow_enabled = q.glow and c.glow > 0.0
	env.glow_intensity = c.glow
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.set_meta("want", {"vol": c.vol_density > 0.0, "ssr": c.ssr, "sdfgi": c.sdfgi, "glow": c.glow > 0.0})
	var we := WorldEnvironment.new()
	we.environment = env
	we.name = "WorldEnvironment"
	era.add_child(we)

	# ---- sun
	sun_dir = (Basis(Vector3.UP, c.sky_yaw) * sun_dir).normalized()
	if c.has("sun_dir"):
		sun_dir = (c.sun_dir as Vector3).normalized()
	var min_el: float = c.sun_min_elevation
	if sun_dir.y < min_el:
		var flat := Vector3(sun_dir.x, 0, sun_dir.z).normalized()
		sun_dir = (flat * sqrt(1.0 - min_el * min_el) + Vector3.UP * min_el).normalized()
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	era.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.RIGHT)
	sun.light_color = c.sun_color
	sun.light_energy = c.sun_energy
	sun.light_angular_distance = c.sun_angular
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = c.shadow_distance
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.6
	sun.light_volumetric_fog_energy = c.vol_sun
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC

	era.env = env
	era.world_env = we
	era.sun = sun


## Re-applies the current graphics quality preset to an environment built by build().
static func apply_quality(env: Environment) -> void:
	if env == null:
		return
	var q: Dictionary = Game.quality()
	var want: Dictionary = env.get_meta("want", {"vol": true, "ssr": true, "sdfgi": true, "glow": true})
	env.volumetric_fog_enabled = q.vol_fog and want.vol
	env.ssao_enabled = q.ssao
	env.ssil_enabled = q.ssil
	env.ssr_enabled = q.ssr and want.ssr
	env.sdfgi_enabled = q.sdfgi and want.sdfgi
	env.glow_enabled = q.glow and want.glow


## Points the sun (and its shadows) along a new direction; `dir` points TOWARD the sun.
static func set_sun_dir(sun: DirectionalLight3D, dir: Vector3) -> void:
	dir = dir.normalized()
	sun.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


## Swaps the HDRI on an existing environment (day -> night and similar).
static func set_hdri(env: Environment, name: String, energy := 1.0) -> void:
	var h := MatLib.hdri(name)
	if h.is_empty():
		return
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = h.tex
	pm.energy_multiplier = energy
	env.sky.sky_material = pm
