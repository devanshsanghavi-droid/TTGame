shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
// FxKit: self-billboarding flame for MultiMesh batches (oil lamps, FireField
// cells, the standing body of a campfire). The quad is anchored at its base.
// INSTANCE_CUSTOM: x = intensity 0..1, y = seed.
//   steady = 1: a calm teardrop lamp flame with a faint warm halo
//   steady = 0: wild tongues, height follows intensity

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform float steady = 0.0;
uniform float y_lock = 1.0;
uniform float brightness = 1.7;
uniform float scroll = 0.8;
uniform float noise_scale = 1.0;
uniform float intensity = 1.0;
uniform bool use_instance = true;
uniform float halo = 0.0;
uniform float tongues = 1.0;
uniform float height_gain = 1.0;   // > 1 lets flames use more of the quad (less wasted fill)
uniform float flame_frac = 1.0;     // steady mode: fraction of the quad the flame fills
uniform float soft_dist = 0.3;
uniform float near_fade = 0.5;

varying float v_int;
varying float v_seed;

vec3 fire_ramp(float h) {
	vec3 c = mix(vec3(0.09, 0.005, 0.0), vec3(0.72, 0.1, 0.008), smoothstep(0.0, 0.4, h));
	c = mix(c, vec3(1.0, 0.34, 0.045), smoothstep(0.35, 0.8, h));
	c = mix(c, vec3(1.0, 0.6, 0.2), smoothstep(0.8, 1.3, h));
	return c;
}

void vertex() {
	vec4 cd = use_instance ? INSTANCE_CUSTOM : vec4(1.0, 0.37, 0.0, 0.0);
	v_int = clamp(cd.x * intensity, 0.0, 1.0);
	v_seed = cd.y;
	vec3 center = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 up = normalize(mix(INV_VIEW_MATRIX[1].xyz, vec3(0.0, 1.0, 0.0), y_lock));
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 right = normalize(cross(up, to_cam));
	vec3 wp = center + right * VERTEX.x * sx + up * VERTEX.y * sy;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(to_cam, 0.0)).xyz;
}

void fragment() {
	float px = UV.x * 2.0 - 1.0;
	float y = 1.0 - UV.y;
	float heat = 0.0;
	float glow = 0.0;
	if (steady > 0.5) {
		// remap so the flame sits in the lower middle of the quad
		float fx = px / flame_frac;
		float fy = (y - 0.12) / flame_frac;
		float n = texture(noise_tex, vec2(v_seed * 9.1, TIME * 0.35 + v_seed * 3.0)).r - 0.5;
		float sway = (sin(TIME * 2.1 + v_seed * 40.0) * 0.05 + n * 0.22) * fy * fy;
		float stretch_y = 1.0 + n * 0.12;
		float yy = clamp(fy / stretch_y, 0.0, 1.0);
		float w = 0.62 * pow(yy, 0.55) * pow(1.0 - yy, 0.8);
		float dd = abs(fx + sway) / max(w, 0.0001);
		float body = (1.0 - smoothstep(0.3, 1.0, dd)) * step(0.0, fy) * step(fy, stretch_y);
		// hottest low in the flame, cooling to orange at the tip, dark at the wick
		heat = body * mix(1.25, 0.55, yy) * smoothstep(0.0, 0.12, yy) * v_int;
		vec2 hc = vec2(px, (y - 0.12 - flame_frac * 0.4) * 2.0);
		glow = exp(-dot(hc, hc) * 5.5) * halo * v_int;
	} else {
		vec2 nuv = vec2(UV.x * 0.9 + v_seed * 7.0, UV.y * 0.75) * noise_scale;
		nuv.y += TIME * scroll;
		float n1 = texture(noise_tex, nuv).r;
		float n2 = texture(noise_tex, nuv * 2.3 + vec2(0.17, TIME * scroll * 0.9)).r;
		float n = n1 * 0.6 + n2 * 0.4;
		// separate tongues: a slow noise across the quad decides how high each part reaches
		float lowf = texture(noise_tex, vec2(UV.x * 0.8 * tongues + v_seed * 3.0, TIME * 0.13 + v_seed)).r;
		// nothing at the sides, so the quad itself never shows
		float prof = 1.0 - smoothstep(0.3, 0.95, abs(px + (n1 - 0.5) * 0.45 * (0.3 + y)));
		float reach = clamp(0.45 + 1.3 * lowf * lowf + 0.25 * n2, 0.05, 1.0);
		float top = mix(0.28, 0.98, v_int) * reach * pow(prof, 0.5) * height_gain;
		heat = (n * 1.75 + 0.42) * (1.0 - y / max(top, 0.001)) - 0.5;
		heat *= smoothstep(0.0, 0.07, y - 0.16 * px * px) * smoothstep(0.0, 0.2, prof) * (1.0 - smoothstep(0.86, 1.0, y));
		// the base sits in the fuel: cooler and redder than the body
		heat *= mix(0.5, 1.0, smoothstep(0.0, 0.22, y));
		heat = clamp(heat, 0.0, 1.4) * step(0.004, v_int);
	}
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float fade = clamp((VERTEX.z - up.z / up.w) / soft_dist, 0.0, 1.0);
	fade *= smoothstep(near_fade * 0.3, near_fade, -VERTEX.z);
	float fa = smoothstep(0.0, 0.28, heat);
	vec3 col = fire_ramp(heat) * brightness;
	vec3 halo_col = vec3(1.0, 0.42, 0.1) * brightness * 0.5;
	float ga = glow * 0.35;
	ALBEDO = mix(halo_col, col, fa);
	ALPHA = max(fa, ga) * fade;
}
