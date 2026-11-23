class_name PlayerInput extends RefCounted
## One frame of player intent. Filled by the keyboard/gamepad or by the AutoPilot,
## so the bot drives the exact same controller code a human does.

var move := Vector2.ZERO          ## x = right, y = forward, camera-relative
var world_move := Vector3.ZERO    ## used instead of `move` when use_world is true
var use_world := false
var climb_axis := 0.0             ## bots: explicit up/down on climb surfaces
var look := Vector2.ZERO
var sprint := false
var crouch := false
var jump := false
var interact := false
var throw := false
var scan := false
var rewind := false
var lock_on := false

var bot := false
var _latched := {}


func clear() -> void:
	move = Vector2.ZERO
	world_move = Vector3.ZERO
	climb_axis = 0.0
	look = Vector2.ZERO
	sprint = false
	crouch = false
	jump = false
	interact = false
	throw = false
	scan = false
	rewind = false
	lock_on = false


## Bots call press() from any frame; the press is delivered on the next poll.
func press(action: String) -> void:
	_latched[action] = true


func poll() -> void:
	if bot:
		jump = _latched.get("jump", false)
		interact = _latched.get("interact", false)
		throw = _latched.get("throw", false)
		scan = _latched.get("scan", false)
		rewind = _latched.get("rewind", false)
		lock_on = _latched.get("lock_on", false)
		_latched.clear()
		return
	use_world = false
	move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	sprint = Input.is_action_pressed("sprint")
	crouch = Input.is_action_pressed("crouch")
	jump = Input.is_action_just_pressed("jump")
	interact = Input.is_action_just_pressed("interact")
	throw = Input.is_action_just_pressed("throw")
	scan = Input.is_action_just_pressed("scan")
	rewind = Input.is_action_just_pressed("rewind")
	lock_on = Input.is_action_just_pressed("lock_on")
	look = Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() < 0.2:
		look = Vector2.ZERO
