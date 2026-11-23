shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
// Wind foliage for alpha-scissor leaf cards (see scripts/kit/foliage_kit.gd).
//
// Mesh contract (built by FoliageKit):
//   NORMAL   bent shading normal (card normal blended with the crown's outward direction)
//   COLOR.r  flutter weight (0 at the card root, 1 at the tip)
//   COLOR.g  per-card phase
//   COLOR.b  ambient occlusion (0 = deep inside the crown, 1 = outside)
//   COLOR.a  1 = living leaf, 0 = dead / dry frond
// MultiMesh INSTANCE_CUSTOM: .r = burn 0..1 (scorch, char, then erode away), .g = snow cover 0..1
// Globals (registered at runtime by FoliageKit, never load this shader directly):
// MultiMesh INSTANCE_CUSTOM is zero on plain MeshInstance3Ds, so the shader also works there.
//   foliage_season  rgb = tint multiplier, a = dryness 0..1
//   foliage_wind    xy = wind direction (world xz), z = strength, w = speed

global uniform vec4 foliage_season;
global uniform vec4 foliage_wind;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_normal_map = false;
uniform float normal_strength = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 dry_tint : source_color = vec3(0.50, 0.40, 0.20);
uniform float dryness = 0.0;
uniform float roughness = 0.66;
uniform float specular = 0.28;
uniform vec3 backlight : source_color = vec3(0.30, 0.36, 0.10);
uniform float alpha_cut = 0.42;
uniform float variation = 0.16;
uniform float sway_height = 10.0;
uniform float sway_amount = 0.35;
uniform float flutter = 0.05;
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;
uniform vec3 snow_color : source_color = vec3(0.86, 0.89, 0.94);
uniform float wrap = 0.45;			// diffuse wrap: leaves facing away from the sun are not black
uniform float shadow_fill = 0.16;	// sunlight that scatters through the canopy into its own shadow

varying vec4 v_inst;	// burn, snow, random a, random b
varying float v_up;		// world-space up-ness of the shading normal

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float iscale = length(MODEL_MATRIX[1].xyz);
	float rnd = hash12(origin.xz * 3.17);
	float rnd2 = hash12(origin.zx * 7.31 + 11.0);
	v_inst = vec4(INSTANCE_CUSTOM.r, INSTANCE_CUSTOM.g, rnd, rnd2);
	vec3 v = VERTEX;
	// ground cover shrinks into the ground before its chunk is culled
	if (fade_end > 0.0) {
		float d = distance(origin, CAMERA_POSITION_WORLD);
		v *= 1.0 - smoothstep(fade_start, fade_end, d + rnd * 6.0);
	}
	// burnt leaves sag
	float sag = smoothstep(0.35, 1.0, INSTANCE_CUSTOM.r);
	v.y -= sag * COLOR.r * 0.12 * sway_height * 0.15;
	// snow load bends boughs a little
	v.y -= INSTANCE_CUSTOM.g * COLOR.r * 0.02 * sway_height;
	// --- wind: whole-plant sway (must match foliage_trunk.gdshader) + leaf flutter
	vec2 wdir = foliage_wind.xy;
	float wstr = foliage_wind.z * (1.0 - sag * 0.7);
	float t = TIME * foliage_wind.w;
	float phase = origin.x * 0.11 + origin.z * 0.13;
	float h = clamp(v.y / sway_height, 0.0, 1.6);
	float s = sin(t * 1.1 + phase) * 0.55 + sin(t * 2.3 + phase * 1.7) * 0.25 + 0.35;
	vec3 off = vec3(wdir.x, 0.0, wdir.y) * (s * wstr * sway_amount * h * h * iscale);
	vec3 wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	float fl = COLOR.r * flutter * wstr * iscale;
	float fp = t * 5.0 + COLOR.g * 37.0 + phase * 3.0 + v.x * 1.3 + v.z * 1.7;
	off += wn * (sin(fp) * fl) + vec3(wdir.x, 0.35, wdir.y) * (sin(fp * 0.63 + 1.7) * fl * 0.8);
	VERTEX = v + (off * mat3(MODEL_MATRIX)) / (iscale * iscale);
	v_up = wn.y;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	// keep coverage in the distance: mips average alpha down, so scale it back up
	float lod = max(textureQueryLod(albedo_tex, UV).x, 0.0);
	float a = tex.a * (1.0 + lod * 0.35);
	float n1 = texture(noise_tex, UV * 1.3 + v_inst.zw).r;
	float n2 = texture(noise_tex, UV * 4.1 + v_inst.wz * 3.0).r;
	float burn = v_inst.x;
	float snow = v_inst.y;

	// burn: erode from the tips toward the stem
	float erode = smoothstep(0.5, 1.0, burn) * 1.45;
	float edge = (UV.y) * 0.55 + n1 * 0.55 + n2 * 0.2;
	a *= smoothstep(erode - 0.04, erode, edge + 0.0001) * step(burn, 0.999);

	vec3 alb = tex.rgb * tint;
	float live = COLOR.a;
	// per-plant variation: brightness and a drift toward yellow-brown
	alb *= 1.0 + (v_inst.z - 0.5) * variation * 1.6;
	alb = mix(alb, alb * vec3(1.22, 1.02, 0.62), v_inst.w * variation * 2.2);
	// dryness: per-vertex dead fronds, material dryness and the global season
	float lum = dot(alb, vec3(0.3, 0.55, 0.15));
	float dry = clamp(max(1.0 - live, dryness + foliage_season.a) + (n1 - 0.5) * 0.3 * step(0.01, dryness + foliage_season.a), 0.0, 1.0);
	alb = mix(alb, dry_tint * (0.35 + lum * 3.2), dry);
	alb *= foliage_season.rgb;
	// soft mottling so cards do not look printed
	alb *= 0.86 + n2 * 0.28;
	alb = mix(vec3(dot(alb, vec3(0.3, 0.55, 0.15))), alb, 0.9);
	// ambient occlusion from the crown interior
	float ao = COLOR.b;
	alb *= mix(0.68, 1.0, ao);

	// scorch (brown) then char (black)
	float scorch = smoothstep(0.0, 0.3, burn);
	float charred = smoothstep(0.15, 0.5, burn);
	alb = mix(alb, vec3(0.16, 0.10, 0.05) * (0.5 + lum * 2.0), scorch * 0.85);
	alb = mix(alb, vec3(0.007, 0.0065, 0.006) + n2 * 0.008, charred);
	float ember = (1.0 - smoothstep(erode, erode + 0.045, edge)) * step(0.52, burn) * step(burn, 0.98);
	EMISSION = vec3(1.0, 0.28, 0.04) * ember * 0.9;

	// snow settles on whatever faces the sky
	float sky = (v_up * 0.5 + 0.5) * 0.62 + n1 * 0.22 + ao * 0.16;
	vec3 geo = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	geo = geo.z < 0.0 ? -geo : geo;
	float geo_up = (mat3(INV_VIEW_MATRIX) * geo).y;
	float cover = smoothstep(0.0, 0.18, snow * 1.1 - (1.0 - sky) * 0.9 - n2 * 0.55 + 0.05) * step(0.01, snow) * (1.0 - charred);
	cover *= smoothstep(-0.35, 0.1, geo_up + (n2 - 0.5) * 0.3);
	alb = mix(alb, snow_color, cover);

	// bent shading normals: undo the engine's back-face flip so both sides shade as one volume
	vec3 nrm = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = nrm;
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength * (1.0 - cover);
	}
	ALBEDO = alb;
	ROUGHNESS = mix(mix(roughness, 0.95, charred), 0.82, cover);
	SPECULAR = specular * (1.0 - charred * 0.8);
	METALLIC = 0.0;
	AO = mix(0.6, 1.0, ao);
	AO_LIGHT_AFFECT = 0.35;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diff = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float att = ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		att = mix(shadow_fill, 1.0, att);
	}
	// transmission: sun behind the leaf, strongest when looking toward the light
	float vdl = clamp(dot(VIEW, -LIGHT), 0.0, 1.0);
	float trans = clamp(0.45 - ndl * 0.55, 0.0, 1.0) * (0.3 + 0.7 * vdl * vdl);
	DIFFUSE_LIGHT += LIGHT_COLOR * att * (vec3(diff) + backlight * (trans * 2.4)) / PI;
	vec3 h = normalize(VIEW + LIGHT);
	float nh = max(dot(NORMAL, h), 0.0);
	// a faint waxy sheen only: bent normals are near-constant across a card, so a real lobe flashes whole cards white
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (pow(nh, mix(70.0, 14.0, ROUGHNESS)) * specular * 0.045 * clamp(ndl, 0.0, 1.0));
}
