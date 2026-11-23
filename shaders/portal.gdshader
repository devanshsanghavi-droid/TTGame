shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// CHRONO portal: a wound in the image. Bends and smears what is behind it,
// splits colour channels, drains saturation at the core. No glow, no neon.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float open_amount = 1.0;

void vertex() {
	// billboard, keeping the node's scale
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mv = mv * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = mv;
	MODELVIEW_NORMAL_MATRIX = mat3(mv);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float edge = smoothstep(1.0, 0.6, r);
	// time runs backwards, in stutters
	float tt = -TIME * 0.55 + floor(TIME * 2.7) * 0.09;
	float swirl = (1.0 - r) * (1.0 - r) * 3.2;
	float ripple = sin(r * 17.0 + tt * 6.0 + a * 3.0) * 0.5 + 0.5;
	vec2 dir = vec2(cos(a + swirl + tt), sin(a + swirl + tt));
	vec2 off = dir * edge * (0.035 + 0.055 * ripple) * open_amount;
	vec3 col = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float k = float(i) / 5.0;
		vec2 o = off * (0.6 + k * 1.6);
		col.r += texture(screen_tex, SCREEN_UV + o * 1.3).r;
		col.g += texture(screen_tex, SCREEN_UV + o).g;
		col.b += texture(screen_tex, SCREEN_UV + o * 0.7).b;
	}
	col /= 6.0;
	float core = smoothstep(0.6, 0.05, r) * open_amount;
	float luma = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(luma) * 0.22, core);
	float rim = smoothstep(0.36, 0.5, r) * smoothstep(0.78, 0.5, r);
	col += vec3(0.8, 0.86, 0.84) * rim * (0.12 + 0.28 * ripple) * open_amount * (0.3 + luma);
	float crack = smoothstep(0.965, 1.0, sin(a * 7.0 + sin(r * 9.0 - tt * 2.0) * 2.2)) * edge;
	col += vec3(0.85) * crack * 0.3 * open_amount;
	ALBEDO = col;
	ALPHA = edge;
}
