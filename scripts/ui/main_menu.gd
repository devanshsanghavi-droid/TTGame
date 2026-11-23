extends Node
## Main menu: continue, new game, era select (unlocked eras only), settings, quit.

var _root: Control
var _main: VBoxContainer
var _eras: VBoxContainer
var _settings: SettingsPanel
var _first: Button
var _bg_mat: ShaderMaterial


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.set_ambience({"wind": 0.35, "rumble": 0.25})
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	layer.add_child(_root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = load("res://shaders/menu_bg.gdshader")
	bg.material = _bg_mat
	_root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 170)
	margin.add_theme_constant_override("margin_top", 150)
	_root.add_child(margin)
	var holder := VBoxContainer.new()
	margin.add_child(holder)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 4)
	holder.add_child(_main)
	_main.add_child(UiKit.label("FRACTURED HOURS", 110))
	_main.add_child(UiKit.label("Eight eras. One malfunctioning wrist.", 30, UiKit.DIM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	_main.add_child(gap)
	var next_id: String = Game.ERAS[mini(Game.unlocked, Game.ERAS.size()) - 1].id
	if Game.unlocked > 1:
		_first = UiKit.button("Continue: " + Game.era_info(next_id).title, func() -> void: Game.goto_era(next_id), 36)
		_main.add_child(_first)
		_main.add_child(UiKit.button("New game", func() -> void: Game.goto_era(Game.ERAS[0].id), 36))
	else:
		_first = UiKit.button("Begin", func() -> void: Game.goto_era(Game.ERAS[0].id), 36)
		_main.add_child(_first)
	_main.add_child(UiKit.button("Era select", func() -> void: _show(_eras), 36))
	_main.add_child(UiKit.button("Settings", func() -> void: _show(_settings), 36))
	_main.add_child(UiKit.button("Quit", func() -> void: get_tree().quit(), 36))

	_eras = VBoxContainer.new()
	_eras.add_theme_constant_override("separation", 2)
	_eras.visible = false
	holder.add_child(_eras)
	_eras.add_child(UiKit.label("ERA SELECT", 44))
	_eras.add_child(UiKit.rule())
	var act := 0
	for i in Game.ERAS.size():
		var e: Dictionary = Game.ERAS[i]
		if e.act != act:
			act = e.act
			_eras.add_child(UiKit.label("ACT %s: %s" % ["I" if act == 1 else "II", "DEEP TIME" if act == 1 else "CIVILIZATIONS"], 20, UiKit.DIM))
		var unlocked := i < Game.unlocked and ResourceLoader.exists(Game.era_scene(e.id))
		var b := UiKit.button("%d.  %s   (%s)" % [i + 1, e.title, e.when] if unlocked else "%d.  Locked" % (i + 1), Game.goto_era.bind(e.id), 30)
		b.disabled = not unlocked
		if not unlocked:
			b.focus_mode = Control.FOCUS_NONE
		_eras.add_child(b)
	_eras.add_child(UiKit.button("Back", func() -> void: _show(_main), 26))

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void: _show(_main))
	holder.add_child(_settings)
	_first.grab_focus.call_deferred()


func _show(panel: Control) -> void:
	_main.visible = panel == _main
	_eras.visible = panel == _eras
	_settings.visible = panel == _settings
	if panel == _main:
		_first.grab_focus()
	elif panel == _settings:
		_settings.first_focus.grab_focus()
	else:
		for c in _eras.get_children():
			if c is Button and not (c as Button).disabled:
				(c as Button).grab_focus()
				break
