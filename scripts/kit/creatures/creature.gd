class_name Creature extends Node3D
## Base for every CreatureKit animal: steering along waypoints, ground snapping,
## world-time, solid body, telemetry, hearing hook, LOD. Faces -Z, feet at y = 0.
##
##   var m := CreatureKit.make("mammoth", {"era": self, "seed": 3})
##   add_child(m); m.global_position = on_ground(40, -20)
##   m.set_path([on_ground(40, -20), on_ground(10, -60)], true)
##   m.footfall.connect(func(pos, weight): camera_rig.add_shake(weight * 0.2))

signal footfall(pos: Vector3, weight: float)     ## a foot (or the body) hit the ground
signal arrived(pos: Vector3)                     ## move_to / non-looping path finished
signal heard(pos: Vector3, loudness: float, source: String)

var kind := ""
var era: Node                      ## optional EraBase: wdelta() + ground_y()
var ground := Callable()           ## (x, z) -> y. Defaults to era.ground_y
var speed := 1.0                   ## cruise speed, m/s
var turn_rate := 0.6               ## rad/s
var accel := 1.0                   ## m/s^2
var auto_tick := true              ## false: the owner calls tick(delta) itself
var size_scale := 1.0
var weight := 0.5                  ## 0..1, passed with footfall (camera shake / sound)
var cur_speed := 0.0
var heading := 0.0
var state := "idle"                ## "idle" | "path" | "goto"
var body: AnimatableBody3D
var look_target: Variant = null    ## Node3D, Vector3 or null
var reacts_to_noise := false
var anim_distance := 260.0         ## beyond this (or off screen) animation is skipped
var lod_near := 70.0               ## beyond this animation runs at half rate
var arrive_radius := 1.0
var cfg := {}

var _path: Array[Vector3] = []
var _path_i := 0
var _loop := false
var _frame := 0
var _lod := 0
var _notifier: VisibleOnScreenNotifier3D
var _noise_t := 0.0
var _noise_prev: Variant = null
var _yaw_rate := 0.0

static var _headless := -1


func _ready() -> void:
	add_to_group("telemetry_ai")
	add_to_group("creature")
	if reacts_to_noise:
		add_to_group("hearing")
	heading = rotation.y
	_frame = randi() % 8
	if body:
		_enable_body()


func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(era.wdelta(delta) if era and era.has_method("wdelta") else delta)


## Advances the creature by `delta` seconds of world time.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_frame += 1
	if _noise_t > 0.0:
		_noise_t -= delta
		if _noise_t <= 0.0:
			look_target = _noise_prev
	_steer(delta)
	_update_lod()
	_animate(delta)


# ----------------------------------------------------------------- movement
## Walk (or fly) through `points`; with `loop` the path repeats forever.
func set_path(points: Array, loop := true) -> void:
	_path.clear()
	for p in points:
		_path.append(p)
	_path_i = 0
	_loop = loop
	state = "path" if _path.size() > 0 else "idle"


func move_to(pos: Vector3) -> void:
	_path.clear()
	_path.append(pos)
	_path_i = 0
	_loop = false
	state = "goto"


func stop() -> void:
	_path.clear()
	state = "idle"


func is_moving() -> bool:
	return state != "idle"


## Head / eyes follow a Node3D or a Vector3; null releases.
func look_at_target(target: Variant) -> void:
	look_target = target
	_noise_t = 0.0


func look_pos() -> Variant:
	if look_target is Vector3:
		return look_target
	if look_target is Node3D and is_instance_valid(look_target):
		return (look_target as Node3D).global_position + Vector3.UP * 1.2
	return null


## Hearing hook (group "hearing" when reacts_to_noise): glance at the sound for a while.
func hear(pos: Vector3, loudness: float, source: String) -> void:
	heard.emit(pos, loudness, source)
	if reacts_to_noise and loudness > 0.2:
		if _noise_t <= 0.0:
			_noise_prev = look_target
		look_target = pos
		_noise_t = 4.0


func ground_at(x: float, z: float) -> float:
	if ground.is_valid():
		return ground.call(x, z)
	if era and era.has_method("ground_y"):
		return era.ground_y(x, z)
	return global_position.y


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func _steer(delta: float) -> void:
	var target_speed := 0.0
	_yaw_rate = 0.0
	if state != "idle" and _path_i < _path.size():
		var wp := _path[_path_i]
		var to := Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
		var d := to.length()
		if d < arrive_radius:
			_path_i += 1
			if _path_i >= _path.size():
				if _loop and _path.size() > 1:
					_path_i = 0
				else:
					var at := _path[_path.size() - 1]
					stop()
					arrived.emit(at)
		else:
			var want := atan2(-to.x, -to.z)
			var diff := wrapf(want - heading, -PI, PI)
			var step := clampf(diff, -turn_rate * delta, turn_rate * delta)
			heading = wrapf(heading + step, -PI, PI)
			_yaw_rate = step / delta
			target_speed = speed * clampf(1.15 - absf(diff) / 1.1, 0.22, 1.0)
			if not _loop and _path_i == _path.size() - 1:
				target_speed = minf(target_speed, maxf(d * 0.9, speed * 0.2))
	cur_speed = move_toward(cur_speed, target_speed, accel * delta)
	var p := global_position
	if cur_speed > 0.0005:
		p += forward() * cur_speed * delta
	_place(p, delta)


## Puts the root at the new position (default: glued to the ground).
func _place(p: Vector3, _delta: float) -> void:
	p.y = ground_at(p.x, p.z)
	global_position = p
	rotation.y = heading


func _animate(_delta: float) -> void:
	pass


# ---------------------------------------------------------------------- lod
func _update_lod() -> void:
	if _headless < 0:
		_headless = 1 if DisplayServer.get_name() == "headless" else 0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		_lod = 0
		return
	var d := cam.global_position.distance_to(global_position)
	var on := _headless == 1 or _notifier == null or _notifier.is_on_screen()
	var big := maxf(1.0, size_scale)
	if d > anim_distance * big or (not on and d > 35.0 * big):
		_lod = 2
	elif d > lod_near * big:
		_lod = 1
	else:
		_lod = 0


func _add_notifier(box: AABB) -> void:
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = box
	add_child(_notifier)


# --------------------------------------------------------------------- body
## Kinematic collider on layer 1 that travels with the creature. The layer is switched
## on after the era's navmesh bake so the animal does not punch a hole in it.
func _make_body(shape: Shape3D, at: Transform3D) -> void:
	body = AnimatableBody3D.new()
	body.name = "Body"
	body.sync_to_physics = false
	body.collision_layer = 0
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = at
	body.add_child(cs)
	add_child(body)


func _enable_body() -> void:
	if era and ("is_ready" in era) and not era.is_ready and era.has_signal("ready_done"):
		era.ready_done.connect(_body_on, CONNECT_ONE_SHOT)
	else:
		_body_on()


func _body_on() -> void:
	if body and is_instance_valid(body):
		body.collision_layer = 1
	for c in get_children():
		if c is AnimatableBody3D and c != body:
			(c as AnimatableBody3D).collision_layer = 1


func set_solid(on: bool) -> void:
	if body:
		body.collision_layer = 1 if on else 0


# ---------------------------------------------------------------- telemetry
func telemetry() -> Dictionary:
	return {"kind": kind, "state": state, "pos": global_position, "speed": cur_speed, "wp": _path_i, "lod": _lod}
