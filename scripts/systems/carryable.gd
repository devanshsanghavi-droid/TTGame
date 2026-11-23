class_name Carryable extends RigidBody3D
## Physics object the player can pick up, carry and throw.

signal picked(player: Player)
signal thrown(player: Player)
signal dropped(player: Player)
signal impact(pos: Vector3, speed: float)

var kind := "rock"
var handle: Interactable
var _armed := false


static func make(parent: Node, pos: Vector3, item_kind: String, visual: Node3D, radius := 0.22, weight := 4.0) -> Carryable:
	var c := Carryable.new()
	c.kind = item_kind
	c.mass = weight
	c.collision_layer = 16
	c.collision_mask = 1 | 4
	c.contact_monitor = true
	c.max_contacts_reported = 2
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	c.add_child(cs)
	c.add_child(visual)
	c.position = pos
	parent.add_child(c)
	c.handle = Interactable.make(c, Vector3.ZERO, "Pick up " + item_kind, func(p: Player) -> void: p.pick_up(c), 2.0)
	c.thrown.connect(func(p: Player) -> void:
		c._armed = true
		Telemetry.log_event("carry_throw", {"item": c.kind, "from": c.global_position, "vel": c.linear_velocity, "facing": p.facing}))
	c.body_entered.connect(c._on_hit)
	return c


func _on_hit(body: Node) -> void:
	if _armed:
		_armed = false
		Telemetry.log_event("carry_impact", {"item": kind, "pos": global_position, "body": String(body.name), "speed": linear_velocity.length()})
		impact.emit(global_position, linear_velocity.length())
