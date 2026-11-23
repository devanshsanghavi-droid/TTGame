class_name Portal extends Node3D
## The exit. Dormant until the era's objectives are met (auto_open) or the era
## calls open_portal(). Walking into the open portal completes the era.

var is_open := false
var auto_open := true
var radius := 1.7
var era: Node

var _disc: MeshInstance3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _particles: GPUParticles3D
var _debris: Array[MeshInstance3D] = []
var _area: Area3D
var _amount := 0.12
var _t := 0.0


static func make(p_era: Node, pos: Vector3, p_auto_open := true) -> Portal:
	var p := Portal.new()
	p.era = p_era
	p.auto_open = p_auto_open
	p.position = pos
	p_era.add_child(p)
	return p


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(5.2, 5.2)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/portal.gdshader")
	_mat.set_shader_parameter("open_amount", _amount)
	_disc = MeshKit.mi(q, _mat, Vector3(0, 1.7, 0), self)
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.extra_cull_margin = 4.0
	_light = OmniLight3D.new()
	_light.light_color = Color(0.78, 0.85, 0.84)
	_light.light_energy = 0.0
	_light.omni_range = 11.0
	_light.shadow_enabled = true
	_light.position = Vector3(0, 1.7, 0)
	add_child(_light)
	# dust that falls *toward* the portal: particles run backward
	_particles = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 4.2
	pm.gravity = Vector3.ZERO
	pm.radial_velocity_min = -2.2
	pm.radial_velocity_max = -1.3
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.75, 0.72, 0.0))
	ramp.add_point(0.25, Color(0.72, 0.74, 0.72, 0.5))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.2, 0.2, 0.2, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	_particles.process_material = pm
	var dm := QuadMesh.new()
	dm.size = Vector2(0.045, 0.045)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.vertex_color_use_as_albedo = true
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.material = dmat
	_particles.draw_pass_1 = dm
	_particles.amount = 90
	_particles.lifetime = 2.4
	_particles.position = Vector3(0, 1.7, 0)
	_particles.emitting = false
	_particles.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	add_child(_particles)
	# local stones caught mid-fall, replaying the same half second
	var stone := MatLib.pbr("dark_rock", {"scale": 1.5, "world": false})
	for i in 7:
		var m := MeshKit.mi(MeshKit.rock_mesh(900 + i, 1), stone, Vector3.ZERO, self)
		m.scale = Vector3.ONE * (0.07 + 0.05 * float(i % 3))
		m.visible = false
		_debris.append(m)
	_area = MeshKit.area_sphere(self, Vector3(0, 1.4, 0), radius)
	_area.body_entered.connect(_on_body)
	add_to_group("lock_target")


func open() -> void:
	is_open = true
	_particles.emitting = true
	for d in _debris:
		d.visible = true
	# someone may already be standing in it
	for b in _area.get_overlapping_bodies():
		_on_body(b)


func close() -> void:
	is_open = false
	_particles.emitting = false
	for d in _debris:
		d.visible = false


func _on_body(b: Node) -> void:
	if is_open and b is Player and era and era.has_method("_on_portal_entered"):
		era._on_portal_entered()


func _physics_process(_delta: float) -> void:
	# the overlap signal can be missed if the portal opens around the player
	if is_open and era and era.get("player") != null:
		var p: Player = era.player
		if p and p.alive and p.global_position.distance_to(global_position + Vector3.UP * 1.0) < radius:
			_on_body(p)


func _process(delta: float) -> void:
	_t += delta
	_amount = move_toward(_amount, 1.0 if is_open else 0.12, delta * 0.8)
	_mat.set_shader_parameter("open_amount", _amount)
	var s := 0.35 + 0.65 * _amount
	_disc.scale = Vector3(s, s, s)
	var flick := 0.75 + 0.25 * sin(_t * 23.0) * sin(_t * 7.3)
	_light.light_energy = (0.9 * flick) * maxf(0.0, _amount - 0.12)
	# debris: orbit backwards, snapping back every 0.6 s
	var loop_t := fmod(_t, 0.6)
	for i in _debris.size():
		var ang := float(i) * 0.9 - (_t - loop_t) * 0.35 - loop_t * 1.4
		var rad := 1.5 + 0.35 * sin(float(i) * 2.1)
		_debris[i].position = Vector3(cos(ang) * rad, 1.2 + 0.7 * sin(float(i) * 1.7) + loop_t * 0.5, sin(ang) * rad)
		_debris[i].rotation = Vector3(ang * 2.0, ang, 0)
