extends Node
## Global game state: era list, run mode, settings, save data, input map.

signal settings_changed

const ERAS: Array[Dictionary] = [
	{"id": "cambrian", "title": "Cambrian Tidal Flats", "when": "510 million years ago", "act": 1},
	{"id": "carboniferous", "title": "Carboniferous Swamp", "when": "310 million years ago", "act": 1},
	{"id": "cretaceous", "title": "Late Cretaceous", "when": "67 million years ago", "act": 1},
	{"id": "pleistocene", "title": "Pleistocene Ice Age", "when": "45,000 years ago", "act": 1},
	{"id": "indus", "title": "Mohenjo-daro", "when": "c. 2500 BCE", "act": 2},
	{"id": "egypt", "title": "Giza", "when": "c. 2560 BCE", "act": 2},
	{"id": "chola", "title": "Thanjavur", "when": "1010 CE", "act": 2},
	{"id": "medieval", "title": "Medieval Europe", "when": "c. 1240 CE", "act": 2},
]
const DEV_SCENES := {"greybox": "res://scenes/dev/greybox.tscn"}
const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://save.cfg"

const QUALITY_PRESETS := {
	"low": {"sdfgi": false, "vol_fog": false, "ssao": false, "ssil": false, "ssr": false, "glow": true, "shadow": 2048, "scale": 0.75, "foliage": 0.5},
	"medium": {"sdfgi": false, "vol_fog": true, "ssao": true, "ssil": false, "ssr": false, "glow": true, "shadow": 2048, "scale": 0.85, "foliage": 0.75},
	"high": {"sdfgi": true, "vol_fog": true, "ssao": true, "ssil": true, "ssr": true, "glow": true, "shadow": 4096, "scale": 1.0, "foliage": 1.0},
	"ultra": {"sdfgi": true, "vol_fog": true, "ssao": true, "ssil": true, "ssr": true, "glow": true, "shadow": 8192, "scale": 1.0, "foliage": 1.0},
}

## Default bindings. Each entry: [keys, mouse buttons, joy buttons]
const DEFAULT_BINDINGS := {
	"move_forward": [[KEY_W, KEY_UP], [], []],
	"move_back": [[KEY_S, KEY_DOWN], [], []],
	"move_left": [[KEY_A, KEY_LEFT], [], []],
	"move_right": [[KEY_D, KEY_RIGHT], [], []],
	"jump": [[KEY_SPACE], [], [JOY_BUTTON_A]],
	"sprint": [[KEY_SHIFT], [], [JOY_BUTTON_LEFT_STICK]],
	"crouch": [[KEY_CTRL, KEY_C], [], [JOY_BUTTON_B]],
	"interact": [[KEY_E], [], [JOY_BUTTON_X]],
	"throw": [[KEY_F], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_RIGHT_SHOULDER]],
	"scan": [[KEY_Q], [], [JOY_BUTTON_Y]],
	"rewind": [[KEY_R], [], [JOY_BUTTON_LEFT_SHOULDER]],
	"lock_on": [[KEY_TAB], [MOUSE_BUTTON_MIDDLE], [JOY_BUTTON_RIGHT_STICK]],
	"pause": [[KEY_ESCAPE], [], [JOY_BUTTON_START]],
}

## "play" | "test" | "capture" | "perf"
var mode := "play"
var headless := false
var bot_enabled := false
var user_args := {}

var settings := {
	"quality": "high",
	"sensitivity": 1.0,
	"invert_y": false,
	"master_volume": 0.8,
	"fullscreen": false,
	"bindings": {},
}
var unlocked := 1
var current_era: Node = null
var _era_index := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	headless = DisplayServer.get_name() == "headless"
	for i in ERAS.size():
		_era_index[ERAS[i].id] = i
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var kv := s.split("=", true, 1)
		user_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_load_settings()
	_load_save()
	_setup_input()
	if not headless:
		apply_window_settings()


# ------------------------------------------------------------------ eras
func era_scene(id: String) -> String:
	if DEV_SCENES.has(id):
		return DEV_SCENES[id]
	if ResourceLoader.exists("res://scenes/dev/%s.tscn" % id):
		return "res://scenes/dev/%s.tscn" % id
	return "res://scenes/eras/%s/%s.tscn" % [id, id]


func era_info(id: String) -> Dictionary:
	if _era_index.has(id):
		return ERAS[_era_index[id]]
	return {"id": id, "title": id.capitalize(), "when": "", "act": 0}


func era_ids() -> Array:
	var out := []
	for e in ERAS:
		out.append(e.id)
	return out


func next_era(id: String) -> String:
	var i: int = _era_index.get(id, -1)
	if i < 0 or i + 1 >= ERAS.size():
		return ""
	return ERAS[i + 1].id


func is_unlocked(id: String) -> bool:
	return _era_index.get(id, 999) < unlocked


func complete_era(id: String) -> void:
	var i: int = _era_index.get(id, -1)
	if i >= 0 and i + 2 > unlocked:
		unlocked = mini(i + 2, ERAS.size())
		_write_save()


func goto_era(id: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(era_scene(id))


func goto_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# -------------------------------------------------------------- settings
func quality() -> Dictionary:
	return QUALITY_PRESETS.get(settings.quality, QUALITY_PRESETS.high)


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	_write_settings()
	if key in ["fullscreen", "quality"] and not headless:
		apply_window_settings()
	settings_changed.emit()


func apply_window_settings() -> void:
	var q := quality()
	var root := get_tree().root
	root.scaling_3d_scale = q.scale
	RenderingServer.directional_shadow_atlas_set_size(q.shadow, true)
	if mode == "play":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(settings.master_volume, 0.0001)))


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings:
		settings[k] = cf.get_value("settings", k, settings[k])


func _write_settings() -> void:
	if mode != "play":
		return
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		unlocked = clampi(cf.get_value("progress", "unlocked", 1), 1, ERAS.size())


func _write_save() -> void:
	if mode != "play":
		return
	var cf := ConfigFile.new()
	cf.set_value("progress", "unlocked", unlocked)
	cf.save(SAVE_PATH)


# ----------------------------------------------------------------- input
func _setup_input() -> void:
	for action in DEFAULT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.3)
		InputMap.action_erase_events(action)
		var saved: Variant = settings.bindings.get(action, null)
		var b: Array = DEFAULT_BINDINGS[action]
		var keys: Array = b[0]
		if saved != null:
			keys = [int(saved)]
		for k in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		for m in b[1]:
			var em := InputEventMouseButton.new()
			em.button_index = m
			InputMap.action_add_event(action, em)
		for j in b[2]:
			var ej := InputEventJoypadButton.new()
			ej.button_index = j
			InputMap.action_add_event(action, ej)
	# Left stick movement
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0]}
	for action in axes:
		var ea := InputEventJoypadMotion.new()
		ea.axis = axes[action][0]
		ea.axis_value = axes[action][1]
		InputMap.action_add_event(action, ea)
	# Trigger = sprint
	var et := InputEventJoypadMotion.new()
	et.axis = JOY_AXIS_TRIGGER_LEFT
	et.axis_value = 1.0
	InputMap.action_add_event("sprint", et)


func rebind(action: String, keycode: int) -> void:
	settings.bindings[action] = keycode
	_write_settings()
	_setup_input()
	settings_changed.emit()


func reset_bindings() -> void:
	settings.bindings = {}
	_write_settings()
	_setup_input()
	settings_changed.emit()


func binding_label(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
	return "?"
