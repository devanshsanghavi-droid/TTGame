class_name HUD extends CanvasLayer
## In-game HUD. Deliberately sparse: objectives, CHRONO subtitles, a context
## prompt, and only the survival meters the current era registers.

const INK := Color(0.9, 0.87, 0.8)
const INK_DIM := Color(0.9, 0.87, 0.8, 0.62)
const SHADE := Color(0.03, 0.03, 0.03, 0.55)

var era: Node
var player: Player
var camera: Camera3D
var hidden_for_capture := false

var _root: Control
var _objectives: VBoxContainer
var _title_small: Label
var _sub_panel: PanelContainer
var _sub_who: Label
var _sub_text: Label
var _prompt: Label
var _meters_box: VBoxContainer
var _meters := {}
var _fade: ColorRect
var _glitch: ColorRect
var _glitch_mat: ShaderMaterial
var _card: VBoxContainer
var _card_title: Label
var _card_sub: Label
var _toast: Label
var _status: Label
var _marks_layer: Control
var _marks: Array = []
var _marks_time := 0.0
var _sub_queue: Array = []
var _sub_time := 0.0
var _glitch_time := 0.0
var _glitch_peak := 0.0
var _card_time := 0.0
var _toast_time := 0.0
var _fade_target := 0.0
var _fade_speed := 1.5
var _font: Font
var _glitch_tint := Vector3(0.8, 0.9, 0.85)


static func serif_font() -> Font:
	var p: String = MatLib.manifest().get("fonts", {}).get("serif", "")
	if p != "" and ResourceLoader.exists(p):
		return load(p)
	return ThemeDB.fallback_font


func _ready() -> void:
	layer = 10
	_font = serif_font()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = _font
	th.default_font_size = 24
	_root.theme = th
	add_child(_root)

	# glitch overlay (below the text)
	_glitch = ColorRect.new()
	_glitch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_mat = ShaderMaterial.new()
	_glitch_mat.shader = load("res://shaders/glitch_overlay.gdshader")
	_glitch.material = _glitch_mat
	_glitch.visible = false
	_root.add_child(_glitch)

	_marks_layer = Control.new()
	_marks_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_marks_layer)

	# objectives, top-left
	var ob := VBoxContainer.new()
	ob.position = Vector2(44, 36)
	ob.add_theme_constant_override("separation", 2)
	_root.add_child(ob)
	_title_small = _label("", 26, INK_DIM)
	ob.add_child(_title_small)
	_objectives = VBoxContainer.new()
	_objectives.add_theme_constant_override("separation", 0)
	ob.add_child(_objectives)

	# meters, bottom-left
	_meters_box = VBoxContainer.new()
	_meters_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_meters_box.position = Vector2(44, -44)
	_meters_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_meters_box.add_theme_constant_override("separation", 10)
	_root.add_child(_meters_box)

	# subtitle, bottom centre
	_sub_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SHADE
	sb.set_content_margin_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.set_corner_radius_all(2)
	_sub_panel.add_theme_stylebox_override("panel", sb)
	_sub_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sub_panel.position.y = -150
	_sub_panel.custom_minimum_size = Vector2(200, 0)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 0)
	_sub_panel.add_child(sv)
	_sub_who = _label("", 22, INK_DIM)
	sv.add_child(_sub_who)
	_sub_text = _label("", 35, INK)
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_text.custom_minimum_size = Vector2(760, 0)
	sv.add_child(_sub_text)
	_sub_panel.visible = false
	_root.add_child(_sub_panel)

	# prompt
	_prompt = _label("", 31, INK)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y = 150
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prompt)

	# toast
	_toast = _label("", 34, INK)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = 110
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_toast)

	# CHRONO status, bottom-right
	_status = _label("", 23, INK_DIM)
	_status.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.position = Vector2(-44, -40)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_status)

	# title card
	_card = VBoxContainer.new()
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_title = _label("", 109, INK)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_sub = _label("", 39, INK_DIM)
	_card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_card_title)
	_card.add_child(_card_sub)
	_card.modulate.a = 0.0
	_root.add_child(_card)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func set_ui_visible(on: bool) -> void:
	hidden_for_capture = not on
	for c in [_objectives.get_parent(), _meters_box, _prompt, _status, _marks_layer, _toast]:
		(c as Control).visible = on
	if not on:
		_sub_queue.clear()
		_sub_time = 0.0
		_sub_panel.visible = false
		_card.modulate.a = 0.0
		_card_time = 0.0


# ----------------------------------------------------------------- content
func set_era_title(title: String) -> void:
	_title_small.text = title.to_upper()


func title_card(title: String, sub: String, seconds := 4.5) -> void:
	_card_title.text = title.to_upper()
	_card_sub.text = sub
	_card_time = seconds


func set_objectives(list: Array) -> void:
	for c in _objectives.get_children():
		c.queue_free()
	for o in list:
		if o.get("hidden", false):
			continue
		var done: bool = o.done
		var l := _label(("✓  " if done else "·  ") + String(o.text), 30, INK_DIM if done else INK)
		_objectives.add_child(l)


func subtitle(who: String, text: String, urgent := false) -> void:
	var item := {"who": who, "text": text, "time": clampf(1.6 + text.length() * 0.055, 2.4, 8.0)}
	if urgent:
		_sub_queue.push_front(item)
		_sub_time = 0.0
	else:
		_sub_queue.append(item)
	if _sub_queue.size() > 4:
		_sub_queue = _sub_queue.slice(_sub_queue.size() - 4)


func toast(text: String, seconds := 3.0) -> void:
	_toast.text = text
	_toast_time = seconds


func add_meter(id: String, label: String, color: Color) -> void:
	if _meters.has(id):
		return
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var l := _label(label.to_upper(), 21, INK_DIM)
	row.add_child(l)
	var track := ColorRect.new()
	track.color = Color(0.02, 0.02, 0.02, 0.6)
	track.custom_minimum_size = Vector2(300, 9)
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(300, 9)
	track.add_child(fill)
	row.add_child(track)
	_meters_box.add_child(row)
	_meters[id] = {"row": row, "fill": fill, "label": l, "color": color}


func set_meter(id: String, value: float, warn := false) -> void:
	if not _meters.has(id):
		return
	var m: Dictionary = _meters[id]
	(m.fill as ColorRect).size.x = 300.0 * clampf(value, 0.0, 1.0)
	var c: Color = m.color
	if warn:
		c = c.lerp(Color(0.75, 0.2, 0.12), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
	(m.fill as ColorRect).color = c


func show_meter(id: String, on: bool) -> void:
	if _meters.has(id):
		(_meters[id].row as Control).visible = on


func show_scan(marks: Array, seconds: float) -> void:
	for c in _marks_layer.get_children():
		c.queue_free()
	_marks.clear()
	for m in marks:
		var l := _label("", 25, INK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_marks_layer.add_child(l)
		_marks.append({"node": m.node, "label": String(m.label), "kind": String(m.kind), "ui": l})
	_marks_time = seconds


func glitch_fx(intensity: float, seconds: float) -> void:
	_glitch_peak = maxf(_glitch_peak, intensity)
	_glitch_time = maxf(_glitch_time, seconds)


func set_glitch_tint(c: Color) -> void:
	_glitch_tint = Vector3(c.r, c.g, c.b)


func fade_to(alpha: float, speed := 1.5) -> void:
	_fade_target = alpha
	_fade_speed = speed


func fade_alpha() -> float:
	return _fade.color.a


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	# subtitles
	if hidden_for_capture:
		_sub_queue.clear()
	if _sub_time > 0.0:
		_sub_time -= delta
		if _sub_time <= 0.0:
			_sub_panel.visible = false
	if _sub_time <= 0.0 and _sub_queue.size() > 0:
		var item: Dictionary = _sub_queue.pop_front()
		_sub_who.text = String(item.who).to_upper()
		_sub_text.text = item.text
		_sub_time = item.time
		_sub_panel.visible = true
		_sub_panel.reset_size()
	# prompt
	var ptxt := ""
	if player and is_instance_valid(player) and player.focus and not player.control_locked:
		ptxt = "[%s]  %s" % [Game.binding_label("interact"), (player.focus as Interactable).prompt]
	elif player and is_instance_valid(player) and player.carried and not player.control_locked:
		ptxt = "[%s]  Throw      [%s]  Drop" % [Game.binding_label("throw"), Game.binding_label("interact")]
	_prompt.text = ptxt
	# toast
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
		if _toast_time <= 0.0:
			_toast.text = ""
	# card
	if _card_time > 0.0:
		_card_time -= delta
		_card.modulate.a = move_toward(_card.modulate.a, 1.0 if _card_time > 1.2 else 0.0, delta * 1.2)
	elif _card.modulate.a > 0.0:
		_card.modulate.a = move_toward(_card.modulate.a, 0.0, delta * 1.2)
	# fade
	_fade.color.a = move_toward(_fade.color.a, _fade_target, delta * _fade_speed)
	# glitch
	if _glitch_time > 0.0:
		_glitch_time -= delta
		_glitch.visible = true
		var k := _glitch_peak * clampf(_glitch_time * 2.0, 0.0, 1.0)
		_glitch_mat.set_shader_parameter("intensity", k)
		_glitch_mat.set_shader_parameter("t", Time.get_ticks_msec() * 0.001)
		_glitch_mat.set_shader_parameter("tint", _glitch_tint)
		if _glitch_time <= 0.0:
			_glitch.visible = false
			_glitch_peak = 0.0
	# CHRONO status
	if era and era.chrono and not hidden_for_capture:
		var ch: ChronoDevice = era.chrono
		var parts := PackedStringArray()
		if ch.scan_enabled:
			parts.append("[%s] SCAN %s" % [Game.binding_label("scan"), "ready" if ch.scan_cooldown <= 0.0 else "%ds" % ceili(ch.scan_cooldown)])
		if ch.rewind_enabled:
			parts.append("[%s] REWIND %s" % [Game.binding_label("rewind"), "ready" if ch.rewind_cooldown <= 0.0 else "%ds" % ceili(ch.rewind_cooldown)])
		_status.text = "     ".join(parts)
	# scan markers
	if _marks_time > 0.0:
		_marks_time -= delta
		var cam := camera if camera and is_instance_valid(camera) else get_viewport().get_camera_3d()
		var vp := get_viewport().get_visible_rect().size
		for m in _marks:
			var ui: Label = m.ui
			var node: Node3D = m.node
			if cam == null or not is_instance_valid(node) or not node.is_inside_tree():
				ui.visible = false
				continue
			var wp := node.global_position + Vector3.UP * 1.2
			var behind := cam.is_position_behind(wp)
			var sp := cam.unproject_position(wp)
			if behind:
				sp = vp - sp
				sp.y = vp.y - 80.0
			sp.x = clampf(sp.x, 90.0, vp.x - 90.0)
			sp.y = clampf(sp.y, 70.0, vp.y - 110.0)
			var dist := cam.global_position.distance_to(wp)
			ui.text = "%s\n%s  %dm" % ["◇" if m.kind != "portal" else "◈", m.label, int(dist)]
			ui.reset_size()
			ui.position = sp - ui.size * 0.5
			ui.visible = true
			ui.modulate.a = clampf(_marks_time, 0.0, 1.0) * (1.0 if m.kind == "portal" else 0.8)
		if _marks_time <= 0.0:
			for m in _marks:
				(m.ui as Label).queue_free()
			_marks.clear()
