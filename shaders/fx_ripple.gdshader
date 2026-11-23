shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_schlick_ggx;
// FxKit: expanding ripple rings on a water surface. A short wave train behind
// a leading front; it bends the surface normal so the rings catch the sky and
// the sun like real ripples, with a little foam on the crests.

instance uniform float progress = 0.0;       // 0 = just hit, 1 = gone
uniform float waves = 26.0;
uniform vec3 foam : source_color = vec3(0.72, 0.74, 0.72);
uniform vec3 trough : source_color = vec3(0.02, 0.035, 0.04);
uniform float opacity = 0.75;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0, 1.0);
	float front = mix(0.06, 0.9, pow(progress, 0.7));
	float behind = front - r;
	float env = smoothstep(-0.03, 0.02, behind) * exp(-max(behind, 0.0) * 7.0);
	env *= 1.0 - smoothstep(0.85, 1.0, r);
	float ph = behind * waves;
	float crest = sin(ph) * 0.5 + 0.5;
	float slope = cos(ph) * env;
	float life = pow(1.0 - progress, 1.3);
	NORMAL_MAP = normalize(vec3(dir.x * slope * 0.9, -dir.y * slope * 0.9, 1.0)) * 0.5 + 0.5;
	ALBEDO = mix(trough, foam, crest * crest);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	ALPHA = env * life * opacity * (0.25 + 0.75 * crest * crest);
}
