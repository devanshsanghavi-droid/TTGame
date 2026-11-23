class_name CreatureWalker extends Creature
## Legged animals (quadrupeds and the theropod biped) on one skinned mesh:
## gait clock with planted feet + two-bone IK, spring chains for neck / tail /
## trunk, head look-at, jaw, ears, breathing. Shapes come from CreatureShapes.

signal roared

class Leg:
	var hip: Vector3
	var sole: Vector3
	var foot_vec: Vector3
	var l1: float
	var l2: float
	var d_up: Vector3
	var d_lo: Vector3
	var bend: float
	var off_walk: float
	var off_trot: float
	var off: float
	var b_up: int
	var b_lo: int
	var b_ft: int
	var plant: Vector3
	var from: Vector3
	var swing := false


class Chain:
	var bones: Array = []
	var rest := PackedVector3Array()
	var dirs := PackedVector3Array()
	var lens := PackedFloat32Array()
	var pts := PackedVector3Array()
	var vel := PackedVector3Array()
	var attach := "body"
	var stiff := 60.0
	var tip_stiff := 30.0
	var damp := 6.0
	var rigid := false
	var yaw_wave := Vector3.ZERO      # amplitude, frequency, lag per joint
	var pitch_wave := Vector3.ZERO
	var yaw_bias := 0.0
	var pitch_bias := 0.0
	var walk_gain := 0.0              # extra wave amplitude while moving


static var _blueprints := {}

var jaw_open := 0.0                  ## 0..1, added to the roar / idle jaw
var seat: Node3D                     ## rider seat (horse, elephant); parent a Humanoid here
var mesh_instance: MeshInstance3D
var skeleton: Skeleton3D
var trot_speed := 1e9                ## above this speed diagonal pairs move together

var _bp: Dictionary
var _legs: Array[Leg] = []
var _chains := {}
var _phase := 0.0
var _t := 0.0
var _stride := 2.0
var _duty := 0.7
var _lift := 0.3
var _bob := 0.03
var _roll := 0.02
var _sway := 0.03
var _toe_pitch := 0.5
var _half_len := 1.0
var _body_dy := 0.0
var _pitch := 0.0
var _dip := 0.0
var _dip_v := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _stale := true
var _settle := false
var _acc_dt := 0.0
var _roar_t := 0.0
var _trot := 0.0
var _seed := 0
var _pivot := Vector3.ZERO
var _head_origin := Vector3.ZERO
var _max_yaw := 1.1
var _head_share := 0.45


static func create(p_kind: String, opts: Dictionary = {}) -> CreatureWalker:
	var c := CreatureWalker.new()
	c.kind = p_kind
	c.cfg = opts
	c._setup()
	return c


static func blueprint(p_kind: String, opts: Dictionary) -> Dictionary:
	var key := p_kind + "|" + CreatureShapes.variant_key(p_kind, opts)
	if not _blueprints.has(key):
		_blueprints[key] = _build_blueprint(CreatureShapes.shape(p_kind, opts), opts)
	return _blueprints[key]


func _setup() -> void:
	_seed = int(cfg.get("seed", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + _seed * 7919
	_bp = blueprint(kind, cfg)
	var S: Dictionary = _bp.shape
	size_scale = float(cfg.get("scale", 1.0)) * (1.0 + (rng.randf() - 0.5) * 0.1 * float(_seed != 0))
	scale = Vector3.ONE * size_scale
	era = cfg.get("era", null)
	if cfg.has("ground"):
		ground = cfg.ground
	var cm: CreatureMesh = _bp.cm
	mesh_instance = cm.instantiate(self)
	skeleton = mesh_instance.get_parent() as Skeleton3D
	var tv := 0.86 + rng.randf() * 0.2 if _seed != 0 else 1.0
	mesh_instance.set_instance_shader_parameter("tint", Color(tv, tv * (0.97 + rng.randf() * 0.06), tv * (0.94 + rng.randf() * 0.1)))
	mesh_instance.extra_cull_margin = 1.0
	# gait + motion
	speed = float(cfg.get("speed", S.get("speed", 1.2))) * size_scale
	turn_rate = S.get("turn", 0.6)
	accel = float(S.get("accel", 0.8)) * size_scale
	weight = S.get("weight", 0.5)
	_stride = S.get("stride", 2.0)
	_duty = S.get("duty", 0.7)
	_lift = S.get("lift", 0.25)
	_bob = S.get("bob", 0.03)
	_roll = S.get("roll", 0.02)
	_sway = S.get("sway", 0.03)
	_toe_pitch = S.get("toe_pitch", 0.5)
	_half_len = S.get("half_len", 1.0)
	_max_yaw = S.get("max_yaw", 1.1)
	_head_share = S.get("head_share", 0.45)
	trot_speed = float(S.get("trot_speed", 1e9)) * size_scale
	arrive_radius = maxf(1.0, _half_len * 0.9 * size_scale)
	reacts_to_noise = cfg.get("hears", S.get("hears", false))
	_pivot = _bp.pivot
	_head_origin = _bp.head_origin
	_phase = rng.randf()
	_t = rng.randf() * 20.0
	for src: Dictionary in _bp.legs:
		var l := Leg.new()
		l.hip = src.hip
		l.sole = src.sole
		l.foot_vec = src.foot_vec
		l.l1 = src.l1
		l.l2 = src.l2
		l.d_up = src.d_up
		l.d_lo = src.d_lo
		l.bend = src.bend
		l.off_walk = src.off_walk
		l.off_trot = src.off_trot
		l.off = l.off_walk
		l.b_up = src.b_up
		l.b_lo = src.b_lo
		l.b_ft = src.b_ft
		_legs.append(l)
	for cname: String in _bp.chains:
		var src: Dictionary = _bp.chains[cname]
		var ch := Chain.new()
		ch.bones = src.bones
		ch.rest = src.rest
		ch.attach = src.attach
		var n := ch.rest.size()
		ch.pts.resize(n)
		ch.vel.resize(n)
		for i in n - 1:
			var d := ch.rest[i + 1] - ch.rest[i]
			ch.lens.append(d.length())
			ch.dirs.append(d.normalized())
		var sim: Dictionary = S.get(cname + "_sim", {})
		ch.stiff = sim.get("stiff", 60.0)
		ch.tip_stiff = sim.get("tip", ch.stiff * 0.5)
		ch.damp = sim.get("damp", 6.0)
		ch.rigid = sim.get("rigid", false)
		ch.yaw_wave = sim.get("yaw", Vector3.ZERO)
		ch.pitch_wave = sim.get("pitch", Vector3.ZERO)
		ch.walk_gain = sim.get("walk", 0.0)
		_chains[cname] = ch
	# collider, culling, seat
	var col: Array = S.get("collider", [1.0, 1.5, 2.0, 0.0])
	var box := BoxShape3D.new()
	box.size = Vector3(col[0], col[1], col[2])
	_make_body(box, Transform3D(Basis.IDENTITY, Vector3(0, float(col[1]) * 0.5 + float(S.get("clearance", 0.0)), col[3])))
	var ext: AABB = S.get("aabb", AABB(Vector3(-2, 0, -4), Vector3(4, 4, 8)))
	_add_notifier(ext)
	mesh_instance.custom_aabb = ext
	if _bp.has("seat"):
		seat = Node3D.new()
		seat.name = "Seat"
		seat.position = _bp.seat
		add_child(seat)
	if S.get("threat", false):
		add_to_group("lock_target")
	name = kind.capitalize().replace(" ", "")


func _ready() -> void:
	super._ready()
	_stale = true


## Teleports and re-plants the feet.
func warp(pos: Vector3, yaw: float) -> void:
	heading = yaw
	global_position = pos
	rotation.y = yaw
	_stale = true


## Opens the jaw for a moment and emits `roared` (the era plays the sound).
func roar(duration := 1.6) -> void:
	_roar_t = duration
	roared.emit()


func eye_position() -> Vector3:
	return global_transform * (_head_origin + Vector3(0, _body_dy, 0))


# ---------------------------------------------------------------- animation
func _animate(delta: float) -> void:
	var dist := (cur_speed * delta + absf(_yaw_rate) * delta * _half_len * size_scale * 0.8) / size_scale
	if dist < 0.0002 and _settle:
		dist = delta * _stride * 0.4
	_phase = fposmod(_phase + dist / _stride, 1.0)
	if _lod == 2:
		_stale = true
		return
	_acc_dt += delta
	if _lod == 1 and (_frame & 1) == 1:
		return
	var dt := minf(_acc_dt, 0.1)
	_acc_dt = 0.0
	_t += dt
	var xf := global_transform
	var inv := xf.affine_inverse()
	if _stale:
		_reset_pose(xf)
		_stale = false
	var sk := skeleton
	var fwd_w := -xf.basis.z.normalized()
	var mf := clampf(cur_speed / maxf(speed, 0.01), 0.0, 1.0)
	var k4 := 1.0 - exp(-dt * 4.0)

	# ---- body
	var p := xf.origin
	var f := fwd_w * _half_len * size_scale
	var gy_f := ground_at(p.x + f.x, p.z + f.z)
	var gy_b := ground_at(p.x - f.x, p.z - f.z)
	_body_dy = lerpf(_body_dy, ((gy_f + gy_b) * 0.5 - p.y) / size_scale, k4)
	_pitch = lerpf(_pitch, atan2(gy_f - gy_b, 2.0 * _half_len * size_scale), k4)
	_dip_v += (-_dip * 70.0 - _dip_v * 9.0) * dt
	_dip += _dip_v * dt
	var ph := _phase * TAU
	var sf := 1.0 - _duty
	var two_legs := _legs.size() == 2
	var bob := sin(ph * (2.0 if two_legs else 4.0) + 0.6) * _bob * mf
	var side := cos(ph - sf * PI)
	var breathe := sin(_t * 1.1)
	var bb := Basis.from_euler(Vector3(_pitch + breathe * 0.004, side * 0.03 * mf, -side * _roll * mf))
	var origin := _pivot + Vector3(side * _sway * mf, _body_dy + bob + _dip + breathe * 0.006 * _pivot.y, 0.0)
	var body_xf := Transform3D(bb, origin - bb * _pivot)
	var br := 1.0 + breathe * 0.012
	sk.set_bone_pose(_bp.body, Transform3D(bb * Basis.from_scale(Vector3(br, br, 1.0)), origin))

	# ---- legs
	_trot = move_toward(_trot, 1.0 if cur_speed > trot_speed else 0.0, dt * 1.5)
	_settle = false
	var thr := _stride * _duty * 0.45 * size_scale
	thr *= thr
	for leg in _legs:
		leg.off = lerpf(leg.off_walk, leg.off_trot, _trot)
		var lp := fposmod(_phase + leg.off, 1.0)
		var home_w := xf * leg.sole
		var in_swing := lp < sf
		if in_swing and not leg.swing:
			leg.swing = true
			leg.from = leg.plant
		var sole_w := leg.plant
		var toe := 0.0
		if leg.swing:
			var s := clampf(lp / sf, 0.0, 1.0) if in_swing else 1.0
			var lead := (_stride * _duty * 0.5 + (1.0 - s) * sf * _stride) * mf * size_scale
			var tgt := home_w + fwd_w * lead
			tgt.y = ground_at(tgt.x, tgt.z)
			if in_swing:
				var e := s * s * (3.0 - 2.0 * s)
				sole_w = leg.from.lerp(tgt, e)
				var lift := sin(s * PI)
				sole_w.y += lift * _lift * size_scale * (0.45 + 0.55 * mf)
				toe = -lift * _toe_pitch * (0.4 + 0.6 * mf)
				_settle = true
			else:
				leg.swing = false
				leg.plant = tgt
				sole_w = tgt
				_dip_v -= 0.25 * _bob * 10.0
				footfall.emit(tgt, weight)
		elif home_w.distance_squared_to(leg.plant) > thr:
			_settle = true
		var sole_m := inv * sole_w
		var hip_m := body_xf * leg.hip
		var fv := leg.foot_vec
		if toe != 0.0:
			fv = fv.rotated(Vector3.RIGHT, toe)
		var ankle := sole_m - fv
		var to := ankle - hip_m
		var d := to.length()
		var maxr := (leg.l1 + leg.l2) * 0.998
		if d > maxr:
			to *= maxr / d
			d = maxr
			ankle = hip_m + to
		d = maxf(d, absf(leg.l1 - leg.l2) + 0.01)
		var dirn := to / d
		var a := (leg.l1 * leg.l1 - leg.l2 * leg.l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(leg.l1 * leg.l1 - a * a, 0.0))
		var pole := Vector3(0.0, 0.0, -leg.bend)
		var perp := pole - dirn * pole.dot(dirn)
		perp = perp.normalized() if perp.length_squared() > 1e-6 else pole
		var knee := hip_m + dirn * a + perp * h
		sk.set_bone_pose(leg.b_up, Transform3D(Basis(Quaternion(leg.d_up, (knee - hip_m).normalized())), hip_m))
		sk.set_bone_pose(leg.b_lo, Transform3D(Basis(Quaternion(leg.d_lo, (ankle - knee).normalized())), knee))
		sk.set_bone_pose(leg.b_ft, Transform3D(Basis(Vector3.RIGHT, toe), ankle))

	# ---- neck + head
	var look: Variant = look_pos()
	var ty := sin(_t * 0.31) * 0.22 + sin(_t * 0.13 + 1.0) * 0.18
	var tp := sin(_t * 0.23) * 0.05
	if look != null:
		var lm: Vector3 = inv * (look as Vector3) - (body_xf * _head_origin)
		ty = clampf(atan2(-lm.x, -lm.z), -_max_yaw, _max_yaw)
		tp = clampf(atan2(lm.y, Vector2(lm.x, lm.z).length()), -0.6, 0.6)
	var k2 := 1.0 - exp(-dt * 2.2)
	_look_yaw = lerpf(_look_yaw, ty, k2)
	_look_pitch = lerpf(_look_pitch, tp, k2)
	var neck: Chain = _chains.neck
	var nseg := neck.bones.size()
	neck.yaw_bias = _look_yaw * (1.0 - _head_share) / nseg
	neck.pitch_bias = _look_pitch * (1.0 - _head_share) / nseg
	var neck_b := _chain_update(neck, body_xf * neck.rest[0], bb, xf, inv, dt, mf)
	var n_last := neck.rest.size() - 1
	var ho := inv * neck.pts[n_last]
	var nod := sin(ph * 2.0) * 0.03 * mf
	var hb := Basis(Vector3.UP, _look_yaw * _head_share) * neck_b * Basis(Vector3.RIGHT, _look_pitch * _head_share + nod)
	sk.set_bone_pose(_bp.head, Transform3D(hb, ho))
	if _bp.jaw >= 0:
		var open := jaw_open + maxf(0.0, sin(_t * 0.7)) * 0.06
		if _roar_t > 0.0:
			_roar_t -= dt
			open += sin(clampf(_roar_t / 1.6, 0.0, 1.0) * PI) * 0.9
		var jo: Vector3 = _bp.jaw_origin
		sk.set_bone_pose(_bp.jaw, Transform3D(hb * Basis(Vector3.RIGHT, -clampf(open, 0.0, 1.2) * 0.55), ho + hb * (jo - _head_origin)))
	for ear: Array in _bp.ears:
		var eo: Vector3 = ear[1]
		var flap := (0.5 + 0.5 * sin(_t * 1.3 + float(ear[2]))) * 0.5 * float(ear[2])
		sk.set_bone_pose(ear[0], Transform3D(hb * Basis(Vector3.UP, flap), ho + hb * (eo - _head_origin)))

	# ---- other chains
	for cname: String in _chains:
		if cname == "neck":
			continue
		var ch: Chain = _chains[cname]
		if ch.attach == "head":
			_chain_update(ch, ho + hb * (ch.rest[0] - _head_origin), hb, xf, inv, dt, mf)
		else:
			_chain_update(ch, body_xf * ch.rest[0], bb, xf, inv, dt, mf)
	if seat:
		seat.transform = Transform3D(bb, body_xf * (_bp.seat as Vector3))


func _chain_update(ch: Chain, base: Vector3, base_basis: Basis, xf: Transform3D, inv: Transform3D, dt: float, mf: float) -> Basis:
	var n := ch.rest.size()
	var r := base_basis
	var tgt := base
	var gain := 1.0 + ch.walk_gain * mf
	ch.pts[0] = xf * tgt
	var damp := exp(-ch.damp * dt)
	var ib := inv.basis
	var last := base_basis
	for i in range(1, n):
		var yaw := ch.yaw_bias + ch.yaw_wave.x * gain * sin(_t * ch.yaw_wave.y - i * ch.yaw_wave.z)
		var pit := ch.pitch_bias + ch.pitch_wave.x * gain * sin(_t * ch.pitch_wave.y - i * ch.pitch_wave.z)
		r = Basis(Vector3.UP, yaw) * r * Basis(Vector3.RIGHT, pit)
		var seg := r * (ch.rest[i] - ch.rest[i - 1])
		var from_m := tgt
		tgt += seg
		var tw := xf * tgt
		last = r
		if ch.rigid:
			ch.pts[i] = tw
		else:
			var p := ch.pts[i]
			var v := ch.vel[i]
			var k := lerpf(ch.stiff, ch.tip_stiff, float(i) / (n - 1))
			v += (tw - p) * k * dt
			v *= damp
			p += v * dt
			var d := p - ch.pts[i - 1]
			var dl := d.length()
			if dl > 0.0001:
				p = ch.pts[i - 1] + d * (ch.lens[i - 1] * size_scale / dl)
			ch.vel[i] = v
			ch.pts[i] = p
			# bend the target orientation by however far the spring has swung the segment
			var dm := (ib * (p - ch.pts[i - 1])).normalized()
			last = Basis(Quaternion(seg.normalized(), dm)) * r
			from_m = inv * ch.pts[i - 1]
		skeleton.set_bone_pose(ch.bones[i - 1], Transform3D(last, from_m))
	return last


func _reset_pose(xf: Transform3D) -> void:
	for leg in _legs:
		var w := xf * leg.sole
		w.y = ground_at(w.x, w.z)
		leg.plant = w
		leg.from = w
		leg.swing = false
	for cname: String in _chains:
		var ch: Chain = _chains[cname]
		for i in ch.rest.size():
			ch.pts[i] = xf * ch.rest[i]
			ch.vel[i] = Vector3.ZERO
	_body_dy = 0.0
	_dip = 0.0
	_dip_v = 0.0


func telemetry() -> Dictionary:
	var d := super.telemetry()
	d["phase"] = _phase
	return d


# ------------------------------------------------------------------ building
static func _sp(st: Array) -> Vector3:
	return Vector3(0.0, st[1], st[0])


## Adds a spring chain (trunk, hair tail, crest) as its own loft.
## stations: Array of [Vector3, radius]. Returns the bone ids.
static func add_chain(cm: CreatureMesh, rig: Dictionary, cname: String, stations: Array, parent_bone: int, attach: String, sides := 8, sub := 2) -> Array:
	var pts: Array = []
	var rads: Array = []
	var rest := PackedVector3Array()
	for st: Array in stations:
		pts.append(st[0])
		var rr: Variant = st[1]
		rads.append(rr if rr is Vector2 else Vector2(rr, rr))
		rest.append(st[0])
	var bones: Array = []
	for i in pts.size() - 1:
		bones.append(cm.bone("%s%d" % [cname, i], pts[i]))
	var rs := CreatureMesh.resample(pts, rads, sub)
	var specs: Array = []
	for q: float in rs[2]:
		specs.append(CreatureMesh.chain_weight(bones, parent_bone, -1, q))
	cm.loft(rs[0], rs[1], specs, sides, Vector3.BACK if absf((pts[1] - pts[0]).normalized().y) > 0.7 else Vector3.UP)
	rig.chains[cname] = {"bones": bones, "rest": rest, "attach": attach}
	return bones


static func _build_blueprint(S: Dictionary, opts: Dictionary) -> Dictionary:
	var cm := CreatureMesh.new()
	var rig := {"cm": cm, "shape": S, "legs": [], "chains": {}, "ears": [], "jaw": -1, "jaw_origin": Vector3.ZERO}
	var body_st: Array = S.body
	var tail_st: Array = S.get("tail", [])
	var neck_st: Array = S.neck
	var ysum := 0.0
	for st: Array in body_st:
		ysum += st[1]
	var pivot := Vector3(0.0, ysum / body_st.size(), 0.0)
	var b_body := cm.bone("body", pivot)
	rig.body = b_body
	rig.pivot = pivot
	var tail_b: Array = []
	var tail_rest := PackedVector3Array()
	for i in tail_st.size():
		tail_rest.append(_sp(tail_st[i]))
		if i < tail_st.size() - 1:
			tail_b.append(cm.bone("tail%d" % i, _sp(tail_st[i])))
	var neck_b: Array = []
	var neck_rest := PackedVector3Array()
	for i in neck_st.size():
		neck_rest.append(_sp(neck_st[i]))
		if i < neck_st.size() - 1:
			neck_b.append(cm.bone("neck%d" % i, _sp(neck_st[i])))
	var head_o := _sp(neck_st[neck_st.size() - 1])
	var b_head := cm.bone("head", head_o)
	rig.head = b_head
	rig.head_origin = head_o
	rig.neck_b = neck_b
	rig.tail_b = tail_b
	rig.chains["neck"] = {"bones": neck_b, "rest": neck_rest, "attach": "body"}
	if tail_b.size() > 0:
		rig.chains["tail"] = {"bones": tail_b, "rest": tail_rest, "attach": "body"}
	# ---- one continuous loft: tail tip -> rump -> chest -> neck -> head joint
	var pts: Array = []
	var rads: Array = []
	var tags: Array = []
	for k in range(tail_st.size() - 1, -1, -1):
		pts.append(_sp(tail_st[k]))
		rads.append(Vector2(tail_st[k][2], tail_st[k][3]))
		tags.append(Vector2i(0, k))
	for st: Array in body_st:
		pts.append(_sp(st))
		rads.append(Vector2(st[2], st[3]))
		tags.append(Vector2i(1, 0))
	for k in neck_st.size():
		pts.append(_sp(neck_st[k]))
		rads.append(Vector2(neck_st[k][2], neck_st[k][3]))
		tags.append(Vector2i(2, k))
	var rs := CreatureMesh.resample(pts, rads, S.get("sub", 2))
	var specs: Array = []
	for q: float in rs[2]:
		var k := mini(int(floor(q)), pts.size() - 2)
		var f := q - k
		var ta: Vector2i = tags[k]
		var tb: Vector2i = tags[k + 1]
		if ta.x == 0 and tb.x == 0:
			specs.append(CreatureMesh.chain_weight(tail_b, b_body, -1, lerpf(ta.y, tb.y, f)))
		elif ta.x == 2 and tb.x == 2:
			specs.append(CreatureMesh.chain_weight(neck_b, b_body, b_head, lerpf(ta.y, tb.y, f)))
		else:
			specs.append(b_body)
	var col: Array = S.col
	cm.shade(col[0], col[1], col[2])
	cm.loft(rs[0], rs[1], specs, S.get("sides", 16))
	# ---- legs
	var pair_i := 0
	for pair: String in ["hind", "front"]:
		if not S.has(pair):
			continue
		var L: Dictionary = S[pair]
		for sgn: float in [-1.0, 1.0]:
			var hz: Vector2 = L.hip
			var kz: Vector2 = L.knee
			var az: Vector2 = L.ankle
			var x: float = float(L.x) * sgn
			var splay: float = L.get("splay", 0.0) * sgn
			var hip := Vector3(x, hz.y, hz.x)
			var knee := Vector3(x + splay * 0.5, kz.y, kz.x)
			var ankle := Vector3(x + splay, az.y, az.x)
			var sole := Vector3(x + splay, 0.0, az.x + float(L.get("foot_dz", 0.0)))
			var tag := "%s%s" % [pair, "L" if sgn < 0.0 else "R"]
			var b_up := cm.bone(tag + "_up", hip)
			var b_lo := cm.bone(tag + "_lo", knee)
			var b_ft := cm.bone(tag + "_ft", ankle)
			var r: Array = L.r
			var top := hip + Vector3(-x * 0.3, float(L.get("top_up", 0.35)) * (hz.y - kz.y), 0.0)
			cm.shade(col[0], col[1], col[0])
			cm.loft([top, hip, hip.lerp(knee, 0.5), knee, knee.lerp(ankle, 0.5), ankle, ankle.lerp(sole, 0.55)],
				[r[0], r[0], r[1], r[2], r[3], r[4], r[4]],
				[b_body, [b_up, b_body, 0.5], b_up, [b_up, b_lo, 0.5], b_lo, [b_lo, b_ft, 0.5], b_ft], S.get("leg_sides", 10), Vector3.BACK)
			CreatureShapes.foot(cm, L, ankle, sole, sgn, b_ft, S)
			var walk_off: float
			var trot_off: float
			if not S.has("front"):
				walk_off = 0.0 if sgn < 0.0 else 0.5
				trot_off = walk_off
			elif pair == "hind":
				walk_off = 0.0 if sgn < 0.0 else 0.5
				trot_off = walk_off
			else:
				walk_off = 0.75 if sgn < 0.0 else 0.25
				trot_off = 0.5 if sgn < 0.0 else 0.0
			rig.legs.append({"hip": hip, "sole": sole, "foot_vec": sole - ankle, "l1": hip.distance_to(knee), "l2": knee.distance_to(ankle),
				"d_up": (knee - hip).normalized(), "d_lo": (ankle - knee).normalized(), "bend": L.get("bend", 1.0),
				"off_walk": walk_off, "off_trot": trot_off, "b_up": b_up, "b_lo": b_lo, "b_ft": b_ft})
		pair_i += 1
	# ---- species head and extras
	cm.shade(col[0], col[1], col[2])
	CreatureShapes.detail(cm, rig, S, opts)
	cm.commit(CreatureShapes.materials(S))
	return rig
