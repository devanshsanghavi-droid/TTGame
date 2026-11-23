class_name Npc extends Node3D
## A person: Humanoid rig + simple behaviours + perception. No navmesh needed.
##
##   var g := Npc.make(self, on_ground(4, 10), "medieval_guard", {"seed": 3, "react": "chase"})
##   g.patrol([a, b, c])                     # or wander(center, radius), go_to(pos), follow(node),
##   g.noticed.connect(func(p): ...)         #    work(), sit(), talk(node), face(node_or_pos), idle()
##   g.alerted.connect(func(p): ...)
##
## Perception: a vision cone (vision_range, vision_half_angle, world raycast on
## layer 1, scaled by player.visibility) and hearing (group "hearing": era.emit_noise
## calls hear(); player.noise inside hearing_radius also counts). `awareness` rises
## 0..1 while the player is sensed and decays otherwise:
##   >= 0.35  alert = "suspicious", signal noticed(player)
##   >= 1.0   alert = "alert",      signal alerted(player)
##   back to 0 after either         signal lost(player)
## What the Npc does about it is `react`: "none" | "look" (stop and watch) |
## "chase" (run at the player, signal caught(player) inside catch_radius) | "flee".
##
## opts for make(): seed, era, yaw, name, speed, run_speed, vision_range, vision_half_angle,
## hearing_radius, notice_time, forget_time, react, perceptive, catch_radius, solid (bool: blocks
## the player), ground (Callable (x, z) -> y), ray_ground (bool: snap with a raycast, for floors
## and steps above the terrain), draw_distance.

signal noticed(player: Player)
signal alerted(player: Player)
signal lost(player: Player)
signal caught(player: Player)
signal arrived
signal heard(pos: Vector3, loudness: float, source: String)

const NOTICE_AT := 0.35

var era: Node
var rig: Humanoid
var outfit := ""
var behaviour := "idle"         ## idle | wander | patrol | go_to | follow | work | sit | talk
var alert := "calm"             ## calm | suspicious | alert
var awareness := 0.0
var speed := 1.3
var run_speed := 3.6
var turn_speed := 6.0
var vision_range := 16.0
var vision_half_angle := 55.0   ## degrees
var hearing_radius := 9.0
var notice_time := 2.2          ## seconds in plain view at mid range to become alert
var forget_time := 5.0
var react := "look"
var catch_radius := 1.1
var perceptive := true
var sees_player := false
var facing := Vector3.FORWARD
var last_known := Vector3.ZERO
var ground_fn := Callable()
var ray_ground := false
var body: StaticBody3D

var _rng := RandomNumberGenerator.new()
var _points: Array = []
var _index := 0
var _loop := true
var _dir_sign := 1
var _pause := 1.0
var _wait := 0.0
var _center := Vector3.ZERO
var _radius := 4.0
var _target := Vector3.ZERO
var _has_target := false
var _follow: Node3D
var _follow_dist := 2.0
var _face_target: Variant = null
var _anim := "walk"
var _speed_now := 0.0
var _perceive_t := 0.0
var _noticed_once := false
var _catch_cd := 0.0
var _avoid_t := 0.0
var _avoid_dir := Vector3.ZERO
var _avoid_check := 0.0
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _look_yaw := 0.0
var _look_t := 0.0
var _anim_acc := 0.0
var _anim_frame := 0
var _solid_pending := false
var _eye_h := 1.55
var _push := Vector3.ZERO


static func make(parent: Node, pos: Vector3, p_outfit: Variant = "medieval_peasant", opts: Dictionary = {}) -> Npc:
	var n := Npc.new()
	n.era = opts.get("era", parent if parent is EraBase else Game.current_era)
	var s: int = opts.get("seed", 0)
	n._rng.seed = hash(pos) + s * 31 + 5
	var cfg: Dictionary
	if p_outfit is Dictionary:
		cfg = p_outfit
	else:
		n.outfit = String(p_outfit)
		cfg = Outfits.cfg(n.outfit, s)
	for k: String in ["speed", "run_speed", "vision_range", "vision_half_angle", "hearing_radius", "notice_time",
			"forget_time", "react", "perceptive", "catch_radius", "ray_ground"]:
		if opts.has(k):
			n.set(k, opts[k])
	if opts.has("ground"):
		n.ground_fn = opts.ground
	n.rig = Humanoid.create(cfg)
	n.add_child(n.rig)
	n._eye_h = 1.6 * n.rig.scale.y
	n.position = pos
	if opts.has("name"):
		n.name = opts.name
	n._solid_pending = opts.get("solid", false)
	n._build_body()
	var dd: float = opts.get("draw_distance", 170.0)
	if dd > 0.0:
		n._set_draw_distance(n.rig, dd)
	parent.add_child(n)
	if opts.has("yaw"):
		n.set_yaw(opts.yaw)
	return n


func _ready() -> void:
	add_to_group("npc")
	add_to_group("telemetry_ai")
	add_to_group("hearing")
	_perceive_t = _rng.randf() * 0.1
	_anim_frame = _rng.randi() % 6
	_stuck_pos = global_position
	last_known = global_position


func _build_body() -> void:
	body = StaticBody3D.new()
	body.collision_layer = 4      # "npc": thrown things hit it, the player and the navmesh bake ignore it
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	# solid Npcs get a tall capsule so the player's ledge-mantle probe never lands on a head
	cap.height = 2.7 if _solid_pending else 1.75
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	body.add_child(cs)
	add_child(body)


func _set_draw_distance(n: Node, d: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = d
		(n as GeometryInstance3D).visibility_range_end_margin = 8.0
	for c in n.get_children():
		_set_draw_distance(c, d)


# ------------------------------------------------------------------ behaviours
func idle() -> Npc:
	behaviour = "idle"
	_anim = "walk"
	_has_target = false
	return self


func stop() -> Npc:
	return idle()


## Strolls between random points inside a disc, pausing at each.
func wander(center: Vector3, radius := 5.0, pause := 3.0) -> Npc:
	behaviour = "wander"
	_center = center
	_radius = radius
	_pause = pause
	_has_target = false
	_wait = _rng.randf() * pause
	return self


## Walks the waypoints in order. loop = false walks there and back again.
func patrol(points: Array, loop := true, pause := 1.2) -> Npc:
	behaviour = "patrol"
	_points = points.duplicate()
	_loop = loop
	_pause = pause
	_index = 0
	_dir_sign = 1
	_wait = 0.0
	return self


## Walks to a point, emits `arrived`, then idles.
func go_to(pos: Vector3, run := false) -> Npc:
	behaviour = "go_to"
	_target = pos
	_has_target = true
	_anim = "run" if run else "walk"
	return self


func follow(node: Node3D, distance := 2.0) -> Npc:
	behaviour = "follow"
	_follow = node
	_follow_dist = distance
	return self


## Loops a work animation on the spot ("work" hammering, "drum", "carry", "crouch" ...).
## Defaults to what suits the outfit.
func work(mode := "") -> Npc:
	behaviour = "work"
	_anim = mode if mode != "" else String(rig.cfg.get("anim", "work"))
	return self


## Sits: on a seat about 0.45 m high, or on the ground with knees drawn up.
func sit(on_ground := false) -> Npc:
	behaviour = "sit"
	_anim = "sit_ground" if on_ground else "sit"
	return self


## Turns to a node or position and gestures as if in conversation.
func talk(target: Variant = null) -> Npc:
	behaviour = "talk"
	_anim = "talk"
	_face_target = target
	return self


## Keeps turning toward a node or position (null clears it).
func face(target: Variant) -> Npc:
	_face_target = target
	return self


func set_yaw(yaw: float) -> void:
	rotation.y = yaw
	facing = Basis(Vector3.UP, yaw) * Vector3.FORWARD


## Adds a "Talk" prompt that travels with the Npc. The Npc turns to the player first.
func add_talk(on_use: Callable, prompt := "Talk", reach := 2.5) -> Interactable:
	return Interactable.make(self, Vector3(0, 1.0, 0), prompt, func(p: Player) -> void:
		face(p)
		on_use.call(p), reach)


## Era noise hook (group "hearing").
func hear(pos: Vector3, loudness: float, source: String) -> void:
	if not perceptive:
		return
	heard.emit(pos, loudness, source)
	var d := global_position.distance_to(pos)
	var gain := loudness * (0.75 if d < 8.0 else 0.45)
	awareness = maxf(awareness, minf(awareness + gain, 0.8))
	last_known = pos


func telemetry() -> Dictionary:
	return {"state": behaviour, "alert": alert, "aw": awareness, "sees": sees_player, "pos": global_position, "outfit": outfit}


# ---------------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	var dt: float = era.wdelta(delta) if era and era.has_method("wdelta") else delta
	if dt <= 0.0:
		return
	if _solid_pending and (era == null or era.get("is_ready") == true):
		_solid_pending = false
		body.collision_layer = 1 | 4
	var pl := _player()
	if perceptive and pl:
		_perceive_t -= dt
		if _perceive_t <= 0.0:
			_perceive(pl, 0.1 - _perceive_t)
			_perceive_t = 0.1
	_catch_cd = maxf(0.0, _catch_cd - dt)
	var moving_speed := 0.0
	var anim := "walk"
	if alert != "calm" and react != "none" and pl:
		moving_speed = _react(pl, dt)
	else:
		moving_speed = _behave(dt)
		anim = _anim if behaviour in ["work", "sit", "talk"] else "walk"
	# ground
	var p := global_position
	p += _push * dt
	_push = _push.move_toward(Vector3.ZERO, dt * 3.0)
	var gy := _ground(p)
	p.y = gy if absf(p.y - gy) > 1.5 else lerpf(p.y, gy, 1.0 - exp(-dt * 14.0))
	global_position = p
	rotation.y = atan2(-facing.x, -facing.z)
	_animate(dt, moving_speed, anim, pl)


func _player() -> Player:
	if era and "player" in era:
		var p: Variant = era.get("player")
		if p is Player and is_instance_valid(p):
			return p
	return null


func _ground(p: Vector3) -> float:
	if ground_fn.is_valid():
		return ground_fn.call(p.x, p.z)
	if ray_ground:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.2, p + Vector3.DOWN * 3.0, 1, [body.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		return hit.position.y if not hit.is_empty() else p.y
	if era and era.has_method("ground_y"):
		return era.ground_y(p.x, p.z)
	return p.y


func _behave(dt: float) -> float:
	match behaviour:
		"wander":
			if not _has_target:
				_wait -= dt
				_turn_to_face(dt)
				if _wait <= 0.0:
					var a := _rng.randf() * TAU
					var r := sqrt(_rng.randf()) * _radius
					_target = _center + Vector3(cos(a) * r, 0, sin(a) * r)
					_has_target = true
				return _slow(dt)
			if _step_to(_target, speed, dt, 0.4):
				_has_target = false
				_wait = _pause * _rng.randf_range(0.5, 1.6)
			return _speed_now
		"patrol":
			if _points.is_empty():
				return _slow(dt)
			if _wait > 0.0:
				_wait -= dt
				return _slow(dt)
			if _step_to(_points[_index], speed, dt, 0.45):
				_wait = _pause
				_advance_waypoint()
			return _speed_now
		"go_to":
			if _has_target and _step_to(_target, run_speed if _anim == "run" else speed, dt, 0.4):
				_has_target = false
				behaviour = "idle"
				_anim = "walk"
				arrived.emit()
			return _speed_now
		"follow":
			if _follow == null or not is_instance_valid(_follow):
				return _slow(dt)
			var tp := _follow.global_position
			var d := Vector2(tp.x - global_position.x, tp.z - global_position.z).length()
			if d > _follow_dist + 0.4:
				_step_to(tp, run_speed if d > _follow_dist + 5.0 else speed, dt, _follow_dist)
				return _speed_now
			_face_pos(tp, dt)
			return _slow(dt)
		_:
			_turn_to_face(dt)
			return _slow(dt)


func _advance_waypoint() -> void:
	if _loop:
		_index = (_index + 1) % _points.size()
		return
	if _points.size() < 2:
		return
	if _index + _dir_sign < 0 or _index + _dir_sign >= _points.size():
		_dir_sign = -_dir_sign
	_index += _dir_sign


func _react(pl: Player, dt: float) -> float:
	var target := pl.global_position if sees_player else last_known
	if alert == "suspicious" or react == "look":
		_face_pos(target, dt)
		return _slow(dt)
	if react == "flee":
		var away := global_position - target
		away.y = 0.0
		if away.length() < 0.1:
			away = -facing
		_step_to(global_position + away.normalized() * 6.0, run_speed, dt, 0.3)
		return _speed_now
	# chase
	var d := Vector2(target.x - global_position.x, target.z - global_position.z).length()
	if d <= catch_radius:
		_face_pos(target, dt)
		if sees_player and _catch_cd <= 0.0 and absf(pl.global_position.y - global_position.y) < 1.6:
			_catch_cd = 2.0
			caught.emit(pl)
		return _slow(dt)
	_step_to(target, run_speed, dt, catch_radius * 0.8)
	return _speed_now


func _slow(dt: float) -> float:
	_speed_now = move_toward(_speed_now, 0.0, dt * 8.0)
	return _speed_now


func _turn_to_face(dt: float) -> void:
	if _face_target == null:
		return
	if _face_target is Vector3:
		_face_pos(_face_target, dt)
	elif _face_target is Node3D and is_instance_valid(_face_target):
		_face_pos((_face_target as Node3D).global_position, dt)


func _face_pos(pos: Vector3, dt: float) -> void:
	var d := pos - global_position
	d.y = 0.0
	if d.length_squared() > 0.01:
		_face_dir(d.normalized(), dt)


func _face_dir(dir: Vector3, dt: float) -> void:
	var cur := atan2(-facing.x, -facing.z)
	var want := atan2(-dir.x, -dir.z)
	var diff := wrapf(want - cur, -PI, PI)
	cur += clampf(diff, -turn_speed * dt, turn_speed * dt)
	facing = Vector3(-sin(cur), 0.0, -cos(cur))


## One steering step toward `target`. Returns true once inside `tol`.
func _step_to(target: Vector3, spd: float, dt: float, tol: float) -> bool:
	var to := target - global_position
	to.y = 0.0
	var d := to.length()
	if d <= tol:
		_slow(dt)
		return true
	var dir := to / d
	# wall avoidance: a short ray at knee height, re-checked a few times a second
	_avoid_check -= dt
	if _avoid_check <= 0.0:
		_avoid_check = 0.15
		var from := global_position + Vector3.UP * 0.55
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.9, 1, [body.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit.normal as Vector3).y < 0.6:
			var nrm: Vector3 = hit.normal
			nrm.y = 0.0
			nrm = nrm.normalized()
			var tangent := nrm.cross(Vector3.UP)
			if _avoid_t > 0.0 and tangent.dot(_avoid_dir) < 0.0:
				tangent = -tangent
			elif _avoid_t <= 0.0 and tangent.dot(dir) < 0.0:
				tangent = -tangent
			_avoid_dir = (tangent + nrm * 0.25).normalized()
			_avoid_t = 0.7
	if _avoid_t > 0.0:
		_avoid_t -= dt
		dir = _avoid_dir
	_face_dir(dir, dt)
	var align := clampf(facing.dot(dir), 0.0, 1.0)
	var want := spd * lerpf(0.15, 1.0, align) * clampf(d / 0.5, 0.35, 1.0)
	_speed_now = move_toward(_speed_now, want, dt * 5.0)
	var step := dir * _speed_now * dt
	global_position += Vector3(step.x, 0.0, step.z)
	# stuck: give up on this waypoint / target after a while
	_stuck_t += dt
	if _stuck_t > 2.5:
		if global_position.distance_to(_stuck_pos) < 0.3:
			_stuck_t = 0.0
			_stuck_pos = global_position
			_avoid_t = 0.0
			return true
		_stuck_t = 0.0
		_stuck_pos = global_position
	return false


# ------------------------------------------------------------------ perception
func _perceive(pl: Player, dt: float) -> void:
	sees_player = false
	if not pl.alive:
		awareness = maxf(0.0, awareness - dt / forget_time)
		_update_alert(pl)
		return
	var eye := global_position + Vector3.UP * _eye_h
	var tgt := pl.global_position + Vector3.UP * (0.6 if pl.crouching else 1.1)
	var to := tgt - eye
	var dist := to.length()
	var vis: float = pl.visibility
	var reach := vision_range * lerpf(0.35, 1.0, vis)
	if dist < reach:
		var flat := Vector3(to.x, 0.0, to.z)
		var in_cone := dist < 1.4
		if not in_cone and flat.length_squared() > 0.0001:
			in_cone = facing.dot(flat.normalized()) > cos(deg_to_rad(vision_half_angle))
		if in_cone:
			var q := PhysicsRayQueryParameters3D.create(eye, tgt, 1, [body.get_rid()])
			sees_player = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if sees_player:
		var gain := dt / notice_time * vis * lerpf(2.0, 0.4, clampf(dist / reach, 0.0, 1.0))
		if alert == "alert":
			gain *= 2.0
		awareness = minf(1.0, awareness + gain)
		last_known = pl.global_position
	else:
		var hr: float = hearing_radius * pl.noise
		if pl.noise > 0.05 and dist < hr:
			if awareness < 0.7:
				awareness = minf(0.7, awareness + dt * 0.6 * pl.noise * (1.0 - dist / hr))
			last_known = pl.global_position
		else:
			awareness = maxf(0.0, awareness - dt / forget_time)
	# keep a little room between neighbours
	for other in get_tree().get_nodes_in_group("npc"):
		if other == self:
			continue
		var off: Vector3 = global_position - (other as Node3D).global_position
		off.y = 0.0
		var d2 := off.length_squared()
		if d2 < 0.36 and d2 > 0.0001:
			_push += off.normalized() * 0.5
	_update_alert(pl)


func _update_alert(pl: Player) -> void:
	match alert:
		"calm":
			if awareness >= NOTICE_AT:
				alert = "suspicious"
				_noticed_once = true
				noticed.emit(pl)
				if awareness >= 1.0:
					alert = "alert"
					alerted.emit(pl)
		"suspicious":
			if awareness >= 1.0:
				alert = "alert"
				alerted.emit(pl)
			elif awareness <= 0.02:
				alert = "calm"
				lost.emit(pl)
		"alert":
			if awareness <= 0.02:
				alert = "calm"
				lost.emit(pl)


# ------------------------------------------------------------------- animation
func _animate(dt: float, spd: float, mode: String, pl: Player) -> void:
	# distance throttling: far people animate at a fraction of the rate
	_anim_acc += dt
	_anim_frame += 1
	var every := 1
	var cam := get_viewport().get_camera_3d()
	var ref := cam.global_position if cam else (pl.global_position if pl else global_position)
	var d2 := ref.distance_squared_to(global_position)
	if d2 > 80.0 * 80.0:
		every = 8
	elif d2 > 35.0 * 35.0:
		every = 3
	if _anim_frame % every != 0:
		return
	var adt := _anim_acc
	_anim_acc = 0.0
	# the rig's stride is tuned for a running player; scale walking pace so feet do not skate
	rig.animate(adt, spd * lerpf(2.0, 1.3, clampf((spd - 1.3) / 2.3, 0.0, 1.0)), mode)
	# head: watch the player when aware, otherwise glance around now and then
	var want_yaw := 0.0
	if alert != "calm" and pl:
		var to := (pl.global_position if sees_player else last_known) - global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			var a := atan2(-to.x, -to.z)
			want_yaw = clampf(wrapf(a - rotation.y, -PI, PI), -1.1, 1.1)
	else:
		_look_t -= adt
		if _look_t <= 0.0:
			_look_t = _rng.randf_range(2.0, 6.0)
			_look_yaw = _rng.randf_range(-0.6, 0.6) if spd < 0.1 and mode == "walk" else _rng.randf_range(-0.2, 0.2)
		want_yaw = _look_yaw
	rig.head.rotation.y = lerp_angle(rig.head.rotation.y, want_yaw, 1.0 - exp(-adt * 5.0))
