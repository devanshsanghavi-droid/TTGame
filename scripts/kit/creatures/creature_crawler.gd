class_name CreatureCrawler extends Creature
## Arthropleura: a 2.5 m millipede relative. It is MOVING TERRAIN: the flat armoured
## back is a row of AnimatableBody3D boxes (layer 1, sync_to_physics) that follow
## the head along its trail, so a CharacterBody3D standing on it is carried.
## One skinned mesh: a bone per segment and per leg, legs ripple in a wave.

const SEGMENTS := 14
const LENGTH := 2.5
const BACK_H := 0.3                  ## height of the flat back at scale 1
const HALF_W := 0.28

static var _bp := {}

var mesh_instance: MeshInstance3D
var skeleton: Skeleton3D
var bodies: Array[AnimatableBody3D] = []

var _seg := LENGTH / SEGMENTS
var _trail := PackedVector3Array()   # newest first, spaced _step apart
var _step := 0.05
var _dist := 0.0
var _seg_xf: Array[Transform3D] = []
var _acc_dt := 0.0


static func create(opts: Dictionary = {}) -> CreatureCrawler:
	var c := CreatureCrawler.new()
	c.kind = "arthropleura"
	c.cfg = opts
	c._setup()
	return c


func _setup() -> void:
	if _bp.is_empty():
		_bp = _build()
	size_scale = cfg.get("scale", 1.0)
	scale = Vector3.ONE * size_scale
	era = cfg.get("era", null)
	if cfg.has("ground"):
		ground = cfg.ground
	speed = float(cfg.get("speed", 0.9)) * size_scale
	turn_rate = 0.9
	accel = 1.0
	weight = 0.1
	arrive_radius = 0.6 * size_scale
	_step = 0.05 * size_scale
	var cm: CreatureMesh = _bp.cm
	mesh_instance = cm.instantiate(self)
	skeleton = mesh_instance.get_parent() as Skeleton3D
	var ext := AABB(Vector3(-3.2, -0.6, -3.2), Vector3(6.4, 1.6, 6.4))
	mesh_instance.custom_aabb = ext
	_add_notifier(ext)
	_seg_xf.resize(SEGMENTS)
	# collision: one box per two segments
	var n_bodies := SEGMENTS / 2
	for j in n_bodies:
		var b := AnimatableBody3D.new()
		b.name = "Back%d" % j
		b.sync_to_physics = true
		b.top_level = true
		b.collision_layer = 0
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		var w := _half_width((j * 2 + 1.0) / SEGMENTS) * 2.0 + 0.04
		cs.shape = MeshKit.box_shape(Vector3(w, 0.26, _seg * 2.0 + 0.05) * size_scale)
		cs.position.y = (BACK_H - 0.13) * size_scale
		b.add_child(cs)
		add_child(b)
		bodies.append(b)
	body = bodies[0]
	anim_distance = 140.0
	lod_near = 40.0
	name = "Arthropleura"


static func _half_width(t: float) -> float:
	return HALF_W * (0.62 + 0.38 * pow(sin(clampf(t, 0.0, 1.0) * PI), 0.45))


func _ready() -> void:
	super._ready()
	_reset_trail()
	_update_segments()


## Teleports and lays the body out straight behind the head.
func warp(pos: Vector3, yaw: float) -> void:
	heading = yaw
	global_position = pos
	rotation.y = yaw
	_reset_trail()
	_update_segments()


func _reset_trail() -> void:
	_trail.clear()
	var p := global_position
	var back := -forward()
	var n := int(LENGTH * size_scale / _step) + 6
	for i in n:
		var q := p + back * _step * (i + 1)
		q.y = ground_at(q.x, q.z)
		_trail.append(q)


func _place(p: Vector3, delta: float) -> void:
	super._place(p, delta)
	_dist += cur_speed * delta
	if _trail.is_empty() or _trail[0].distance_to(global_position) >= _step:
		_trail.insert(0, global_position)
		var keep := int(LENGTH * size_scale / _step) + 8
		if _trail.size() > keep:
			_trail.resize(keep)


## True while `player` stands on the back.
func is_carrying(player: CharacterBody3D) -> bool:
	if not player.is_on_floor():
		return false
	for i in player.get_slide_collision_count():
		var col := player.get_slide_collision(i).get_collider()
		if col is AnimatableBody3D and bodies.has(col):
			return true
	var lp := player.global_position
	for b in bodies:
		var d := lp - b.global_position
		if Vector2(d.x, d.z).length() < 0.45 * size_scale and absf(d.y - BACK_H * size_scale) < 0.25:
			return true
	return false


## Top-centre of the back (where to stand), world space.
func back_point(t := 0.5) -> Vector3:
	var i := clampi(int(t * SEGMENTS), 0, SEGMENTS - 1)
	return _seg_xf[i] * Vector3(0, BACK_H * size_scale, 0)


func _update_segments() -> void:
	# walk the trail once, dropping each segment at its arc distance behind the head
	var head := global_position
	var prev := head
	var acc := 0.0
	var ti := 0
	var pts: Array[Vector3] = []
	var want := _seg * 0.5 * size_scale
	var seg_len := _seg * size_scale
	while pts.size() < SEGMENTS + 1:
		if ti >= _trail.size():
			pts.append(prev + (prev - head).normalized() * (want - acc) if prev != head else prev)
			want += seg_len
			continue
		var nxt := _trail[ti]
		var d := prev.distance_to(nxt)
		if acc + d >= want and d > 0.00001:
			pts.append(prev.lerp(nxt, (want - acc) / d))
			want += seg_len
		else:
			acc += d
			prev = nxt
			ti += 1
	for i in SEGMENTS:
		var a := head if i == 0 else pts[i - 1]
		var dir := a - pts[i + 1]
		if dir.length_squared() < 1e-8:
			dir = forward()
		_seg_xf[i] = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), pts[i])
	for j in bodies.size():
		var x0 := _seg_xf[j * 2]
		var x1 := _seg_xf[j * 2 + 1]
		var dir := x0.origin - x1.origin
		if dir.length_squared() < 1e-8:
			dir = forward()
		bodies[j].global_transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (x0.origin + x1.origin) * 0.5)


func _animate(delta: float) -> void:
	_update_segments()
	if _lod == 2:
		return
	_acc_dt += delta
	if _lod == 1 and (_frame & 1) == 1:
		return
	_acc_dt = 0.0
	var inv := global_transform.affine_inverse()
	var sk := skeleton
	var seg_b: Array = _bp.seg_b
	var leg_b: Array = _bp.leg_b
	var hinge: Array = _bp.hinge
	var s := size_scale
	var wave := _dist / (0.2 * s) * TAU
	var idle := Time.get_ticks_msec() * 0.0004
	for i in SEGMENTS:
		var w := _seg_xf[i]
		var m := inv * Transform3D(w.basis.scaled(Vector3(s, s, s)), w.origin)
		sk.set_bone_pose(seg_b[i], m)
		var ph := wave - i * 0.85
		for side in 2:
			var sgn := -1.0 if side == 0 else 1.0
			var swing := sin(ph) * 0.45
			var lift := maxf(0.0, cos(ph)) * 0.4 + sin(idle + i) * 0.02
			var h: Vector3 = hinge[i * 2 + side]
			sk.set_bone_pose(leg_b[i * 2 + side], m * Transform3D(Basis(Vector3.UP, swing * sgn) * Basis(Vector3.BACK, lift * sgn), h))


func telemetry() -> Dictionary:
	var d := super.telemetry()
	d["tail"] = _seg_xf[SEGMENTS - 1].origin if _seg_xf.size() > 0 else Vector3.ZERO
	return d


static func _build() -> Dictionary:
	var cm := CreatureMesh.new()
	var rig := {"cm": cm, "seg_b": [], "leg_b": [], "hinge": []}
	var seg := LENGTH / SEGMENTS
	var plate := Color(0.33, 0.17, 0.1)
	var edge := Color(0.5, 0.3, 0.14)
	var dark := Color(0.13, 0.08, 0.06)
	var under := Color(0.42, 0.3, 0.18)
	# bones first: segment origins at ground level under each plate, in a straight line
	for i in SEGMENTS:
		rig.seg_b.append(cm.bone("seg%d" % i, Vector3(0, 0, (i + 0.5) * seg)))
	for i in SEGMENTS:
		var t := (i + 0.5) / SEGMENTS
		var w := _half_width(t)
		var c := Vector3(0, 0, (i + 0.5) * seg)
		var b: int = rig.seg_b[i]
		# tergite: flat-topped plate with down-turned side lobes and a raised rear rim
		cm.shade(plate, under, plate.darkened(0.25), 1.0, 0.55)
		cm.ellipsoid(Vector3(w * 0.8, 0.085, seg * 0.66), c + Vector3(0, BACK_H - 0.09, 0), b, 1)
		cm.shade(edge, under, plate, 1.0, 0.55)
		for sgn: float in [-1.0, 1.0]:
			cm.ellipsoid(Vector3(w * 0.42, 0.04, seg * 0.6), Transform3D(Basis(Vector3.BACK, -0.4 * sgn), c + Vector3(w * 0.72 * sgn, BACK_H - 0.115, 0)), b, 1)
		cm.shade(dark, dark, dark, 1.0, 0.5)
		cm.ellipsoid(Vector3(w * 0.74, 0.03, 0.022), c + Vector3(0, BACK_H - 0.035, seg * 0.5), b, 0)
		for k in 3:
			cm.ellipsoid(Vector3(0.03, 0.016, 0.03), c + Vector3((k - 1) * w * 0.42, BACK_H - 0.012, -seg * 0.08), b, 0)
		cm.shade(under, under, under, 1.0, 0.7)
		cm.ellipsoid(Vector3(w * 0.5, 0.07, seg * 0.55), c + Vector3(0, 0.15, 0), b, 1)
		# legs
		for sgn: float in [-1.0, 1.0]:
			var h := Vector3(w * 0.45 * sgn, 0.14, 0.0)
			var lb := cm.bone("leg%d%s" % [i, "L" if sgn < 0.0 else "R"], c + h)
			rig.leg_b.append(lb)
			rig.hinge.append(h)
			cm.shade(dark.lerp(edge, 0.3), null, null, 0.6, 0.5)
			cm.loft([c + h, c + Vector3((w + 0.05) * sgn, 0.13, 0), c + Vector3((w + 0.12) * sgn, 0.0, 0.01)], [0.024, 0.018, 0.008], lb, 5)
	# head shield, antennae, eyes; tail plate
	var hb: int = rig.seg_b[0]
	cm.shade(plate.darkened(0.15), under, dark, 1.0, 0.5)
	cm.ellipsoid(Vector3(0.17, 0.075, 0.12), Vector3(0, BACK_H - 0.11, 0.02), hb)
	cm.paint(dark, 0.3, 0.4)
	for sgn: float in [-1.0, 1.0]:
		cm.loft([Vector3(0.07 * sgn, 0.2, -0.05), Vector3(0.16 * sgn, 0.24, -0.25), Vector3(0.26 * sgn, 0.16, -0.42)], [0.016, 0.012, 0.005], hb, 5)
		cm.ellipsoid(Vector3(0.02, 0.018, 0.022), Vector3(0.12 * sgn, 0.215, -0.03), hb, 1)
		cm.loft([Vector3(0.05 * sgn, 0.16, LENGTH - 0.04), Vector3(0.09 * sgn, 0.13, LENGTH + 0.1)], [0.02, 0.006], rig.seg_b[SEGMENTS - 1], 5)
	cm.commit({"hide": CreatureMesh.material("pine_bark", {"scale": 2.6, "contrast": 0.7, "normal": 1.3, "rough": 0.75})})
	return rig
