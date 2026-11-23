class_name EraBase extends Node3D
## Base class for every era. Subclasses override the underscore-prefixed hooks:
##
##   _configure()          set era_id, spawn_pos, glitch pool, time limit ...
##   _build_world()        environment, terrain, props, creatures, portal
##   _setup()              objectives, events, interactions, meters, intro lines
##   _era_process(delta)   per-physics-frame era logic
##   required_mechanics()  names that must be mark()ed during a bot run
##   autopilot_plan()      Array of AutoPilot steps that finishes the era
##   capture_shots()       camera shots for the --capture flythrough

signal completed
signal ready_done
signal noise_emitted(pos: Vector3, radius: float, loudness: float, source: String)
signal objective_done(id: String)

# ---- set these in _configure()
var era_id := "unknown"
var spawn_pos := Vector3(0, 2, 0)
var spawn_yaw := 0.0
var time_limit := 600.0              ## bot must finish within this many game seconds
var nav_enabled := true
var nav_cell := 0.5
var nav_bounds := AABB()             ## optional: limit the navmesh bake volume
var flash_tint := Color(0.75, 0.8, 0.95)

# ---- runtime
var player: Player
var camera_rig: CameraRig
var hud: HUD
var dialogue: DialogueUI
var chrono: ChronoDevice
var director: EventDirector
var portal: Portal
var terrain: Terrain
var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var world_time_scale := 1.0          ## time_stutter glitch slows the world, not the player
var water_level := -1000.0
var objectives: Array[Dictionary] = []
var mechanics := {}
var meters := {}
var checkpoint_pos := Vector3.ZERO
var checkpoint_index := 0
var is_complete := false
var is_ready := false
var era_flash_active := false
var deaths := 0
var bot: Node = null

var _respawn_timer := -1.0
var _env_saved := {}
var _finish_timer := -1.0


func _ready() -> void:
	var seed_arg: String = Game.user_args.get("seed", "")
	if seed_arg != "":
		rng.seed = int(seed_arg)
	elif Game.mode == "test" or Game.mode == "capture":
		rng.seed = 1337
	else:
		rng.randomize()
	_configure()
	Game.current_era = self
	Telemetry.log_event("era_load", {"era": era_id, "seed": rng.seed})
	var t0 := Time.get_ticks_msec()
	_build_world()
	_spawn_player()
	director = EventDirector.new()
	director.era = self
	add_child(director)
	_setup()
	if portal and not portal.is_in_group("poi"):
		portal.add_to_group("poi")
		portal.set_meta("poi_label", "Portal (predicted)")
		portal.set_meta("poi_kind", "portal")
	hud.set_objectives(objectives)
	if nav_enabled:
		_bake_navigation()
	checkpoint_pos = spawn_pos
	Telemetry.set_era(self)
	Telemetry.log_event("era_ready", {"era": era_id, "build_ms": Time.get_ticks_msec() - t0,
		"events": director.events.size(), "event_types": director.types()})
	var info := Game.era_info(era_id)
	hud.set_era_title(info.title)
	if Game.mode == "play":
		hud.title_card(info.title, info.when)
		if not Game.bot_enabled:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	is_ready = true
	ready_done.emit()


# --------------------------------------------------------------- overrides
func _configure() -> void:
	pass


func _build_world() -> void:
	pass


func _setup() -> void:
	pass


func _era_process(_delta: float) -> void:
	pass


func required_mechanics() -> Array:
	return []


func autopilot_plan() -> Array:
	return []


func capture_shots() -> Array:
	return []


## Called when the era_flash glitch starts/ends. Override for gameplay effects.
func _on_era_flash(_active: bool) -> void:
	pass


func _on_respawn() -> void:
	pass


func on_scan(_marks: Array) -> void:
	pass


## Water surface height at a position (default: one global plane).
func water_height_at(_pos: Vector3) -> float:
	return water_level


# ------------------------------------------------------------------ player
func _spawn_player() -> void:
	player = Player.new()
	player.era = self
	player.position = spawn_pos
	player.input.bot = Game.bot_enabled
	add_child(player)
	player.facing = Basis(Vector3.UP, spawn_yaw) * Vector3.FORWARD
	player.died.connect(_on_player_died)
	player.footstep.connect(func(wet: bool) -> void: Sfx.play("step_wet" if wet else "step", player.global_position))
	camera_rig = CameraRig.new()
	camera_rig.target = player
	camera_rig.yaw = spawn_yaw
	add_child(camera_rig)
	player.camera_rig = camera_rig
	if Game.mode != "capture":
		camera_rig.make_current()
	hud = HUD.new()
	hud.era = self
	hud.player = player
	add_child(hud)
	hud.camera = camera_rig.cam
	hud.set_glitch_tint(flash_tint)
	dialogue = DialogueUI.new()
	dialogue.era = self
	add_child(dialogue)
	chrono = ChronoDevice.new()
	add_child(chrono)
	chrono.setup(self, player, hud, rng.randi())


func _on_player_died(cause: String) -> void:
	deaths += 1
	mark("death")
	Telemetry.log_event("death", {"cause": cause, "pos": player.global_position})
	hud.fade_to(1.0, 3.0)
	_respawn_timer = 1.4
	chrono.end_all_glitches()
	var quips := {
		"oxygen": "You have stopped breathing. I am rewinding the embarrassing part.",
		"drown": "Lungs are not designed for that. Restoring from checkpoint.",
		"fall": "That was the ground. Restoring from checkpoint.",
		"fire": "You are on fire. Were. Restoring.",
		"cold": "You have become a historical ice sample. Restoring.",
		"eaten": "I am told that was quick. Restoring.",
		"caught": "That went badly. Let us pretend it did not happen.",
	}
	chrono.say(quips.get(cause, "That went badly. Let us pretend it did not happen."), true)


func set_checkpoint(pos: Vector3, index := -1) -> void:
	if index >= 0 and index <= checkpoint_index:
		return
	if index >= 0:
		checkpoint_index = index
	checkpoint_pos = pos
	mark("checkpoint")
	Telemetry.log_event("checkpoint", {"pos": pos, "index": checkpoint_index})


## Checkpoint trigger volume.
func add_checkpoint(pos: Vector3, radius := 6.0, index := -1) -> Area3D:
	var a := MeshKit.area_sphere(self, pos, radius)
	a.body_entered.connect(func(b: Node) -> void:
		if b == player:
			set_checkpoint(pos + Vector3.UP * 0.5, index))
	return a


# -------------------------------------------------------------- objectives
func add_objective(id: String, text: String, optional := false, hidden := false) -> void:
	objectives.append({"id": id, "text": text, "done": false, "optional": optional, "hidden": hidden})
	if hud:
		hud.set_objectives(objectives)


func complete_objective(id: String) -> void:
	for o in objectives:
		if o.id == id and not o.done:
			o.done = true
			Telemetry.log_event("objective", {"id": id})
			hud.set_objectives(objectives)
			Sfx.play("objective")
			objective_done.emit(id)
			return


func reveal_objective(id: String) -> void:
	for o in objectives:
		if o.id == id:
			o.hidden = false
	hud.set_objectives(objectives)


func set_objective_text(id: String, text: String) -> void:
	for o in objectives:
		if o.id == id:
			o.text = text
	hud.set_objectives(objectives)


func objective_is_done(id: String) -> bool:
	for o in objectives:
		if o.id == id:
			return o.done
	return false


func objectives_complete() -> bool:
	for o in objectives:
		if not o.done and not o.optional:
			return false
	return true


# ------------------------------------------------------- mechanics / meters
## Records that a mechanic actually fired (tests assert on these).
func mark(mechanic: String) -> void:
	if not mechanics.has(mechanic):
		Telemetry.log_event("mechanic_first", {"name": mechanic})
	mechanics[mechanic] = int(mechanics.get(mechanic, 0)) + 1


func add_meter(id: String, label: String, start := 1.0, color := Color(0.85, 0.82, 0.74)) -> void:
	meters[id] = start
	hud.add_meter(id, label, color)
	hud.set_meter(id, start)


func set_meter(id: String, value: float, warn_below := 0.25) -> void:
	value = clampf(value, 0.0, 1.0)
	meters[id] = value
	hud.set_meter(id, value, value < warn_below)


func meter(id: String) -> float:
	return meters.get(id, 0.0)


func rewind_capture() -> Dictionary:
	return meters.duplicate()


func rewind_restore(d: Dictionary) -> void:
	for k in d:
		if meters.has(k):
			set_meter(k, d[k])


# ------------------------------------------------------------ world hooks
func wdelta(delta: float) -> float:
	return delta * world_time_scale


## Broadcasts a sound to anything in group "hearing" (they get hear(pos, loudness, source)).
func emit_noise(pos: Vector3, radius: float, loudness := 1.0, source := "player") -> void:
	mark("noise_event")
	noise_emitted.emit(pos, radius, loudness, source)
	for n in get_tree().get_nodes_in_group("hearing"):
		var n3 := n as Node3D
		if n3 and n3.has_method("hear") and n3.global_position.distance_to(pos) <= radius:
			n3.hear(pos, loudness, source)


func set_era_flash(active: bool) -> void:
	if active == era_flash_active:
		return
	era_flash_active = active
	if env:
		if active:
			_env_saved = {
				"sat": env.adjustment_saturation, "con": env.adjustment_contrast,
				"fog": env.fog_light_color, "vol": env.volumetric_fog_albedo,
				"bri": env.adjustment_brightness,
			}
			env.adjustment_enabled = true
			env.adjustment_saturation = 0.35
			env.adjustment_contrast = 1.25
			env.adjustment_brightness = 0.92
			env.fog_light_color = flash_tint * 0.6
			env.volumetric_fog_albedo = flash_tint
		elif not _env_saved.is_empty():
			env.adjustment_saturation = _env_saved.sat
			env.adjustment_contrast = _env_saved.con
			env.adjustment_brightness = _env_saved.bri
			env.fog_light_color = _env_saved.fog
			env.volumetric_fog_albedo = _env_saved.vol
	for n in get_tree().get_nodes_in_group("flash_only"):
		(n as Node3D).visible = active
	for n in get_tree().get_nodes_in_group("flash_hidden"):
		(n as Node3D).visible = not active
	_on_era_flash(active)


## Register a point of interest for the scanner.
func add_poi(node: Node3D, label: String, kind := "poi") -> void:
	node.add_to_group("poi")
	node.set_meta("poi_label", label)
	node.set_meta("poi_kind", kind)


func remove_poi(node: Node3D) -> void:
	if node.is_in_group("poi"):
		node.remove_from_group("poi")


func ground_y(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain else 0.0


func on_ground(x: float, z: float, lift := 0.0) -> Vector3:
	return Vector3(x, ground_y(x, z) + lift, z)


# ------------------------------------------------------------- completion
func open_portal() -> void:
	if portal and not portal.is_open:
		portal.open()
		mark("portal_open")
		Telemetry.log_event("portal_open", {})
		Sfx.play("portal", portal.global_position)


func _on_portal_entered() -> void:
	if is_complete or not player.alive:
		return
	is_complete = true
	mark("portal_entered")
	Telemetry.log_event("era_complete", {"era": era_id, "time": elapsed, "deaths": deaths, "mechanics": mechanics})
	Telemetry.flush()
	Game.complete_era(era_id)
	player.control_locked = true
	hud.glitch_fx(1.0, 1.6)
	hud.fade_to(1.0, 0.9)
	completed.emit()
	if Game.mode == "play":
		_finish_timer = 1.8


func _physics_process(delta: float) -> void:
	if not is_ready:
		return
	elapsed += delta
	if _respawn_timer >= 0.0:
		_respawn_timer -= delta
		if _respawn_timer < 0.0:
			player.revive(checkpoint_pos)
			hud.fade_to(0.0, 1.5)
			_on_respawn()
			Telemetry.log_event("respawn", {"pos": checkpoint_pos})
	if _finish_timer >= 0.0:
		_finish_timer -= delta
		if _finish_timer < 0.0:
			_goto_next()
			return
	if portal and portal.auto_open and not portal.is_open and objectives_complete():
		open_portal()
	_era_process(delta)


func _goto_next() -> void:
	var nxt := Game.next_era(era_id)
	if nxt == "":
		Game.goto_menu()
	else:
		Game.goto_era(nxt)


# ------------------------------------------------------------- navigation
func _bake_navigation() -> void:
	var t0 := Time.get_ticks_msec()
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nav_cell)
	NavigationServer3D.map_set_cell_height(map, 0.25)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.cell_size = nav_cell
	nm.cell_height = 0.25
	nm.agent_radius = nav_cell
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 46.0
	nm.region_min_size = 8.0
	if nav_bounds.size != Vector3.ZERO:
		nm.filter_baking_aabb = nav_bounds
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	region.navigation_mesh = nm
	add_child(region)
	Telemetry.log_event("nav_bake", {"ms": Time.get_ticks_msec() - t0, "polys": nm.get_polygon_count()})


# -------------------------------------------------------------- telemetry
func telemetry_snapshot() -> Dictionary:
	var objs := {}
	for o in objectives:
		objs[o.id] = o.done
	var ai := {}
	for n in get_tree().get_nodes_in_group("telemetry_ai"):
		if n.has_method("telemetry"):
			ai[String(n.name)] = n.telemetry()
	var snap := {
		"era": era_id,
		"elapsed": elapsed,
		"player": {
			"pos": player.global_position, "state": player.state_name(), "speed": player.horizontal_speed(),
			"noise": player.noise, "vis": player.visibility, "crouch": player.crouching,
			"water": player.water_depth, "alive": player.alive, "carry": player.carried != null,
			"on_floor": player.is_on_floor(),
		},
		"meters": meters.duplicate(),
		"objectives": objs,
		"events": director.fired.keys(),
		"glitches": chrono.active_glitches.keys(),
		"ai": ai,
		"water_level": water_level if water_level > -999.0 else null,
		"portal_open": portal.is_open if portal else false,
	}
	if bot and is_instance_valid(bot):
		snap["bot"] = bot.telemetry()
	var extra := _telemetry_extra()
	if not extra.is_empty():
		snap["x"] = extra
	return snap


func _telemetry_extra() -> Dictionary:
	return {}
