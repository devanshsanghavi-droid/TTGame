shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled;
// FxKit: cheap LIT soft dot / streak (snow, rain, ash, sand grains, dust motes,
// water droplets). Receives shadows, so motes only shine inside light shafts.

uniform float ambient = 1.0;
uniform float backlight = 0.5;
uniform float hardness = 1.4;
uniform float near_fade = 0.5;
uniform float boost = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = pow(clamp(1.0 - length(p), 0.0, 1.0), hardness);
	ALBEDO = COLOR.rgb * boost;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(backlight);
	AO = ambient;
	AO_LIGHT_AFFECT = 0.0;
	ALPHA = a * COLOR.a * smoothstep(near_fade * 0.3, near_fade, -VERTEX.z);
}
