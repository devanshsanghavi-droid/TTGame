shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Trunks, branches and stems for FoliageKit plants: object-space triplanar bark
// (or cylindrical UV mapping for patterned bark), the same whole-plant wind
// sway as foliage.gdshader, burn darkening and snow.
// MultiMesh INSTANCE_CUSTOM: .r = burn 0..1, .g = snow cover 0..1

global uniform vec4 foliage_wind;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_uv = false;
uniform vec2 uv_scale = vec2(8.0, 0.5);
uniform float tex_scale = 0.4;
uniform vec3 tint : source_color = vec3(1.0);
uniform float rough_mul = 1.0;
uniform float normal_strength = 1.0;
uniform float sway_height = 10.0;
uniform float sway_amount = 0.35;
uniform vec3 moss_tint : source_color = vec3(0.16, 0.20, 0.08);
uniform float moss = 0.0;
uniform vec3 snow_color : source_color = vec3(0.86, 0.89, 0.94);

varying vec3 v_pos;		// object position in metres (instance scale applied)
varying vec3 v_nrm;		// object-space normal
varying vec3 v_r0;		// object -> view rotation, rows
varying vec3 v_r1;
varying vec3 v_r2;
varying vec3 v_inst;	// burn, snow, world up-ness
varying float v_base;	// height above the plant base, metres

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float iscale = length(MODEL_MATRIX[1].xyz);
	vec3 v = VERTEX;
	vec2 wdir = foliage_wind.xy;
	float sag = smoothstep(0.35, 1.0, INSTANCE_CUSTOM.r);
	float wstr = foliage_wind.z * (1.0 - sag * 0.7);
	float t = TIME * foliage_wind.w;
	float phase = origin.x * 0.11 + origin.z * 0.13;
	float h = clamp(v.y / sway_height, 0.0, 1.6);
	float s = sin(t * 1.1 + phase) * 0.55 + sin(t * 2.3 + phase * 1.7) * 0.25 + 0.35;
	vec3 off = vec3(wdir.x, 0.0, wdir.y) * (s * wstr * sway_amount * h * h * iscale);
	v_pos = VERTEX * iscale;
	v_nrm = NORMAL;
	v_base = VERTEX.y * iscale;
	mat3 m = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX);
	m[0] = normalize(m[0]);
	m[1] = normalize(m[1]);
	m[2] = normalize(m[2]);
	v_r0 = m[0];
	v_r1 = m[1];
	v_r2 = m[2];
	v_inst = vec3(INSTANCE_CUSTOM.r, INSTANCE_CUSTOM.g, normalize(mat3(MODEL_MATRIX) * NORMAL).y);
	VERTEX = v + (off * mat3(MODEL_MATRIX)) / (iscale * iscale);
}

void fragment() {
	vec3 n = normalize(v_nrm);
	vec3 alb;
	vec3 arm;
	vec3 on;	// perturbed object-space normal
	if (use_uv) {
		vec2 uv = UV * uv_scale;
		alb = texture(albedo_tex, uv).rgb;
		arm = texture(arm_tex, uv).rgb;
		vec2 tn = texture(normal_tex, uv).rg * 2.0 - 1.0;
		vec3 tang = normalize(cross(vec3(0.0, 1.0, 0.0), n) + vec3(0.0, 0.0, 0.0001));
		vec3 bit = cross(n, tang);
		on = normalize(n + (tang * tn.x + bit * tn.y) * normal_strength);
	} else {
		vec3 bw = pow(abs(n), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec3 p = v_pos * tex_scale;
		vec2 ux = vec2(p.z, -p.y);
		vec2 uy = p.xz;
		vec2 uz = vec2(p.x, -p.y);
		alb = texture(albedo_tex, ux).rgb * bw.x + texture(albedo_tex, uy).rgb * bw.y + texture(albedo_tex, uz).rgb * bw.z;
		arm = texture(arm_tex, ux).rgb * bw.x + texture(arm_tex, uy).rgb * bw.y + texture(arm_tex, uz).rgb * bw.z;
		vec2 tx = texture(normal_tex, ux).rg * 2.0 - 1.0;
		vec2 ty = texture(normal_tex, uy).rg * 2.0 - 1.0;
		vec2 tz = texture(normal_tex, uz).rg * 2.0 - 1.0;
		vec3 pb = vec3(0.0, tx.y, tx.x) * bw.x + vec3(ty.x, 0.0, -ty.y) * bw.y + vec3(tz.x, tz.y, 0.0) * bw.z;
		on = normalize(n + pb * normal_strength);
	}
	alb *= tint;
	float rough = arm.g * rough_mul;
	float n1 = texture(noise_tex, v_pos.xy * 0.21 + v_pos.z * 0.17).r;
	float n2 = texture(noise_tex, v_pos.zy * 0.9 + v_pos.x * 0.31).r;
	// large-scale variation and damp darkening toward the base
	alb *= 0.82 + n1 * 0.36;
	alb *= mix(0.72, 1.0, smoothstep(0.0, 1.6, v_base + n1 * 0.6));
	// moss on the lower trunk
	float mo = moss * smoothstep(0.45, 0.75, n1 + (1.0 - smoothstep(0.0, 5.0, v_base)) * 0.45);
	alb = mix(alb, moss_tint * (0.6 + arm.r * 0.8), mo);

	// burn: bark blackens with ember-red deep cracks while it is burning
	float burn = v_inst.x;
	float charred = smoothstep(0.05, 0.5, burn + (n2 - 0.5) * 0.2 * step(0.01, burn));
	float lum = dot(alb, vec3(0.33));
	alb = mix(alb, vec3(0.02, 0.018, 0.016) + lum * 0.10, charred);
	rough = mix(rough, 0.96, charred);
	float ember = (1.0 - smoothstep(0.25, 0.42, arm.r * 0.5 + lum)) * smoothstep(0.35, 0.6, burn) * (1.0 - smoothstep(0.8, 1.0, burn)) * smoothstep(0.62, 0.85, n2);
	EMISSION = vec3(1.0, 0.25, 0.03) * ember * 0.5;

	// snow on upward faces
	float snow = v_inst.y;
	float up = v_inst.z;
	float cover = smoothstep(1.0 - snow * 0.9, 1.12 - snow * 0.9, up * 0.5 + 0.5 + (n2 - 0.5) * 0.25) * step(0.01, snow) * (1.0 - charred);
	alb = mix(alb, snow_color, cover);
	rough = mix(rough, 0.85, cover);
	on = normalize(mix(on, n, cover * 0.8));

	NORMAL = normalize(mat3(v_r0, v_r1, v_r2) * on);
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.4 * (1.0 - charred * 0.6);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.4;
}
