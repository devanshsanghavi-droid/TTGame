class_name CameraRig extends Node3D
## Third-person camera: mouse / right stick orbit, spring-arm collision, lock-on.

var target: Player
var yaw := 0.0
var pitch := -0.22
var distance := 4.8
var cam: Camera3D
var arm: SpringArm3D
var lock_target: Node3D
var shake := 0.0
var fov_base := 68.0

var _shake_t := 0.0


func _ready() -> void:
	top_level = true
	arm = SpringArm3D.new()
	arm.spring_length = distance
	arm.margin = 0.25
	arm.collision_mask = 1
	var s := SphereShape3D.new()
	s.radius = 0.22
	arm.shape = s
	add_child(arm)
	cam = Camera3D.new()
	cam.fov = fov_base
	cam.near = 0.12
	cam.far = 3000.0
	arm.add_child(cam)
	if target:
		arm.add_excluded_object(target.get_rid())
		global_position = target.global_position + Vector3.UP * 1.5


func make_current() -> void:
	cam.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = 0.0026 * Game.settings.sensitivity
		yaw -= event.relative.x * sens
		var dy: float = event.relative.y * sens
		pitch -= -dy if Game.settings.invert_y else dy
		pitch = clampf(pitch, -1.25, 0.7)
		if lock_target and absf(event.relative.x) > 60.0:
			lock_target = null


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var look := target.input.look
	if look != Vector2.ZERO and not target.input.bot:
		yaw -= look.x * delta * 2.6 * Game.settings.sensitivity
		pitch = clampf(pitch - look.y * delta * 1.8 * Game.settings.sensitivity, -1.25, 0.7)
	if target.input.lock_on:
		toggle_lock()
	if lock_target and is_instance_valid(lock_target):
		var to := lock_target.global_position - target.global_position
		if to.length() > 45.0:
			lock_target = null
		else:
			var want := atan2(-to.x, -to.z)
			yaw = lerp_angle(yaw, want, 1.0 - exp(-delta * 6.0))
			pitch = lerpf(pitch, clampf(-0.2 + atan2(to.y, Vector2(to.x, to.z).length()) * 0.5, -0.8, 0.4), 1.0 - exp(-delta * 4.0))
	elif target.input.bot:
		# bots: drift behind the direction of travel so captures read well
		var f := target.facing
		yaw = lerp_angle(yaw, atan2(-f.x, -f.z), 1.0 - exp(-delta * 1.5))
	var pivot := target.global_position + Vector3.UP * (1.05 if target.crouching else 1.55)
	global_position = global_position.lerp(pivot, 1.0 - exp(-delta * 16.0))
	rotation = Vector3(pitch, yaw, 0.0)
	arm.spring_length = lerpf(arm.spring_length, distance * (0.8 if target.crouching else 1.0), 1.0 - exp(-delta * 5.0))
	# never render the inside of the player's head when the arm is squeezed short
	if target.rig:
		target.rig.visible = cam.global_position.distance_to(pivot) > 0.85 or not cam.current
	var sprint_fov := 6.0 if target.is_sprinting else 0.0
	cam.fov = lerpf(cam.fov, fov_base + sprint_fov, 1.0 - exp(-delta * 5.0))
	if shake > 0.001:
		_shake_t += delta * 40.0
		cam.h_offset = sin(_shake_t * 1.3) * shake * 0.12
		cam.v_offset = cos(_shake_t * 1.7) * shake * 0.12
		shake = move_toward(shake, 0.0, delta * 1.5)
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


func add_shake(amount: float) -> void:
	shake = clampf(shake + amount, 0.0, 2.0)


func toggle_lock() -> void:
	if lock_target:
		lock_target = null
		return
	var best: Node3D = null
	var best_score := 1e9
	var fwd := -global_basis.z
	for n in get_tree().get_nodes_in_group("lock_target"):
		var n3 := n as Node3D
		if n3 == null or not n3.is_visible_in_tree():
			continue
		var to := n3.global_position - target.global_position
		var d := to.length()
		if d > 40.0 or d < 0.5:
			continue
		var ang := fwd.angle_to(to.normalized())
		if ang > 1.1:
			continue
		var score := d * (0.4 + ang)
		if score < best_score:
			best_score = score
			best = n3
	lock_target = best


func forward_flat() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3.FORWARD
