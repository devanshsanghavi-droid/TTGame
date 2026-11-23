class_name WaterKit extends RefCounted
## Water surfaces using shaders/water.gdshader.

## A flat water sheet centred at `pos` (its y is the surface height).
## opts: shallow, deep (Color), clarity (m), wave_scale, wave_speed, wave_strength,
##       swell, foam_width, foam_color, roughness, murk (0..1), subdiv
static func plane(parent: Node, pos: Vector3, size: Vector2, opts: Dictionary = {}) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	var sub: int = opts.get("subdiv", 48)
	pm.subdivide_width = sub
	pm.subdivide_depth = sub
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("wave_n", MatLib.noise_tex(91, 0.035, true))
	for k in ["clarity", "wave_scale", "wave_speed", "wave_strength", "swell", "foam_width", "roughness", "murk", "refraction"]:
		if opts.has(k):
			mat.set_shader_parameter(k, opts[k])
	for k in ["shallow", "deep", "foam_color"]:
		if opts.has(k):
			var c: Color = opts[k]
			mat.set_shader_parameter(k, Vector3(c.r, c.g, c.b))
	var m := MeshInstance3D.new()
	m.mesh = pm
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	m.name = "Water"
	parent.add_child(m)
	return m
