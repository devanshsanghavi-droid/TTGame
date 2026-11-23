shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Heightmap terrain: 3 PBR layers.
//   A = base (flat ground, top-down projection)
//   B = slopes / rock (full triplanar)
//   C = secondary ground, blended by vertex colour R (top-down)
// Vertex colour G = local damp, plus a global wet line that follows `wet_level`
// (tides, floods). `paint_tex` is a runtime-painted mask (burn, tracks, drift).

uniform sampler2D a_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D c_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float a_scale = 0.3;
uniform float b_scale = 0.18;
uniform float c_scale = 0.3;
uniform vec3 a_tint : source_color = vec3(1.0);
uniform vec3 b_tint : source_color = vec3(1.0);
uniform vec3 c_tint : source_color = vec3(1.0);
uniform float slope_lo = 0.70;
uniform float slope_hi = 0.86;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float macro_scale = 0.011;
uniform float macro_strength = 0.28;
uniform float wet_level = -1000.0;
uniform float wet_band = 0.45;
uniform float wet_dark = 0.5;
uniform float wet_rough = 0.18;
uniform sampler2D paint_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec3 paint_tint : source_color = vec3(0.04, 0.035, 0.03);
uniform float paint_rough = 0.95;
uniform float terrain_size = 384.0;
uniform float normal_strength = 1.0;
uniform float rough_mul = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

vec2 nxy(sampler2D t, vec2 uv) {
	return texture(t, uv).rg * 2.0 - 1.0;
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec4 vc = COLOR;
	float macro = texture(macro_noise, wpos.xz * macro_scale).r;
	float macro2 = texture(macro_noise, wpos.xz * macro_scale * 0.23 + 0.37).r;

	// --- A: base ground
	vec2 uva = wpos.xz * a_scale;
	vec3 alb_a = texture(a_alb, uva).rgb * a_tint;
	vec3 arm_a = texture(a_arm, uva).rgb;
	vec2 n_a = nxy(a_nrm, uva);
	// --- C: secondary ground
	vec2 uvc = wpos.xz * c_scale;
	vec3 alb_c = texture(c_alb, uvc).rgb * c_tint;
	vec3 arm_c = texture(c_arm, uvc).rgb;
	vec2 n_c = nxy(c_nrm, uvc);
	float lum_a = dot(alb_a, vec3(0.33));
	float lum_c = dot(alb_c, vec3(0.33));
	float cw = clamp((vc.r + (macro - 0.5) * 0.35 - 0.5) * 3.0 + 0.5 + (lum_c - lum_a) * 0.6, 0.0, 1.0);
	cw *= step(0.02, vc.r);
	vec3 alb = mix(alb_a, alb_c, cw);
	vec3 arm = mix(arm_a, arm_c, cw);
	vec2 nflat = mix(n_a, n_c, cw);
	vec3 perturb = vec3(nflat.x, 0.0, -nflat.y);

	// --- B: rock on slopes, triplanar
	float flatness = smoothstep(slope_lo, slope_hi, n.y);
	float rock = 1.0 - flatness;
	if (rock > 0.003) {
		vec3 bw = pow(abs(n), vec3(5.0));
		bw /= (bw.x + bw.y + bw.z);
		vec2 ux = vec2(wpos.z, -wpos.y) * b_scale;
		vec2 uy = wpos.xz * b_scale;
		vec2 uz = vec2(wpos.x, -wpos.y) * b_scale;
		vec3 alb_b = (texture(b_alb, ux).rgb * bw.x + texture(b_alb, uy).rgb * bw.y + texture(b_alb, uz).rgb * bw.z) * b_tint;
		vec3 arm_b = texture(b_arm, ux).rgb * bw.x + texture(b_arm, uy).rgb * bw.y + texture(b_arm, uz).rgb * bw.z;
		vec2 tx = nxy(b_nrm, ux);
		vec2 ty = nxy(b_nrm, uy);
		vec2 tz = nxy(b_nrm, uz);
		vec3 pb = vec3(0.0, tx.y, tx.x) * bw.x + vec3(ty.x, 0.0, -ty.y) * bw.y + vec3(tz.x, tz.y, 0.0) * bw.z;
		float lum_b = dot(alb_b, vec3(0.33));
		float rw = clamp((rock - 0.5) * 2.4 + 0.5 + (lum_b - dot(alb, vec3(0.33))) * 0.5, 0.0, 1.0);
		alb = mix(alb, alb_b, rw);
		arm = mix(arm, arm_b, rw);
		perturb = mix(perturb, pb, rw);
	}

	// macro variation: breaks tiling over tens of metres
	alb *= 1.0 + (macro - 0.5) * macro_strength + (macro2 - 0.5) * macro_strength * 1.2;

	float rough = arm.g * rough_mul;
	// wetness: tide line + local damp
	float wet = 1.0 - smoothstep(wet_level, wet_level + wet_band, wpos.y + (macro - 0.5) * 0.25);
	wet = max(wet, vc.g);
	alb *= mix(1.0, wet_dark, wet);
	rough = mix(rough, wet_rough, wet * 0.9);
	perturb *= mix(1.0, 0.45, wet);
	// ground that is actually under the water is not a mirror: the surface above it is
	float under = 1.0 - smoothstep(wet_level - 0.6, wet_level - 0.32, wpos.y);
	rough = mix(rough, 0.9, under);

	// runtime paint (burn / tracks / drift)
	float p = texture(paint_tex, wpos.xz / terrain_size + 0.5).r;
	if (p > 0.003) {
		float lum = dot(alb, vec3(0.33));
		alb = mix(alb, paint_tint * (0.55 + lum * 1.4), p);
		rough = mix(rough, paint_rough, p);
	}

	vec3 wn = normalize(n + perturb * normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.08, under);
}
