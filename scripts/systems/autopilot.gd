class_name AutoPilot extends Node
## Scripted bot. Drives the real Player through PlayerInput using a
## NavigationAgent3D for pathing plus per-era scripted steps.
##
## Build plans with the static helpers:
##   AutoPilot.goto(pos, {"sprint": true})      walk/run to a point
##   AutoPilot.use(node_or_callable)            walk to an Interactable and use it
##   AutoPilot.wait(seconds)
##   AutoPilot.until(callable, timeout)         stand still until callable() is true
##   AutoPilot.run(callable)                    call a function once
##   AutoPilot.press("jump")                    tap an action
##   AutoPilot.climb(target_y)                  hold "climb up" until y >= target_y
##   AutoPilot.choose(index_or_callable)        pick a dialogue choice (auto-advances lines)
##   AutoPilot.drive(func(bot, delta) -> bool)  custom per-frame control; return true when done
##   AutoPilot.label("name")                    no-op marker shown in telemetry
## Any step may carry {"skip_if": Callable}: the step is skipped when it returns true
## at the moment the step starts (use it to keep plans correct when counts vary).

signal finished
signal failed(reason: String)

var era: EraBase
var player: Player
var plan: Array = []
var index := 0
var done := false
var fail_reason := ""
var agent: NavigationAgent3D
var step_time := 0.0
var total_time := 0.0
var last_label := ""

var _started := false
var _stuck_pos := Vector3.ZERO
var _stuck_t := 0.0
var _stuck_count := 0
var _sidestep := 0.0
var _side_sign := 1.0
var _repath := 0.0
var _use_fired := false
var _use_conn: Variant = null
var _dialogue_t := 0.0
var _press_cd := 0.0
var _checked_skip := -1


# ------------------------------------------------------------ plan helpers
static func goto(pos: Variant, opts: Dictionary = {}) -> Dictionary:
	var s := {"op": "goto", "pos": pos}
	s.merge(opts)
	return s


static func use(target: Variant, opts: Dictionary = {}) -> Dictionary:
	var s := {"op": "use", "target": target}
	s.merge(opts)
	return s


static func wait(seconds: float) -> Dictionary:
	return {"op": "wait", "time": seconds}


static func until(cond: Callable, timeout := 60.0) -> Dictionary:
	return {"op": "until", "cond": cond, "timeout": timeout}


static func run(fn: Callable) -> Dictionary:
	return {"op": "run", "fn": fn}


static func press(action: String) -> Dictionary:
	return {"op": "press", "action": action}


static func climb(target_y: float, timeout := 40.0) -> Dictionary:
	return {"op": "climb", "y": target_y, "timeout": timeout}


static func choose(choice: Variant, timeout := 30.0) -> Dictionary:
	return {"op": "choose", "choice": choice, "timeout": timeout}


static func drive(fn: Callable, timeout := 60.0) -> Dictionary:
	return {"op": "drive", "fn": fn, "timeout": timeout}


static func label(text: String) -> Dictionary:
	return {"op": "label", "text": text}


# ---------------------------------------------------------------- running
func start(p_era: EraBase) -> void:
	era = p_era
	player = era.player
	plan = era.autopilot_plan()
	era.bot = self
	player.input.bot = true
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 1.2
	agent.target_desired_distance = 1.0
	agent.path_max_distance = 6.0
	agent.avoidance_enabled = false
	player.add_child(agent)
	_started = true
	Telemetry.log_event("bot_start", {"steps": plan.size()})


func telemetry() -> Dictionary:
	var op := ""
	if index < plan.size():
		op = String(plan[index].op)
	return {"step": index, "of": plan.size(), "op": op, "label": last_label, "t": step_time, "stuck": _stuck_count}


func _fail(reason: String) -> void:
	if fail_reason != "":
		return
	fail_reason = "step %d/%d (%s, after '%s'): %s" % [index, plan.size(), plan[index].op if index < plan.size() else "end", last_label, reason]
	Telemetry.log_event("bot_fail", {"reason": fail_reason, "pos": player.global_position})
	failed.emit(fail_reason)


func _next() -> void:
	index += 1
	step_time = 0.0
	_stuck_t = 0.0
	_stuck_count = 0
	_sidestep = 0.0
	_repath = 0.0
	_use_fired = false
	_use_conn = null
	if index < plan.size():
		Telemetry.log_event("bot_step", {"i": index, "op": plan[index].op})


func _physics_process(delta: float) -> void:
	if not _started or done or fail_reason != "" or era == null:
		return
	var inp := player.input
	inp.clear()
	inp.use_world = true
	total_time += delta
	if era.is_complete:
		done = true
		finished.emit()
		return
	if not player.alive:
		return
	if index >= plan.size():
		# plan exhausted but era not complete: keep idling until the time limit trips
		return
	var step: Dictionary = plan[index]
	if _checked_skip != index:
		_checked_skip = index
		if step.has("skip_if") and bool((step["skip_if"] as Callable).call()):
			_next()
			return
	step_time += delta
	_press_cd = maxf(0.0, _press_cd - delta)
	# dialogue lines without choices are advanced automatically
	if era.dialogue.active and step.op != "choose":
		_dialogue_t += delta
		if era.dialogue.choices_shown.is_empty() and _dialogue_t > 0.4:
			_dialogue_t = 0.0
			era.dialogue.advance()
		if step.op == "use" and _use_fired:
			_next()
			return
		if step.op in ["goto", "use", "climb"]:
			return
	match step.op:
		"label":
			last_label = step.text
			_next()
		"wait":
			if step_time >= float(step.time):
				_next()
		"run":
			(step.fn as Callable).call()
			_next()
		"press":
			inp.press(step.action)
			_next()
		"until":
			if bool((step.cond as Callable).call()):
				_next()
			elif step_time > float(step.timeout):
				_fail("condition never became true")
		"drive":
			if bool((step.fn as Callable).call(self, delta)):
				_next()
			elif step_time > float(step.get("timeout", 60.0)):
				_fail("drive timed out")
		"climb":
			inp.climb_axis = 1.0
			var a := player._active_climb()
			if a:
				inp.world_move = -a.normal()
			else:
				inp.world_move = player.facing
			if player.global_position.y >= float(step.y) and player.state != Player.State.CLIMB and player.state != Player.State.MANTLE:
				_next()
			elif step_time > float(step.timeout):
				_fail("climb timed out at y=%.1f (wanted %.1f)" % [player.global_position.y, float(step.y)])
		"choose":
			if era.dialogue.active:
				_dialogue_t += delta
				if _dialogue_t > 0.4:
					_dialogue_t = 0.0
					if era.dialogue.choices_shown.is_empty():
						era.dialogue.advance()
					else:
						var c: Variant = step.choice
						var i: int = int((c as Callable).call()) if c is Callable else int(c)
						era.dialogue.choose(clampi(i, 0, era.dialogue.choices_shown.size() - 1))
						_next()
			elif step_time > float(step.timeout):
				_fail("no dialogue with choices appeared")
		"goto":
			_do_goto(step, delta)
		"use":
			_do_use(step, delta)


func _resolve_pos(v: Variant) -> Variant:
	if v is Callable:
		v = (v as Callable).call()
	if v is Node3D:
		return (v as Node3D).global_position
	if v is Vector3:
		return v
	return null


func _do_goto(step: Dictionary, delta: float) -> void:
	var pos: Variant = _resolve_pos(step.pos)
	if pos == null:
		_fail("goto target is null")
		return
	if step.has("until") and bool((step["until"] as Callable).call()):
		_next()
		return
	var tol: float = step.get("tol", 1.4)
	var flat := Vector2(pos.x - player.global_position.x, pos.z - player.global_position.z)
	var dy := absf(pos.y - player.global_position.y)
	if flat.length() < tol and (dy < float(step.get("ytol", 3.0))):
		_next()
		return
	if step_time > float(step.get("timeout", 90.0)):
		_fail("goto %s timed out %.1fm away at %s" % [str(pos), flat.length(), str(player.global_position)])
		return
	_steer(pos, step, delta)


func _do_use(step: Dictionary, delta: float) -> void:
	var t: Variant = step.target
	if t is Callable:
		t = (t as Callable).call()
	var it := t as Interactable
	if it == null and t is Node:
		for c in (t as Node).get_children():
			if c is Interactable:
				it = c
				break
	if it == null or not is_instance_valid(it):
		if _use_fired or step.get("optional", false):
			_next()
		else:
			_fail("use target missing")
		return
	if _use_conn == null:
		_use_conn = it
		it.used.connect(func(_p: Player) -> void: _use_fired = true, CONNECT_ONE_SHOT)
	if _use_fired:
		_next()
		return
	if step_time > float(step.get("timeout", 90.0)):
		_fail("use '%s' timed out %.1fm away" % [it.prompt, it.global_position.distance_to(player.global_position)])
		return
	var d := it.global_position.distance_to(player.global_position + Vector3.UP * 0.9)
	if d < it.radius * 0.8 and it.enabled:
		if player.focus == it:
			if _press_cd <= 0.0:
				_press_cd = 0.35
				player.input.press("interact")
		else:
			# something else is nearer: nudge closer
			_steer(it.global_position, step, delta)
	else:
		_steer(it.global_position, step, delta)


## Steers toward `pos` using the navmesh when it has a path, otherwise directly.
func _steer(pos: Vector3, step: Dictionary, delta: float) -> void:
	var inp := player.input
	var next := pos
	if not step.get("direct", false) and player.state != Player.State.SWIM:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.75
			agent.target_position = pos
		if not agent.is_navigation_finished():
			var np := agent.get_next_path_position()
			if np.distance_to(player.global_position) > 0.2:
				next = np
	var dir := next - player.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = pos - player.global_position
		dir.y = 0.0
	dir = dir.normalized()
	# stuck handling
	_stuck_t += delta
	if _stuck_t >= 1.0:
		var moved := player.global_position.distance_to(_stuck_pos)
		_stuck_pos = player.global_position
		_stuck_t = 0.0
		if moved < 0.35 and player.state != Player.State.MANTLE:
			_stuck_count += 1
			Telemetry.log_event("bot_stuck", {"count": _stuck_count, "pos": player.global_position, "state": player.state_name()})
			inp.press("jump")
			if _stuck_count >= 2:
				_sidestep = 0.8
				_side_sign = -_side_sign
		else:
			_stuck_count = maxi(0, _stuck_count - 1)
	if _sidestep > 0.0:
		_sidestep -= delta
		dir = (dir + dir.cross(Vector3.UP) * _side_sign * 1.4).normalized()
	inp.world_move = dir
	inp.sprint = step.get("sprint", false)
	inp.crouch = step.get("crouch", false)
	if player.state == Player.State.CLIMB:
		inp.climb_axis = 1.0
	if step.get("jump_gaps", false) and player.is_on_floor():
		# hop when the ground ahead drops away
		var ahead := player.global_position + dir * 1.2 + Vector3.UP * 0.5
		var q := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 2.0, 1, [player.get_rid()])
		if player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			inp.press("jump")
