extends Node2D

# 壁纸节点 - 仅在 livingroom 场景显示
# 使用 draw_polygon 绘制形变四边形并填充纹理，支持透视变形
# 点击壁纸区域弹出操作面板（与 interactive_element 动画一致）

var texture: Texture2D = null

@export var uv_top_left: Vector2 = Vector2(0.0, 0.0)
@export var uv_top_right: Vector2 = Vector2(1.0, 0.0)
@export var uv_bottom_right: Vector2 = Vector2(1.0, 1.0)
@export var uv_bottom_left: Vector2 = Vector2(0.0, 1.0)

@export var pos_top_left: Vector2 = Vector2(0.630, 0.194)
@export var pos_top_right: Vector2 = Vector2(0.806, 0.136)
@export var pos_bottom_right: Vector2 = Vector2(0.806, 0.432)
@export var pos_bottom_left: Vector2 = Vector2(0.630, 0.438)

var scene_rect: Rect2 = Rect2()

const ANIMATION_DURATION = 0.2

# 用 Control 做点击区域（参与 GUI 事件系统，不会被 Node2D._input 干扰）
var _hit_area: Control = null
# 弹出面板
var _popup_panel: Panel = null
var _popup_visible: bool = false
var _is_animating: bool = false

# 面板是否打开（打开时禁用壁纸点击）
var _panel_open: bool = false

signal change_wallpaper_requested

func set_texture(tex: Texture2D):
	texture = tex
	queue_redraw()

func set_scene_rect(rect: Rect2):
	scene_rect = rect
	queue_redraw()
	_update_hit_area()
	_update_popup_position()

func set_panel_open(open: bool):
	"""由外部（main.gd）在面板打开/关闭时调用"""
	_panel_open = open
	if _hit_area:
		_hit_area.mouse_filter = Control.MOUSE_FILTER_IGNORE if open else Control.MOUSE_FILTER_STOP

func _ready():
	_create_hit_area()
	_create_popup_panel()

# ── Hit Area（Control，参与 GUI 层级）────────────────────

func _create_hit_area():
	_hit_area = Control.new()
	_hit_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit_area.gui_input.connect(_on_hit_area_input)
	# 挂到父节点（Background），与 _popup_panel 同层，确保层级正确
	get_parent().add_child(_hit_area)

func _update_hit_area():
	if _hit_area == null or scene_rect.size == Vector2.ZERO:
		return
	# 用壁纸四边形的 AABB 作为点击区域，再在回调里做精确判断
	var r = scene_rect
	var vtl = r.position + Vector2(pos_top_left.x * r.size.x,     pos_top_left.y * r.size.y)
	var vtr = r.position + Vector2(pos_top_right.x * r.size.x,    pos_top_right.y * r.size.y)
	var vbr = r.position + Vector2(pos_bottom_right.x * r.size.x, pos_bottom_right.y * r.size.y)
	var vbl = r.position + Vector2(pos_bottom_left.x * r.size.x,  pos_bottom_left.y * r.size.y)

	var min_x = min(vtl.x, vtr.x, vbr.x, vbl.x)
	var min_y = min(vtl.y, vtr.y, vbr.y, vbl.y)
	var max_x = max(vtl.x, vtr.x, vbr.x, vbl.x)
	var max_y = max(vtl.y, vtr.y, vbr.y, vbl.y)

	_hit_area.position = Vector2(min_x, min_y)
	_hit_area.size = Vector2(max_x - min_x, max_y - min_y)

func _input(event: InputEvent):
	if not _popup_visible or _is_animating:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_viewport().get_mouse_position()
		# 用全局坐标判断是否点在面板或 hit_area 内
		var panel_rect = Rect2(_popup_panel.global_position, _popup_panel.size)
		var hit_rect = Rect2(_hit_area.global_position, _hit_area.size)
		if panel_rect.has_point(mouse_pos) or hit_rect.has_point(mouse_pos):
			return
		_hide_popup()
		get_viewport().set_input_as_handled()

func _on_hit_area_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 精确判断是否在四边形内
		var local_pos = to_local(get_viewport().get_mouse_position())
		if not _point_in_quad(local_pos):
			return
		if _popup_visible:
			_hide_popup()
		else:
			_show_popup()
		_hit_area.accept_event()

# ── 弹出面板 ──────────────────────────────────────────────

func _create_popup_panel():
	_popup_panel = Panel.new()
	_popup_panel.custom_minimum_size = Vector2(110, 0)
	_popup_panel.visible = false
	_popup_panel.modulate.a = 0.0
	_popup_panel.z_index = 10

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_popup_panel.add_child(margin)

	var btn = Button.new()
	btn.text = "🖼 壁纸"
	btn.pressed.connect(_on_change_wallpaper_pressed)
	margin.add_child(btn)

	get_parent().add_child(_popup_panel)

func _update_popup_position():
	if _popup_panel == null or scene_rect.size == Vector2.ZERO:
		return
	var r = scene_rect
	var btn_pos = r.position + Vector2(
		pos_top_right.x * r.size.x - 120,
		pos_top_right.y * r.size.y + 5
	)
	_popup_panel.position = btn_pos

func _show_popup():
	if _popup_visible or _is_animating:
		return
	_popup_visible = true
	_update_popup_position()
	_popup_panel.visible = true
	_popup_panel.pivot_offset = _popup_panel.size / 2.0
	_popup_panel.scale = Vector2(0.8, 0.8)

	var tween = _popup_panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_popup_panel, "modulate:a", 1.0, ANIMATION_DURATION)
	tween.tween_property(_popup_panel, "scale", Vector2.ONE, ANIMATION_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_popup():
	if not _popup_visible or _is_animating:
		return
	_popup_visible = false
	_is_animating = true
	_popup_panel.pivot_offset = _popup_panel.size / 2.0

	var tween = _popup_panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_popup_panel, "modulate:a", 0.0, ANIMATION_DURATION)
	tween.tween_property(_popup_panel, "scale", Vector2(0.8, 0.8), ANIMATION_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	await tween.finished
	_popup_panel.visible = false
	_is_animating = false

func _on_change_wallpaper_pressed():
	_popup_visible = false

	_popup_panel.visible = false

	change_wallpaper_requested.emit()

# ── 几何判断 ──────────────────────────────────────────────

func _point_in_quad(p: Vector2) -> bool:
	if scene_rect.size == Vector2.ZERO:
		return false
	var r = scene_rect
	var vtl = r.position + Vector2(pos_top_left.x * r.size.x,     pos_top_left.y * r.size.y)
	var vtr = r.position + Vector2(pos_top_right.x * r.size.x,    pos_top_right.y * r.size.y)
	var vbr = r.position + Vector2(pos_bottom_right.x * r.size.x, pos_bottom_right.y * r.size.y)
	var vbl = r.position + Vector2(pos_bottom_left.x * r.size.x,  pos_bottom_left.y * r.size.y)
	return _point_in_triangle(p, vtl, vtr, vbr) or _point_in_triangle(p, vtl, vbr, vbl)

func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 = _sign(p, a, b)
	var d2 = _sign(p, b, c)
	var d3 = _sign(p, c, a)
	var has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)

func _sign(p: Vector2, a: Vector2, b: Vector2) -> float:
	return (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)

# ── 绘制 ──────────────────────────────────────────────────

func _draw():
	if texture == null or scene_rect.size == Vector2.ZERO:
		return

	var r = scene_rect
	var vtl = r.position + Vector2(pos_top_left.x * r.size.x,     pos_top_left.y * r.size.y)
	var vtr = r.position + Vector2(pos_top_right.x * r.size.x,    pos_top_right.y * r.size.y)
	var vbr = r.position + Vector2(pos_bottom_right.x * r.size.x, pos_bottom_right.y * r.size.y)
	var vbl = r.position + Vector2(pos_bottom_left.x * r.size.x,  pos_bottom_left.y * r.size.y)

	draw_polygon(
		PackedVector2Array([vtl, vtr, vbr]),
		PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		PackedVector2Array([uv_top_left, uv_top_right, uv_bottom_right]),
		texture
	)
	draw_polygon(
		PackedVector2Array([vtl, vbr, vbl]),
		PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		PackedVector2Array([uv_top_left, uv_bottom_right, uv_bottom_left]),
		texture
	)
