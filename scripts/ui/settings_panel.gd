class_name SettingsPanel extends VBoxContainer
## Graphics quality presets, look sensitivity, volume, fullscreen, key rebinding.

signal closed

const ACTIONS := [["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["jump", "Jump / climb"], ["sprint", "Sprint"], ["crouch", "Crouch / slide"], ["interact", "Interact"], ["throw", "Throw"],
	["scan", "CHRONO scan"], ["rewind", "CHRONO rewind"], ["lock_on", "Lock on"]]

var _listening := ""
var _bind_buttons := {}
var first_focus: Control


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(UiKit.label("SETTINGS", 44))
	add_child(UiKit.rule())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	# quality
	grid.add_child(UiKit.label("Graphics quality", 26, UiKit.DIM))
	var q := OptionButton.new()
	var presets := ["low", "medium", "high", "ultra"]
	for p in presets:
		q.add_item(p.capitalize())
	q.select(maxi(0, presets.find(Game.settings.quality)))
	q.item_selected.connect(func(i: int) -> void: Game.set_setting("quality", presets[i]))
	grid.add_child(q)
	first_focus = q
	# sensitivity
	grid.add_child(UiKit.label("Look sensitivity", 26, UiKit.DIM))
	grid.add_child(_slider(0.2, 3.0, Game.settings.sensitivity, func(v: float) -> void: Game.set_setting("sensitivity", v)))
	grid.add_child(UiKit.label("Master volume", 26, UiKit.DIM))
	grid.add_child(_slider(0.0, 1.0, Game.settings.master_volume, func(v: float) -> void: Game.set_setting("master_volume", v)))
	grid.add_child(UiKit.label("Invert vertical look", 26, UiKit.DIM))
	grid.add_child(_check(Game.settings.invert_y, func(on: bool) -> void: Game.set_setting("invert_y", on)))
	grid.add_child(UiKit.label("Fullscreen", 26, UiKit.DIM))
	grid.add_child(_check(Game.settings.fullscreen, func(on: bool) -> void: Game.set_setting("fullscreen", on)))
	add_child(UiKit.rule())
	add_child(UiKit.label("Key bindings (select one, then press a key)", 22, UiKit.DIM))
	var keys := GridContainer.new()
	keys.columns = 4
	keys.add_theme_constant_override("h_separation", 24)
	add_child(keys)
	for a in ACTIONS:
		keys.add_child(UiKit.label(a[1], 22, UiKit.DIM))
		var b := UiKit.button(Game.binding_label(a[0]), _listen.bind(a[0]), 22)
		b.custom_minimum_size = Vector2(150, 0)
		keys.add_child(b)
		_bind_buttons[a[0]] = b
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	add_child(row)
	row.add_child(UiKit.button("Reset bindings", func() -> void:
		Game.reset_bindings()
		_refresh(), 24))
	row.add_child(UiKit.button("Back", func() -> void: closed.emit(), 24))


func _slider(lo: float, hi: float, value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(320, 30)
	s.value_changed.connect(on_change)
	return s


func _check(on: bool, on_change: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = on
	c.toggled.connect(on_change)
	return c


func _listen(action: String) -> void:
	_listening = action
	(_bind_buttons[action] as Button).text = "press a key..."


func _refresh() -> void:
	for a in _bind_buttons:
		(_bind_buttons[a] as Button).text = Game.binding_label(a)


func _input(event: InputEvent) -> void:
	if _listening == "" or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()
		if event.physical_keycode != KEY_ESCAPE:
			Game.rebind(_listening, event.physical_keycode)
		_listening = ""
		_refresh()
