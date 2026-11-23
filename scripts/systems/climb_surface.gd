class_name ClimbSurface extends Area3D
## A climbable face (vines, rough rock, carved stone, rigging).
## Local +Z points away from the wall. The player climbs while inside the box.

var size := Vector3(2, 4, 1)
var exit_top := true
var enabled := true


## `face_center` is the middle of the wall face; the box sticks out `depth` from it.
static func make(parent: Node, face_center: Vector3, width: float, height: float, rot_y := 0.0, top_exit := true, depth := 1.0) -> ClimbSurface:
	var a := ClimbSurface.new()
	a.size = Vector3(width, height, depth)
	a.exit_top = top_exit
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitorable = false
	var cs := CollisionShape3D.new()
	cs.shape = MeshKit.box_shape(a.size)
	a.add_child(cs)
	a.rotation.y = rot_y
	a.position = face_center + Basis(Vector3.UP, rot_y) * Vector3(0, 0, depth * 0.5)
	parent.add_child(a)
	a.body_entered.connect(a._on_enter)
	a.body_exited.connect(a._on_exit)
	return a


func normal() -> Vector3:
	return global_basis.z.normalized()


func top_y() -> float:
	return global_position.y + size.y * 0.5


func _on_enter(b: Node) -> void:
	if b is Player and not (b as Player).climb_areas.has(self):
		(b as Player).climb_areas.append(self)


func _on_exit(b: Node) -> void:
	if b is Player:
		(b as Player).climb_areas.erase(self)
