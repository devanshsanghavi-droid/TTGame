class_name CoverZone extends Area3D
## Volume that hides the player (tall ferns, canopy shade, crowds, reeds).

static func make(parent: Node, pos: Vector3, size: Vector3, rot_y := 0.0) -> CoverZone:
	var a := CoverZone.new()
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitorable = false
	var cs := CollisionShape3D.new()
	cs.shape = MeshKit.box_shape(size)
	a.add_child(cs)
	a.position = pos
	a.rotation.y = rot_y
	parent.add_child(a)
	a.body_entered.connect(func(b: Node) -> void:
		if b is Player:
			(b as Player).cover_count += 1)
	a.body_exited.connect(func(b: Node) -> void:
		if b is Player:
			(b as Player).cover_count = maxi(0, (b as Player).cover_count - 1))
	return a
