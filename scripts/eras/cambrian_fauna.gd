class_name CambrianFauna extends RefCounted
## Cambrian animals built from sculpted primitives with procedural animation.

static var _tri_mesh: ArrayMesh


static func chitin(tint: Color, rough := 0.5) -> StandardMaterial3D:
	var m := MatLib.pbr("brown_leather", {"tint": tint, "scale": 3.5, "world": false, "rough": maxf(rough, 0.75) * 1.25, "sharp": 2.0})
	m.metallic_specular = 0.25
	return m


## One merged trilobite shell mesh (about 0.42 m long, head toward -Z).
static func trilobite_mesh() -> ArrayMesh:
	if _tri_mesh:
		return _tri_mesh
	var parts: Array = []
	# cephalon (head shield)
	parts.append([MeshKit.ellipsoid_mesh(Vector3(0.15, 0.05, 0.085), 2), Transform3D(Basis.IDENTITY, Vector3(0, 0.035, -0.135))])
	parts.append([MeshKit.ellipsoid_mesh(Vector3(0.055, 0.045, 0.06), 1), Transform3D(Basis.IDENTITY, Vector3(0, 0.06, -0.14))])  # glabella
	# thorax ribs, tapering
	for i in 9:
		var k := float(i) / 8.0
		var w := lerpf(0.145, 0.085, k)
		parts.append([MeshKit.ellipsoid_mesh(Vector3(w, 0.038, 0.024), 1), Transform3D(Basis.IDENTITY, Vector3(0, 0.03, -0.07 + i * 0.027))])
		parts.append([MeshKit.ellipsoid_mesh(Vector3(0.04, 0.045, 0.02), 1), Transform3D(Basis.IDENTITY, Vector3(0, 0.045, -0.07 + i * 0.027))])  # axial lobe
	# pygidium (tail shield)
	parts.append([MeshKit.ellipsoid_mesh(Vector3(0.075, 0.03, 0.055), 1), Transform3D(Basis.IDENTITY, Vector3(0, 0.028, 0.19))])
	# genal spines
	for sx in [-1.0, 1.0]:
		var spine := MeshKit.loft_mesh(PackedVector3Array([Vector3(0.13 * sx, 0.03, -0.1), Vector3(0.16 * sx, 0.025, 0.0), Vector3(0.15 * sx, 0.02, 0.09)]), [0.014, 0.01, 0.002], 5)
		parts.append([spine, Transform3D.IDENTITY])
		# eyes
		parts.append([MeshKit.ellipsoid_mesh(Vector3(0.018, 0.016, 0.026), 1), Transform3D(Basis.IDENTITY, Vector3(0.075 * sx, 0.07, -0.14))])
		# antennae
		var ant := MeshKit.loft_mesh(PackedVector3Array([Vector3(0.03 * sx, 0.03, -0.2), Vector3(0.07 * sx, 0.035, -0.3), Vector3(0.13 * sx, 0.02, -0.37)]), [0.005, 0.004, 0.001], 4)
		parts.append([ant, Transform3D.IDENTITY])
	_tri_mesh = MeshKit.merge(parts)
	return _tri_mesh


## A trilobite that scuttles around a pool floor and flees from noise.
class Trilobite extends Node3D:
	var era: Node
	var home := Vector3.ZERO
	var roam := 3.0
	var floor_y := 0.0
	var handle: Interactable
	var collected := false
	var _target := Vector3.ZERO
	var _wait := 0.0
	var _speed := 0.35
	var _flee := 0.0
	var _phase := 0.0
	var _mesh: MeshInstance3D

	func setup(p_era: Node, pos: Vector3, radius: float, size := 1.0, tint := Color(0.36, 0.24, 0.17)) -> void:
		era = p_era
		home = pos
		roam = radius
		floor_y = pos.y
		position = pos
		_target = pos
		_mesh = MeshKit.mi(CambrianFauna.trilobite_mesh(), CambrianFauna.chitin(tint, 0.42), Vector3.ZERO, self)
		_mesh.scale = Vector3.ONE * size
		_phase = pos.x * 3.1
		add_to_group("trilobite")

	func _physics_process(delta: float) -> void:
		if collected or era == null:
			return
		var d: float = era.wdelta(delta)
		_phase += d * (6.0 + _speed * 14.0)
		_flee = maxf(0.0, _flee - d)
		var p: Player = era.player
		var to_p := p.global_position - global_position
		to_p.y = 0.0
		# startled by loud feet nearby
		if to_p.length() < 5.5 and p.noise > 0.35 and _flee <= 0.0:
			_flee = 2.2
			var away := (-to_p).normalized()
			_target = _clamp_home(global_position + away * 3.0)
			era.mark("trilobite_flee")
		_wait -= d
		var flat := _target - global_position
		flat.y = 0.0
		if flat.length() < 0.15:
			if _wait <= 0.0:
				_wait = era.rng.randf_range(0.6, 3.0)
				var a: float = era.rng.randf() * TAU
				_target = _clamp_home(home + Vector3(cos(a), 0, sin(a)) * era.rng.randf() * roam)
		elif _wait <= 0.0 or _flee > 0.0:
			var sp := 1.9 if _flee > 0.0 else _speed
			var dir := flat.normalized()
			global_position += dir * sp * d
			var yaw := atan2(-dir.x, -dir.z)
			rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-d * 8.0))
		global_position.y = era.ground_y(global_position.x, global_position.z) + 0.01
		_mesh.rotation.z = sin(_phase) * 0.05
		_mesh.position.y = absf(sin(_phase * 0.5)) * 0.006

	func _clamp_home(v: Vector3) -> Vector3:
		var off := v - home
		off.y = 0.0
		if off.length() > roam:
			off = off.normalized() * roam
		return home + off

	## Sends the animal running (CHRONO yelling, stampede event).
	func startle(from: Vector3, seconds := 3.0) -> void:
		var away := global_position - from
		away.y = 0.0
		_flee = seconds
		_target = _clamp_home(global_position + away.normalized() * 4.0)


## Anomalocaris: apex predator of the Cambrian seas. Harmless to you, but it
## investigates anything splashing in its channel and shoves it back out.
class Anomalocaris extends Node3D:
	signal bumped(player: Player)

	var era: Node
	var path: Array = []
	var speed := 2.4
	var state := "patrol"
	var body_len := 2.8
	var roam_min_depth := 1.1
	var _segs: Array[Node3D] = []
	var _lobes: Array = []
	var _arms: Array[Node3D] = []
	var _i := 0
	var _t := 0.0
	var _cool := 0.0
	var _heading := Vector3.FORWARD
	var _surface_bias := 0.0

	func setup(p_era: Node, points: Array, scale_mul := 1.0) -> void:
		era = p_era
		path = points
		name = "Anomalocaris"
		var hide := CambrianFauna.chitin(Color(0.2, 0.12, 0.09), 0.5)
		var belly := CambrianFauna.chitin(Color(0.34, 0.25, 0.19), 0.5)
		var n := 12
		var seg_len := body_len / n
		var parent: Node3D = self
		for i in n:
			var k := float(i) / (n - 1)
			var seg := Node3D.new()
			seg.position = Vector3(0, 0, seg_len) if i > 0 else Vector3.ZERO
			parent.add_child(seg)
			var w := lerpf(0.34, 0.1, pow(k, 1.4)) * (0.8 + 0.5 * sin(k * PI))
			MeshKit.ellipsoid(Vector3(w, w * 0.62, seg_len * 0.85), hide, Vector3.ZERO, seg)
			MeshKit.ellipsoid(Vector3(w * 0.8, w * 0.3, seg_len * 0.8), belly, Vector3(0, -w * 0.4, 0), seg, 1)
			var pair: Array = []
			if i >= 1 and i <= 10:
				for sx in [-1.0, 1.0]:
					var lobe := Node3D.new()
					lobe.position = Vector3(w * 0.8 * sx, -0.02, 0)
					seg.add_child(lobe)
					var lw := lerpf(0.5, 0.2, k) * (0.7 + 0.5 * sin(k * PI))
					MeshKit.ellipsoid(Vector3(lw, 0.025, seg_len * 1.05), hide, Vector3(lw * 0.85 * sx, 0, 0), lobe, 1)
					pair.append(lobe)
			_lobes.append(pair)
			_segs.append(seg)
			parent = seg
		# tail fan
		for j in 3:
			for sx in [-1.0, 1.0]:
				var fin := MeshKit.ellipsoid(Vector3(0.05, 0.02, 0.3), hide, Vector3(0.1 * sx, 0.12 + j * 0.07, 0.12 + j * 0.03), _segs[n - 1], 1)
				fin.rotation = Vector3(0.9, 0.5 * sx, 0.4 * sx)
		# head: eyes on stalks, great appendages
		var head := _segs[0]
		var eye := StandardMaterial3D.new()
		eye.albedo_color = Color(0.02, 0.02, 0.02)
		eye.roughness = 0.1
		eye.metallic = 0.3
		for sx in [-1.0, 1.0]:
			MeshKit.loft([Vector3(0.2 * sx, 0.1, -0.05), Vector3(0.36 * sx, 0.22, -0.1)], [0.045, 0.035], hide, head, 6)
			MeshKit.ellipsoid(Vector3(0.085, 0.075, 0.085), eye, Vector3(0.39 * sx, 0.24, -0.11), head)
			var arm := Node3D.new()
			arm.position = Vector3(0.11 * sx, -0.12, -0.2)
			head.add_child(arm)
			MeshKit.loft([Vector3(0, 0, 0), Vector3(0.03 * sx, -0.05, -0.25), Vector3(0.02 * sx, -0.2, -0.42), Vector3(0, -0.36, -0.36), Vector3(0, -0.4, -0.22)],
				[0.075, 0.065, 0.05, 0.035, 0.012], hide, arm, 7)
			for s in 5:
				var sp := MeshKit.cyl(0.0, 0.012, 0.11, belly, Vector3(0.015 * sx, -0.1 - s * 0.055, -0.3 - 0.02 * s), arm, 4)
				sp.rotation.x = -1.3
			_arms.append(arm)
		MeshKit.ellipsoid(Vector3(0.14, 0.05, 0.14), belly, Vector3(0, -0.2, 0.05), head, 1)  # oral cone
		scale = Vector3.ONE * scale_mul
		add_to_group("lock_target")
		add_to_group("telemetry_ai")
		add_to_group("hearing")
		if path.size() > 0:
			position = path[0]

	func telemetry() -> Dictionary:
		return {"state": state, "pos": global_position}

	func hear(pos: Vector3, _loudness: float, _source: String) -> void:
		# splashes and thrown things draw it
		if state == "patrol" and _deep_enough(pos):
			state = "investigate"
			_investigate_pos = pos
			_investigate_t = 6.0

	var _investigate_pos := Vector3.ZERO
	var _investigate_t := 0.0

	func _deep_enough(p: Vector3) -> bool:
		return era.water_height_at(p) - era.ground_y(p.x, p.z) > roam_min_depth

	func _physics_process(delta: float) -> void:
		if era == null:
			return
		var d: float = era.wdelta(delta)
		_t += d
		_cool = maxf(0.0, _cool - d)
		var p: Player = era.player
		var water: float = era.water_height_at(global_position)
		var target: Vector3
		var sp := speed
		var player_wet := p.water_depth > 0.55 and p.alive
		var to_p := p.global_position - global_position
		to_p.y = 0.0
		match state:
			"patrol":
				if path.size() > 0:
					target = path[_i]
					if Vector2(target.x - global_position.x, target.z - global_position.z).length() < 2.0:
						_i = (_i + 1) % path.size()
				if player_wet and to_p.length() < 22.0 and _cool <= 0.0:
					state = "approach"
					era.mark("anomalocaris_notice")
			"investigate":
				target = _investigate_pos
				_investigate_t -= d
				if _investigate_t <= 0.0:
					state = "patrol"
				if player_wet and to_p.length() < 22.0 and _cool <= 0.0:
					state = "approach"
			"approach":
				target = p.global_position
				sp = speed * 2.4
				if not player_wet or to_p.length() > 30.0:
					state = "patrol"
				elif to_p.length() < 2.3:
					_bump(p)
			"retreat":
				target = path[_i] if path.size() > 0 else global_position
				if _cool < 3.0:
					state = "patrol"
		var flat := target - global_position
		flat.y = 0.0
		if flat.length() > 0.3:
			var want := flat.normalized()
			_heading = _heading.slerp(want, 1.0 - exp(-d * 2.2)).normalized()
			var next := global_position + _heading * sp * d
			# never beach itself: stay where the water is deep enough
			if _deep_enough(next) or state == "approach" and era.water_height_at(next) - era.ground_y(next.x, next.z) > 0.7:
				global_position = next
			else:
				_heading = _heading.rotated(Vector3.UP, 1.4 * d)
		# ride just under the surface so the back breaks it
		_surface_bias = lerpf(_surface_bias, 0.06 if state in ["approach", "investigate"] else -0.32, 1.0 - exp(-d * 1.5))
		var floor_y: float = era.ground_y(global_position.x, global_position.z)
		global_position.y = maxf(water - 0.3 + _surface_bias + sin(_t * 0.7) * 0.08, floor_y + 0.35)
		rotation.y = atan2(-_heading.x, -_heading.z)
		# undulation: lobes beat in a wave from head to tail
		var beat := 3.2 + sp * 0.5
		for i in _segs.size():
			if i > 0:
				_segs[i].rotation.y = sin(_t * beat * 0.5 - i * 0.55) * 0.06
				_segs[i].rotation.x = cos(_t * beat * 0.5 - i * 0.5) * 0.025
			var pair: Array = _lobes[i]
			for j in pair.size():
				var sx := -1.0 if j == 0 else 1.0
				(pair[j] as Node3D).rotation.z = sin(_t * beat - i * 0.7) * 0.5 * sx
		for j in _arms.size():
			_arms[j].rotation.x = sin(_t * 1.3 + j) * 0.18 + (0.5 if state == "approach" else 0.0)

	func _bump(p: Player) -> void:
		var away := p.global_position - global_position
		away.y = 0.0
		away = away.normalized()
		p.knockback(away * 8.5 + Vector3.UP * 4.5)
		p.bump_noise(0.8)
		_cool = 7.0
		state = "retreat"
		Sfx.play("splash", global_position)
		Sfx.play("thud", global_position)
		bumped.emit(p)
