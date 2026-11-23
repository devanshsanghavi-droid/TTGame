extends CanvasLayer
## In-game pause menu: resume, restart from checkpoint, settings, quit to menu.

var era: Node
var is_open := false

var _root: Control
var _main: VBoxContainer
var _settings: SettingsPanel
var _first: Button
var _prev_mouse := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.visible = false
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 160)
	margin.add_theme_constant_override("margin_top", 130)
	_root.add_child(margin)
	var holder := VBoxContainer.new()
	margin.add_child(holder)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 4)
	holder.add_child(_main)
	_main.add_child(UiKit.label("PAUSED", 64))
	_main.add_child(UiKit.label(Game.era_info(era.era_id).title if era else "", 26, UiKit.DIM))
	_main.add_child(UiKit.rule())
	_first = UiKit.button("Resume", close)
	_main.add_child(_first)
	_main.add_child(UiKit.button("Restart from checkpoint", func() -> void:
		close()
		if era:
			era.restart_from_checkpoint()))
	_main.add_child(UiKit.button("Settings", func() -> void:
		_main.visible = false
		_settings.visible = true
		_settings.first_focus.grab_focus()))
	_main.add_child(UiKit.button("Quit to main menu", func() -> void:
		close()
		Game.goto_menu()))
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_main.visible = true
		_first.grab_focus())
	holder.add_child(_settings)


func open() -> void:
	if is_open:
		return
	is_open = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_root.visible = true
	_main.visible = true
	_settings.visible = false
	_first.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	get_tree().paused = false
	_root.visible = false
	Input.mouse_mode = _prev_mouse


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and Game.mode == "play":
		if is_open:
			close()
		elif era == null or not era.is_complete:
			open()
		get_viewport().set_input_as_handled()
