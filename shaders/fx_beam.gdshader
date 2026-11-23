shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// FxKit: soft shaft of sunlight (mirror puzzle beam). A cylinder that is
// brightest through its middle and vanishes at its silhouette, with slow dust
// drifting through it. Reads as lit haze, not a laser.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform vec3 color : source_color = vec3(1.0, 0.8, 0.54);
uniform float energy = 1.3;
uniform float opacity = 0.22;
uniform float strength = 1.0;
uniform float soft_dist = 0.5;
uniform float near_fade = 0.8;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 2.2);
	vec2 nuv = vec2(v_wpos.x + v_wpos.z, v_wpos.y) * 0.22 + vec2(TIME * 0.02, -TIME * 0.03);
	float n = texture(noise_tex, nuv).r;
	float n2 = texture(noise_tex, nuv * 3.1 + vec2(TIME * 0.05, 0.0)).r;
	float dust = 0.55 + 0.6 * n * n2 * 2.0;
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float fade = clamp((VERTEX.z - up.z / up.w) / soft_dist, 0.0, 1.0);
	fade *= smoothstep(near_fade * 0.3, near_fade, -VERTEX.z);
	float ends = smoothstep(0.0, 0.04, UV.y) * smoothstep(1.0, 0.96, UV.y);
	ALBEDO = color * energy;
	ALPHA = clamp(core * dust * opacity * strength * fade * mix(0.6, 1.0, ends), 0.0, 1.0);
}
