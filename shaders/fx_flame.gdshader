shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// FxKit: one rising lick of flame (GPUParticles3D, Z_BILLBOARD). Noise scrolls
// downward through a teardrop body; "heat" picks the colour from deep red at
// the fringe to orange and a restrained warm core. No additive blowout.
// INSTANCE_CUSTOM: y = age 0..1, z = seed.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform float noise_scale = 0.8;
uniform float scroll = 0.9;
uniform float erode = 0.75;
uniform float brightness = 1.7;
uniform float soft_dist = 0.35;
uniform float near_fade = 0.6;

varying float v_age;
varying float v_seed;

vec3 fire_ramp(float h) {
	vec3 c = mix(vec3(0.09, 0.005, 0.0), vec3(0.72, 0.1, 0.008), smoothstep(0.0, 0.4, h));
	c = mix(c, vec3(1.0, 0.34, 0.045), smoothstep(0.35, 0.8, h));
	c = mix(c, vec3(1.0, 0.6, 0.2), smoothstep(0.8, 1.3, h));
	return c;
}

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.z;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float y = 1.0 - UV.y;
	vec2 nuv = UV * noise_scale + vec2(v_seed * 13.7, v_seed * 7.3);
	nuv.y += TIME * scroll + v_age * 0.4;
	float n1 = texture(noise_tex, nuv).r;
	float n2 = texture(noise_tex, nuv * 2.1 + vec2(0.31, TIME * scroll * 0.8)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	float wob = (n1 - 0.5) * 0.5 * y;
	float w = mix(0.85, 0.1, pow(y, 0.8));
	float body = 1.0 - smoothstep(0.0, w, abs(p.x + wob));
	body *= smoothstep(0.0, 0.14, y) * (1.0 - smoothstep(0.55, 1.0, y));
	float heat = body * (0.45 + n * 1.5) - v_age * v_age * erode - 0.1;
	heat = clamp(heat, 0.0, 1.4);
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float fade = clamp((VERTEX.z - up.z / up.w) / soft_dist, 0.0, 1.0);
	fade *= smoothstep(near_fade * 0.3, near_fade, -VERTEX.z);
	ALBEDO = fire_ramp(heat) * brightness * COLOR.rgb;
	ALPHA = smoothstep(0.0, 0.3, heat) * COLOR.a * fade;
}
