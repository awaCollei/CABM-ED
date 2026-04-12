extends Panel

signal scene_selected(scene_id: String)
signal character_called()
signal map_open_requested()

@onready var vbox: VBoxContainer = $MarginContainer/VBoxContainer

const ANIMATION_DURATION = 0.2

var scene_buttons: Array = []
var call_button: Button = null
var map_button: Button = null

func _ready():
	visible = false
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # Initially ignore mouse events
	_apply_panel_style()

func _apply_panel_style():
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.4, 0.5, 0.6)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 6
	style.shadow_offset = Vector2(2, 3)
	add_theme_stylebox_override("panel", style)

func setup_scenes(scenes_config: Dictionary, current_scene: String):
	# 清除现有按钮
	for button in scene_buttons:
		button.queue_free()
	scene_buttons.clear()
	if call_button:
		call_button.queue_free()
		call_button = null
	if map_button:
		map_button.queue_free()
		map_button = null
	
	# 获取角色名称
	var character_name = _get_character_name()
	
	# 添加"呼唤角色"按钮
	call_button = Button.new()
	call_button.text = "💬 呼唤" + character_name
	call_button.pressed.connect(_on_call_button_pressed)
	_style_button(call_button)
	vbox.add_child(call_button)

	if current_scene == "entryway" or current_scene == "shop" or current_scene == "rooftop":
		map_button = Button.new()
		map_button.text = "🗺️ 打开地图"
		map_button.pressed.connect(_on_map_button_pressed)
		_style_button(map_button)
		vbox.add_child(map_button)
	
	# 获取当前场景的连通场景列表
	var current_scene_data = scenes_config.get(current_scene, {})
	var connected_scenes = current_scene_data.get("connect", [])
	
	# 只为连通的场景创建按钮
	for scene_id in connected_scenes:
		if not scenes_config.has(scene_id):
			continue
		
		var scene_data = scenes_config[scene_id]
		var button = Button.new()
		
		# 使用场景数据获取图标
		var icon = _get_scene_icon(scene_data)
		button.text = icon + " 前往" + scene_data.get("name", scene_id)
		button.pressed.connect(_on_scene_button_pressed.bind(scene_id))
		_style_button(button)
		vbox.add_child(button)
		scene_buttons.append(button)

func show_menu(at_position: Vector2):
	# 先显示以便计算大小
	visible = true
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	mouse_filter = Control.MOUSE_FILTER_STOP # Stop mouse events from propagating
	
	# 等待布局更新
	await get_tree().process_frame
	
	# 手动计算所需高度
	var button_count = 1 + scene_buttons.size()
	if map_button:
		button_count += 1
	var button_height = 40.0  # 按钮默认高度
	var separation = 5.0  # 按钮间距
	var total_height = button_count * button_height + (button_count - 1) * separation
	
	# 设置面板大小（宽度170，高度根据按钮数量计算）
	var panel_width = 180.0
	var margin = 16.0
	custom_minimum_size = Vector2(panel_width, total_height + margin)
	size = Vector2(panel_width, total_height + margin)
	
	# 设置菜单位置
	position = at_position
	pivot_offset = size / 2.0
	
	# 展开动画
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, ANIMATION_DURATION)
	tween.tween_property(self, "scale", Vector2.ONE, ANIMATION_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_menu():
	if not visible:
		return
	
	pivot_offset = size / 2.0
	
	# 收起动画
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, ANIMATION_DURATION)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), ANIMATION_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	await tween.finished
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE # Ignore mouse events when hidden

func _on_scene_button_pressed(scene_id: String):
	scene_selected.emit(scene_id)
	hide_menu()

func _on_call_button_pressed():
	character_called.emit()
	hide_menu()

func _on_map_button_pressed():
	map_open_requested.emit()
	hide_menu()

func _get_character_name() -> String:
	"""获取角色名称"""
	if has_node("/root/EventHelpers"):
		var helpers = get_node("/root/EventHelpers")
		return helpers.get_character_name()
	return "角色"

func _get_scene_icon(scene_data: Dictionary) -> String:
	"""返回场景图标，优先使用配置中的 icon 字段，否则按 class 回退"""
	if scene_data.has("icon") and scene_data["icon"] != "":
		return scene_data["icon"]
	match scene_data.get("class", ""):
		"home":
			return "🏠"
		"outdoor":
			return "🌳"
		_:
			return "📍"

func _style_button(btn: Button) -> void:
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 26)
	btn.custom_minimum_size=Vector2(170,40)
	# 普通状态
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.0)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", normal)
	# 悬停状态
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.12)
	hover.corner_radius_top_left = 6
	hover.corner_radius_top_right = 6
	hover.corner_radius_bottom_left = 6
	hover.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("hover", hover)
	# 按下状态
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(1, 1, 1, 0.2)
	pressed_style.corner_radius_top_left = 6
	pressed_style.corner_radius_top_right = 6
	pressed_style.corner_radius_bottom_left = 6
	pressed_style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("pressed", pressed_style)
	# 字体颜色
	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))

func _input(event):
	# 如果菜单可见，且点击了菜单外的区域，则隐藏菜单
	if visible and event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# 检查点击位置是否在菜单内
			var local_pos = get_local_mouse_position()
			var menu_rect = Rect2(Vector2.ZERO, size)
			if not menu_rect.has_point(local_pos):
				hide_menu()
				get_viewport().set_input_as_handled()
