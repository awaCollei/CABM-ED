class_name UIStyleFactory
extends RefCounted

## 全局界面风格工厂。这里只创建 Theme/StyleBox，不持有场景节点。
const STYLE_DEFAULT := "default"
const STYLE_NOTEBOOK := "notebook"
const STYLE_MODERN := "modern"
const STYLE_SCIFI := "scifi"
const VALID_STYLES := [STYLE_DEFAULT, STYLE_NOTEBOOK, STYLE_MODERN, STYLE_SCIFI]


static func normalize_style(style_id: String) -> String:
	return style_id if style_id in VALID_STYLES else STYLE_NOTEBOOK


static func create_theme(
	style_id: String, button_opacity: float = 1.0, panel_opacity: float = 1.0
) -> Theme:
	style_id = normalize_style(style_id)
	button_opacity = clampf(button_opacity, 0.0, 1.0)
	panel_opacity = clampf(panel_opacity, 0.0, 1.0)
	if style_id == STYLE_DEFAULT:
		return null

	var palette := _palette(style_id)
	var result := Theme.new()
	var text: Color = palette.text
	var muted: Color = palette.muted
	var accent: Color = palette.accent

	for type_name in ["Label", "Button", "CheckBox", "CheckButton", "LineEdit", "TextEdit"]:
		result.set_color("font_color", type_name, text)
	result.set_color("font_hover_color", "Button", accent)
	result.set_color("font_pressed_color", "Button", accent.darkened(0.2))
	result.set_color("font_focus_color", "Button", text)
	result.set_color("font_disabled_color", "Button", Color(muted.r, muted.g, muted.b, 0.55))
	result.set_color("font_placeholder_color", "LineEdit", muted)
	result.set_color("font_placeholder_color", "TextEdit", muted)
	result.set_color("caret_color", "LineEdit", accent)
	result.set_color("caret_color", "TextEdit", accent)

	result.set_stylebox(
		"normal", "Button", _button_box(style_id, "normal", palette, button_opacity)
	)
	result.set_stylebox("hover", "Button", _button_box(style_id, "hover", palette, button_opacity))
	result.set_stylebox(
		"pressed", "Button", _button_box(style_id, "pressed", palette, button_opacity)
	)
	result.set_stylebox(
		"disabled", "Button", _button_box(style_id, "disabled", palette, button_opacity)
	)
	result.set_stylebox("focus", "Button", _focus_box(accent))

	for input_type in ["LineEdit", "TextEdit"]:
		result.set_stylebox(
			"normal", input_type, _input_box(palette.surface, palette.border, 1, style_id)
		)
		result.set_stylebox("focus", input_type, _input_box(palette.surface, accent, 2, style_id))
		result.set_stylebox(
			"readonly",
			input_type,
			_input_box(palette.surface.darkened(0.05), palette.border, 1, style_id)
		)

	result.set_stylebox("panel", "Panel", create_panel_style(style_id, panel_opacity))
	result.set_stylebox("separator", "HSeparator", _separator_box(style_id, palette))
	result.set_stylebox(
		"scroll",
		"VScrollBar",
		_flat_box(
			Color(palette.border.r, palette.border.g, palette.border.b, 0.22),
			Color.TRANSPARENT,
			0,
			4
		)
	)
	result.set_stylebox("grabber", "VScrollBar", _flat_box(palette.border, Color.TRANSPARENT, 0, 4))
	result.set_stylebox(
		"grabber_highlight", "VScrollBar", _flat_box(accent, Color.TRANSPARENT, 0, 4)
	)
	result.set_stylebox(
		"grabber_pressed", "VScrollBar", _flat_box(accent.darkened(0.15), Color.TRANSPARENT, 0, 4)
	)

	if style_id == STYLE_NOTEBOOK:
		# 标签的下沿模拟横格线；需要无横线的标签可在节点上覆盖 StyleBoxEmpty。
		var ruled := StyleBoxFlat.new()
		ruled.bg_color = Color.TRANSPARENT
		ruled.border_color = Color(0.647, 0.729, 0.827, 0.48)
		ruled.border_width_bottom = 1
		ruled.content_margin_left = 5.0
		ruled.content_margin_right = 5.0
		ruled.content_margin_bottom = 5.0
		result.set_stylebox("normal", "Label", ruled)

	return result


static func create_panel_style(style_id: String, opacity: float = 1.0) -> StyleBox:
	style_id = normalize_style(style_id)
	if style_id == STYLE_DEFAULT:
		return StyleBoxEmpty.new()
	var p := _palette(style_id)
	var background: Color = p.background
	background.a *= clampf(opacity, 0.0, 1.0)
	var panel := _flat_box(
		background,
		p.border,
		2 if style_id == STYLE_SCIFI else 1,
		3 if style_id == STYLE_NOTEBOOK else 10
	)
	panel.content_margin_left = 8.0
	panel.content_margin_top = 8.0
	panel.content_margin_right = 8.0
	panel.content_margin_bottom = 8.0
	panel.shadow_color = Color(0, 0, 0, 0.28)
	panel.shadow_size = 8 if style_id != STYLE_SCIFI else 3
	panel.shadow_offset = Vector2(0, 3)
	return panel


static func _palette(style_id: String) -> Dictionary:
	match style_id:
		STYLE_MODERN:
			return {
				"background": Color(0.965, 0.973, 0.98, 0.96),
				"surface": Color(1, 1, 1, 0.96),
				"button": Color(0.91, 0.93, 0.945, 1),
				"button_hover": Color(0.84, 0.9, 0.94, 1),
				"text": Color(0.10, 0.14, 0.17),
				"muted": Color(0.38, 0.44, 0.48),
				"border": Color(0.65, 0.7, 0.73),
				"accent": Color(0.08, 0.48, 0.56)
			}
		STYLE_SCIFI:
			return {
				"background": Color(0.025, 0.065, 0.09, 0.94),
				"surface": Color(0.035, 0.10, 0.135, 0.96),
				"button": Color(0.045, 0.15, 0.19, 0.98),
				"button_hover": Color(0.06, 0.24, 0.28, 1),
				"text": Color(0.78, 0.96, 0.98),
				"muted": Color(0.48, 0.72, 0.76),
				"border": Color(0.10, 0.58, 0.64),
				"accent": Color(0.18, 0.92, 0.92)
			}
		_:
			return {
				"background": Color(0.965, 0.945, 0.878, 0.98),
				"surface": Color(1.0, 0.984, 0.89, 0.98),
				"button": Color(1.0, 0.91, 0.47, 0.98),
				"button_hover": Color(1.0, 0.95, 0.62, 1),
				"text": Color(0.243, 0.196, 0.153),
				"muted": Color(0.427, 0.361, 0.286),
				"border": Color(0.66, 0.54, 0.34),
				"accent": Color(0.753, 0.373, 0.302)
			}


static func _button_box(
	style_id: String, state: String, p: Dictionary, opacity: float
) -> StyleBoxFlat:
	var fill: Color = p.button
	var border: Color = p.border
	var shadow_size := 3
	if state == "hover":
		fill = p.button_hover
		border = p.accent
		shadow_size = 5
	elif state == "pressed":
		fill = p.button_hover.darkened(0.08)
		border = p.accent.darkened(0.1)
		shadow_size = 0
	elif state == "disabled":
		fill = Color(p.button.r, p.button.g, p.button.b, 0.45)
		border = Color(p.border.r, p.border.g, p.border.b, 0.45)
		shadow_size = 0
	fill.a *= opacity
	border.a *= opacity
	var box := _flat_box(
		fill, border, 2 if state == "pressed" else 1, 3 if style_id == STYLE_NOTEBOOK else 8
	)
	box.border_width_bottom = (
		3 if style_id == STYLE_NOTEBOOK and state != "pressed" else box.border_width_bottom
	)
	box.shadow_color = Color(0.12, 0.08, 0.04, 0.25 * opacity)
	box.shadow_size = shadow_size
	box.shadow_offset = Vector2(0, 2)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 7.0 if state != "pressed" else 9.0
	box.content_margin_bottom = 9.0 if state != "pressed" else 7.0
	return box


static func _input_box(fill: Color, border: Color, width: int, style_id: String) -> StyleBoxFlat:
	var box := _flat_box(fill, border, width, 3 if style_id == STYLE_NOTEBOOK else 8)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 7.0
	box.content_margin_bottom = 7.0
	return box


static func _separator_box(style_id: String, p: Dictionary) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = p.accent if style_id == STYLE_SCIFI else p.border
	box.border_width_bottom = 1
	box.content_margin_top = 6.0
	return box


static func _focus_box(accent: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	return box


static func _flat_box(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	return box
