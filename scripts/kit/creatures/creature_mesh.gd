class_name CreatureMesh extends RefCounted
## Sculpts a creature out of lofts and ellipsoids into ONE skinned surface per
## material (usually one draw call for the whole animal).
##
## Colour lives in the vertices (hide colour, pale belly, dark back, ivory, eyes),
## the texture only supplies luminance detail + normal + AO/roughness, projected
## triplanar from the BIND pose (CUSTOM0/1) so the pattern sticks to the skin
## while bones move.
##
##   var cm := CreatureMesh.new()
##   var body := cm.bone("body", Vector3(0, 2, 0))
##   cm.shade(Color(0.3, 0.2, 0.15), Color(0.45, 0.35, 0.28), Color(0.2, 0.13, 0.1))
##   cm.loft(points, radii, [body, body, [neck0, body, 0.5], neck0])
##   cm.commit({"hide": CreatureMesh.material("thatch_roof_angled", {"scale": 1.4})})
##   var mi := cm.instantiate(parent)        # MeshInstance3D + its own Skeleton3D

const SHADER_CODE := "
shader_type spatial;
render_mode CULL, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.8;
uniform float tex_lum = 0.2;
uniform float contrast = 1.0;
uniform float sharp = 3.0;
uniform float rough_mul = 1.0;
uniform float normal_strength = 1.0;
uniform float rim = 0.0;
uniform float backlight = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
varying vec3 tp;
varying vec3 tw;
varying vec2 misc;
varying vec3 vcol;

void vertex() {
	vec3 bn = normalize(CUSTOM1.xyz + vec3(0.0, 0.0001, 0.0));
	TANGENT = normalize(vec3(0.0, 0.0, -1.0) * abs(NORMAL.x) + vec3(1.0, 0.0, 0.0) * abs(NORMAL.y) + vec3(1.0, 0.0, 0.0) * abs(NORMAL.z));
	BINORMAL = normalize(vec3(0.0, 1.0, 0.0) * abs(NORMAL.x) + vec3(0.0, 0.0, -1.0) * abs(NORMAL.y) + vec3(0.0, 1.0, 0.0) * abs(NORMAL.z));
	tw = pow(abs(bn), vec3(sharp));
	tw /= dot(tw, vec3(1.0));
	tp = CUSTOM0.xyz * tex_scale * vec3(1.0, -1.0, 1.0);
	misc = UV;
	vcol = pow(COLOR.rgb, vec3(2.2));
}

void fragment() {
	vec2 ux = tp.zy * vec2(-1.0, 1.0);
	vec3 a = texture(albedo_tex, tp.xy).rgb * tw.z + texture(albedo_tex, tp.xz).rgb * tw.y + texture(albedo_tex, ux).rgb * tw.x;
	vec3 arm = texture(arm_tex, tp.xy).rgb * tw.z + texture(arm_tex, tp.xz).rgb * tw.y + texture(arm_tex, ux).rgb * tw.x;
	vec3 nm = texture(normal_tex, tp.xy).rgb * tw.z + texture(normal_tex, tp.xz).rgb * tw.y + texture(normal_tex, ux).rgb * tw.x;
	float d = misc.x;
	float lum = dot(a, vec3(0.299, 0.587, 0.114)) / tex_lum;
	lum = clamp(mix(1.0, lum, contrast), 0.3, 1.8);
	ALBEDO = vcol * tint.rgb * mix(1.0, lum, d);
	AO = mix(1.0, arm.r, d);
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = clamp(mix(0.6, arm.g * rough_mul, d) * COLOR.a, 0.04, 1.0);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_strength * d;
	RIM = rim * d;
	RIM_TINT = 0.75;
	BACKLIGHT = vec3(backlight) * vcol;
}
"

## Linear luminance of the textures used for hides (so vertex colour is the true colour).
const TEX_LUM := {
	"thatch_roof_angled": 0.078, "dry_ground_01": 0.19, "mud_cracked_dry_03": 0.41, "pine_bark": 0.088,
	"acg_fabric": 0.104, "brown_leather": 0.03, "bark_willow_02": 0.18, "rock_06": 0.12,
	"palm_tree_bark": 0.28, "bark_brown_02": 0.09, "rough_wood": 0.16, "wool_boucle": 0.15,
}

static var _shaders := {}
static var _mats := {}


class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var b := PackedInt32Array()
	var w := PackedFloat32Array()
	var i := PackedInt32Array()

	func push(p: Vector3, nn: Vector3, col: Color, misc: Vector2, b0: int, b1: int, w1: float) -> void:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(misc)
		b.append(b0)
		b.append(b1)
		b.append(0)
		b.append(0)
		w.append(1.0 - w1)
		w.append(w1)
		w.append(0.0)
		w.append(0.0)


var bone_names := PackedStringArray()
var bone_origins := PackedVector3Array()
var mesh: ArrayMesh
var tris := 0

var _surfs := {}
var _order: Array[String] = []
var _cur: Surf
var _base := Color.WHITE
var _belly := Color.WHITE
var _back := Color.WHITE
var _gloss := 1.0
var _detail := 1.0
var _opacity := 1.0
var _mat_for := {}


func _init() -> void:
	surface("hide")


## Hide material. opts: scale (tiles per metre), contrast (0..1.5 texture strength), rough,
## normal, rim (fur fuzz), backlight (membranes), sharp, double (cull disabled)
static func material(tex_name: String, opts: Dictionary = {}) -> ShaderMaterial:
	var key := tex_name + str(opts)
	if _mats.has(key):
		return _mats[key]
	var double: bool = opts.get("double", false)
	if not _shaders.has(double):
		var sh := Shader.new()
		sh.code = SHADER_CODE.replace("CULL", "cull_disabled" if double else "cull_back")
		_shaders[double] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[double]
	var alb := MatLib.tex(tex_name, "diff")
	var lum: float = TEX_LUM.get(tex_name, 0.18)
	if alb == null:
		alb = MatLib.noise_tex(tex_name.hash() % 1000, 0.03, false, Color(0.35, 0.35, 0.35), Color(0.9, 0.9, 0.9))
		lum = 0.33
	m.set_shader_parameter("albedo_tex", alb)
	var nor := MatLib.tex(tex_name, "nor")
	m.set_shader_parameter("normal_tex", nor if nor else MatLib.noise_tex(tex_name.hash() % 1000 + 1, 0.05, true))
	var arm := MatLib.tex(tex_name, "arm")
	if arm:
		m.set_shader_parameter("arm_tex", arm)
	m.set_shader_parameter("tex_lum", lum)
	m.set_shader_parameter("tex_scale", opts.get("scale", 0.8))
	m.set_shader_parameter("contrast", opts.get("contrast", 1.0))
	m.set_shader_parameter("sharp", opts.get("sharp", 3.0))
	m.set_shader_parameter("rough_mul", opts.get("rough", 1.0))
	m.set_shader_parameter("normal_strength", opts.get("normal", 1.0))
	m.set_shader_parameter("rim", opts.get("rim", 0.0))
	m.set_shader_parameter("backlight", opts.get("backlight", 0.0))
	_mats[key] = m
	return m


# ------------------------------------------------------------------ authoring
func bone(bone_name: String, origin: Vector3) -> int:
	bone_names.append(bone_name)
	bone_origins.append(origin)
	return bone_names.size() - 1


## Switches the surface that following geometry goes into (one draw call each).
func surface(surf_name: String) -> void:
	if not _surfs.has(surf_name):
		_surfs[surf_name] = Surf.new()
		_order.append(surf_name)
	_cur = _surfs[surf_name]


## Countershaded hide colour: base on the flanks, `belly` underneath, `back` on top.
func shade(base: Color, belly: Variant = null, back: Variant = null, detail := 1.0, gloss := 1.0) -> void:
	_base = base
	_belly = belly if belly is Color else base
	_back = back if back is Color else base
	_detail = detail
	_gloss = gloss


## Flat colour (ivory, claws, eyes). detail = texture strength, gloss < 1 = shinier.
func paint(c: Color, detail := 0.3, gloss := 0.6) -> void:
	shade(c, null, null, detail, gloss)


func _col(nn: Vector3) -> Color:
	var col := _base
	if nn.y < 0.0:
		col = _base.lerp(_belly, smoothstep(0.1, 0.8, -nn.y))
	else:
		col = _base.lerp(_back, smoothstep(0.3, 0.95, nn.y))
	col.a = _gloss
	return col


## Appends mesh arrays. `bones` is an int (rigid) or, for lofts, one spec per ring:
## int or [bone_a, bone_b, weight_b].
func add_arrays(arr: Array, xf: Transform3D, bones: Variant, ring := 0) -> void:
	var s := _cur
	var base := s.v.size()
	var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var si: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	var misc := Vector2(_detail, _opacity)
	var rigid := -1
	var specs: Array = []
	var nrings := 0
	if bones is Array:
		specs = bones
		nrings = specs.size()
	else:
		rigid = int(bones)
	for k in sv.size():
		var nn := (nb * sn[k]).normalized()
		var b0 := rigid
		var b1 := 0
		var w1 := 0.0
		if rigid < 0:
			var r := k / ring
			if r >= nrings:
				r = 0 if k == nrings * ring else nrings - 1
			var spec: Variant = specs[r]
			if spec is Array:
				b0 = spec[0]
				b1 = spec[1]
				w1 = spec[2]
			else:
				b0 = int(spec)
		s.push(xf * sv[k], nn, _col(nn), misc, b0, b1, w1)
	for k in si.size():
		s.i.append(base + si[k])


## Tube through `points` (model space) with per-point radii (float or Vector2(side, up)).
func loft(points: Array, radii: Array, bones: Variant, sides := 10, up_hint := Vector3.UP) -> void:
	var m := MeshKit.loft_mesh(PackedVector3Array(points), radii, sides, up_hint)
	var spec: Variant = bones
	if not (bones is Array):
		spec = []
		for _i in points.size():
			spec.append(bones)
	add_arrays(m.surface_get_arrays(0), Transform3D.IDENTITY, spec, sides + 1)


func ellipsoid(radii: Vector3, at: Variant, bone_id: int, subdiv := 2) -> void:
	var xf: Transform3D = at if at is Transform3D else Transform3D(Basis.IDENTITY, at)
	add_arrays(MeshKit.ellipsoid_mesh(radii, subdiv).surface_get_arrays(0), xf, bone_id)


func box(size: Vector3, at: Variant, bone_id: int) -> void:
	var xf: Transform3D = at if at is Transform3D else Transform3D(Basis.IDENTITY, at)
	var bm := BoxMesh.new()
	bm.size = size
	add_arrays(bm.get_mesh_arrays(), xf, bone_id)


## Cone / horn / claw: a loft that tapers to a point along a curve.
func horn(points: Array, r0: float, bone_id: int, sides := 7, r1 := 0.012) -> void:
	var radii: Array = []
	if points.size() > 2:
		var smooth: Array = []
		var m := points.size()
		for k in m - 1:
			var p0: Vector3 = points[maxi(k - 1, 0)]
			var p1: Vector3 = points[k]
			var p2: Vector3 = points[k + 1]
			var p3: Vector3 = points[mini(k + 2, m - 1)]
			for s in 3:
				smooth.append(p1.cubic_interpolate(p2, p0, p3, s / 3.0))
		smooth.append(points[m - 1])
		points = smooth
	var n := points.size()
	for i in n:
		var t := float(i) / (n - 1)
		radii.append(lerpf(r0, r1, pow(t, 0.8)))
	loft(points, radii, bone_id, sides)


## Thin two-sided sheet (membranes, ears, cloth). `verts` in model space, `idx` triangles
## with any consistent winding, `bones` one spec per vertex (int or [a, b, w]).
func sheet(verts: PackedVector3Array, idx: PackedInt32Array, bones: Array) -> void:
	for side in 2:
		var ii := idx
		if side == 1:
			ii = PackedInt32Array()
			for k in range(0, idx.size(), 3):
				ii.append_array([idx[k], idx[k + 2], idx[k + 1]])
		var m := MeshKit.mesh_from(verts, ii)
		add_arrays(m.surface_get_arrays(0), Transform3D.IDENTITY, bones, 1)


## Hanging tuft of fur / hair: a short drooping cone from `at` along `dir`.
func tuft(at: Vector3, dir: Vector3, length: float, radius: float, bone_id: int) -> void:
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	loft([at - dir * radius * 0.5, at + dir * length * 0.45, at + dir * length],
		[Vector2(radius, radius * 0.6), Vector2(radius * 0.8, radius * 0.5), 0.01], bone_id, 5, side)


# -------------------------------------------------------------------- output
## Bakes the surfaces. mats: surface name -> Material.
func commit(mats: Dictionary) -> void:
	mesh = ArrayMesh.new()
	_mat_for = mats
	var fmt := (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	tris = 0
	for surf_name in _order:
		var s: Surf = _surfs[surf_name]
		if s.v.is_empty():
			continue
		var c0 := PackedFloat32Array()
		var c1 := PackedFloat32Array()
		c0.resize(s.v.size() * 3)
		c1.resize(s.v.size() * 3)
		for k in s.v.size():
			c0[k * 3] = s.v[k].x
			c0[k * 3 + 1] = s.v[k].y
			c0[k * 3 + 2] = s.v[k].z
			c1[k * 3] = s.n[k].x
			c1[k * 3 + 1] = s.n[k].y
			c1[k * 3 + 2] = s.n[k].z
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.v
		arrays[Mesh.ARRAY_NORMAL] = s.n
		arrays[Mesh.ARRAY_COLOR] = s.c
		arrays[Mesh.ARRAY_TEX_UV] = s.uv
		arrays[Mesh.ARRAY_CUSTOM0] = c0
		arrays[Mesh.ARRAY_CUSTOM1] = c1
		arrays[Mesh.ARRAY_INDEX] = s.i
		if bone_names.size() > 0:
			arrays[Mesh.ARRAY_BONES] = s.b
			arrays[Mesh.ARRAY_WEIGHTS] = s.w
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats.get(surf_name, mats.get("hide")))
		tris += s.i.size() / 3
	_surfs.clear()
	_cur = null


## A new instance of the baked mesh with its own skeleton (flat bone list, rest =
## translation to the bone origin, so a pose is simply the bone's model-space transform).
func instantiate(parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if bone_names.size() > 0:
		var sk := Skeleton3D.new()
		sk.name = "Skeleton"
		for k in bone_names.size():
			sk.add_bone(bone_names[k])
			sk.set_bone_rest(k, Transform3D(Basis.IDENTITY, bone_origins[k]))
			sk.set_bone_pose(k, Transform3D(Basis.IDENTITY, bone_origins[k]))
		parent.add_child(sk)
		sk.add_child(mi)
		mi.skin = sk.create_skin_from_rest_transforms()
		mi.skeleton = NodePath("..")
	else:
		parent.add_child(mi)
	return mi


# ------------------------------------------------------------------- helpers
## Catmull-Rom resample of stations [{p: Vector3, r: Vector2, ...}] -> [points, radii, params]
## where params[i] is the fractional station index of ring i.
static func resample(pts: Array, rads: Array, sub: int) -> Array:
	var n := pts.size()
	var out_p: Array = []
	var out_r: Array = []
	var out_q: Array = []
	for k in n - 1:
		var p0: Vector3 = pts[maxi(k - 1, 0)]
		var p1: Vector3 = pts[k]
		var p2: Vector3 = pts[k + 1]
		var p3: Vector3 = pts[mini(k + 2, n - 1)]
		var r0: Vector2 = rads[maxi(k - 1, 0)]
		var r1: Vector2 = rads[k]
		var r2: Vector2 = rads[k + 1]
		var r3: Vector2 = rads[mini(k + 2, n - 1)]
		for s in sub:
			var f := float(s) / sub
			out_p.append(p1.cubic_interpolate(p2, p0, p3, f))
			var rr := r1.cubic_interpolate(r2, r0, r3, f)
			var lo := r1.lerp(r2, f) * 0.8
			out_r.append(Vector2(maxf(rr.x, lo.x), maxf(rr.y, lo.y)))
			out_q.append(k + f)
	out_p.append(pts[n - 1])
	out_r.append(rads[n - 1])
	out_q.append(float(n - 1))
	return [out_p, out_r, out_q]


## Skin weights for a ring at chain parameter q (joint index + fraction).
## `chain` = bone ids of the segments, `parent` = bone the chain hangs off, `tip` = bone
## after the last segment (or -1).
static func chain_weight(chain: Array, parent: int, tip: int, q: float) -> Variant:
	var nseg := chain.size()
	var j := int(floor(q))
	var f := q - j
	if j >= nseg:
		if tip >= 0:
			return [chain[nseg - 1], tip, 0.5]
		return chain[nseg - 1]
	if j < 0:
		return parent
	if f < 0.5:
		var prev: int = parent if j == 0 else chain[j - 1]
		return [chain[j], prev, 0.5 - f]
	if j == nseg - 1:
		if tip >= 0:
			return [chain[j], tip, f - 0.5]
		return chain[j]
	return [chain[j], chain[j + 1], f - 0.5]
