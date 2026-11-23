class_name UiKit extends RefCounted
## Shared menu styling: bone-coloured serif text on near-black, thin rules.

const INK := Color(0.9, 0.87, 0.8)
const DIM := Color(0.9, 0.87, 0.8, 0.5)
const BG := Color(0.03, 0.03, 0.032, 0.94)


static func theme() -> Theme:
	var th := Theme.new()
	th.default_font = HUD.serif_font()
	th.default_font_size = 30
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_content_margin_all(8)
	flat.content_margin_left = 18
	flat.content_margin_right = 18
	var hover := flat.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.9, 0.87, 0.8, 0.08)
	hover.border_color = Color(0.9, 0.87, 0.8, 0.55)
	hover.border_width_left = 2
	for st in ["normal", "disabled"]:
		th.set_stylebox(st, "Button", flat)
	for st in ["hover", "focus", "pressed"]:
		th.set_stylebox(st, "Button", hover)
	th.set_color("font_color", "Button", DIM)
	th.set_color("font_hover_color", "Button", INK)
	th.set_color("font_focus_color", "Button", INK)
	th.set_color("font_pressed_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color(0.9, 0.87, 0.8, 0.2))
	th.set_color("font_color", "Label", INK)
	th.set_stylebox("normal", "OptionButton", hover)
	th.set_stylebox("focus", "OptionButton", hover)
	th.set_stylebox("hover", "OptionButton", hover)
	th.set_color("font_color", "CheckBox", DIM)
	th.set_color("font_hover_color", "CheckBox", INK)
	th.set_color("font_focus_color", "CheckBox", INK)
	return th


static func button(text: String, on_press: Callable, size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void:
		Sfx.play("ui")
		on_press.call())
	return b


static func label(text: String, size := 30, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.9, 0.87, 0.8, 0.18)
	r.custom_minimum_size = Vector2(0, 1)
	return r
