class_name FxEmitter extends Node3D
## Handle for a bundle of particle systems (smoke column, mist, dust burst,
## splash, shockwave ...). Continuous effects: set_strength(), stop(),
## prewarm(). One-shots free themselves (expire()).

signal finished
signal shook(amount: float)

var systems: Array[GPUParticles3D] = []
var ratios: Array[float] = []
var strength := 1.0

var _life := -1.0
var _age := 0.0


func _init() -> void:
	set_process(false)


func add_system(p: GPUParticles3D, ratio := 1.0) -> GPUParticles3D:
	systems.append(p)
	ratios.append(ratio)
	return p


## 0..1: scales emission without restarting the systems.
func set_strength(v: float) -> void:
	strength = clampf(v, 0.0, 1.0)
	for i in systems.size():
		var r := clampf(strength * ratios[i], 0.0, 1.0)
		systems[i].amount_ratio = maxf(r, 0.001)
		if not systems[i].one_shot:
			systems[i].emitting = r > 0.004


## Stops emitting; existing particles live out their time. Frees the node afterwards unless told not to.
func stop(free_after := true) -> void:
	var longest := 0.0
	for p in systems:
		p.emitting = false
		longest = maxf(longest, p.lifetime)
	if free_after:
		expire(longest + 0.3)


## Starts continuous systems as if they had already been running for `seconds`.
func prewarm(seconds := 6.0) -> void:
	for p in systems:
		if not p.one_shot:
			p.preprocess = minf(seconds, p.lifetime * 1.5)
			p.restart()


## Frees this effect after `seconds`.
func expire(seconds: float) -> void:
	_life = seconds
	_age = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	if _life >= 0.0 and _age >= _life:
		finished.emit()
		queue_free()
