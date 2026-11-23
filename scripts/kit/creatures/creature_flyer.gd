class_name CreatureFlyer extends Creature
## Quetzalcoatlus: a giraffe-sized pterosaur (10.5 m span). Membrane wings on three
## bones per side that flap or glide, long stiff neck, toothless beak that opens.
## Path points carry altitude; circle() and dive_at() build the usual patterns.

signal swooped(pos: Vector3)         ## lowest point of a dive_at()

static var _bp := {}

var mesh_instance: MeshInstance3D
var skeleton: Skeleton3D
var jaw_open := 0.0
var min_clearance := 3.0             ## never fly lower than this above the ground
var climb_rate := 5.0
var flap := 0.0                      ## 0 glide .. 1 hard flapping (driven automatically)

var _t := 0.0
var _phase := 0.0
var _alt := 20.0
var _bank := 0.0
var _vpitch := 0.0
var _saved_path: Array[Vector3] = []
var _saved_loop := false
var _diving := false
var _look_yaw := 0.0
var _acc_dt := 0.0


static func create(opts: Dictionary = {}) -> CreatureFlyer:
	var c := CreatureFlyer.new()
	c.kind = "quetzalcoatlus"
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
	var cm: CreatureMesh = _bp.cm
	mesh_instance = cm.instantiate(self)
	skeleton = mesh_instance.get_parent() as Skeleton3D
	var ext := AABB(Vector3(-6.5, -3.5, -6.5), Vector3(13, 7, 10))
	mesh_instance.custom_aabb = ext
	_add_notifier(ext)
	speed = float(cfg.get("speed", 11.0)) * size_scale
	turn_rate = 0.55
	accel = 4.0
	weight = 0.6
	arrive_radius = 7.0 * size_scale
	anim_distance = 600.0
	lod_near = 160.0
	_t = float(cfg.get("seed", 0)) * 1.7
	add_to_group("lock_target")
	name = "Quetzalcoatlus"


func _ready() -> void:
	super._ready()
	_alt = global_position.y


## Teleports to `pos` (altitude included), level and facing `yaw`.
func warp(pos: Vector3, yaw: float) -> void:
	heading = yaw
	global_position = pos
	_alt = pos.y
	_bank = 0.0
	_vpitch = 0.0
	flap = 0.2


## Loops around `center` at `altitude` above it.
func circle(center: Vector3, radius := 30.0, altitude := 22.0, clockwise := false) -> void:
	var pts: Array = []
	for i in 12:
		var a := i / 12.0 * TAU * (-1.0 if clockwise else 1.0)
		pts.append(center + Vector3(cos(a) * radius, altitude, sin(a) * radius))
	set_path(pts, true)
	_diving = false


## Swoops down over `pos`, emits swooped(pos), then climbs back to the previous path.
func dive_at(pos: Vector3) -> void:
	if not _diving:
		_saved_path = _path.duplicate()
		_saved_loop = _loop
	_diving = true
	var p := pos
	p.y = maxf(pos.y + 2.5 * size_scale, ground_at(pos.x, pos.z) + min_clearance)
	set_path([p], false)
	state = "dive"


func _steer(delta: float) -> void:
	var was := state
	super._steer(delta)
	if was == "dive" and state == "idle":
		swooped.emit(global_position)
		_diving = false
		if _saved_path.size() > 0:
			set_path(_saved_path, _saved_loop)
	if state == "idle":
		# a flyer never stops: hold a circle over where it is
		var g := ground_at(global_position.x, global_position.z)
		circle(Vector3(global_position.x, g, global_position.z) + forward().rotated(Vector3.UP, PI * 0.5) * 30.0 * size_scale, 30.0 * size_scale, maxf(_alt - g, min_clearance + 6.0))


func _place(p: Vector3, delta: float) -> void:
	var want := _alt
	if _path_i < _path.size():
		want = _path[_path_i].y
	want = maxf(want, ground_at(p.x, p.z) + min_clearance)
	var rate := climb_rate * (2.4 if state == "dive" else 1.0) * size_scale
	var before := _alt
	_alt = move_toward(_alt, want, rate * delta * clampf(absf(want - _alt) * 0.4, 0.15, 1.0))
	var vy := (_alt - before) / delta
	p.y = _alt
	global_position = p
	_bank = lerpf(_bank, clampf(_yaw_rate * 1.3, -0.7, 0.7), 1.0 - exp(-delta * 2.0))
	_vpitch = lerpf(_vpitch, clampf(atan2(vy, maxf(cur_speed, 1.0)), -0.7, 0.6), 1.0 - exp(-delta * 2.5))
	basis = Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, _vpitch) * Basis(Vector3.BACK, _bank) * Basis.from_scale(Vector3.ONE * size_scale)
	var climb := clampf(vy / (climb_rate * size_scale), 0.0, 1.0)
	flap = lerpf(flap, maxf(climb, 0.12 + 0.2 * maxf(0.0, sin(_t * 0.23))), 1.0 - exp(-delta * 1.5))


func _animate(delta: float) -> void:
	_phase += delta * (5.2 + 2.2 * flap)
	if _lod == 2:
		return
	_acc_dt += delta
	if _lod == 1 and (_frame & 1) == 1:
		return
	var dt := _acc_dt
	_acc_dt = 0.0
	_t += dt
	var sk := skeleton
	var amp := 0.1 + 0.55 * flap
	var body_o: Vector3 = _bp.body_o
	var bob := -sin(_phase) * 0.12 * flap
	var bxf := Transform3D(Basis.IDENTITY, Vector3(0, bob, 0))
	sk.set_bone_pose(_bp.body, Transform3D(Basis.IDENTITY, body_o + Vector3(0, bob, 0)))
	for w: Dictionary in _bp.wings:
		var sgn: float = w.sgn
		var j: PackedVector3Array = w.joints
		var a1 := 0.1 + amp * sin(_phase)
		var a2 := a1 + amp * 0.75 * sin(_phase - 0.7) - 0.12
		var a3 := a2 + amp * 0.9 * sin(_phase - 1.4) - 0.1
		var r1 := Basis(Vector3.BACK, a1 * sgn)
		var r2 := Basis(Vector3.BACK, a2 * sgn) * Basis(Vector3.UP, -0.12 * sgn * maxf(0.0, -cos(_phase)) * flap)
		var r3 := Basis(Vector3.BACK, a3 * sgn) * Basis(Vector3.UP, -0.2 * sgn * maxf(0.0, -cos(_phase - 0.5)) * flap)
		var o1 := bxf * j[0]
		var o2 := o1 + r1 * (j[1] - j[0])
		var o3 := o2 + r2 * (j[2] - j[1])
		sk.set_bone_pose(w.b[0], Transform3D(r1, o1))
		sk.set_bone_pose(w.b[1], Transform3D(r2, o2))
		sk.set_bone_pose(w.b[2], Transform3D(r3, o3))
	# neck + head: gentle counter-bob, look toward the target
	var ty := 0.0
	var tp := -0.12
	var look: Variant = look_pos()
	if look != null:
		var lm: Vector3 = global_transform.affine_inverse() * (look as Vector3) - (_bp.head_o as Vector3)
		ty = clampf(atan2(-lm.x, -lm.z), -0.8, 0.8)
		tp = clampf(atan2(lm.y, Vector2(lm.x, lm.z).length()), -0.9, 0.3)
	_look_yaw = lerpf(_look_yaw, ty, 1.0 - exp(-dt * 2.0))
	var nb: Array = _bp.neck_b
	var nrest: PackedVector3Array = _bp.neck_rest
	var r := Basis.IDENTITY
	var o := bxf * nrest[0]
	var n := nb.size()
	for i in n:
		r = Basis(Vector3.UP, _look_yaw * 0.6 / n) * r * Basis(Vector3.RIGHT, (tp * 0.5 - bob * 0.25) / n)
		sk.set_bone_pose(nb[i], Transform3D(r, o))
		o += r * (nrest[i + 1] - nrest[i])
	var hb := Basis(Vector3.UP, _look_yaw * 0.4) * r * Basis(Vector3.RIGHT, tp * 0.5)
	sk.set_bone_pose(_bp.head, Transform3D(hb, o))
	var jo: Vector3 = _bp.jaw_o
	var open := clampf(jaw_open + maxf(0.0, sin(_t * 0.9) - 0.8) * 1.5 + (0.5 if state == "dive" else 0.0), 0.0, 1.0)
	sk.set_bone_pose(_bp.jaw, Transform3D(hb * Basis(Vector3.RIGHT, -open * 0.35), o + hb * (jo - (_bp.head_o as Vector3))))


func telemetry() -> Dictionary:
	var d := super.telemetry()
	d["alt"] = _alt
	return d


static func _build() -> Dictionary:
	var cm := CreatureMesh.new()
	var rig := {"cm": cm, "wings": []}
	var fuzz := Color(0.5, 0.42, 0.33)
	var pale := Color(0.74, 0.68, 0.56)
	var dark := Color(0.3, 0.24, 0.19)
	var body_o := Vector3(0, 0, 0)
	var bb := cm.bone("body", body_o)
	rig.body = bb
	rig.body_o = body_o
	# neck stations (z toward -head)
	var neck: Array = [[-0.55, 0.12, 0.2, 0.22], [-1.1, 0.3, 0.14, 0.16], [-1.7, 0.42, 0.115, 0.13], [-2.3, 0.48, 0.105, 0.12], [-2.9, 0.48, 0.1, 0.115], [-3.4, 0.44, 0.1, 0.12]]
	var nb: Array = []
	var nrest := PackedVector3Array()
	for i in neck.size():
		var st: Array = neck[i]
		nrest.append(Vector3(0, st[1], st[0]))
		if i < neck.size() - 1:
			nb.append(cm.bone("neck%d" % i, Vector3(0, st[1], st[0])))
	var ho := nrest[nrest.size() - 1]
	var hb := cm.bone("head", ho)
	rig.neck_b = nb
	rig.neck_rest = nrest
	rig.head = hb
	rig.head_o = ho
	# torso + neck in one loft
	var pts: Array = [Vector3(0, -0.02, 1.0), Vector3(0, 0.0, 0.7), Vector3(0, 0.02, 0.2), Vector3(0, 0.05, -0.25)]
	var rads: Array = [Vector2(0.06, 0.06), Vector2(0.2, 0.2), Vector2(0.3, 0.3), Vector2(0.3, 0.3)]
	var tags: Array = [-1, -1, -1, -1]
	for i in neck.size():
		pts.append(nrest[i])
		rads.append(Vector2(neck[i][2], neck[i][3]))
		tags.append(i)
	var rs := CreatureMesh.resample(pts, rads, 2)
	var specs: Array = []
	for q: float in rs[2]:
		var k := mini(int(floor(q)), pts.size() - 2)
		var f := q - k
		if int(tags[k]) >= 0:
			specs.append(CreatureMesh.chain_weight(nb, bb, hb, lerpf(tags[k], tags[k + 1], f)))
		else:
			specs.append(bb)
	cm.shade(fuzz, pale, dark)
	cm.loft(rs[0], rs[1], specs, 12)
	# head: skull, crest, long beak, lower jaw
	cm.loft([ho + Vector3(0, 0.02, 0.22), ho + Vector3(0, 0.05, -0.1), ho + Vector3(0, 0.02, -0.5)], [Vector2(0.1, 0.13), Vector2(0.13, 0.17), Vector2(0.1, 0.13)], hb, 10)
	cm.shade(Color(0.62, 0.36, 0.2), null, dark)
	cm.loft([ho + Vector3(0, 0.12, 0.2), ho + Vector3(0, 0.3, -0.1), ho + Vector3(0, 0.26, -0.5), ho + Vector3(0, 0.1, -0.8)], [Vector2(0.02, 0.05), Vector2(0.025, 0.12), Vector2(0.02, 0.09), Vector2(0.01, 0.02)], hb, 6)
	cm.paint(Color(0.78, 0.66, 0.4), 0.5, 0.55)
	cm.loft([ho + Vector3(0, 0.04, -0.4), ho + Vector3(0, 0.02, -1.1), ho + Vector3(0, -0.03, -1.9), ho + Vector3(0, -0.07, -2.5)], [Vector2(0.095, 0.09), Vector2(0.07, 0.07), Vector2(0.04, 0.045), Vector2(0.008, 0.01)], hb, 8)
	var jo := ho + Vector3(0, -0.08, -0.12)
	var jb := cm.bone("jaw", jo)
	rig.jaw = jb
	rig.jaw_o = jo
	cm.loft([jo + Vector3(0, 0.0, 0.05), jo + Vector3(0, -0.03, -0.9), jo + Vector3(0, -0.02, -1.75), jo + Vector3(0, 0.0, -2.36)], [Vector2(0.085, 0.05), Vector2(0.06, 0.04), Vector2(0.035, 0.028), Vector2(0.008, 0.008)], jb, 8)
	CreatureShapes.eyes(cm, hb, ho + Vector3(0, 0.07, -0.3), 0.115, 0.03)
	# hind legs trail behind
	for sgn: float in [-1.0, 1.0]:
		cm.shade(fuzz, pale, dark)
		cm.loft([Vector3(0.16 * sgn, -0.05, 0.35), Vector3(0.3 * sgn, -0.12, 0.95), Vector3(0.34 * sgn, -0.1, 1.75), Vector3(0.36 * sgn, -0.12, 2.1)], [0.11, 0.07, 0.04, 0.03], bb, 6)
		cm.paint(CreatureShapes.HORN, 0.2, 0.5)
		for k in 3:
			var c0 := Vector3((0.36 + (k - 1) * 0.04) * sgn, -0.12, 2.08)
			cm.horn([c0, c0 + Vector3(0, -0.03, 0.14), c0 + Vector3(0, -0.1, 0.2)], 0.02, bb, 4)
	# wings
	for sgn: float in [-1.0, 1.0]:
		var sh := Vector3(0.28 * sgn, 0.1, -0.2)
		var el := Vector3(1.25 * sgn, 0.14, 0.05)
		var wr := Vector3(2.35 * sgn, 0.12, -0.62)
		var mid := Vector3(3.9 * sgn, 0.06, -0.1)
		var tip := Vector3(5.25 * sgn, 0.0, 0.55)
		var b1 := cm.bone("arm%d" % int(sgn), sh)
		var b2 := cm.bone("fore%d" % int(sgn), el)
		var b3 := cm.bone("finger%d" % int(sgn), wr)
		rig.wings.append({"sgn": sgn, "b": [b1, b2, b3], "joints": PackedVector3Array([sh, el, wr])})
		cm.shade(fuzz, pale, dark)
		cm.loft([sh + Vector3(-0.15 * sgn, 0, 0), sh, el, wr, mid, tip], [0.12, 0.11, 0.085, 0.07, 0.045, 0.012],
			[bb, [b1, bb, 0.5], [b1, b2, 0.5], [b2, b3, 0.5], b3, b3], 7)
		cm.paint(CreatureShapes.HORN, 0.2, 0.5)
		for k in 3:
			var c0 := wr + Vector3(0, 0, -0.04 - k * 0.05)
			cm.horn([c0, c0 + Vector3(0.04 * sgn, 0, -0.2), c0 + Vector3(0.02 * sgn, -0.08, -0.3)], 0.025, b3, 4)
		# membrane: leading edge -> trailing edge strips, plus the propatagium in front of the elbow
		var t0 := Vector3(0.24 * sgn, -0.02, 0.75)
		var t1 := Vector3(1.2 * sgn, 0.0, 1.25)
		var t2 := Vector3(2.4 * sgn, 0.0, 1.1)
		var t3 := Vector3(3.8 * sgn, 0.0, 0.95)
		var hip := Vector3(0.3 * sgn, -0.08, 1.0)
		var v := PackedVector3Array([sh, el, wr, mid, tip, t0, t1, t2, t3, hip, Vector3(1.3 * sgn, 0.12, -0.5)])
		var ix := PackedInt32Array([0, 1, 5, 1, 6, 5, 1, 2, 6, 2, 7, 6, 2, 3, 7, 3, 8, 7, 3, 4, 8, 5, 6, 9, 0, 10, 1, 10, 2, 1])
		if sgn < 0.0:
			for k in range(0, ix.size(), 3):
				var tmp := ix[k + 1]
				ix[k + 1] = ix[k + 2]
				ix[k + 2] = tmp
		cm.shade(Color(0.52, 0.33, 0.24), Color(0.6, 0.42, 0.32), Color(0.4, 0.27, 0.2), 1.0, 0.9)
		cm.sheet(v, ix, [bb, [b1, b2, 0.5], [b2, b3, 0.5], b3, b3, bb, [b1, bb, 0.4], [b2, b1, 0.3], b3, bb, [b1, b2, 0.5]])
	cm.commit({"hide": CreatureMesh.material("dry_ground_01", {"scale": 1.6, "contrast": 0.6, "normal": 0.9, "backlight": 0.35, "rough": 0.95})})
	return rig
