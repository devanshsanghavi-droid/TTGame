class_name FxFlicker extends Node
## Flicker for a torch / brazier / fire light. Add as a child of the light
## (FxKit.flicker(light) does it). Layered slow and fast wobble with an
## occasional gutter; optionally jitters the light so shadows breathe.

var base_energy := 1.0
var amount := 0.3          ## 0 = steady, 1 = violent
var speed := 9.0
var move := 0.0            ## metres of position jitter
var level := 1.0           ## external multiplier (fire intensity)

var _light: Light3D
var _origin := Vector3.ZERO
var _t := 0.0
var _p := Vector3.ZERO


func _ready() -> void:
	_light = get_parent() as Light3D
	if _light == null:
		set_process(false)
		return
	_origin = _light.position
	var h := float(hash(get_instance_id()) % 1000)
	_p = Vector3(h * 0.37, h * 0.73, h * 1.31)
	_t = h * 0.1


func _process(delta: float) -> void:
	_t += delta * speed
	var n := sin(_t + _p.x) * 0.5 + sin(_t * 2.31 + _p.y) * 0.3 + sin(_t * 5.3 + _p.z) * 0.2
	var gutter := maxf(0.0, sin(_t * 0.37 + _p.y) - 0.86) * 4.0
	_light.light_energy = base_energy * level * maxf(0.0, 1.0 + amount * (n * 0.6 - gutter))
	if move > 0.0:
		_light.position = _origin + Vector3(sin(_t * 0.9 + _p.z), sin(_t * 1.3 + _p.x) * 0.6, cos(_t * 1.1 + _p.y)) * move
