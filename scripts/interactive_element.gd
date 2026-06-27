extends Control
class_name InteractiveElement

# 通用交互元素
# 通过 element_id 从配置文件读取所有信息

# 判定区域（隐藏的点击区域）
var click_area: Control
# 选项菜单
var options_panel: Panel
var options_margin: MarginContainer
var options_container: VBoxContainer
var option_buttons: Array[Button] = []

const ANIMATION_DURATION = 0.2
const DEFAULT_MENU_GAP = 10.0
const DEFAULT_VIEWPORT_MARGIN = 8.0
const OUTSIDE_CLICK_TOLERANCE = 4.0

@export var element_id: String = ""

var is_enabled: bool = false
var is_menu_visible: bool = false
var element_config: Dictionary = {}

var _menu_rng := RandomNumberGenerator.new()
var _menu_tween: Tween = null
var _menu_animation_token: int = 0

# 动态信号 - 根据配置发射
signal action_triggered(action_name: String)

func _ready():
	_menu_rng.randomize()

	if element_id.is_empty():
		push_error("InteractiveElement: element_id 未设置")
		return

	# 从配置获取元素信息
	if has_node("/root/InteractiveElementManager"):
		var mgr = get_node("/root/InteractiveElementManager")
		element_config = mgr.get_element_config(element_id)
		if element_config.is_empty():
			push_error("InteractiveElement: 找不到元素配置 " + element_id)
			return

		mgr.register_element(element_id, self)

	# 创建隐藏的点击区域
	var element_size = Vector2(
		element_config.get("size", {}).get("width", 80),
		element_config.get("size", {}).get("height", 80)
	)

	# custom_minimum_size 只会给容器布局参考；这里显式设置 size。
	# 否则点击区域的实际尺寸可能为 0。
	custom_minimum_size = element_size
	size = element_size

	click_area = Control.new()
	click_area.custom_minimum_size = element_size
	click_area.size = element_size
	click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	click_area.gui_input.connect(_on_click_area_input)
	add_child(click_area)

	# 创建选项面板
	_create_options_panel()

	visible = false

func _create_options_panel():
	"""创建选项面板"""
	options_panel = Panel.new()
	options_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	options_panel.custom_minimum_size = Vector2(200, 0)
	options_panel.visible = false
	options_panel.modulate.a = 0.0
	options_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	options_panel.gui_input.connect(_on_options_panel_gui_input)

	# 菜单视觉上仍然属于本交互元素，但输入/坐标不再受小判定区域限制。
	# 否则当菜单画在判定区域外时，按钮可能先被“外部点击关闭”逻辑销毁。
	options_panel.set_as_top_level(true)
	options_panel.z_as_relative = false
	options_panel.z_index = 100
	add_child(options_panel)

	options_margin = MarginContainer.new()
	options_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_margin.add_theme_constant_override("margin_left", 10)
	options_margin.add_theme_constant_override("margin_top", 10)
	options_margin.add_theme_constant_override("margin_right", 10)
	options_margin.add_theme_constant_override("margin_bottom", 10)
	options_panel.add_child(options_margin)

	options_container = VBoxContainer.new()
	options_container.add_theme_constant_override("separation", 5)
	options_margin.add_child(options_container)

	# 从配置创建选项按钮
	var options = element_config.get("options", [])
	for option in options:
		var btn = Button.new()
		var text = option.get("text", "")

		# 处理文本中的占位符
		text = _process_text_placeholders(text)

		btn.text = text
		btn.theme = load("res://theme/blue_button.tres")
		btn.add_theme_font_size_override("font_size", 30)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.pressed.connect(_on_option_pressed.bind(option))
		options_container.add_child(btn)
		option_buttons.append(btn)

	# 等待布局更新，并缓存一次真实尺寸。
	await get_tree().process_frame
	_update_options_panel_size()

func _process_text_placeholders(text: String) -> String:
	"""处理文本中的占位符"""
	# 替换 {character_name}
	if text.contains("{character_name}"):
		var character_name = _get_character_name()
		text = text.replace("{character_name}", character_name)

	return text

func _get_character_name() -> String:
	"""获取角色名称"""
	if not has_node("/root/SaveManager"):
		return "角色"

	var save_mgr = get_node("/root/SaveManager")
	return save_mgr.get_character_name()

func enable():
	"""启用判定区域"""
	if is_enabled:
		return

	is_enabled = true
	visible = true

	# 检查UIManager的状态，如果UI被禁用，则不启用交互
	if has_node("/root/UIManager"):
		var ui_mgr = get_node("/root/UIManager")
		if ui_mgr.is_ui_interactive():
			click_area.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			click_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

func disable():
	"""禁用判定区域"""
	if not is_enabled:
		return

	is_enabled = false

	# 如果菜单正在显示，先隐藏
	if is_menu_visible:
		hide_menu()

	visible = false

func set_interactive(interactive: bool):
	"""设置交互状态（由UIManager调用）"""
	# 只有在enabled状态下才响应交互状态变化
	if not is_enabled:
		return

	if interactive:
		click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		click_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 如果菜单正在显示，先隐藏
		if is_menu_visible:
			hide_menu()

func _on_click_area_input(event: InputEvent):
	"""点击区域输入事件"""
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# 消耗打开菜单的这次点击，避免同一事件继续走到外部关闭逻辑。
			click_area.accept_event()
			if is_menu_visible:
				hide_menu()
			else:
				show_menu(click_area.get_global_mouse_position())

func _on_options_panel_gui_input(event: InputEvent):
	"""菜单面板自身吞掉鼠标事件，点击面板空白处不会被当成外部点击。"""
	if event is InputEventMouseButton:
		options_panel.accept_event()

func show_menu(click_global_pos: Vector2 = Vector2.ZERO):
	"""显示选项菜单"""
	if is_menu_visible:
		return

	is_menu_visible = true
	_menu_animation_token += 1
	var token = _menu_animation_token

	_update_options_panel_size()
	var panel_size = _get_options_panel_size()

	# 未传点击位置时，以判定区域中心作为菜单锚点。
	var anchor_pos = click_global_pos
	if anchor_pos == Vector2.ZERO:
		anchor_pos = click_area.get_global_rect().get_center()

	options_panel.position = _calculate_menu_position(anchor_pos, panel_size)
	options_panel.visible = true
	options_panel.modulate.a = 0.0
	options_panel.pivot_offset = panel_size / 2.0
	options_panel.scale = Vector2(0.8, 0.8)

	if _menu_tween:
		_menu_tween.kill()

	# 展开动画
	_menu_tween = create_tween()
	_menu_tween.set_parallel(true)
	_menu_tween.tween_property(options_panel, "modulate:a", 1.0, ANIMATION_DURATION)
	var scale_tweener = _menu_tween.tween_property(
		options_panel,
		"scale",
		Vector2.ONE,
		ANIMATION_DURATION
	)
	scale_tweener.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_menu_tween.finished.connect(func():
		if token == _menu_animation_token:
			_menu_tween = null
	)

func hide_menu():
	"""隐藏选项菜单"""
	if not is_menu_visible:
		return

	is_menu_visible = false
	_menu_animation_token += 1
	var token = _menu_animation_token
	options_panel.pivot_offset = _get_options_panel_size() / 2.0

	if _menu_tween:
		_menu_tween.kill()

	# 收起动画
	_menu_tween = create_tween()
	_menu_tween.set_parallel(true)
	_menu_tween.tween_property(options_panel, "modulate:a", 0.0, ANIMATION_DURATION)
	var scale_tweener = _menu_tween.tween_property(
		options_panel,
		"scale",
		Vector2(0.8, 0.8),
		ANIMATION_DURATION
	)
	scale_tweener.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	await _menu_tween.finished
	if token == _menu_animation_token:
		options_panel.visible = false
		_menu_tween = null

func _on_option_pressed(option: Dictionary):
	"""选项按钮点击"""
	var action = option.get("action", "")

	# 发射通用信号
	action_triggered.emit(action)

	# 执行内置动作
	_execute_action(action)

	# 隐藏菜单
	hide_menu()

func _execute_action(action: String):
	"""执行内置动作"""
	match action:
		"music_player":
			_open_music_player()

func _open_music_player():
	"""打开音乐播放器"""
	await get_tree().process_frame
	var music_player_panel = get_node_or_null("/root/Main/MusicPlayerPanel")
	if music_player_panel:
		# 显示音乐播放器前禁用其他UI交互
		if has_node("/root/UIManager"):
			get_node("/root/UIManager").disable_all()
		music_player_panel.show_panel()

func _input(event: InputEvent):
	"""点击外部关闭菜单。

	这里不用 _unhandled_input：场景里常见的全屏 Control/背景 UI 可能会先消费事件，
	导致点外部时收不到 _unhandled_input。改回 _input 后，外部点击一定能收到；
	同时用菜单/判定区域的全局 Rect 排除内部点击，避免抢在 Button.pressed 前关闭。
	"""
	if not is_menu_visible:
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var click_pos = get_global_mouse_position()
			if _is_point_inside_menu_or_click_area(click_pos):
				return

			hide_menu()
			get_viewport().set_input_as_handled()

func _is_point_inside_menu_or_click_area(point: Vector2) -> bool:
	"""判断点击是否落在菜单或原判定区域内。"""
	if options_panel.visible:
		var menu_rect = options_panel.get_global_rect().grow(OUTSIDE_CLICK_TOLERANCE)
		if menu_rect.has_point(point):
			return true

	var click_rect = click_area.get_global_rect().grow(OUTSIDE_CLICK_TOLERANCE)
	return click_rect.has_point(point)

func _update_options_panel_size():
	"""确保 options_panel.size 是实际可点击尺寸，而不是 0 或旧布局尺寸。"""
	if not options_panel:
		return

	var margin_left = 10.0
	var margin_top = 10.0
	var margin_right = 10.0
	var margin_bottom = 10.0
	if options_margin:
		margin_left = float(options_margin.get_theme_constant("margin_left"))
		margin_top = float(options_margin.get_theme_constant("margin_top"))
		margin_right = float(options_margin.get_theme_constant("margin_right"))
		margin_bottom = float(options_margin.get_theme_constant("margin_bottom"))

	var content_size = options_container.get_combined_minimum_size()
	if content_size.y <= 0.0:
		var separation = float(options_container.get_theme_constant("separation"))
		for btn in option_buttons:
			var btn_size = btn.get_combined_minimum_size()
			content_size.x = max(content_size.x, btn_size.x)
			content_size.y += btn_size.y
		if option_buttons.size() > 1:
			content_size.y += separation * float(option_buttons.size() - 1)

	var minimum_size = options_panel.get_combined_minimum_size()
	var panel_width = max(
		200.0,
		max(minimum_size.x, content_size.x + margin_left + margin_right)
	)
	var panel_height = max(minimum_size.y, content_size.y + margin_top + margin_bottom)
	var panel_size = Vector2(panel_width, panel_height)
	options_panel.custom_minimum_size = panel_size
	options_panel.size = panel_size

	if options_margin:
		options_margin.position = Vector2.ZERO
		options_margin.size = panel_size

func _get_options_panel_size() -> Vector2:
	"""获取菜单尺寸；布局尚未刷新时也能返回可用值。"""
	_update_options_panel_size()
	var panel_size = options_panel.size
	if panel_size.x <= 0:
		panel_size.x = 200
	if panel_size.y <= 0:
		panel_size.y = 100
	return panel_size

func _calculate_menu_position(anchor_pos: Vector2, panel_size: Vector2) -> Vector2:
	"""根据配置计算菜单位置。

	支持 element_config 中配置：
	- menu_position_mode: "smart_random"(默认), "auto", "random", "above",
	"below", "left", "right", "top_left", "top_right",
	"bottom_left", "bottom_right", "center"
	- menu_gap: 菜单与点击点之间的距离
	- menu_viewport_margin: 菜单距离屏幕边缘的最小边距
	"""
	var mode = element_config.get("menu_position_mode", "smart_random")
	var gap = float(element_config.get("menu_gap", DEFAULT_MENU_GAP))
	var candidates = _get_menu_position_candidates(anchor_pos, panel_size, gap)

	match mode:
		"auto":
			return _choose_auto_menu_position(candidates, panel_size)
		"random", "smart_random":
			return _choose_random_menu_position(candidates, panel_size)
		_:
			if candidates.has(mode):
				return _clamp_menu_position(candidates[mode], panel_size)
			push_warning(
				"InteractiveElement: 未知 menu_position_mode: "
				+ str(mode)
				+ "，已回退到 smart_random"
			)
			return _choose_random_menu_position(candidates, panel_size)

func _get_menu_position_candidates(
	anchor_pos: Vector2,
	panel_size: Vector2,
	gap: float
) -> Dictionary:
	"""生成围绕点击点的一组候选位置。"""
	return {
		"above": anchor_pos + Vector2(-panel_size.x / 2.0, -panel_size.y - gap),
		"below": anchor_pos + Vector2(-panel_size.x / 2.0, gap),
		"left": anchor_pos + Vector2(-panel_size.x - gap, -panel_size.y / 2.0),
		"right": anchor_pos + Vector2(gap, -panel_size.y / 2.0),
		"top_left": anchor_pos + Vector2(-panel_size.x - gap, -panel_size.y - gap),
		"top_right": anchor_pos + Vector2(gap, -panel_size.y - gap),
		"bottom_left": anchor_pos + Vector2(-panel_size.x - gap, gap),
		"bottom_right": anchor_pos + Vector2(gap, gap),
		"center": anchor_pos - panel_size / 2.0,
	}

func _choose_auto_menu_position(candidates: Dictionary, panel_size: Vector2) -> Vector2:
	"""自动选择第一个完整留在屏幕内的位置。"""
	var priority = [
		"above",
		"below",
		"right",
		"left",
		"top_right",
		"top_left",
		"bottom_right",
		"bottom_left",
		"center",
	]
	for key in priority:
		var pos = candidates[key]
		if _is_menu_position_inside_viewport(pos, panel_size):
			return pos

	return _clamp_menu_position(candidates["above"], panel_size)

func _choose_random_menu_position(candidates: Dictionary, panel_size: Vector2) -> Vector2:
	"""在所有不会出屏幕的位置里随机选一个；都不合适时再 clamp。"""
	var valid_positions: Array[Vector2] = []
	var fallback_positions: Array[Vector2] = []
	var keys = [
		"above",
		"below",
		"left",
		"right",
		"top_left",
		"top_right",
		"bottom_left",
		"bottom_right",
	]

	for key in keys:
		var pos = candidates[key]
		fallback_positions.append(pos)
		if _is_menu_position_inside_viewport(pos, panel_size):
			valid_positions.append(pos)

	if not valid_positions.is_empty():
		return valid_positions[_menu_rng.randi_range(0, valid_positions.size() - 1)]

	var fallback = fallback_positions[_menu_rng.randi_range(0, fallback_positions.size() - 1)]
	return _clamp_menu_position(fallback, panel_size)

func _is_menu_position_inside_viewport(pos: Vector2, panel_size: Vector2) -> bool:
	var viewport_size = get_viewport_rect().size
	var margin = float(element_config.get("menu_viewport_margin", DEFAULT_VIEWPORT_MARGIN))
	return (
		pos.x >= margin
		and pos.y >= margin
		and pos.x + panel_size.x <= viewport_size.x - margin
		and pos.y + panel_size.y <= viewport_size.y - margin
	)

func _clamp_menu_position(pos: Vector2, panel_size: Vector2) -> Vector2:
	"""保证菜单不超出视口。"""
	var viewport_size = get_viewport_rect().size
	var margin = float(element_config.get("menu_viewport_margin", DEFAULT_VIEWPORT_MARGIN))
	var max_x = max(margin, viewport_size.x - panel_size.x - margin)
	var max_y = max(margin, viewport_size.y - panel_size.y - margin)
	return Vector2(
		clamp(pos.x, margin, max_x),
		clamp(pos.y, margin, max_y)
	)
