extends PanelContainer

signal next_page_requested
signal page_fully_shown(text: String)

@export var target_path: NodePath
@export var follow_margin: float = 16.0
@export var screen_padding: float = 12.0
@export var tail_size: float = 14.0
@export var tail_half_height: float = 10.0
@export var bubble_color: Color = Color(0.13, 0.17, 0.23, 0.95)
@export var bubble_border_color: Color = Color(0.48, 0.63, 0.86, 1.0)

@onready var content_label: Label = $Margin/VBox/ContentLabel
@onready var hint_label: Label = $Margin/VBox/HintLabel
@onready var typing_timer: Timer = $TypingTimer

var _target_node: Control
var _full_text: String = ""
var _typing_index: int = 0
var _is_typing: bool = false
var _is_waiting_indicator: bool = false
var _tail_on_left: bool = true
var _tail_anchor_y: float = 20.0

func _ready() -> void:
	visible = false
	hint_label.visible = false
	typing_timer.timeout.connect(_on_typing_timer_timeout)
	_try_resolve_target()

func _process(_delta: float) -> void:
	if not visible:
		return
	_update_position_near_target()

func set_target(node: Control) -> void:
	_target_node = node
	_update_position_near_target()

func show_page(text: String) -> void:
	_full_text = text.strip_edges()
	_typing_index = 0
	_is_typing = true
	_is_waiting_indicator = false
	visible = true
	content_label.text = ""
	hint_label.visible = false
	typing_timer.start()
	_update_position_near_target()

func show_waiting_indicator(text: String = "...") -> void:
	# 等待首个 token 时显示占位符，不触发分页逻辑。
	typing_timer.stop()
	_full_text = text
	_typing_index = text.length()
	_is_typing = false
	_is_waiting_indicator = true
	visible = true
	content_label.text = text
	hint_label.visible = false
	_update_position_near_target()

func hide_waiting_indicator() -> void:
	if not _is_waiting_indicator:
		return
	clear_page()

func clear_page() -> void:
	typing_timer.stop()
	_full_text = ""
	_typing_index = 0
	_is_typing = false
	_is_waiting_indicator = false
	content_label.text = ""
	hint_label.visible = false
	visible = false
	queue_redraw()

func is_typing() -> bool:
	return _is_typing

func has_active_page() -> bool:
	return _is_typing or not _full_text.is_empty()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _is_waiting_indicator:
			return
		if _full_text.is_empty():
			return
		if _is_typing:
			_finish_typing_immediately()
		else:
			next_page_requested.emit()
		get_viewport().set_input_as_handled()

func _on_typing_timer_timeout() -> void:
	if _typing_index >= _full_text.length():
		_is_typing = false
		typing_timer.stop()
		hint_label.visible = true
		page_fully_shown.emit(_full_text)
		return

	_typing_index += 1
	content_label.text = _full_text.substr(0, _typing_index)
	_update_position_near_target()

func _finish_typing_immediately() -> void:
	typing_timer.stop()
	_is_typing = false
	_typing_index = _full_text.length()
	content_label.text = _full_text
	hint_label.visible = true
	_update_position_near_target()
	page_fully_shown.emit(_full_text)

func _try_resolve_target() -> void:
	if target_path.is_empty():
		return
	var found = get_node_or_null(target_path)
	if found is Control:
		_target_node = found

func _update_position_near_target() -> void:
	if not is_instance_valid(_target_node):
		_try_resolve_target()
		if not is_instance_valid(_target_node):
			return

	# 角色移动时实时跟随，并在屏幕边缘进行钳制，避免聊天气泡超出可视区域。
	var viewport_size = get_viewport_rect().size
	var bubble_size = size
	if bubble_size.x <= 0.0 or bubble_size.y <= 0.0:
		bubble_size = get_combined_minimum_size()

	var target_rect = _target_node.get_global_rect()
	var prefer_right_x = target_rect.position.x + target_rect.size.x + follow_margin
	var prefer_left_x = target_rect.position.x - bubble_size.x - follow_margin
	var pos_y = target_rect.position.y - bubble_size.y * 0.35

	var pos_x = prefer_right_x
	if prefer_right_x + bubble_size.x > viewport_size.x - screen_padding:
		pos_x = prefer_left_x
	if pos_x < screen_padding:
		pos_x = screen_padding

	# 如果气泡位于角色右侧，小三角绘制在左边；反之绘制在右边。
	_tail_on_left = pos_x >= target_rect.position.x

	pos_y = clampf(pos_y, screen_padding, max(screen_padding, viewport_size.y - bubble_size.y - screen_padding))
	global_position = Vector2(pos_x, pos_y)
	var target_center_y = target_rect.position.y + target_rect.size.y * 0.5
	_tail_anchor_y = clampf(target_center_y - global_position.y, 16.0, max(19.0, bubble_size.y - 19.0))
	queue_redraw()

func _draw() -> void:
	if not visible:
		return

	# 动态绘制气泡尖角，方向与角色相对位置一致。
	var base_x = 0.0 if _tail_on_left else size.x
	var tip_x = -tail_size if _tail_on_left else size.x + tail_size
	var y_top = _tail_anchor_y - tail_half_height
	var y_bottom = _tail_anchor_y + tail_half_height
	var y_mid = _tail_anchor_y

	var border_points := PackedVector2Array([
		Vector2(base_x, y_top),
		Vector2(tip_x, y_mid),
		Vector2(base_x, y_bottom),
	])
	draw_colored_polygon(border_points, bubble_border_color)

	var inset = 2.0
	var fill_base_x = base_x + inset if _tail_on_left else base_x - inset
	var fill_tip_x = tip_x + inset if _tail_on_left else tip_x - inset
	var fill_points := PackedVector2Array([
		Vector2(fill_base_x, y_top + inset),
		Vector2(fill_tip_x, y_mid),
		Vector2(fill_base_x, y_bottom - inset),
	])
	draw_colored_polygon(fill_points, bubble_color)
