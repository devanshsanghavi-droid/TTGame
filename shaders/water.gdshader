shader_type spatial;
render_mode specular_schlick_ggx, cull_back, depth_draw_never;
// Water with depth-based absorption, refraction, shoreline foam and a
// two-octave scrolling normal. Refraction is fed through EMISSION so the
// surface still takes real specular and sky reflection.

uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D wave_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.16, 0.22, 0.2);
uniform vec3 deep : source_color = vec3(0.02, 0.05, 0.06);
uniform float clarity = 2.2;
uniform float wave_scale = 0.045;
uniform float wave_speed = 0.018;
uniform float wave_strength = 0.55;
uniform float swell = 0.05;
uniform float foam_width = 0.28;
uniform vec3 foam_color : source_color = vec3(0.75, 0.76, 0.72);
uniform float roughness = 0.06;
uniform float refraction = 0.025;
uniform float murk = 0.0;
uniform vec2 disc_center = vec2(0.0);
uniform float disc_radius = 0.0;   // > 0: only draw inside this radius (tide pools)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.21 + TIME * 0.7) * cos(wpos.z * 0.17 + TIME * 0.5);
	VERTEX.y += w * swell;
	wpos.y += w * swell;
}

void fragment() {
	if (disc_radius > 0.0 && distance(wpos.xz, disc_center) > disc_radius) {
		discard;
	}
	vec2 uv = wpos.xz * wave_scale;
	vec3 n1 = texture(wave_n, uv + TIME * wave_speed * vec2(1.0, 0.35)).rgb;
	vec3 n2 = texture(wave_n, uv * 2.3 - TIME * wave_speed * vec2(0.4, 1.1)).rgb;
	vec3 nm = normalize(n1 + n2 - 1.0 + vec3(0.0, 0.0, 1.0));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = wave_strength;

	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	float thick = max(scene_z + VERTEX.z, 0.0);

	vec2 ruv = SCREEN_UV + nm.xy * refraction * clamp(thick * 0.6, 0.0, 1.0);
	float d2 = texture(depth_tex, ruv).r;
	vec4 v2 = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, d2, 1.0);
	if (-v2.z / v2.w < -VERTEX.z) {
		ruv = SCREEN_UV;
	} else {
		thick = max(-v2.z / v2.w + VERTEX.z, 0.0);
	}
	vec3 behind = texture(screen_tex, ruv).rgb;
	float fade = clamp(1.0 - exp(-thick / max(clarity, 0.01)), 0.0, 1.0);
	fade = max(fade, murk * clamp(thick * 4.0, 0.0, 1.0));
	vec3 tint = mix(vec3(1.0), shallow * 2.2, clamp(fade * 1.6, 0.0, 1.0));
	float foam = (1.0 - smoothstep(0.0, foam_width, thick)) * (0.55 + 0.45 * n2.r);
	foam *= smoothstep(0.0, 0.05, thick);
	// energy conservation: what the surface reflects, it does not transmit
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	ALBEDO = mix(deep * fade, foam_color, foam);
	EMISSION = behind * tint * (1.0 - fade) * (1.0 - foam) * (1.0 - fres);
	ROUGHNESS = clamp(mix(roughness, 0.6, foam), 0.12, 1.0);
	// soft shoreline instead of a hard polygon edge
	ALPHA = smoothstep(0.0, 0.07, thick);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
