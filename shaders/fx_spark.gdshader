shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// FxKit: glowing ember / spark. Small, hot, flickering; cools through the
// particle colour ramp. Alpha blended so fog treats it correctly.

uniform float brightness = 3.0;
uniform float near_fade = 0.4;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);

varying float v_seed;

void vertex() {
	v_seed = INSTANCE_CUSTOM.z;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = clamp(1.0 - length(p), 0.0, 1.0);
	float flick = 0.72 + 0.28 * sin(TIME * (17.0 + v_seed * 13.0) + v_seed * 60.0);
	ALBEDO = COLOR.rgb * tint * brightness * flick * (0.45 + r * r);
	ALPHA = smoothstep(0.0, 0.55, r) * COLOR.a * smoothstep(near_fade * 0.3, near_fade, -VERTEX.z);
}
