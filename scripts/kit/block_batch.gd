class_name BlockBatch extends Node3D
## Modular stone blocks drawn as one MultiMesh with one compound collider.
## Use for walls, steps, columns, pyramids: thousands of blocks, one draw call.
##
##   var b := BlockBatch.new(); b.material = MatLib.pbr("sandstone_blocks_08")
##   parent.add_child(b); b.add(pos, size); ...; b.commit()

var material: Material
var collide := true
var cast_shadows := true
var visibility_end := 0.0

var _xf: Array[Transform3D] = []
var _sizes: Array[Vector3] = []
var _solid: Array[bool] = []


## Adds one block. `pos` is the block centre in this node's local space.
func add(pos: Vector3, size: Vector3, rot_y := 0.0, solid := true, tilt := Vector3.ZERO) -> void:
	var basis := Basis.from_euler(Vector3(tilt.x, rot_y, tilt.z))
	_xf.append(Transform3D(basis, pos))
	_sizes.append(size)
	_solid.append(solid)


## A straight wall of staggered blocks from `a` to `b` (base line), `height` tall.
func wall(a: Vector3, b: Vector3, height: float, thickness: float, block := Vector3(1.6, 0.8, 0), jitter := 0.03, wall_seed := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = wall_seed
	var dir := b - a
	var length := Vector2(dir.x, dir.z).length()
	if length < 0.01:
		return
	var rot_y := atan2(-dir.z, dir.x)
	var fwd := Vector3(dir.x, 0, dir.z).normalized()
	var rows := maxi(1, int(round(height / block.y)))
	var row_h := height / rows
	for r in rows:
		var offset := (block.x * 0.5) if r % 2 == 1 else 0.0
		var x := -offset
		while x < length - 0.01:
			var x0 := maxf(x, 0.0)
			var x1 := minf(x + block.x, length)
			var w := x1 - x0
			if w > 0.05:
				var c := a + fwd * (x0 + w * 0.5) + Vector3.UP * (r * row_h + row_h * 0.5)
				c.y += dir.y * ((x0 + w * 0.5) / length)
				var th := thickness * (1.0 + rng.randf_range(-jitter, jitter) * 2.0)
				add(c, Vector3(w - 0.015, row_h - 0.01, th), rot_y, false)
			x += block.x
	# one collider for the whole wall
	var mid := (a + b) * 0.5 + Vector3.UP * height * 0.5
	_xf.append(Transform3D(Basis.from_euler(Vector3(0, rot_y, 0)), mid))
	_sizes.append(Vector3(length, height, thickness))
	_solid.append(true)
	_collider_only[_xf.size() - 1] = true


var _collider_only := {}


## Adds an invisible collider box (for hand-tuned collision of a visual cluster).
func add_collider(pos: Vector3, size: Vector3, rot_y := 0.0) -> void:
	_xf.append(Transform3D(Basis.from_euler(Vector3(0, rot_y, 0)), pos))
	_sizes.append(size)
	_solid.append(true)
	_collider_only[_xf.size() - 1] = true


func count() -> int:
	return _xf.size()


func commit() -> void:
	var visible_ids: Array[int] = []
	for i in _xf.size():
		if not _collider_only.has(i):
			visible_ids.append(i)
	if visible_ids.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = MeshKit.unit_box()
		mm.instance_count = visible_ids.size()
		for k in visible_ids.size():
			var i := visible_ids[k]
			mm.set_instance_transform(k, Transform3D(_xf[i].basis.scaled_local(_sizes[i]), _xf[i].origin))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if visibility_end > 0.0:
			mmi.visibility_range_end = visibility_end
			mmi.visibility_range_end_margin = visibility_end * 0.1
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	if collide:
		var body := StaticBody3D.new()
		var any := false
		for i in _xf.size():
			if not _solid[i]:
				continue
			var cs := CollisionShape3D.new()
			cs.shape = MeshKit.box_shape(_sizes[i])
			cs.transform = _xf[i]
			body.add_child(cs)
			any = true
		if any:
			add_child(body)
		else:
			body.free()
	_xf.clear()
	_sizes.clear()
	_solid.clear()
	_collider_only.clear()
