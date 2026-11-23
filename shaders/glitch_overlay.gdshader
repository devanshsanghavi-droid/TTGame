shader_type canvas_item;
// CHRONO malfunction overlay: horizontal tearing, chromatic split, desaturation.
// Meant to feel like the image itself is failing, not like a neon filter.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float intensity = 0.0;
uniform float t = 0.0;
uniform vec3 tint = vec3(0.8, 0.9, 0.85);

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float band = floor(uv.y * 46.0);
	float gate = step(0.80, hash(band * 1.7 + floor(t * 19.0))) * intensity;
	uv.x += (hash(band * 3.1 + floor(t * 27.0)) - 0.5) * 0.11 * gate;
	// slow vertical "time smear": rows borrow from above
	float smear = step(0.93, hash(floor(uv.x * 90.0) + floor(t * 7.0))) * intensity;
	uv.y -= smear * 0.035 * hash(floor(t * 13.0) + uv.x);
	float split = 0.0045 * intensity + 0.018 * gate;
	float r = texture(screen_tex, uv + vec2(split, 0.0)).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - vec2(split, 0.0)).b;
	vec3 col = vec3(r, g, b);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma) * tint, 0.6 * intensity);
	// dropped scanlines
	col *= 1.0 - 0.35 * intensity * step(0.5, fract(uv.y * 240.0 + t * 3.0)) * step(0.6, hash(floor(t * 11.0)));
	// vignette pulse
	vec2 c = SCREEN_UV - 0.5;
	col *= 1.0 - dot(c, c) * 1.3 * intensity;
	COLOR = vec4(col, 1.0);
}
