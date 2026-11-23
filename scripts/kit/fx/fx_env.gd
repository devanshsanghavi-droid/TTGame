class_name FxEnv extends RefCounted
## Layered Environment driver. Each FX (sandstorm, blizzard, wildfire smoke)
## owns a named layer: a target look and a weight. The result is the era's
## own look blended toward each layer in turn, so several drivers can run at
## once and weight 0 always restores the original values.
##
## Target keys: any float or Color property of Environment ("fog_density",
## "fog_light_color", "volumetric_fog_density", ...), "sun_color" (Color), and
## the multipliers "sun_energy", "ambient" (ambient light), "sky" (background).

var layers := {}

var _env: WeakRef
var _sun: DirectionalLight3D
var _base := {}


static func of(env: Environment, sun: DirectionalLight3D = null) -> FxEnv:
	var m: FxEnv = env.get_meta("fx_env") if env.has_meta("fx_env") else null
	if m == null:
		m = FxEnv.new()
		m._env = weakref(env)
		env.set_meta("fx_env", m)
	if sun != null:
		m._sun = sun
	return m


func set_layer(layer: String, target: Dictionary, weight: float) -> void:
	weight = clampf(weight, 0.0, 1.0)
	if weight <= 0.0 and not layers.has(layer):
		return
	layers[layer] = {"target": target, "weight": weight}
	apply()
	if weight <= 0.0:
		layers.erase(layer)


func remove_layer(layer: String) -> void:
	if layers.has(layer):
		layers[layer].weight = 0.0
		apply()
		layers.erase(layer)


## Forget the remembered base look (call after the era deliberately relights itself).
func rebase() -> void:
	_base.clear()


func weight_of(layer: String) -> float:
	return layers[layer].weight if layers.has(layer) else 0.0


func _base_of(env: Environment, key: String) -> Variant:
	if _base.has(key):
		return _base[key]
	var v: Variant = null
	match key:
		"sun_color":
			v = _sun.light_color if is_instance_valid(_sun) else null
		"sun_energy":
			v = _sun.light_energy if is_instance_valid(_sun) else null
		"ambient":
			v = env.ambient_light_energy
		"sky":
			v = env.background_energy_multiplier
		_:
			v = env.get(key)
	if v != null:
		_base[key] = v
	return v


func apply() -> void:
	var env: Environment = _env.get_ref() if _env else null
	if env == null:
		return
	var out := {}
	for layer in layers:
		var l: Dictionary = layers[layer]
		var w: float = l.weight
		var target: Dictionary = l.target
		for key in target:
			var b: Variant = _base_of(env, key)
			if b == null:
				continue
			var cur: Variant = out.get(key, b)
			var t: Variant = target[key]
			if key == "sun_energy" or key == "ambient" or key == "sky":
				t = float(b) * float(t)
			if cur is Color:
				out[key] = (cur as Color).lerp(t as Color, w)
			else:
				out[key] = lerpf(float(cur), float(t), w)
	for key in out:
		match key:
			"sun_color":
				if is_instance_valid(_sun):
					_sun.light_color = out[key]
			"sun_energy":
				if is_instance_valid(_sun):
					_sun.light_energy = out[key]
			"ambient":
				env.ambient_light_energy = out[key]
			"sky":
				env.background_energy_multiplier = out[key]
			_:
				env.set(key, out[key])
