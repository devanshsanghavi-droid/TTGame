class_name DialogueUI extends CanvasLayer
## Branching dialogue with choices.
##
## Tree format: { "start": {"who": "Trader", "text": "...",
##     "choices": [{"text": "...", "goto": "node_id", "do": Callable, "if": Callable}],
##     "goto": "node_id",   # used when there are no choices
##     "do": Callable}, ... }
## A node with no choices and no goto ends the conversation.
## While CHRONO's translator is glitching, non-CHRONO lines are scrambled.

signal finished(last_node: String)
signal node_shown(id: String)

var era: Node
var active := false
var current := ""
var choices_shown: Array = []

var _tree := {}
var _panel: PanelContainer
var _who: Label
var _text: Label
var _choices: VBoxContainer
var _hint: Label
var _sel := 0
var _line_time := 0.0


func _ready() -> void:
	layer = 12
	var font := HUD.serif_font()
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.032, 0.03, 0.86)
	sb.border_color = Color(0.9, 0.87, 0.8, 0.25)
	sb.border_width_top = 1
	sb.set_content_margin_all(26)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.position.y = -60
	_panel.custom_minimum_size = Vector2(980, 0)
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 26
	_panel.theme = th
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_who = Label.new()
	_who.add_theme_font_size_override("font_size", 20)
	_who.add_theme_color_override("font_color", Color(0.9, 0.87, 0.8, 0.6))
	v.add_child(_who)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(920, 0)
	_text.add_theme_font_size_override("font_size", 29)
	_text.add_theme_color_override("font_color", Color(0.92, 0.89, 0.82))
	v.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	v.add_child(_choices)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.9, 0.87, 0.8, 0.4))
	v.add_child(_hint)
	_panel.visible = false
	add_child(_panel)


func start(tree: Dictionary, start_id := "start") -> void:
	_tree = tree
	active = true
	_panel.visible = true
	if era and era.player:
		era.player.control_locked = true
	if era:
		era.mark("dialogue")
	Telemetry.log_event("dialogue_start", {"node": start_id})
	_show(start_id)


func stop() -> void:
	if not active:
		return
	active = false
	_panel.visible = false
	choices_shown = []
	if era and era.player:
		era.player.control_locked = false
	Telemetry.log_event("dialogue_end", {"node": current})
	finished.emit(current)


func _show(id: String) -> void:
	if not _tree.has(id):
		stop()
		return
	current = id
	var node: Dictionary = _tree[id]
	if node.has("do"):
		(node["do"] as Callable).call()
		if not active:
			return
	var who: String = node.get("who", "")
	var text: String = node.get("text", "")
	var chrono: ChronoDevice = era.chrono if era else null
	if chrono and who != "CHRONO" and who != "You":
		text = chrono.translate(text)
	_who.text = who.to_upper()
	_text.text = text
	for c in _choices.get_children():
		c.queue_free()
	choices_shown = []
	for ch in node.get("choices", []):
		if ch.has("if") and not bool((ch["if"] as Callable).call()):
			continue
		choices_shown.append(ch)
	_sel = 0
	for i in choices_shown.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 26)
		_choices.add_child(l)
	_refresh_choices()
	_hint.text = "[%s] continue" % Game.binding_label("interact") if choices_shown.is_empty() else "[W/S] choose    [%s] confirm" % Game.binding_label("interact")
	_line_time = 0.0
	_panel.reset_size()
	Telemetry.log_event("dialogue_node", {"node": id, "choices": choices_shown.size()})
	node_shown.emit(id)


func _refresh_choices() -> void:
	var labels := _choices.get_children()
	for i in mini(labels.size(), choices_shown.size()):
		var l := labels[i] as Label
		l.text = ("›  " if i == _sel else "    ") + String(choices_shown[i].text)
		l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78) if i == _sel else Color(0.9, 0.87, 0.8, 0.55))


## Advance a line with no choices.
func advance() -> void:
	if not active or not choices_shown.is_empty():
		return
	var node: Dictionary = _tree.get(current, {})
	if node.has("goto"):
		_show(node["goto"])
	else:
		stop()


func choose(i: int) -> void:
	if not active or i < 0 or i >= choices_shown.size():
		return
	var ch: Dictionary = choices_shown[i]
	Telemetry.log_event("dialogue_choice", {"node": current, "choice": i, "text": ch.text})
	if ch.has("do"):
		(ch["do"] as Callable).call()
		if not active:
			return
	if ch.has("goto"):
		_show(ch["goto"])
	else:
		stop()


func _process(delta: float) -> void:
	if active:
		_line_time += delta


func _unhandled_input(event: InputEvent) -> void:
	if not active or _line_time < 0.25:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		if choices_shown.is_empty():
			advance()
		else:
			choose(_sel)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_back") and not choices_shown.is_empty():
		_sel = (_sel + 1) % choices_shown.size()
		_refresh_choices()
	elif event.is_action_pressed("move_forward") and not choices_shown.is_empty():
		_sel = (_sel - 1 + choices_shown.size()) % choices_shown.size()
		_refresh_choices()
