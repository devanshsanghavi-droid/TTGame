class_name FxKit extends RefCounted
## Shared effects kit. One-call constructors that return a Node3D handle.
## Everything is lit by the scene or lights it, sits in fog, and uses soft,
## noise-eroded billboards generated in code (see shaders/fx_*.gdshader).
##
##   var camp := FxKit.fire(self, pos, {"size": 1.0, "shadow": true})   # FxFire
##   camp.set_intensity(0.4); camp.extinguish()
##   FxKit.lamps(self, positions)                                       # FxLamps: hundreds of oil lamps
##   var field := FxKit.fire_field(self, {"cell_size": 3.0, "height": ground_y})   # FxFireField
##   field.set_cell(Vector2i(4, 7), 1.0); field.bind_environment(env, sun)
##   FxKit.smoke(self, pos, {"size": 0.5, "height": 14.0})              # chimney / column
##   FxKit.dust_puff(self, pos, {"size": 2.0}); FxKit.debris(self, pos); FxKit.splash(self, pos)
##   FxKit.mist(self, pos, {"size": Vector3(8, 0.5, 2)}); FxKit.spray(self, pos, {"width": 6.0})
##   var storm := FxKit.weather(self, "sandstorm"); storm.set_strength(0.7)        # FxWeather
##   FxKit.god_rays(self, pos, {"size": Vector3(3, 2, 3)})              # dust motes in light shafts
##   var beam := FxKit.beam(self); beam.set_points([a, b, c])           # FxBeam
##   FxKit.shockwave(self, pos, {"size": 6.0})                          # dust ring + debris + camera shake
##   FxKit.flicker(torch_light, {"amount": 0.35})                       # FxFlicker
##
## Particle counts follow Game.quality().foliage (see density()). All
## positions are in the parent's local space unless noted.

const FireField = preload("res://scripts/kit/fx/fx_fire_field.gd")

## Global wind in m/s. Smoke drifts with it and weather defaults to it.
static var wind := Vector3(1.6, 0.0, 0.7)
## Extra multiplier on every particle count (on top of the quality preset).
static var density_scale := 1.0

static var _tex := {}
static var _shaders := {}
static var _res := {}


# ------------------------------------------------------------------ fire
## Flames + smoke + embers + flickering OmniLight3D.
## opts: size (0.05 .. 12 m flame height; < 0.3 is a steady lamp flame), width (m along
## local X: turns a big fire into a wall), smoke, embers, light (bool), shadow (bool,
## default false), energy / range (light overrides), intensity (start value), scorch (bool:
## soot decal), wind (Vector3).
static func fire(parent: Node, pos: Vector3, opts: Dictionary = {}) -> FxFire:
	var f := FxFire.new()
	f.position = pos
	parent.add_child(f)
	f.build(opts)
	return f


## Hundreds of tiny steady flames as one MultiMesh plus a capped pool of real
## lights that settle on the lamp clusters nearest the camera.
## opts: size (flame height, default 0.09), max_lights (8), energy, range, cluster (m),
## lit (bool, default true).
static func lamps(parent: Node, positions: Variant, opts: Dictionary = {}) -> FxLamps:
	var l := FxLamps.new()
	parent.add_child(l)
	l.build(PackedVector3Array(positions), opts)
	return l


## Grid of burning cells for cellular wildfire. See FxFireField.
## opts: cell_size (3), max_cells (600), flame_height (4), max_lights (6), flames_per_cell (2),
## height (Callable(x, z) -> ground y), smoke, embers (bool), env + sun (auto smoke tint).
static func fire_field(parent: Node, opts: Dictionary = {}) -> FxFireField:
	var f := FxFireField.new()
	parent.add_child(f)
	f.build(opts)
	return f


## Flicker for any torch / brazier light. opts: amount (0..1), speed, move (m of position jitter).
static func flicker(light: Light3D, opts: Dictionary = {}) -> FxFlicker:
	var f := FxFlicker.new()
	f.amount = opts.get("amount", 0.3)
	f.speed = opts.get("speed", 9.0)
	f.move = opts.get("move", 0.0)
	f.base_energy = opts.get("energy", light.light_energy)
	light.add_child(f)
	return f


# ----------------------------------------------------------------- smoke
## Continuous smoke column (chimney, smouldering ruin, signal fire).
## opts: size (base radius m, 0.5), height (m, 12), color, opacity (0.6), rate (1),
## glow (Color: fire under-light at the base), wind.
static func smoke(parent: Node, pos: Vector3, opts: Dictionary = {}) -> FxEmitter:
	var e := FxEmitter.new()
	e.position = pos
	parent.add_child(e)
	var size: float = opts.get("size", 0.5)
	var rise := 1.1 + 0.55 * sqrt(size)
	var height: float = opts.get("height", 12.0)
	e.add_system(smoke_system(e, {
		"size": size, "rise": rise, "lifetime": clampf(height / rise, 2.5, 16.0),
		"color": opts.get("color", Color(0.1, 0.095, 0.09)), "opacity": opts.get("opacity", 0.5),
		"rate": opts.get("rate", 1.0), "glow": opts.get("glow", Color.BLACK),
		"wind": opts.get("wind", wind), "extents": Vector3(size * 0.35, 0.05, size * 0.35),
	}))
	return e


## Shared smoke builder (used by fire(), smoke() and FxFireField).
## cfg: size, rise, lifetime, color, opacity, rate, glow, wind, extents, y, amount, pm (extra
## ParticleProcessMaterial properties), fade (glow fade age).
static func smoke_system(parent: Node, cfg: Dictionary) -> GPUParticles3D:
	var size: float = cfg.get("size", 0.5)
	var life: float = cfg.get("lifetime", 6.0)
	var rise: float = cfg.get("rise", 1.5)
	var w: Vector3 = cfg.get("wind", wind)
	var col: Color = cfg.get("color", Color(0.1, 0.095, 0.09))
	var op: float = cfg.get("opacity", 0.5)
	var glow: Color = cfg.get("glow", Color.BLACK)
	var lite := col.lerp(Color(0.42, 0.41, 0.4), 0.45)
	var props := {
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX,
		"emission_box_extents": cfg.get("extents", Vector3(size * 0.3, 0.05, size * 0.3)),
		"direction": Vector3.UP, "spread": 9.0,
		"initial_velocity_min": rise * 0.75, "initial_velocity_max": rise * 1.2,
		"gravity": Vector3(w.x * 0.14, 0.05, w.z * 0.14),
		"damping_min": 0.05, "damping_max": 0.12,
		"angle_min": -180.0, "angle_max": 180.0,
		"angular_velocity_min": -14.0, "angular_velocity_max": 14.0,
		"scale_min": size * 1.9, "scale_max": size * 2.9,
		"scale_curve": curve([0.0, 0.75, 0.3, 1.3, 1.0, 3.0]),
		"anim_offset_min": 0.0, "anim_offset_max": 1.0,
		"lifetime_randomness": 0.25,
		"color_ramp": ramp([[0.0, Color(col, 0.0)], [0.1, Color(col, op)], [0.55, Color(col.lerp(lite, 0.6), op * 0.6)], [1.0, Color(lite, 0.0)]]),
		"turbulence_enabled": true, "turbulence_noise_strength": 0.7, "turbulence_noise_scale": 4.0,
		"turbulence_influence_min": 0.02, "turbulence_influence_max": 0.06,
	}
	props.merge(cfg.get("pm", {}), true)
	var m := smat("puff", {
		"noise_scale": 0.75, "erosion": 0.45, "soft_dist": clampf(size * 1.2, 0.3, 3.0),
		"near_fade": clampf(size * 2.0, 0.8, 6.0), "backlight": 0.25,
		"glow": Vector3(glow.r, glow.g, glow.b), "glow_fade": cfg.get("fade", 0.3),
	})
	var reach := rise * life + size * 6.0
	var drift := Vector2(w.x, w.z).length() * 0.07 * life * life + size * 6.0 + 4.0
	var amount: float = cfg.get("amount", clampf(life * 7.0, 14.0, 90.0) * float(cfg.get("rate", 1.0)))
	return particles(parent, {
		"amount": count(amount), "lifetime": life, "pm": ppm(props), "mesh": quad(Vector2.ONE, m),
		"order": GPUParticles3D.DRAW_ORDER_VIEW_DEPTH, "pos": Vector3(0, cfg.get("y", 0.0), 0),
		"aabb": AABB(Vector3(-drift, -2.0, -drift), Vector3(drift * 2.0, reach + 4.0, drift * 2.0)),
	})


# -------------------------------------------------------------- one-shots
## Soft burst of dust: footfalls of giant animals, falling blocks, landings.
## opts: size (cloud radius m, 1), color, amount (multiplier).
static func dust_puff(parent: Node, pos: Vector3, opts: Dictionary = {}) -> FxEmitter:
	var col: Color = opts.get("color", Color(0.33, 0.27, 0.21))
	var key := "dust_" + col.to_html()
	if not _res.has(key):
		var m := smat("puff", {"noise_scale": 0.8, "erosion": 0.9, "soft_dist": 0.5, "near_fade": 0.8})
		_res[key] = [ppm({
			"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, "emission_sphere_radius": 0.45,
			"direction": Vector3.UP, "spread": 85.0, "flatness": 0.7,
			"initial_velocity_min": 0.9, "initial_velocity_max": 3.0,
			"gravity": Vector3(wind.x * 0.05, 0.12, wind.z * 0.05),
			"damping_min": 1.6, "damping_max": 2.6,
			"angle_min": -180.0, "angle_max": 180.0, "angular_velocity_min": -25.0, "angular_velocity_max": 25.0,
			"scale_min": 0.55, "scale_max": 1.0, "scale_curve": curve([0.0, 0.3, 0.2, 0.9, 1.0, 1.7]),
			"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.35,
			"color_ramp": ramp([[0.0, Color(col, 0.0)], [0.06, Color(col, 0.5)], [0.5, Color(col, 0.3)], [1.0, Color(col.lightened(0.15), 0.0)]]),
		}), quad(Vector2.ONE, m)]
	var e := FxEmitter.new()
	e.position = pos
	e.scale = Vector3.ONE * float(opts.get("size", 1.0))
	parent.add_child(e)
	e.add_system(particles(e, {
		"amount": count(18.0 * float(opts.get("amount", 1.0))), "lifetime": 2.4, "pm": _res[key][0], "mesh": _res[key][1],
		"one_shot": true, "explosiveness": 0.94, "local": true, "order": GPUParticles3D.DRAW_ORDER_VIEW_DEPTH,
		"aabb": AABB(Vector3(-3.5, -0.5, -3.5), Vector3(7, 5, 7)),
	}))
	e.expire(2.7)
	return e


## Burst of stone chips that fall, bounce and settle.
## opts: size (throw radius m, 1), amount (16), material, dir (Vector3), spread (deg), chip (m),
## ground (bool: bounce on the plane through `pos`, default true).
static func debris(parent: Node, pos: Vector3, opts: Dictionary = {}) -> FxEmitter:
	var size: float = opts.get("size", 1.0)
	var chip: float = opts.get("chip", 0.1 * sqrt(maxf(size, 0.3)))
	var sp := sqrt(maxf(size, 0.2))
	if not _res.has("chip_mesh"):
		_res["chip_mesh"] = MeshKit.rock_mesh(5, 1, 0.35, Vector3(1.0, 0.55, 0.8), 5)
	var e := FxEmitter.new()
	e.position = pos
	parent.add_child(e)
	var dir: Vector3 = opts.get("dir", Vector3.UP)
	var p := particles(e, {
		"amount": maxi(4, int(float(opts.get("amount", 16)) * density())), "lifetime": 2.6,
		"pm": ppm({
			"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, "emission_sphere_radius": 0.15 * size,
			"direction": dir.normalized(), "spread": opts.get("spread", 55.0),
			"initial_velocity_min": 2.4 * sp, "initial_velocity_max": 6.5 * sp,
			"gravity": Vector3(0, -9.8, 0),
			"angle_min": -180.0, "angle_max": 180.0, "angular_velocity_min": -500.0, "angular_velocity_max": 500.0,
			"scale_min": chip * 0.5, "scale_max": chip * 1.5,
			"scale_curve": curve([0.0, 1.0, 0.85, 1.0, 1.0, 0.0]),
			"collision_mode": ParticleProcessMaterial.COLLISION_RIGID if opts.get("ground", true) else ParticleProcessMaterial.COLLISION_DISABLED,
			"collision_bounce": 0.28, "collision_friction": 0.35,
		}),
		"mesh": _res["chip_mesh"], "one_shot": true, "explosiveness": 1.0, "align": GPUParticles3D.TRANSFORM_ALIGN_DISABLED,
		"aabb": AABB(Vector3(-6, -1, -6) * sp, Vector3(12, 8, 12) * sp),
	})
	p.material_override = opts.get("material", MatLib.pbr("rock_06", {"scale": 1.4, "world": false}))
	p.collision_base_size = chip * 0.6
	if opts.get("ground", true):
		var c := GPUParticlesCollisionBox3D.new()
		c.size = Vector3(16.0 * sp, 1.0, 16.0 * sp)
		c.position = Vector3(0, -0.5, 0)
		e.add_child(c)
	e.add_system(p)
	e.expire(2.9)
	return e


## Water splash: thrown droplets, a short crown of mist and an expanding ripple.
## opts: size (1 = a thrown rock, 3 = a large animal), ripple (bool), color.
static func splash(parent: Node, pos: Vector3, opts: Dictionary = {}) -> FxEmitter:
	var col: Color = opts.get("color", Color(0.6, 0.65, 0.68))
	var key := "splash_" + col.to_html()
	if not _res.has(key):
		var dm := smat("dot", {"hardness": 0.7, "backlight": 0.8, "near_fade": 0.3})
		var mm := smat("puff", {"noise_scale": 1.1, "erosion": 0.5, "soft_dist": 0.25, "near_fade": 0.5, "backlight": 0.6, "warp": 0.7})
		_res[key] = [
			ppm({
				"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, "emission_sphere_radius": 0.12,
				"direction": Vector3.UP, "spread": 34.0,
				"initial_velocity_min": 1.8, "initial_velocity_max": 5.2,
				"gravity": Vector3(0, -9.8, 0), "scale_min": 0.6, "scale_max": 1.5,
				"color_ramp": ramp([[0.0, Color(col.lightened(0.3), 0.8)], [0.7, Color(col.lightened(0.3), 0.65)], [1.0, Color(col, 0.0)]]),
				"lifetime_randomness": 0.3,
			}), quad(Vector2(0.024, 0.08), dm),
			ppm({
				"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, "emission_sphere_radius": 0.16,
				"direction": Vector3.UP, "spread": 30.0,
				"initial_velocity_min": 1.0, "initial_velocity_max": 3.4,
				"gravity": Vector3(0, -4.5, 0), "damping_min": 1.0, "damping_max": 2.0,
				"angle_min": -180.0, "angle_max": 180.0,
				"scale_min": 0.3, "scale_max": 0.6, "scale_curve": curve([0.0, 0.4, 0.3, 1.0, 1.0, 1.6]),
				"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.3,
				"color_ramp": ramp([[0.0, Color(col, 0.0)], [0.08, Color(col, 0.34)], [0.5, Color(col, 0.16)], [1.0, Color(col, 0.0)]]),
			}), quad(Vector2.ONE, mm)]
	var size: float = opts.get("size", 1.0)
	var e := FxEmitter.new()
	e.position = pos
	e.scale = Vector3.ONE * size
	parent.add_child(e)
	var r: Array = _res[key]
	e.add_system(particles(e, {
		"amount": count(80.0), "lifetime": 1.0, "pm": r[0], "mesh": r[1], "one_shot": true, "explosiveness": 0.97,
		"local": true, "align": GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY,
		"aabb": AABB(Vector3(-3, -0.5, -3), Vector3(6, 4, 6)), "sort": 0.3,
	}))
	e.add_system(particles(e, {
		"amount": count(16.0), "lifetime": 1.2, "pm": r[2], "mesh": r[3], "one_shot": true, "explosiveness": 0.92,
		"local": true, "aabb": AABB(Vector3(-3, -0.5, -3), Vector3(6, 4, 6)), "sort": 0.2,
	}))
	if opts.get("ripple", true):
		ripple(parent, pos, {"size": 2.4 * size, "life": 2.4})
	e.expire(1.6)
	return e


## Expanding ripple rings lying on a water surface (also good for wading steps and rain).
## opts: size (final diameter m, 2.5), life (s, 2.2).
static func ripple(parent: Node, pos: Vector3, opts: Dictionary = {}) -> MeshInstance3D:
	if not _res.has("ripple"):
		var q := QuadMesh.new()
		q.orientation = PlaneMesh.FACE_Y
		q.size = Vector2.ONE
		q.material = smat("ripple", {}, 2)
		_res["ripple"] = q
	var mi := MeshInstance3D.new()
	mi.mesh = _res["ripple"]
	mi.position = pos + Vector3(0, 0.03, 0)
	mi.scale = Vector3.ONE * float(opts.get("size", 2.5))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.set_instance_shader_parameter("progress", 0.0)
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: mi.set_instance_shader_parameter("progress", v), 0.0, 1.0, float(opts.get("life", 2.2)))
	tw.tween_callback(mi.queue_free)
	return mi


## Low drifting mist (shoreline, waterfall base, cold ground).
## opts: size (Vector3 half extents, (6, 0.5, 2)), color, opacity (0.32), rise (m/s), amount.
static func mist(parent: Node, pos: Vector3, opts: Dictionary = {}) -> FxEmitter:
	var ext: Vector3 = opts.get("size", Vector3(6, 0.5, 2))
	var col: Color = opts.get("color", Color(0.6, 0.63, 0.66))
	var op: float = opts.get("opacity", 0.07)
	var w: Vector3 = opts.get("wind", wind)
	var e := FxEmitter.new()
	e.position = pos
	parent.add_child(e)
	var m := smat("puff", {"noise_scale": 0.5, "erosion": 0.3, "soft_dist": 1.5, "near_fade": 3.0, "backlight": 0.6, "bump": 0.3, "warp": 0.8})
	var vel := Vector3(w.x * 0.3, float(opts.get("rise", 0.2)), w.z * 0.3)
	e.add_system(particles(e, {
		"amount": count(float(opts.get("amount", clampf(ext.x * ext.z * 0.4, 6.0, 48.0)))), "lifetime": 6.0,
		"pm": ppm({
			"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": ext,
			"direction": vel.normalized(), "spread": 25.0,
			"initial_velocity_min": vel.length() * 0.6, "initial_velocity_max": vel.length() * 1.3,
			"gravity": Vector3.ZERO, "angle_min": -180.0, "angle_max": 180.0,
			"angular_velocity_min": -6.0, "angular_velocity_max": 6.0,
			"scale_min": 3.0, "scale_max": 6.0, "scale_curve": curve([0.0, 0.6, 1.0, 1.5]),
			"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.2,
			"color_ramp": ramp([[0.0, Color(col, 0.0)], [0.3, Color(col, op)], [0.7, Color(col, op * 0.8)], [1.0, Color(col, 0.0)]]),
		}),
		"mesh": quad(Vector2.ONE, m), "order": GPUParticles3D.DRAW_ORDER_VIEW_DEPTH, "preprocess": 6.0,
		"aabb": AABB(-ext - Vector3(8, 3, 8), ext * 2.0 + Vector3(16, 9, 16)),
	}))
	return e


## Rhythmic wave-crash spray along a shoreline: a burst every `interval` seconds.
## opts: width (m along local X, 4), height (m, 2.2), interval (s, 3.2), dir (Vector3 the spray is thrown), color.
static func spray(parent: Node, pos: Vector3, opts: Dictionary = {}) -> FxEmitter:
	var width: float = opts.get("width", 4.0)
	var height: float = opts.get("height", 2.2)
	var interval: float = opts.get("interval", 3.2)
	var col: Color = opts.get("color", Color(0.62, 0.66, 0.69))
	var dir: Vector3 = (Vector3(opts.get("dir", Vector3(0, 0, 1))) * 0.45 + Vector3.UP).normalized()
	var v0 := sqrt(2.0 * 6.0 * height)
	var vis := clampf(1.7 / interval, 0.1, 1.0)     # visible fraction of each cycle
	var e := FxEmitter.new()
	e.position = pos
	parent.add_child(e)
	var mm := smat("puff", {"noise_scale": 1.0, "erosion": 0.5, "soft_dist": 0.3, "near_fade": 0.8, "backlight": 0.7, "warp": 0.7})
	e.add_system(particles(e, {
		"amount": count(5.0 * width), "lifetime": interval, "explosiveness": 0.86, "randomness": 0.3,
		"pm": ppm({
			"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": Vector3(width * 0.5, 0.1, 0.3),
			"direction": dir, "spread": 20.0, "initial_velocity_min": v0 * 0.45, "initial_velocity_max": v0,
			"gravity": Vector3(wind.x * 0.2, -6.0, wind.z * 0.2), "damping_min": 0.4, "damping_max": 1.0,
			"angle_min": -180.0, "angle_max": 180.0,
			"scale_min": 0.7, "scale_max": 1.5, "scale_curve": curve([0.0, 0.35, vis * 0.5, 1.0, 1.0, 1.6]),
			"anim_offset_min": 0.0, "anim_offset_max": 1.0,
			"color_ramp": ramp([[0.0, Color(col, 0.0)], [vis * 0.08, Color(col, 0.32)], [vis * 0.6, Color(col, 0.15)], [vis, Color(col, 0.0)], [1.0, Color(col, 0.0)]]),
		}),
		"mesh": quad(Vector2.ONE, mm), "order": GPUParticles3D.DRAW_ORDER_VIEW_DEPTH,
		"aabb": AABB(Vector3(-width * 0.5 - 4.0, -1.5, -5.0), Vector3(width + 8.0, height + 5.0, 10.0)),
	}))
	var dm := smat("dot", {"hardness": 0.7, "backlight": 0.8, "near_fade": 0.3})
	e.add_system(particles(e, {
		"amount": count(9.0 * width), "lifetime": interval, "explosiveness": 0.9, "randomness": 0.3,
		"align": GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY,
		"pm": ppm({
			"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": Vector3(width * 0.5, 0.1, 0.3),
			"direction": dir, "spread": 26.0, "initial_velocity_min": v0 * 0.5, "initial_velocity_max": v0 * 1.25,
			"gravity": Vector3(0, -9.8, 0), "scale_min": 0.6, "scale_max": 1.5,
			"color_ramp": ramp([[0.0, Color(col, 0.6)], [vis * 0.7, Color(col, 0.45)], [vis, Color(col, 0.0)], [1.0, Color(col, 0.0)]]),
		}),
		"mesh": quad(Vector2(0.02, 0.075), dm), "sort": 0.3,
		"aabb": AABB(Vector3(-width * 0.5 - 4.0, -1.5, -5.0), Vector3(width + 8.0, height + 6.0, 10.0)),
	}))
	return e


## Slow dust motes that only shine where direct light reaches them (they take
## shadows), for interiors and forest shafts. Not camera-following: place a box.
## opts: size (Vector3 half extents, (3, 2, 3)), amount, color.
static func god_rays(parent: Node, pos: Vector3, opts: Dictionary = {}) -> FxEmitter:
	var ext: Vector3 = opts.get("size", Vector3(3, 2, 3))
	var e := FxEmitter.new()
	e.position = pos
	parent.add_child(e)
	var vol := ext.x * ext.y * ext.z * 8.0
	e.add_system(particles(e, {
		"amount": count(float(opts.get("amount", clampf(vol * 4.0, 60.0, 900.0)))), "lifetime": 9.0, "preprocess": 9.0,
		"pm": motes_pm(ext, opts.get("color", Color(1.0, 0.93, 0.8))), "mesh": motes_mesh(), "local": true,
		"aabb": AABB(-ext - Vector3.ONE, ext * 2.0 + Vector3.ONE * 2.0),
	}))
	return e


static func motes_pm(ext: Vector3, col: Color) -> ParticleProcessMaterial:
	return ppm({
		"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX, "emission_box_extents": ext,
		"direction": Vector3.UP, "spread": 180.0, "initial_velocity_min": 0.02, "initial_velocity_max": 0.1,
		"gravity": Vector3(0, -0.006, 0), "scale_min": 0.5, "scale_max": 1.6,
		"scale_curve": curve([0.0, 0.0, 0.15, 1.0, 0.8, 1.0, 1.0, 0.0]),
		"color": Color(col, 0.85), "lifetime_randomness": 0.3,
		"turbulence_enabled": true, "turbulence_noise_strength": 0.25, "turbulence_noise_scale": 3.0,
		"turbulence_influence_min": 0.02, "turbulence_influence_max": 0.08,
	})


static func motes_mesh() -> QuadMesh:
	if not _res.has("motes"):
		_res["motes"] = quad(Vector2(0.03, 0.03), smat("dot", {"ambient": 0.1, "backlight": 1.0, "hardness": 1.0, "boost": 2.4, "near_fade": 0.25}))
	return _res["motes"]


# ---------------------------------------------------------------- set pieces
## Camera-following weather. kind: "snow" | "blizzard" | "rain" | "sandstorm" | "ash" |
## "dust_motes" | "embers". Returns FxWeather: set_strength(0..1), prewarm(), stop().
## opts: strength (start, default 1), wind (Vector3), env (Environment) + sun
## (DirectionalLight3D) to drive (default: the current era's), drive_env (bool),
## ground (Callable(x, z) -> y for rain splashes), fade (strength units per second).
static func weather(parent: Node, kind: String, opts: Dictionary = {}) -> FxWeather:
	var w := FxWeather.new()
	parent.add_child(w)
	w.build(kind, opts)
	return w


## Soft shaft of sunlight between points (mirror puzzle), with a hit glow at the end.
## opts: radius (0.22), color, energy, glow (bool: decal + light at the last point).
static func beam(parent: Node, opts: Dictionary = {}) -> FxBeam:
	var b := FxBeam.new()
	parent.add_child(b)
	b.build(opts)
	return b


## Heavy impact (trebuchet stone, falling monolith): a dust ring racing outward, a
## rising dust column, debris and camera shake. The returned emitter emits
## `shook(amount)`; the current era's camera_rig.add_shake() is called for you.
## opts: size (ring radius m, 6), shake (0.8; 0 disables), debris (bool), mark (bool: grime decal), color.
static func shockwave(parent: Node, pos: Vector3, opts: Dictionary = {}) -> FxEmitter:
	var size: float = opts.get("size", 6.0)
	var col: Color = opts.get("color", Color(0.3, 0.25, 0.2))
	var key := "shock_" + col.to_html()
	if not _res.has(key):
		var m := smat("puff", {"noise_scale": 0.8, "erosion": 0.8, "soft_dist": 0.7, "near_fade": 1.2})
		var cr := ramp([[0.0, Color(col, 0.0)], [0.05, Color(col, 0.5)], [0.45, Color(col, 0.3)], [1.0, Color(col.lightened(0.12), 0.0)]])
		_res[key] = [
			ppm({
				"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_RING, "emission_ring_axis": Vector3.UP,
				"emission_ring_radius": 0.16, "emission_ring_inner_radius": 0.06, "emission_ring_height": 0.03,
				"direction": Vector3.UP, "spread": 20.0, "initial_velocity_min": 0.0, "initial_velocity_max": 0.12,
				"radial_velocity_min": 0.8, "radial_velocity_max": 1.5, "damping_min": 1.0, "damping_max": 1.6,
				"gravity": Vector3(0, 0.02, 0), "angle_min": -180.0, "angle_max": 180.0,
				"angular_velocity_min": -20.0, "angular_velocity_max": 20.0,
				"scale_min": 0.24, "scale_max": 0.46, "scale_curve": curve([0.0, 0.35, 0.25, 1.0, 1.0, 1.7]),
				"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.3, "color_ramp": cr,
			}),
			ppm({
				"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, "emission_sphere_radius": 0.1,
				"direction": Vector3.UP, "spread": 35.0, "initial_velocity_min": 0.3, "initial_velocity_max": 1.0,
				"damping_min": 0.9, "damping_max": 1.6, "gravity": Vector3(wind.x * 0.01, 0.03, wind.z * 0.01),
				"angle_min": -180.0, "angle_max": 180.0, "angular_velocity_min": -15.0, "angular_velocity_max": 15.0,
				"scale_min": 0.35, "scale_max": 0.7, "scale_curve": curve([0.0, 0.3, 0.2, 0.9, 1.0, 1.6]),
				"anim_offset_min": 0.0, "anim_offset_max": 1.0, "lifetime_randomness": 0.25, "color_ramp": cr,
			}), quad(Vector2.ONE, m)]
	var e := FxEmitter.new()
	e.position = pos
	e.scale = Vector3.ONE * size
	parent.add_child(e)
	var r: Array = _res[key]
	e.add_system(particles(e, {
		"amount": count(72.0), "lifetime": 3.0, "pm": r[0], "mesh": r[2], "one_shot": true, "explosiveness": 0.97,
		"local": true, "order": GPUParticles3D.DRAW_ORDER_VIEW_DEPTH, "aabb": AABB(Vector3(-2.2, -0.2, -2.2), Vector3(4.4, 2.2, 4.4)),
	}))
	e.add_system(particles(e, {
		"amount": count(18.0), "lifetime": 3.4, "pm": r[1], "mesh": r[2], "one_shot": true, "explosiveness": 0.9,
		"local": true, "order": GPUParticles3D.DRAW_ORDER_VIEW_DEPTH, "aabb": AABB(Vector3(-2.2, -0.2, -2.2), Vector3(4.4, 3.5, 4.4)),
		"sort": 0.2,
	}))
	if opts.get("debris", true):
		debris(parent, pos + Vector3(0, 0.1, 0), {"size": size * 0.55, "amount": 26, "spread": 62.0})
	if opts.get("mark", true):
		MatLib.decal(parent, pos, Vector3(size * 0.9, 2.0, size * 0.9), "grime", pos.x * 1.7, 0.75)
	var amount: float = opts.get("shake", 0.8)
	if amount > 0.0:
		_shake.call_deferred(e, amount, size)
	e.expire(3.8)
	return e


static func _shake(e: FxEmitter, amount: float, size: float) -> void:
	if not is_instance_valid(e) or not e.is_inside_tree():
		return
	var era: Node = Game.current_era
	var k := 1.0
	var cam := e.get_viewport().get_camera_3d()
	if cam:
		k = clampf(1.0 - cam.global_position.distance_to(e.global_position) / (size * 9.0), 0.0, 1.0)
	e.shook.emit(amount * k)
	if k > 0.0 and era and is_instance_valid(era) and era.get("camera_rig") != null:
		var rig: Node = era.get("camera_rig")
		if rig and rig.has_method("add_shake"):
			rig.call("add_shake", amount * k)


## Blends an Environment (and sun) toward `target` by `weight`, layered with every
## other FX driver (weather, wildfire smoke) so they never fight. Keys: any float /
## Color Environment property, plus "sun_color", and multipliers "sun_energy",
## "ambient", "sky". weight 0 restores the era's own values.
static func env_layer(env: Environment, sun: DirectionalLight3D, layer: String, target: Dictionary, weight: float) -> void:
	FxEnv.of(env, sun).set_layer(layer, target, weight)


# ------------------------------------------------------------------ helpers
## Particle-count multiplier from the quality preset (0.5 on low .. 1.0 on high).
static func density() -> float:
	var q: Dictionary = Game.quality()
	return clampf(float(q.get("foliage", 1.0)) * density_scale, 0.15, 3.0)


static func count(n: float) -> int:
	return maxi(1, int(round(n * density())))


## Seamless noise, generated once: "fbm" (smoke, flame) or "cell".
static func noise(kind := "fbm") -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var n := FastNoiseLite.new()
	n.seed = 4711
	if kind == "cell":
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.03
		n.fractal_octaves = 2
	else:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.013
		n.fractal_octaves = 4
		n.fractal_lacunarity = 2.1
		n.fractal_gain = 0.52
	var img := n.get_seamless_image(256, 256, false, false, 0.2, true)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


## Soft white radial falloff (decal glows).
static func radial() -> Texture2D:
	if _tex.has("radial"):
		return _tex["radial"]
	var s := 64
	var img := Image.create(s, s, true, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var u := (x + 0.5) / s * 2.0 - 1.0
			var v := (y + 0.5) / s * 2.0 - 1.0
			var a := clampf(1.0 - sqrt(u * u + v * v), 0.0, 1.0)
			img.set_pixel(x, y, Color(a * a, a * a, a * a, a * a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex["radial"] = t
	return t


## Baked decal textures: "soot" (dark scorch, alpha mask) and "ember" (glowing bed, RGB fades to black).
static func decal_tex(kind: String) -> Texture2D:
	var key := "decal_" + kind
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.seed = 913
	n.frequency = 0.035
	n.fractal_octaves = 4
	var s := 96
	var img := Image.create(s, s, true, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var u := (x + 0.5) / s * 2.0 - 1.0
			var v := (y + 0.5) / s * 2.0 - 1.0
			var a := clampf(1.0 - sqrt(u * u + v * v), 0.0, 1.0)
			var nv := n.get_noise_2d(x, y) * 0.5 + 0.5
			if kind == "ember":
				var k := pow(clampf(a * 1.6 + nv * 0.9 - 0.75, 0.0, 1.0), 1.4) * smoothstep(0.0, 0.3, a)
				var vein := smoothstep(0.55, 0.8, n.get_noise_2d(x * 3.0 + 200.0, y * 3.0) * 0.5 + 0.5)
				img.set_pixel(x, y, Color(k * (0.75 + 0.25 * vein), k * (0.2 + 0.25 * vein), k * 0.04, 1.0))
			else:
				var al := clampf((a * 1.8 + nv * 0.9 - 0.8) * 1.6, 0.0, 1.0) * smoothstep(0.0, 0.3, a)
				var sh := 0.022 + 0.02 * nv
				img.set_pixel(x, y, Color(sh, sh * 0.92, sh * 0.85, al))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


static func shader(name: String) -> Shader:
	if not _shaders.has(name):
		_shaders[name] = load("res://shaders/fx_%s.gdshader" % name)
	return _shaders[name]


## ShaderMaterial on shaders/fx_<name>.gdshader. Priority 1 keeps effects in front of water.
static func smat(name: String, params: Dictionary = {}, priority := 1) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(name)
	m.render_priority = priority
	if name in ["puff", "flame", "flame_mm", "beam"]:
		m.set_shader_parameter("noise_tex", noise())
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func quad(size: Vector2, material: Material, base_anchor := false) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	if base_anchor:
		q.center_offset = Vector3(0, size.y * 0.5, 0)
	q.material = material
	return q


## CurveTexture from a flat [x0, y0, x1, y1, ...] list.
static func curve(pts: Array) -> CurveTexture:
	var c := Curve.new()
	var top := 1.0
	for i in range(1, pts.size(), 2):
		top = maxf(top, float(pts[i]))
	c.max_value = top
	for i in range(0, pts.size(), 2):
		c.add_point(Vector2(float(pts[i]), float(pts[i + 1])))
	var t := CurveTexture.new()
	t.width = 64
	t.curve = c
	return t


## GradientTexture1D from [[offset, Color], ...].
static func ramp(stops: Array) -> GradientTexture1D:
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		cols.append(s[1] as Color)
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.width = 64
	t.gradient = g
	return t


## ParticleProcessMaterial from a property dictionary (unknown names are reported).
static func ppm(props: Dictionary) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	for k in props:
		if not (k in pm):
			push_error("FxKit.ppm: unknown ParticleProcessMaterial property '%s'" % k)
			continue
		pm.set(k, props[k])
	return pm


## GPUParticles3D with FX defaults: no shadows, no GI, camera-facing quads.
## cfg: amount, lifetime, pm, mesh, one_shot, explosiveness, randomness, local, align, order,
## aabb, sort, fps, preprocess, pos, emitting.
static func particles(parent: Node, cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, int(cfg.get("amount", 16)))
	p.lifetime = cfg.get("lifetime", 1.0)
	p.process_material = cfg["pm"]
	p.draw_pass_1 = cfg["mesh"]
	p.one_shot = cfg.get("one_shot", false)
	p.explosiveness = cfg.get("explosiveness", 0.0)
	p.randomness = cfg.get("randomness", 0.0)
	p.local_coords = cfg.get("local", false)
	p.transform_align = cfg.get("align", GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD)
	p.draw_order = cfg.get("order", GPUParticles3D.DRAW_ORDER_INDEX)
	p.visibility_aabb = cfg.get("aabb", AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8)))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.sorting_offset = cfg.get("sort", 0.0)
	p.fixed_fps = cfg.get("fps", 30)
	p.preprocess = cfg.get("preprocess", 0.0)
	p.position = cfg.get("pos", Vector3.ZERO)
	p.emitting = cfg.get("emitting", true)
	parent.add_child(p)
	return p
