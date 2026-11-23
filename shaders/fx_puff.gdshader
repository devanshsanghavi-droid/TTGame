shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap, specular_disabled;
// FxKit: soft, noise-eroded, LIT billboard for smoke, dust, mist, spray, sand
// and snow sheets. Drawn by GPUParticles3D with transform_align = Z_BILLBOARD.
// INSTANCE_CUSTOM: y = age 0..1, z = random seed. COLOR = particle colour ramp.
// A fake sphere normal gives each puff a lit side and a shadowed side.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform float noise_scale = 0.7;
uniform vec2 stretch = vec2(1.0, 1.0);
uniform vec2 scroll = vec2(0.0, 0.0);
uniform float erosion = 0.6;        // how far the puff breaks into wisps as it ages
uniform float density = 1.0;
uniform float soft_dist = 0.6;      // depth fade against scene geometry (m)
uniform float near_fade = 1.2;      // fade out this close to the camera (m)
uniform float backlight = 0.3;
uniform float ambient = 1.0;
uniform float bump = 0.9;
uniform float warp = 0.6;
uniform vec3 glow : source_color = vec3(0.0, 0.0, 0.0);   // under-light from a fire, fades with age
uniform float glow_fade = 0.35;

varying float v_age;
varying float v_seed;

void vertex() {
	v_age = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.z;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 nuv = p * 0.5 * noise_scale * stretch + vec2(v_seed * 17.31, v_seed * 9.73) + scroll * TIME;
	float n1 = texture(noise_tex, nuv).r;
	float n2 = texture(noise_tex, nuv * 2.7 + vec2(0.37, 0.11) + scroll * TIME * 0.6).r;
	float n = n1 * 0.62 + n2 * 0.38;
	// warp the silhouette with the noise so puffs never read as discs
	vec2 pw = p + (vec2(n1, n2) - 0.5) * warp;
	float body = 1.0 - smoothstep(0.0, 1.0, length(pw));
	body *= 1.0 - smoothstep(0.7, 1.0, r);
	float val = body * (0.3 + n * 1.3);
	float lo = 0.07 + erosion * v_age * 0.5;
	float a = smoothstep(lo, lo + 0.6, val);
	// lit volume: sphere normal roughened by the noise
	vec3 nm = vec3(p.x + (n1 - 0.5) * bump, -p.y + (n2 - 0.5) * bump, sqrt(max(1.0 - r * r, 0.04)));
	NORMAL_MAP = normalize(nm) * 0.5 + 0.5;
	ALBEDO = COLOR.rgb * (0.72 + 0.56 * n2);
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(backlight);
	AO = ambient;
	AO_LIGHT_AFFECT = 0.0;
	float g = max(1.0 - v_age / max(glow_fade, 0.001), 0.0);
	EMISSION = glow * g * g * (0.4 + n);
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = up.z / up.w;
	float fade = clamp((VERTEX.z - scene_z) / soft_dist, 0.0, 1.0);
	fade *= smoothstep(near_fade * 0.3, near_fade, -VERTEX.z);
	ALPHA = a * COLOR.a * density * fade;
}
