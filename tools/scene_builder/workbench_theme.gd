@tool
extends RefCounted

const ACCENT := Color("65d6c3")
const TEXT := Color("dce8ef")
const MUTED := Color("91a8b8")

static func box(color: Color, border: Color = Color("304754"), radius: int = 6, margin: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

static func build() -> Theme:
	var theme := Theme.new()
	theme.set_stylebox("panel", "PanelContainer", box(Color("15232d"), Color("385564"), 8, 8))
	for type in ["Label", "Button", "OptionButton", "CheckBox", "CheckButton", "LineEdit", "MenuButton"]:
		theme.set_font_size("font_size", type, 14)
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, MUTED.darkened(0.25))
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, box(Color("223744"), Color("304754"), 5, 3))
		theme.set_stylebox("hover", type, box(Color("2c4958"), ACCENT.darkened(0.3), 5, 3))
		theme.set_stylebox("pressed", type, box(Color("285a59"), ACCENT, 5, 3))
		theme.set_stylebox("disabled", type, box(Color("1a2a34"), Color("273c49"), 5, 3))
		theme.set_stylebox("focus", type, box(Color(0, 0, 0, 0), ACCENT, 6, 0))
	theme.set_stylebox("normal", "LineEdit", box(Color("101c25"), Color("304754"), 5, 4))
	theme.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), ACCENT, 6, 0))
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_stylebox("panel", "ItemList", box(Color("111d26"), Color("263d4a"), 5, 5))
	theme.set_stylebox("selected", "ItemList", box(Color("284c55"), ACCENT))
	theme.set_stylebox("selected_focus", "ItemList", box(Color("284c55"), ACCENT))
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_font_size("font_size", "ItemList", 14)
	theme.set_stylebox("background", "ProgressBar", box(Color("101b23"), Color("101b23"), 2, 0))
	theme.set_stylebox("fill", "ProgressBar", box(ACCENT, ACCENT, 2, 0))
	theme.set_constant("separation", "VBoxContainer", 5)
	theme.set_constant("separation", "HBoxContainer", 5)
	return theme
