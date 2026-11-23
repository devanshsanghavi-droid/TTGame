shader_type canvas_item;
// Menu backdrop: slow dark fog with a faint off-centre tear, like the portal seen from far away.

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + 7.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * vec2(1.78, 1.0);
	float t = TIME * 0.02;
	float f = fbm(uv * 2.2 + vec2(t, -t * 0.6) + fbm(uv * 1.3 - t) * 0.8);
	vec2 c = uv - vec2(1.28, 0.42);
	float r = length(c);
	float tear = smoothstep(0.34, 0.0, r);
	float swirl = fbm(vec2(atan(c.y, c.x) * 1.5 - TIME * 0.05, r * 6.0 + TIME * 0.03));
	vec3 col = mix(vec3(0.016, 0.017, 0.02), vec3(0.085, 0.082, 0.078), f * f);
	col += vec3(0.22, 0.23, 0.22) * tear * tear * (0.35 + 0.65 * swirl);
	col *= 1.0 - smoothstep(0.0, 0.1, tear * tear * (1.0 - swirl)) * 0.0;
	col *= 1.0 - 0.55 * length(UV - 0.5);
	COLOR = vec4(col, 1.0);
}
