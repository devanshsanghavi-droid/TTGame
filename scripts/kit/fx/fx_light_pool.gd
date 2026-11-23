class_name FxLightPool extends RefCounted
## A capped set of real OmniLight3Ds shared by many small emitters (lamps,
## burning cells). Call assign() now and then with the candidate spots; the
## pool keeps lights that are still wanted and cross-fades the rest, so
## nothing pops.

var lights: Array[OmniLight3D] = []
var keys: Array = []
var level := 1.0
var flicker := 0.25
var speed := 8.0

var _cur := PackedFloat32Array()
var _target := PackedFloat32Array()
var _energy := PackedFloat32Array()
var _t := 0.0


func setup(parent: Node3D, n: int, color: Color, fog_energy := 1.0) -> void:
	for i in n:
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = fog_energy
		l.light_specular = 0.3
		l.visible = false
		parent.add_child(l)
		lights.append(l)
		keys.append(null)
	_cur.resize(n)
	_target.resize(n)
	_energy.resize(n)


## cands: Array of [key, local position, energy, range, score]. Highest scores win.
func assign(cands: Array) -> void:
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[4] > b[4])
	var want := {}
	for i in mini(cands.size(), lights.size()):
		want[cands[i][0]] = cands[i]
	for i in lights.size():
		if keys[i] != null and want.has(keys[i]):
			var c: Array = want[keys[i]]
			_target[i] = 1.0
			_energy[i] = c[2]
			lights[i].omni_range = c[3]
			want.erase(keys[i])
		else:
			_target[i] = 0.0
	if want.is_empty():
		return
	var rest: Array = want.values()
	for i in lights.size():
		if rest.is_empty():
			break
		if _target[i] <= 0.0 and _cur[i] <= 0.02:
			var c: Array = rest.pop_back()
			keys[i] = c[0]
			lights[i].position = c[1]
			lights[i].omni_range = c[3]
			_energy[i] = c[2]
			_target[i] = 1.0


func process(delta: float) -> void:
	_t += delta * speed
	for i in lights.size():
		_cur[i] = move_toward(_cur[i], _target[i], delta * 2.2)
		var l := lights[i]
		if _cur[i] <= 0.001:
			if l.visible:
				l.visible = false
				keys[i] = null
			continue
		l.visible = true
		var ph := float(i) * 2.39
		var n := sin(_t + ph) * 0.5 + sin(_t * 2.31 + ph * 1.7) * 0.3 + sin(_t * 5.3 + ph * 0.6) * 0.2
		l.light_energy = _energy[i] * _cur[i] * level * (1.0 + flicker * n * 0.6)
