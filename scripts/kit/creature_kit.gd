class_name CreatureKit extends RefCounted
## One call to get an animal. Every creature is a Creature (Node3D): sculpted,
## skinned, procedurally animated, with a solid body, telemetry and world-time.
##
##   var rex := CreatureKit.spawn(self, "trex", on_ground(30, -40), {"era": self, "yaw": 1.2})
##   rex.set_path([on_ground(30, -40), on_ground(-10, -60)], true)
##   rex.look_at_target(player)
##   rex.footfall.connect(func(pos, w): camera_rig.add_shake(w * 0.25 / maxf(1.0, pos.distance_to(player.global_position) * 0.08)))
##
## Kinds: mammoth, woolly_rhino, cave_bear, sauropod, elephant ({"howdah": true}),
## horse ({"saddle": true, "caparison": true, "coat": "bay"|"chestnut"|"grey"|"black"}),
## ox ({"hump": true}), trex, quetzalcoatlus, meganeura ({"count": 12, "radius": 6}),
## arthropleura.
##
## Common opts: era (EraBase: world time + ground), ground (Callable (x, z) -> y),
## scale, seed (size / tint / phase variation), speed, hears (join group "hearing"),
## yaw (spawn only).
##
## Common API (class Creature): set_path(points, loop), move_to(pos), stop(), speed,
## look_at_target(node_or_pos_or_null), tick(delta) with auto_tick = false,
## hear(pos, loudness, source), telemetry(), signals footfall(pos, weight),
## arrived(pos), heard(pos, loudness, source); `body` is the layer-1 collider.

const WALKERS := ["mammoth", "woolly_rhino", "cave_bear", "sauropod", "elephant", "horse", "ox", "trex"]
const KINDS := ["mammoth", "woolly_rhino", "cave_bear", "sauropod", "elephant", "horse", "ox", "trex", "quetzalcoatlus", "meganeura", "arthropleura"]

## Rough life-size dimensions (length, height in metres at scale 1).
const SIZES := {
	"mammoth": Vector2(7.0, 3.6), "woolly_rhino": Vector2(4.4, 1.9), "cave_bear": Vector2(3.0, 1.55),
	"sauropod": Vector2(25.0, 9.8), "elephant": Vector2(5.6, 2.9), "horse": Vector2(2.6, 2.1), "ox": Vector2(2.8, 1.55),
	"trex": Vector2(12.5, 4.9), "quetzalcoatlus": Vector2(6.0, 10.5), "meganeura": Vector2(0.45, 0.7), "arthropleura": Vector2(2.5, 0.3),
}


static func names() -> PackedStringArray:
	return PackedStringArray(KINDS)


## Builds a creature (not yet in the tree). Returns null for an unknown kind.
static func make(kind: String, opts: Dictionary = {}) -> Creature:
	if WALKERS.has(kind):
		return CreatureWalker.create(kind, opts)
	match kind:
		"quetzalcoatlus":
			return CreatureFlyer.create(opts)
		"meganeura":
			return CreatureSwarm.create(opts)
		"arthropleura":
			return CreatureCrawler.create(opts)
	push_error("CreatureKit: unknown creature '%s'" % kind)
	return null


## make() + add_child + place on the spot. opts.yaw sets the facing.
static func spawn(parent: Node, kind: String, pos: Vector3, opts: Dictionary = {}) -> Creature:
	var o := opts.duplicate()
	if not o.has("era") and parent.has_method("wdelta"):
		o["era"] = parent
	var c := make(kind, o)
	if c == null:
		return null
	parent.add_child(c)
	var yaw: float = o.get("yaw", 0.0)
	if c.has_method("warp"):
		c.call("warp", pos, yaw)
	else:
		c.global_position = pos
		c.heading = yaw
		c.rotation.y = yaw
	return c


## A loose herd walking the same route, each animal offset sideways / behind.
## Returns the creatures. opts as for make(), plus spacing (m).
static func herd(parent: Node, kind: String, count: int, path: Array, loop := true, opts: Dictionary = {}) -> Array[Creature]:
	var out: Array[Creature] = []
	if path.is_empty():
		return out
	var sz: Vector2 = SIZES.get(kind, Vector2(3, 2))
	var spacing: float = opts.get("spacing", sz.x * 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1)) * 31 + count
	var p0: Vector3 = path[0]
	var p1: Vector3 = path[1] if path.size() > 1 else p0 + Vector3.FORWARD
	var fwd := (p1 - p0)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	for i in count:
		var o := opts.duplicate()
		o["seed"] = int(opts.get("seed", 1)) + i + 1
		if not o.has("scale"):
			o["scale"] = rng.randf_range(0.78, 1.05) if i > 0 else 1.0
		var off := side * ((i % 3) - 1) * spacing * rng.randf_range(0.7, 1.1) - fwd * (i / 3) * spacing * 1.3 - fwd * rng.randf() * spacing * 0.4
		var pts: Array = []
		for p: Vector3 in path:
			pts.append(p + off)
		var start: Vector3 = pts[0]
		o["yaw"] = atan2(-fwd.x, -fwd.z)
		var c := spawn(parent, kind, start, o)
		if c == null:
			continue
		c.set_path(pts, loop)
		c.speed *= rng.randf_range(0.9, 1.05)
		out.append(c)
	return out


## Triangle count of a creature's mesh (builds the blueprint if needed).
static func triangles(kind: String, opts: Dictionary = {}) -> int:
	if WALKERS.has(kind):
		var cm: CreatureMesh = CreatureWalker.blueprint(kind, opts).cm
		return cm.tris
	var c := make(kind, opts)
	var n := 0
	if c is CreatureFlyer:
		n = (CreatureFlyer._bp.cm as CreatureMesh).tris
	elif c is CreatureCrawler:
		n = (CreatureCrawler._bp.cm as CreatureMesh).tris
	elif c is CreatureSwarm:
		n = (CreatureSwarm._body_mesh.surface_get_array_index_len(0) + CreatureSwarm._wing_mesh.surface_get_array_index_len(0)) / 3
	if c:
		c.free()
	return n


## {kind: {"tris": int, "length": m, "height": m}} for every kind (for budgets and reports).
static func stats() -> Dictionary:
	var out := {}
	for kind: String in KINDS:
		var sz: Vector2 = SIZES[kind]
		out[kind] = {"tris": triangles(kind), "length": sz.x, "height": sz.y}
	return out


## Poses a Humanoid astride a mount. Parent it to `creature.seat` at about
## Vector3(0, -0.9, 0) and call this every frame instead of Humanoid.animate().
static func pose_rider(h: Humanoid, delta: float) -> void:
	h.animate(delta, 0.0, "walk")
	h.leg_l.rotation = Vector3(0.9, 0.0, -0.5)
	h.leg_r.rotation = Vector3(0.9, 0.0, 0.5)
	h.knee_l.rotation.x = -1.2
	h.knee_r.rotation.x = -1.2
	h.arm_l.rotation.x = 0.45
	h.arm_r.rotation.x = 0.45
	h.elbow_l.rotation.x = 0.95
	h.elbow_r.rotation.x = 0.95
