class_name Player extends CharacterBody3D
## Third-person controller: run, sprint, jump, ledge mantle, climb surfaces,
## crouch, slide, wade/swim, interact, carry and throw.
## Reads a PlayerInput, so humans and the AutoPilot share this code.

signal died(cause: String)
signal landed(fall_speed: float)
signal footstep(wet: bool)
signal state_changed(new_state: int)

enum State { GROUND, AIR, CLIMB, MANTLE, SLIDE, SWIM }

const SPEED_RUN := 5.0
const SPEED_SPRINT := 7.6
const SPEED_CROUCH := 2.3
const SPEED_SWIM := 2.8
const SPEED_CLIMB := 2.6
const JUMP_V := 5.6
const GRAVITY := 16.0
const STAND_H := 1.8
const CROUCH_H := 1.05
const RADIUS := 0.34

var input := PlayerInput.new()
var era: Node
var camera_rig: Node3D
var rig: Humanoid
var state: int = State.AIR
var crouching := false
var is_sprinting := false
var gravity_scale := 1.0
var speed_scale := 1.0
var sprint_allowed := true
var control_locked := false
var alive := true
var noise := 0.0              ## 0..1 loudness right now (stealth systems read this)
var visibility := 1.0         ## 0..1 how exposed the player is (cover zones lower it)
var cover_count := 0
var water_depth := 0.0        ## metres of water above the feet
var carried: Node3D
var focus: Node               ## interactable currently in reach
var facing := Vector3.FORWARD
var climb_areas: Array = []
var stamina := 1.0
var stamina_enabled := false
var fall_kill_speed := 26.0
var invulnerable := false     ## capture flythroughs: hazards cannot kill
var distance_travelled := 0.0
var counters := {"jump": 0, "mantle": 0, "slide": 0, "climb": 0, "swim": 0, "crouch": 0, "throw": 0, "sprint": 0}

var _col: CollisionShape3D
var _capsule: CapsuleShape3D
var _carry_point: Node3D
var _coyote := 0.0
var _prev_crouch := false
var _slide_t := 0.0
var _slide_dir := Vector3.ZERO
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_t := 0.0
var _climb_cooldown := 0.0
var _step_acc := 0.0
var _air_peak_fall := 0.0
var _noise_bump := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(52.0)
	safe_margin = 0.02
	add_to_group("player")
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_capsule.height = STAND_H
	_col = CollisionShape3D.new()
	_col.shape = _capsule
	_col.position.y = STAND_H * 0.5
	add_child(_col)
	rig = Humanoid.create({
		"skin": Color(0.6, 0.44, 0.34), "top": ["wool_boucle", Color(0.34, 0.3, 0.27)],
		"bottom": ["denim_fabric", Color(0.5, 0.48, 0.46)], "cloak": ["rough_linen", Color(0.36, 0.29, 0.2)],
		"head": "hood", "device": true, "shoe": Color(0.2, 0.15, 0.12)})
	add_child(rig)
	_carry_point = Node3D.new()
	_carry_point.position = Vector3(0, 1.15, -0.55)
	rig.add_child(_carry_point)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	input.poll()
	var wish := _wish_dir()
	_update_water()
	_climb_cooldown = maxf(0.0, _climb_cooldown - delta)
	var before := global_position
	match state:
		State.GROUND: _ground(delta, wish)
		State.AIR: _air(delta, wish)
		State.CLIMB: _climb(delta, wish)
		State.MANTLE: _mantle(delta)
		State.SLIDE: _slide(delta)
		State.SWIM: _swim(delta, wish)
	var moved := global_position - before
	moved.y = 0.0
	distance_travelled += moved.length()
	_interact_update()
	_update_noise(delta)
	_animate(delta, moved.length() / maxf(delta, 0.0001))
	if stamina_enabled:
		if is_sprinting:
			stamina = maxf(0.0, stamina - delta * 0.16)
		else:
			stamina = minf(1.0, stamina + delta * 0.07)
	if global_position.y < -200.0:
		kill("void")


# ------------------------------------------------------------------ states
func _wish_dir() -> Vector3:
	if control_locked:
		return Vector3.ZERO
	if input.use_world:
		var w := input.world_move
		w.y = 0.0
		return w.limit_length(1.0)
	var m := input.move
	if m.length_squared() < 0.0004:
		return Vector3.ZERO
	var yaw: float = camera_rig.yaw if camera_rig else 0.0
	return (Basis(Vector3.UP, yaw) * Vector3(m.x, 0.0, -m.y)).limit_length(1.0)


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	match s:
		State.CLIMB: counters.climb += 1
		State.SWIM: counters.swim += 1
		State.SLIDE: counters.slide += 1
		State.MANTLE: counters.mantle += 1
	state_changed.emit(s)


func _ground(delta: float, wish: Vector3) -> void:
	var want_crouch := input.crouch and not control_locked
	if crouching and not want_crouch and not _can_stand():
		want_crouch = true
	var was_sprinting := is_sprinting
	_set_crouch(want_crouch)
	is_sprinting = (input.sprint and not crouching and sprint_allowed and wish.length() > 0.1
		and water_depth < 0.7 and carried == null and (not stamina_enabled or stamina > 0.03))
	if is_sprinting and not was_sprinting:
		counters.sprint += 1
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if input.crouch and not _prev_crouch and was_sprinting and hspeed > 5.5:
		_slide_t = 0.85
		_slide_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		_prev_crouch = true
		_set_state(State.SLIDE)
		return
	_prev_crouch = input.crouch
	var speed := SPEED_RUN
	if is_sprinting:
		speed = SPEED_SPRINT
	elif crouching:
		speed = SPEED_CROUCH
	speed *= speed_scale * lerpf(1.0, 0.55, clampf(water_depth / 1.2, 0.0, 1.0))
	if carried:
		speed *= 0.85
	var target := wish * speed
	var accel := 14.0 if wish.length() > 0.05 else 18.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * maxf(speed, 3.0) * 0.5)
	velocity.z = move_toward(velocity.z, target.z, accel * delta * maxf(speed, 3.0) * 0.5)
	if wish.length() > 0.1:
		facing = wish.normalized()
	if is_on_floor():
		_coyote = 0.12
		velocity.y = -1.0
	else:
		_coyote -= delta
		velocity.y -= GRAVITY * gravity_scale * delta
	if input.jump and _coyote > 0.0 and not control_locked:
		if not _try_mantle():
			velocity.y = JUMP_V
			counters.jump += 1
			_coyote = 0.0
			_set_crouch(false)
			_air_peak_fall = 0.0
			_set_state(State.AIR)
	move_and_slide()
	if state == State.GROUND:
		if not is_on_floor() and _coyote <= 0.0:
			_air_peak_fall = 0.0
			_set_state(State.AIR)
		elif water_depth > 1.3:
			_enter_swim()
		elif _wants_climb(wish):
			_set_state(State.CLIMB)
	# footsteps
	if is_on_floor() and hspeed > 0.8:
		_step_acc += hspeed * delta
		if _step_acc > (2.6 if is_sprinting else 1.9):
			_step_acc = 0.0
			footstep.emit(water_depth > 0.1)


func _air(delta: float, wish: Vector3) -> void:
	velocity.y -= GRAVITY * gravity_scale * delta
	_air_peak_fall = maxf(_air_peak_fall, -velocity.y)
	var target := wish * SPEED_RUN * speed_scale
	if wish.length() > 0.05:
		velocity.x = move_toward(velocity.x, target.x, 9.0 * delta)
		velocity.z = move_toward(velocity.z, target.z, 9.0 * delta)
		facing = wish.normalized()
	move_and_slide()
	if is_on_floor():
		landed.emit(_air_peak_fall)
		_noise_bump = maxf(_noise_bump, clampf(_air_peak_fall / 9.0, 0.3, 1.0))
		if _air_peak_fall > fall_kill_speed and water_depth < 0.8:
			kill("fall")
			return
		_set_state(State.GROUND)
	elif water_depth > 1.3:
		_enter_swim()
	elif _wants_climb(wish):
		_set_state(State.CLIMB)
	elif wish.length() > 0.3 and velocity.y < 2.5:
		_try_mantle()


func _enter_swim() -> void:
	_set_crouch(false)
	_set_state(State.SWIM)


func _swim(delta: float, wish: Vector3) -> void:
	var water_y := global_position.y + water_depth
	var float_y := water_y - 1.3
	velocity.y = clampf((float_y - global_position.y) * 4.0, -3.0, 2.5)
	var speed := SPEED_SWIM * speed_scale * (1.3 if input.sprint else 1.0)
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, 6.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 6.0 * delta)
	if wish.length() > 0.1:
		facing = wish.normalized()
	is_sprinting = false
	move_and_slide()
	if water_depth < 1.05:
		_set_state(State.GROUND if is_on_floor() else State.AIR)
	elif _wants_climb(wish):
		_set_state(State.CLIMB)
	elif wish.length() > 0.3:
		if not _try_mantle():
			_try_bank_exit()


## Swimming into a steep bank: haul out onto the nearest standable ground ahead.
func _try_bank_exit() -> bool:
	if get_real_velocity().length() > 0.8:
		return false
	var fwd := facing
	fwd.y = 0.0
	fwd = fwd.normalized()
	var water_y := global_position.y + water_depth
	for dist in [0.8, 1.3, 1.9]:
		var probe: Vector3 = global_position + fwd * dist
		probe.y = water_y + 2.2
		var top := _ray(probe, probe + Vector3.DOWN * 3.6)
		if top.is_empty() or top.normal.y < 0.6:
			continue
		if top.position.y < water_y - 0.9 or top.position.y > water_y + 1.6:
			continue
		_start_mantle(top.position)
		return true
	return false


func _slide(delta: float) -> void:
	_slide_t -= delta
	_set_crouch(true)
	var sp := lerpf(4.0, 9.5, clampf(_slide_t / 0.85, 0.0, 1.0)) * speed_scale
	velocity.x = _slide_dir.x * sp
	velocity.z = _slide_dir.z * sp
	velocity.y = -1.0 if is_on_floor() else velocity.y - GRAVITY * gravity_scale * delta
	facing = _slide_dir
	move_and_slide()
	if _slide_t <= 0.0 or get_real_velocity().length() < 1.0:
		_set_state(State.GROUND)


func _wants_climb(wish: Vector3) -> bool:
	if _climb_cooldown > 0.0 or control_locked or carried != null:
		return false
	var a := _active_climb()
	if a == null:
		return false
	if input.use_world and input.climb_axis > 0.1:
		return true
	return wish.dot(-a.normal()) > 0.45 and global_position.y < a.top_y() - 0.3


func _active_climb() -> ClimbSurface:
	for i in range(climb_areas.size() - 1, -1, -1):
		var a: Variant = climb_areas[i]
		if not is_instance_valid(a) or not a.enabled:
			climb_areas.remove_at(i)
			continue
		return a
	return null


func _climb(delta: float, wish: Vector3) -> void:
	var area := _active_climb()
	if area == null:
		_set_state(State.AIR)
		return
	_set_crouch(false)
	is_sprinting = false
	var n := area.normal()
	var axis: float
	var lat := 0.0
	var side := Vector3.UP.cross(n).normalized()
	if input.use_world:
		axis = input.climb_axis if absf(input.climb_axis) > 0.01 else wish.dot(-n)
		lat = wish.dot(side)
	else:
		axis = input.move.y
		lat = wish.dot(side)
	if control_locked:
		axis = 0.0
		lat = 0.0
	velocity = Vector3.UP * axis * SPEED_CLIMB * speed_scale + side * lat * 1.6 - n * 1.2
	facing = -n
	move_and_slide()
	if input.jump and not control_locked:
		velocity = n * 4.0 + Vector3.UP * 4.0
		_climb_cooldown = 0.5
		_air_peak_fall = 0.0
		_set_state(State.AIR)
	elif global_position.y > area.top_y() - 0.25 and axis > 0.0:
		if area.exit_top:
			var to := global_position - n * 1.0
			to.y = area.top_y() + 0.05
			_start_mantle(to)
		else:
			velocity.y = 0.0
	elif axis < -0.1 and is_on_floor():
		_climb_cooldown = 0.3
		_set_state(State.GROUND)


func _try_mantle() -> bool:
	if control_locked or carried != null:
		return false
	var fwd := facing
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		return false
	fwd = fwd.normalized()
	var from := global_position + Vector3.UP * 0.9
	var hit := _ray(from, from + fwd * 0.75)
	if hit.is_empty():
		from = global_position + Vector3.UP * 0.35
		hit = _ray(from, from + fwd * 0.75)
		if hit.is_empty():
			return false
	if hit.normal.y > 0.35:
		return false
	var probe: Vector3 = hit.position + fwd * 0.35
	probe.y = global_position.y + 2.7
	var top := _ray(probe, probe + Vector3.DOWN * 2.6)
	if top.is_empty() or top.normal.y < 0.7:
		return false
	var h: float = top.position.y - global_position.y
	if h < 0.45 or h > 2.45:
		return false
	# room to stand?
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule
	q.transform = Transform3D(Basis.IDENTITY, top.position + Vector3.UP * (STAND_H * 0.5 + 0.1))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
		return false
	_start_mantle(top.position)
	return true


func _start_mantle(to: Vector3) -> void:
	_mantle_from = global_position
	_mantle_to = to
	_mantle_t = 0.0
	velocity = Vector3.ZERO
	_set_crouch(false)
	_set_state(State.MANTLE)


func _mantle(delta: float) -> void:
	_mantle_t += delta / 0.5
	var t := clampf(_mantle_t, 0.0, 1.0)
	var up_t := smoothstep(0.0, 0.7, t)
	var fw_t := smoothstep(0.45, 1.0, t)
	var p := _mantle_from.lerp(_mantle_to, fw_t)
	p.y = lerpf(_mantle_from.y, _mantle_to.y + 0.05, up_t)
	global_position = p
	velocity = Vector3.ZERO
	if t >= 1.0:
		_coyote = 0.1
		_set_state(State.GROUND)


# ------------------------------------------------------------------ helpers
func _ray(from: Vector3, to: Vector3, mask := 1) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)


func _can_stand() -> bool:
	var from := global_position + Vector3.UP * (CROUCH_H - 0.1)
	return _ray(from, global_position + Vector3.UP * (STAND_H + 0.05)).is_empty()


func _set_crouch(on: bool) -> void:
	if on == crouching:
		return
	crouching = on
	if on:
		counters.crouch += 1
	var h := CROUCH_H if on else STAND_H
	_capsule.height = h
	_col.position.y = h * 0.5


func _update_water() -> void:
	water_depth = 0.0
	if era and era.has_method("water_height_at"):
		water_depth = maxf(0.0, era.water_height_at(global_position) - global_position.y)


func _update_noise(delta: float) -> void:
	var target := 0.0
	var hs := Vector2(velocity.x, velocity.z).length()
	match state:
		State.GROUND:
			if hs > 0.5:
				target = 0.1 if crouching else (1.0 if is_sprinting else 0.5)
			if water_depth > 0.25:
				target *= 0.5
		State.SLIDE: target = 0.7
		State.SWIM: target = 0.25 if hs > 0.5 else 0.05
		State.CLIMB: target = 0.15
		State.AIR: target = 0.1
	_noise_bump = move_toward(_noise_bump, 0.0, delta * 1.5)
	noise = maxf(move_toward(noise, target, delta * 3.0), _noise_bump)
	visibility = (0.45 if crouching else 1.0) * (0.3 if cover_count > 0 else 1.0)


## One-off loud event (landing, shouting device, thrown object).
func bump_noise(loudness: float) -> void:
	_noise_bump = maxf(_noise_bump, loudness)


func _animate(delta: float, speed: float) -> void:
	if rig == null:
		return
	var yaw := atan2(-facing.x, -facing.z)
	rig.rotation.y = lerp_angle(rig.rotation.y, yaw, 1.0 - exp(-delta * 12.0))
	var mode := "walk"
	var cs := 0.0
	match state:
		State.SWIM: mode = "swim"
		State.CLIMB, State.MANTLE:
			mode = "climb"
			cs = absf(velocity.y) + 1.0 * float(state == State.MANTLE)
		State.SLIDE: mode = "crouch"
		_:
			if crouching:
				mode = "crouch"
			elif carried:
				mode = "carry"
	rig.animate(delta, speed, mode, cs)
	rig.rotation.x = lerp_angle(rig.rotation.x, -0.9 if state == State.SLIDE else 0.0, 1.0 - exp(-delta * 10.0))


# -------------------------------------------------------- interact / carry
func _interact_update() -> void:
	focus = null
	if control_locked:
		return
	var best := 1e9
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it == null or not it.enabled or not it.is_inside_tree():
			continue
		if carried and it.get_parent() == carried:
			continue
		var d := it.global_position.distance_to(global_position + Vector3.UP * 0.9)
		if d < it.radius and d < best:
			best = d
			focus = it
	if input.interact:
		if focus:
			(focus as Interactable).interact(self)
		elif carried:
			drop()
	if input.throw and carried:
		throw_carried()


func pick_up(c: Node3D) -> void:
	if carried:
		drop()
	carried = c
	if c is RigidBody3D:
		(c as RigidBody3D).freeze = true
		(c as RigidBody3D).collision_layer = 0
		(c as RigidBody3D).collision_mask = 0
	c.reparent(_carry_point, false)
	c.transform = Transform3D.IDENTITY
	if c.has_signal("picked"):
		c.emit_signal("picked", self)


func drop() -> Node3D:
	return _release(Vector3.ZERO)


func throw_carried() -> Node3D:
	counters["throw"] += 1
	return _release(facing * 9.0 + Vector3.UP * 4.0)


func _release(impulse: Vector3) -> Node3D:
	if carried == null:
		return null
	var c := carried
	carried = null
	var gp := c.global_position
	var parent: Node = era if era else get_parent()
	c.reparent(parent, false)
	c.global_position = gp + facing * 0.2
	if c is RigidBody3D:
		var rb := c as RigidBody3D
		rb.collision_layer = 16
		rb.collision_mask = 1 | 4
		rb.freeze = false
		rb.linear_velocity = impulse + Vector3(velocity.x, 0, velocity.z) * 0.5
	if impulse != Vector3.ZERO and c.has_signal("thrown"):
		c.emit_signal("thrown", self)
	elif c.has_signal("dropped"):
		c.emit_signal("dropped", self)
	return c


# ------------------------------------------------------------ life / rewind
func kill(cause: String) -> void:
	if not alive or invulnerable:
		return
	alive = false
	velocity = Vector3.ZERO
	died.emit(cause)


func revive(pos: Vector3) -> void:
	alive = true
	teleport(pos)


func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_air_peak_fall = 0.0
	_set_crouch(false)
	state = State.AIR
	reset_physics_interpolation()


## Shove the player (creature bumps, waves, explosions).
func knockback(v: Vector3) -> void:
	if not alive or state == State.MANTLE:
		return
	velocity = v
	_air_peak_fall = 0.0
	_set_crouch(false)
	_coyote = 0.0
	_set_state(State.AIR)


func snapshot() -> Dictionary:
	return {"pos": global_position, "vel": velocity, "facing": facing}


func restore(s: Dictionary) -> void:
	teleport(s.pos)
	facing = s.facing


func eye_position() -> Vector3:
	return global_position + Vector3.UP * (0.95 if crouching else 1.6)


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func state_name() -> String:
	return State.keys()[state]
