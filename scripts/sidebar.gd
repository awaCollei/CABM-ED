extends Panel

signal scene_changed(scene_id: String, weather_id: String, time_id: String)

const UIStyleFactory = preload("res://scripts/ui/ui_style_factory.gd")

# 日记本纸页风格配色
const PAPER_COLOR := Color(0.964706, 0.945098, 0.878431)  # 纸页底色
const PAPER_LINE_COLOR := Color(0.858824, 0.811765, 0.686275)  # 纸页描边
const INK_COLOR := Color(0.243137, 0.196078, 0.152941)  # 墨色文字
const INK_SOFT_COLOR := Color(0.427451, 0.360784, 0.286275)  # 次要墨色
const PAPER_ACCENT_COLOR := Color(0.752941, 0.372549, 0.301961)  # 书签/高亮暗红
const RULE_COLOR := Color(0.647059, 0.729412, 0.827451, 0.55)  # 横格线（蓝灰）
const SEPARATOR_COLOR := Color(0.298039, 0.454902, 0.690196, 0.9)  # 分节线（更深的蓝色，区别于普通格线）
const ROW_HEIGHT := 40.0  # 每个内容行的高度 = 一格横格线间距
const CONTENT_MARGIN_LEFT := 40  # 正文左侧留白（红线右侧）

@onready var scene_list: VBoxContainer = %SceneList
@onready var toggle_button: Button = %ToggleButton
@onready var exit_button: Button = $MarginContainer/VBoxContainer/Exit
@onready var dynamic_content: VBoxContainer = %DynamicContent
@onready var header_container: VBoxContainer = %HeaderContainer
@onready var paper_background: Control = %PaperBackground

# 头部（时钟 / 角色状态）节点引用
@onready var clock_label: Label = %ClockLabel
@onready var auto_checkbox: CheckBox = %AutoCheckbox
@onready var user_name_input: LineEdit = %UserNameInput
@onready var character_location_label: Label = %CharacterLocationLabel
@onready var affection_label: Label = %AffectionLabel
@onready var willingness_label: Label = %WillingnessLabel
@onready var mood_label: Label = %MoodLabel
@onready var api_key_status: Label = %ApiKeyStatus

# 定时器
@onready var time_update_timer: Timer = %TimeUpdateTimer
@onready var auto_save_timer: Timer = %AutoSaveTimer

var current_ui_style: String = UIStyleFactory.STYLE_NOTEBOOK
var sidebar_opacity: float = 1.0
var button_opacity: float = 1.0
var is_expanded: bool = false  # 默认收起
var collapsed_width: float = 50.0
var expanded_width: float = 320.0

# 收起/展开通过整页平移实现（而不是改变宽度），纸页始终按展开宽度绘制
var base_x: float = 0.0
var _slide_offset: float = 0.0

var slide_offset: float:
	get:
		return _slide_offset
	set(value):
		_slide_offset = clampf(value, 0.0, expanded_width - collapsed_width)
		position.x = base_x - _slide_offset

# 滑动手势相关
var swipe_start_pos: Vector2 = Vector2.ZERO
var is_swiping: bool = false
var swipe_touch_index: int = -1  # 正在进行滑动的触摸点索引
var swipe_threshold: float = 80.0  # 触发滑动的像素阈值
var swipe_edge_margin: float = 100.0  # 判定为从边缘滑动的范围

# 场景配置
var scenes = {
	"livingroom":
	{
		"name": "客厅",
		"times": {"day": "白天", "dusk": "黄昏", "night": "夜晚"},
		"weathers": {"sunny": "晴天", "rainy": "雨天", "storm": "雷雨"}
	}
}

var current_scene_id: String = "livingroom"
var current_time_id: String = "day"
var current_weather_id: String = ""  # 将从存档加载
var auto_time_enabled: bool = true  # 默认开启自动调整时间
var time_buttons = {}
var weather_buttons = {}

# 自动保存定时器（在 sidebar.tscn 中定义）


func _ready():
	if has_node("/root/UIStyleManager"):
		var style_manager = get_node("/root/UIStyleManager")
		current_ui_style = style_manager.load_ui_style()
		style_manager.ui_style_changed.connect(_apply_ui_style)
		style_manager.ui_opacity_changed.connect(_on_ui_opacity_changed)
	_apply_ui_style(current_ui_style)
	toggle_button.mouse_entered.connect(_on_bookmark_hover.bind(true))
	toggle_button.mouse_exited.connect(_on_bookmark_hover.bind(false))
	# 先填充用户名再连接信号，避免初始化时触发 text_changed
	user_name_input.text = _load_user_name()
	_connect_signals()
	_load_scenes_config()

	# 从存档加载天气
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		var saved_weather = save_mgr.get_current_weather()
		if saved_weather != "":
			current_weather_id = saved_weather
			print("从存档加载天气: ", current_weather_id)
		else:
			current_weather_id = "sunny"  # 默认值
	else:
		current_weather_id = "sunny"  # 默认值

	# 如果启用了自动时间，在构建UI之前先调整时间
	if auto_time_enabled:
		var time_dict = Time.get_time_dict_from_system()
		var time_id = TimeUtil.get_time_period_from_hour(time_dict["hour"])
		current_time_id = time_id
		print("初始化自动时间: ", time_id)

	# 初始化头部数据
	_load_api_key_display()

	_build_scene_list()

	# 固定为展开宽度；收起时整页向左平移，靠屏幕边缘裁切，线条始终存在
	custom_minimum_size.x = expanded_width
	size.x = expanded_width
	toggle_button.text = ">"
	_apply_content_margins()
	slide_offset = expanded_width - collapsed_width

	# 启动时钟更新定时器
	time_update_timer.timeout.connect(_update_clock)
	_update_clock()

	# 启动自动保存定时器（每5分钟保存一次）
	auto_save_timer.timeout.connect(_on_auto_save)

	# 立即连接SaveManager信号（不等待），确保不会错过任何信号
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		save_mgr.affection_changed.connect(_update_character_stats)
		save_mgr.willingness_changed.connect(_update_character_stats)
		save_mgr.mood_changed.connect(_update_character_stats)
		save_mgr.energy_changed.connect(_update_character_stats)
		# 监听角色场景变化
		if save_mgr.has_signal("character_scene_changed"):
			save_mgr.character_scene_changed.connect(_update_character_stats)

	# 等待自动加载节点准备好
	await get_tree().process_frame

	# 监听AI服务的字段提取信号以实时更新
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		ai_service.chat_fields_extracted.connect(_on_ai_fields_updated)

	# 强制刷新一次角色状态显示，确保启动时显示正确
	_update_character_stats()


func _connect_signals():
	"""连接 tscn 中静态节点的信号"""
	toggle_button.pressed.connect(_on_toggle_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	auto_checkbox.toggled.connect(_on_auto_time_toggled)
	user_name_input.text_changed.connect(_on_user_name_changed)
	%AiConfigButton.pressed.connect(_on_ai_config_pressed)
	%MusicSettingsButton.pressed.connect(_on_music_settings_pressed)
	%DebugButton.pressed.connect(_on_debug_save_pressed)
	%AboutButton.pressed.connect(_on_about_pressed)


func _update_clock():
	var time_dict = Time.get_time_dict_from_system()
	var hour = time_dict["hour"]
	var minute = time_dict["minute"]
	var second = time_dict["second"]

	clock_label.text = "%02d:%02d:%02d" % [hour, minute, second]

	# 如果启用自动时间，更新时间段
	if auto_time_enabled:
		_auto_adjust_time_period(hour)


func _auto_adjust_time_period(hour: int):
	var time_id = TimeUtil.get_time_period_from_hour(hour)

	# 更新当前时间选择
	if current_time_id != time_id:
		current_time_id = time_id
		_update_button_states()
		_emit_scene_change()


func _on_auto_time_toggled(enabled: bool):
	auto_time_enabled = enabled

	if enabled:
		# 立即更新一次时间
		var time_dict = Time.get_time_dict_from_system()
		_auto_adjust_time_period(time_dict["hour"])


func _load_scenes_config():
	var config_path = "res://config/scenes.json"
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			var data = json.data
			if data.has("scenes"):
				scenes = data["scenes"]
				# 为每个场景添加通用的 times 和 weathers
				var common_times = data.get("times", {})
				var common_weathers = data.get("weathers", {})
				for scene_id in scenes:
					if not scenes[scene_id].has("times"):
						scenes[scene_id]["times"] = common_times
					if not scenes[scene_id].has("weathers"):
						scenes[scene_id]["weathers"] = common_weathers


func _build_scene_list():
	# 清空动态内容（时钟/角色状态头部固定在 tscn 中，保持不变）
	for child in dynamic_content.get_children():
		child.queue_free()

	# 清空按钮引用
	time_buttons.clear()
	weather_buttons.clear()

	# 只显示当前场景
	if not scenes.has(current_scene_id):
		print("场景 %s 不存在" % current_scene_id)
		return

	var scene_data = scenes[current_scene_id]

	# 场景标题（隐藏）
	var scene_label = Label.new()
	scene_label.text = "当前场景: " + scene_data["name"]
	scene_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scene_label.visible = false  # 隐藏调试元素
	dynamic_content.add_child(scene_label)

	# 分隔线（隐藏）
	var separator1 = HSeparator.new()
	separator1.visible = false  # 隐藏调试元素
	dynamic_content.add_child(separator1)

	# 时间按钮组（隐藏）
	if scene_data.has("times"):
		var time_label = Label.new()
		time_label.text = "时间"
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.visible = false  # 隐藏调试元素
		dynamic_content.add_child(time_label)

		var time_container = VBoxContainer.new()
		time_container.add_theme_constant_override("separation", 5)
		time_container.visible = false  # 隐藏调试元素
		for time_id in scene_data["times"]:
			var time_name = scene_data["times"][time_id]
			var button = Button.new()
			button.text = time_name
			button.toggle_mode = true
			button.pressed.connect(_on_time_selected.bind(time_id))
			time_container.add_child(button)

			# 保存按钮引用
			time_buttons[time_id] = button
		dynamic_content.add_child(time_container)

	# 分隔线
	var separator2 = HSeparator.new()
	separator2.set_meta("notebook_only", true)
	separator2.visible = current_ui_style == UIStyleFactory.STYLE_NOTEBOOK
	dynamic_content.add_child(separator2)

	# 已移除实验性玩法入口

	var weather_emojis = {
		"晴天": "☀️", "雨天": "🌧️", "雪天": "❄️", "阴天": "☁️", "多云": "⛅", "雷雨": "⛈️", "雾天": "🌫️", "大风": "💨"
	}
	# 天气按钮组
	if scene_data.has("weathers"):
		var weather_label = Label.new()
		weather_label.text = "天气"
		weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 分隔线由上面的 notebook_only HSeparator 负责，避免其他风格残留蓝线。
		dynamic_content.add_child(weather_label)

		# 天气按钮组：一行并排、只留图标，强调"多选一"
		var weather_container = HBoxContainer.new()
		weather_container.set_meta("keep_separation", true)
		weather_container.add_theme_constant_override("separation", 6)
		for weather_id in scene_data["weathers"]:
			var weather_name = scene_data["weathers"][weather_id]
			var button = Button.new()
			button.text = weather_emojis.get(weather_name, "🌡️")
			button.tooltip_text = weather_name
			button.toggle_mode = true
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(_on_weather_selected.bind(weather_id))
			weather_container.add_child(button)

			# 保存按钮引用
			weather_buttons[weather_id] = button
		dynamic_content.add_child(weather_container)

	# 初始化按钮状态
	_update_button_states()

	# 让每一行内容各占一格横格线
	_apply_ruled_layout()
	_apply_button_opacity_tree(
		self, button_opacity if current_ui_style == UIStyleFactory.STYLE_DEFAULT else 1.0
	)


func _apply_ruled_layout():
	"""把内容行的高度统一为格子高度，使横格线正好落在每行文字下方"""
	_apply_ruled_rows(scene_list)


func _apply_ruled_rows(container: Node):
	# 自己声明了间距的容器（选项按钮组、天气那一行）保留设置，其余行紧贴格线
	if container is BoxContainer and not container.has_meta("keep_separation"):
		container.add_theme_constant_override("separation", 0)

	for child in container.get_children():
		if child is HSeparator:
			# 保留为蓝色分节线，并让它占满一格横格线高度以对齐纸页格线
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, ROW_HEIGHT)
		elif child is BoxContainer:
			_apply_ruled_rows(child)
		elif child is Label:
			child.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, ROW_HEIGHT)
		elif child is Control:
			child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, ROW_HEIGHT)


func _apply_content_margins():
	"""正文留白：左边让开红色边线，右边让开笔记本外壳"""
	var margin: MarginContainer = $MarginContainer
	margin.add_theme_constant_override("margin_left", CONTENT_MARGIN_LEFT)
	margin.add_theme_constant_override("margin_right", int(collapsed_width))
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 12)


func set_current_scene(scene_id: String):
	"""设置当前场景并重建UI"""
	if current_scene_id != scene_id:
		current_scene_id = scene_id
		_build_scene_list()


func _on_time_selected(time_id: String):
	# 手动选择时间时，禁用自动模式
	if auto_time_enabled:
		auto_time_enabled = false
		auto_checkbox.button_pressed = false

	current_time_id = time_id
	_update_button_states()
	_emit_scene_change()


func _on_weather_selected(weather_id: String):
	current_weather_id = weather_id
	_update_button_states()
	_emit_scene_change()


func _update_button_states():
	# 更新时间按钮状态
	for time_id in time_buttons:
		time_buttons[time_id].button_pressed = (time_id == current_time_id)

	# 更新天气按钮状态
	for weather_id in weather_buttons:
		weather_buttons[weather_id].button_pressed = (weather_id == current_weather_id)


func _emit_scene_change():
	print("选择场景: %s, 天气: %s, 时间: %s" % [current_scene_id, current_weather_id, current_time_id])
	scene_changed.emit(current_scene_id, current_weather_id, current_time_id)


func _on_toggle_pressed():
	set_expanded(!is_expanded)


func set_expanded(expand: bool):
	if is_expanded == expand:
		return

	is_expanded = expand

	toggle_button.text = "<" if expand else ">"

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(
		self, "slide_offset", 0.0 if expand else (expanded_width - collapsed_width), 0.3
	)


func set_base_x(x: float):
	"""由布局管理器提供侧边栏的基础横向位置"""
	base_x = x
	position.x = base_x - _slide_offset


func get_visible_width() -> float:
	"""当前实际露在屏幕内的宽度"""
	return expanded_width - _slide_offset


func _input(event: InputEvent):
	# 处理鼠标和触屏滑动手势
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_swipe(event.position, -1)
			elif is_swiping and swipe_touch_index == -1:
				_end_swipe(event.position)

	elif event is InputEventScreenTouch:
		if event.pressed:
			if not is_swiping:
				_start_swipe(event.position, event.index)
		elif is_swiping and event.index == swipe_touch_index:
			_end_swipe(event.position)

	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		if is_swiping:
			if event is InputEventScreenDrag and event.index != swipe_touch_index:
				return
			# 可选：在这里实时更新边栏位置以增加跟随感
			pass


func _start_swipe(pos: Vector2, index: int):
	# 如果已展开，从边栏范围内开始滑动都可以
	if is_expanded:
		if pos.x <= expanded_width:
			swipe_start_pos = pos
			swipe_touch_index = index
			is_swiping = true
	# 如果未展开，必须从左边缘开始滑动
	else:
		if pos.x <= swipe_edge_margin:
			swipe_start_pos = pos
			swipe_touch_index = index
			is_swiping = true


func _end_swipe(pos: Vector2):
	is_swiping = false
	swipe_touch_index = -1
	var swipe_dist_x = pos.x - swipe_start_pos.x
	var swipe_dist_y = pos.y - swipe_start_pos.y

	# 确保是水平滑动且位移超过阈值
	if abs(swipe_dist_x) > abs(swipe_dist_y) and abs(swipe_dist_x) > swipe_threshold:
		# 从左往右滑：展开
		if swipe_dist_x > 0 and not is_expanded:
			set_expanded(true)
		# 从右往左滑：收起
		elif swipe_dist_x < 0 and is_expanded:
			set_expanded(false)


func _update_character_stats(_new_value = null):
	"""更新角色数据显示"""
	if not has_node("/root/SaveManager"):
		return

	var save_mgr = get_node("/root/SaveManager")

	# 角色位置
	var character_scene = save_mgr.get_character_scene()
	var scene_name = _get_scene_name(character_scene)
	var character_name = _get_character_name()
	character_location_label.text = "%s位于：%s" % [character_name, scene_name]
	print("[边栏] 更新角色位置显示: %s 位于 %s (场景ID: %s)" % [character_name, scene_name, character_scene])

	# 好感度
	var affection = save_mgr.get_affection()
	var affection_icon = "💕" if affection > 100 else ("❤" if affection >= 0 else "💔")
	affection_label.text = "%s好感度: %d" % [affection_icon, affection]
	affection_label.add_theme_color_override(
		"font_color", _get_stat_color(affection).darkened(0.35)
	)

	# 状态
	var willingness = save_mgr.get_reply_willingness()
	willingness_label.text = _get_willingness_text(willingness)
	willingness_label.add_theme_color_override(
		"font_color", _get_stat_color(willingness).darkened(0.35)
	)

	# 心情
	var mood = save_mgr.get_mood()
	var mood_text = _get_mood_text(mood)
	var mood_icon = _get_mood_icon(mood)
	mood_label.text = "%s心情: %s" % [mood_icon, mood_text]
	mood_label.add_theme_color_override("font_color", _get_mood_color(mood).darkened(0.3))


func _on_ai_fields_updated(_fields: Dictionary):
	"""AI字段更新时刷新显示"""
	_update_character_stats()


func _get_mood_icon(mood: String) -> String:
	"""根据心情的 valence 返回图标"""
	var mood_config = _load_mood_config()
	if mood_config.is_empty():
		return "☁️"
	for mood_data in mood_config.moods:
		if mood_data.name_en == mood:
			match mood_data.get("valence", "neutral"):
				"positive":
					return "🌈"
				"negative":
					return "🌧️"
				_:
					return "☁️"
	return "☁️"


func _get_willingness_text(willingness: int) -> String:
	"""将交互意愿数值转换为带图标的状态文本"""
	var percentage = float(willingness) / 100.0
	if percentage >= 1.0:
		return "⚡状态: 亢奋"
	elif percentage >= 0.8:
		return "🌟状态: 活跃"
	elif percentage >= 0.6:
		return "✨状态: 正常"
	elif percentage >= 0.4:
		return "💤状态: 疲惫"
	elif percentage >= 0.2:
		return "💢状态: 冷漠"
	else:
		return "💥状态: 抗拒"


func _get_stat_color(value: int) -> Color:
	"""根据数值返回颜色（每20点一个区间）"""
	if value >= 80:
		return Color(0.3, 1.0, 0.3)  # 绿色（80-100）
	elif value >= 60:
		return Color(0.6, 1.0, 0.3)  # 黄绿色（60-79）
	elif value >= 40:
		return Color(1.0, 1.0, 0.3)  # 黄色（40-59）
	elif value >= 20:
		return Color(1.0, 0.7, 0.3)  # 橙色（20-39）
	else:
		return Color(1.0, 0.3, 0.3)  # 红色（0-19）


func _get_mood_text(mood: String) -> String:
	"""获取心情文本（从配置文件）"""
	var mood_config = _load_mood_config()
	if mood_config.is_empty():
		return mood

	for mood_data in mood_config.moods:
		if mood_data.name_en == mood:
			return mood_data.name

	return mood


func _get_mood_color(mood: String) -> Color:
	"""根据心情返回颜色（从配置文件）"""
	var mood_config = _load_mood_config()
	if mood_config.is_empty():
		return Color(1.0, 1.0, 1.0)

	for mood_data in mood_config.moods:
		if mood_data.name_en == mood:
			return Color(mood_data.color)

	return Color(1.0, 1.0, 1.0)


func _load_mood_config() -> Dictionary:
	"""加载心情配置"""
	var mood_config_path = "res://config/mood_config.json"
	if not FileAccess.file_exists(mood_config_path):
		return {}

	var file = FileAccess.open(mood_config_path, FileAccess.READ)
	if file == null:
		print("错误: 无法打开心情配置文件: ", mood_config_path)
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		return {}

	return json.data


func _on_auto_save():
	"""自动保存"""
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		save_mgr.save_game()
		print("自动保存完成")


# === AI 设置相关 ===
# 配置状态标签与选项按钮已移至 sidebar.tscn，见 _connect_signals() 中的连接


func _load_api_key_display():
	"""加载并显示 API 配置状态"""
	# 使用统一的AI配置加载器
	var ai_service = get_node_or_null("/root/AIService")
	if ai_service and ai_service.config_loader:
		var chat_config = ai_service.config_loader.get_model_config("chat_model")
		if not chat_config.is_empty():
			var api_key = chat_config.get("api_key", "")
			if not api_key.is_empty():
				api_key_status.text = "✓ 已配置"
				api_key_status.add_theme_color_override(
					"font_color", Color(0.156863, 0.443137, 0.219608)
				)
				return

	api_key_status.text = "✗ 未配置"
	api_key_status.add_theme_color_override("font_color", Color(0.615686, 0.196078, 0.180392))


func _mask_api_key(key: String) -> String:
	"""遮蔽 API 密钥，只显示前后几位"""
	if key.length() <= 10:
		return "***"
	return key.substr(0, 7) + "..." + key.substr(key.length() - 4)


func _on_ai_config_pressed():
	"""打开AI配置面板"""
	# 先关闭音乐设置面板（如果存在）
	for child in get_tree().root.get_children():
		if child is Panel and child.name in ["MusicPlayerPanel", "AboutDialog"]:
			child.queue_free()
			break
		if child is Panel and child.name == "AIConfigPanel":
			# 如果已存在，关闭它（切换显示状态）
			if child.visible:
				child.queue_free()
			else:
				child.show()
			return

	# 如果不存在，创建新面板
	var config_panel_scene = load("res://scenes/ai_config_panel.tscn")
	if config_panel_scene:
		var config_panel = config_panel_scene.instantiate()
		config_panel.name = "AIConfigPanel"  # 设置一个固定的名称便于识别
		get_tree().root.add_child(config_panel)
		# 面板关闭后刷新状态显示
		config_panel.tree_exited.connect(_load_api_key_display)


func _load_user_name() -> String:
	"""从存档系统加载用户名"""
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		return save_mgr.get_user_name()
	return "未设置"


func _on_user_name_changed(new_name: String):
	"""用户名改变时自动保存"""
	_save_user_name(new_name)


func _save_user_name(user_name: String):
	"""保存用户名到存档系统"""
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		save_mgr.set_user_name(user_name)
		print("用户名已保存到存档: ", user_name)


func _on_debug_save_pressed():
	"""打开存档调试面板"""
	var debug_panel_scene = load("res://scenes/save_debug_panel.tscn")
	if debug_panel_scene:
		var debug_panel = debug_panel_scene.instantiate()
		get_tree().root.add_child(debug_panel)


func _on_about_pressed():
	"""打开关于对话框"""
	# 一次性关闭音乐设置面板和AI配置面板
	for child in get_tree().root.get_children():
		if child is Panel and child.name in ["MusicPlayerPanel", "AIConfigPanel"]:
			child.queue_free()
			break
		if child is Panel and child.name == "AboutDialog":
			if child.visible:
				child.queue_free()
			else:
				child.visible = true
			return

	# 如果不存在，创建新对话框
	var about_dialog_scene = load("res://scenes/about_dialog.tscn")
	if about_dialog_scene:
		var about_dialog = about_dialog_scene.instantiate()
		get_tree().root.add_child(about_dialog)


func _get_scene_name(scene_id: String) -> String:
	"""获取场景名称"""
	if scenes.has(scene_id):
		return scenes[scene_id].get("name", scene_id)
	return scene_id


func _get_character_name() -> String:
	"""获取角色名称"""
	if not has_node("/root/SaveManager"):
		return "角色"

	var save_mgr = get_node("/root/SaveManager")
	return save_mgr.get_character_name()


func _on_music_settings_pressed():
	"""打开音乐设置面板"""
	# 先关闭AI配置面板（如果存在）
	for child in get_tree().root.get_children():
		if child is Panel and child.name in ["AIConfigPanel", "AboutDialog"]:
			child.queue_free()
			break
		if child is Panel and child.name == "MusicPlayerPanel":
			# 如果已存在，关闭它（切换显示状态）
			if child.visible:
				child.queue_free()
			else:
				child.show_panel()
			return

	# 如果不存在，创建新面板
	var music_panel_scene = load("res://scenes/music_player_panel.tscn")
	if music_panel_scene:
		var music_panel = music_panel_scene.instantiate()
		music_panel.name = "MusicPlayerPanel"  # 设置一个固定的名称便于识别
		get_tree().root.add_child(music_panel)
		music_panel.show_panel()


func _setup_experimental_section():
	"""设置实验性玩法部分"""
	# 标题
	var exp_label = Label.new()
	exp_label.text = "实验性玩法（没做）"
	exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exp_label.add_theme_color_override("font_color", Color(0.596078, 0.400000, 0.098039))
	scene_list.add_child(exp_label)


func _on_exit_button_pressed():
	"""退出按钮按下，显示确认对话框"""
	print("[Sidebar] 退出按钮按下")

	# 创建确认对话框（使用 ConfirmationDialog 自带取消按钮）
	var dialog = ConfirmationDialog.new()
	dialog.title = "退出游戏"
	dialog.dialog_text = "保存并返回主页面？"
	dialog.ok_button_text = "确定"
	dialog.cancel_button_text = "取消"

	# 连接确认信号
	dialog.confirmed.connect(_on_exit_confirmed)

	# 添加到场景树并显示
	get_tree().root.add_child(dialog)
	dialog.popup_centered()


func _on_exit_confirmed():
	"""确认退出游戏"""
	print("[Sidebar] 确认退出游戏")

	# 停止所有定时器
	if time_update_timer:
		time_update_timer.stop()
	if auto_save_timer:
		auto_save_timer.stop()

	# 停止主场景中的定时器（如果存在）
	var main_scene = get_tree().current_scene
	if main_scene:
		# 停止音频管理器
		if main_scene.has_node("AudioManager"):
			var audio_mgr = main_scene.get_node("AudioManager")
			if audio_mgr.has_method("stop_all"):
				audio_mgr.stop_all()

		# 停止所有定时器
		for child in main_scene.get_children():
			if child is Timer:
				child.stop()

	# 使用场景过渡管理器进行淡出
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.fade_out()

	# 保存游戏
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		save_mgr.save_game(save_mgr.current_slot)
		print("[Sidebar] 游戏已保存")

		# 等待保存完成
		await get_tree().create_timer(0.5).timeout

	# 淡入主菜单
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		transition.change_scene_with_fade("res://scenes/main_menu.tscn")
	else:
		# 如果没有过渡管理器，直接切换
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# === 可切换界面风格 ===


func _apply_ui_style(style_id: String) -> void:
	"""应用全局风格；默认模式不保留任何局部覆盖。"""
	current_ui_style = UIStyleFactory.normalize_style(style_id)
	if has_node("/root/UIStyleManager"):
		var opacity = get_node("/root/UIStyleManager").load_ui_style_opacity(current_ui_style)
		sidebar_opacity = opacity.sidebar
		button_opacity = opacity.buttons
	paper_background.visible = current_ui_style == UIStyleFactory.STYLE_NOTEBOOK
	paper_background.modulate.a = sidebar_opacity
	api_key_status.remove_theme_stylebox_override("normal")
	_clear_toggle_button_style()
	remove_theme_stylebox_override("panel")

	if current_ui_style == UIStyleFactory.STYLE_DEFAULT:
		theme = null
		_apply_default_panel_opacity(sidebar_opacity)
	elif current_ui_style == UIStyleFactory.STYLE_NOTEBOOK:
		theme = _build_paper_theme(button_opacity)
		# API 状态与按钮之间不画横格线。
		api_key_status.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		_style_toggle_button()
	else:
		theme = UIStyleFactory.create_theme(current_ui_style, button_opacity, sidebar_opacity)
		add_theme_stylebox_override(
			"panel", UIStyleFactory.create_panel_style(current_ui_style, sidebar_opacity)
		)
	_refresh_notebook_only_nodes()
	_apply_button_opacity_tree(
		self, button_opacity if current_ui_style == UIStyleFactory.STYLE_DEFAULT else 1.0
	)
	queue_redraw()


func _on_ui_opacity_changed(
	style_id: String, sidebar: float, _dialog: float, buttons: float
) -> void:
	if style_id != current_ui_style:
		return
	sidebar_opacity = sidebar
	button_opacity = buttons
	_apply_ui_style(current_ui_style)


func _refresh_notebook_only_nodes() -> void:
	for node in find_children("*", "HSeparator", true, false):
		if node.has_meta("notebook_only"):
			node.visible = current_ui_style == UIStyleFactory.STYLE_NOTEBOOK


func _apply_button_opacity_tree(root: Node, opacity: float) -> void:
	for child in root.get_children():
		if child is Button:
			child.modulate.a = opacity
		_apply_button_opacity_tree(child, opacity)


func _apply_default_panel_opacity(opacity: float) -> void:
	if is_equal_approx(opacity, 1.0):
		return
	var inherited := get_theme_stylebox("panel").duplicate()
	if inherited is StyleBoxFlat:
		inherited.bg_color.a *= opacity
		inherited.shadow_color.a *= opacity
		add_theme_stylebox_override("panel", inherited)


func _apply_paper_style():
	"""兼容编辑器或旧调用入口。"""
	_apply_ui_style(UIStyleFactory.STYLE_NOTEBOOK)


func _build_paper_theme(button_alpha: float = 1.0) -> Theme:
	"""基于纸页配色构建主题，使侧边栏内所有文字/按钮都适配浅色纸张"""
	var paper_theme := Theme.new()

	# 文字：深墨色
	paper_theme.set_color("font_color", "Label", INK_COLOR)
	paper_theme.set_color("font_color", "RichTextLabel", INK_SOFT_COLOR)
	paper_theme.set_color("default_color", "RichTextLabel", INK_SOFT_COLOR)

	# 标签：文字写在横线上（行下划线由行自身绘制，天然与内容对齐）
	paper_theme.set_stylebox(
		"normal", "Label", _make_ruled_stylebox(Color(0, 0, 0, 0), 1, RULE_COLOR, 6.0)
	)

	# 按钮：暖黄色便签纸，悬停变亮、按下时阴影消失并加深下沿。
	var note_normal := Color(1.0, 0.91, 0.47, 0.98 * button_alpha)
	var note_hover := Color(1.0, 0.96, 0.65, button_alpha)
	var note_pressed := Color(0.92, 0.78, 0.34, button_alpha)
	paper_theme.set_stylebox(
		"normal",
		"Button",
		_make_chip_stylebox(note_normal, Color(0.66, 0.54, 0.34, button_alpha), 3, 3)
	)
	paper_theme.set_stylebox(
		"hover",
		"Button",
		_make_chip_stylebox(
			note_hover,
			Color(PAPER_ACCENT_COLOR.r, PAPER_ACCENT_COLOR.g, PAPER_ACCENT_COLOR.b, button_alpha),
			3,
			5
		)
	)
	paper_theme.set_stylebox(
		"pressed",
		"Button",
		_make_chip_stylebox(
			note_pressed,
			Color(PAPER_ACCENT_COLOR.r, PAPER_ACCENT_COLOR.g, PAPER_ACCENT_COLOR.b, button_alpha),
			1,
			0
		)
	)
	paper_theme.set_stylebox(
		"disabled",
		"Button",
		_make_chip_stylebox(
			Color(1, 1, 1, 0.20),
			Color(PAPER_LINE_COLOR.r, PAPER_LINE_COLOR.g, PAPER_LINE_COLOR.b, 0.5),
			1,
			0
		)
	)
	paper_theme.set_stylebox("focus", "Button", _make_focus_stylebox())
	paper_theme.set_color("font_color", "Button", INK_COLOR)
	paper_theme.set_color("font_hover_color", "Button", PAPER_ACCENT_COLOR.darkened(0.25))
	paper_theme.set_color("font_pressed_color", "Button", PAPER_ACCENT_COLOR.darkened(0.35))
	paper_theme.set_color("font_focus_color", "Button", INK_COLOR)
	paper_theme.set_color(
		"font_disabled_color",
		"Button",
		Color(INK_SOFT_COLOR.r, INK_SOFT_COLOR.g, INK_SOFT_COLOR.b, 0.5)
	)

	# 勾选框 / 输入框
	paper_theme.set_color("font_color", "CheckBox", INK_COLOR)
	paper_theme.set_color("font_color", "LineEdit", INK_COLOR)
	paper_theme.set_color(
		"font_placeholder_color",
		"LineEdit",
		Color(INK_SOFT_COLOR.r, INK_SOFT_COLOR.g, INK_SOFT_COLOR.b, 0.7)
	)
	paper_theme.set_color("caret_color", "LineEdit", INK_COLOR)
	paper_theme.set_stylebox("normal", "LineEdit", _make_line_edit_stylebox(PAPER_LINE_COLOR, 1))
	paper_theme.set_stylebox("focus", "LineEdit", _make_line_edit_stylebox(PAPER_ACCENT_COLOR, 2))

	# 分隔线：贴在行底部的深蓝色横线，作为日记本的分节标记
	paper_theme.set_stylebox("separator", "HSeparator", _make_separator_stylebox())

	# 滚动条：纸卷质感
	paper_theme.set_stylebox(
		"scroll",
		"VScrollBar",
		_make_button_stylebox(
			Color(PAPER_LINE_COLOR.r, PAPER_LINE_COLOR.g, PAPER_LINE_COLOR.b, 0.25)
		)
	)
	paper_theme.set_stylebox(
		"grabber",
		"VScrollBar",
		_make_button_stylebox(
			Color(PAPER_LINE_COLOR.r, PAPER_LINE_COLOR.g, PAPER_LINE_COLOR.b, 0.8)
		)
	)
	paper_theme.set_stylebox(
		"grabber_highlight",
		"VScrollBar",
		_make_button_stylebox(
			Color(PAPER_ACCENT_COLOR.r, PAPER_ACCENT_COLOR.g, PAPER_ACCENT_COLOR.b, 0.9),
			PAPER_ACCENT_COLOR,
			0,
			0
		)
	)
	paper_theme.set_stylebox(
		"grabber_pressed", "VScrollBar", _make_button_stylebox(PAPER_ACCENT_COLOR.darkened(0.15))
	)

	return paper_theme


func _style_toggle_button():
	"""展开/收起按钮：只显示箭头文字，书签本体由纸页背景绘制"""
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		toggle_button.add_theme_stylebox_override(state, empty)
	toggle_button.add_theme_color_override("font_color", PAPER_COLOR)
	toggle_button.add_theme_color_override("font_hover_color", Color.WHITE)
	toggle_button.add_theme_color_override("font_pressed_color", PAPER_COLOR)
	toggle_button.add_theme_color_override("font_focus_color", PAPER_COLOR)


func _clear_toggle_button_style() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		toggle_button.remove_theme_stylebox_override(state)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		toggle_button.remove_theme_color_override(color_name)


func _on_bookmark_hover(hovered: bool):
	if paper_background:
		paper_background.set("bookmark_hovered", hovered)
		paper_background.queue_redraw()


func _make_chip_stylebox(
	fill: Color, edge: Color, edge_bottom: int, shadow_size: int
) -> StyleBoxFlat:
	"""有厚度的小标签：淡色底 + 一圈描边 + 下沿加厚 + 投影"""
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_bottom = maxi(1, edge_bottom)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0.14, 0.10, 0.07, 0.22 * fill.a)
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 6.0
	return style


func _make_ruled_stylebox(
	bg: Color, border_width: int, border_color: Color, corner_radius: int = 4
) -> StyleBoxFlat:
	"""一行内容 = 写在一条横格线上：下边框即格线，其余三边留空"""
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 6.0
	return style


func _make_separator_stylebox() -> StyleBoxFlat:
	"""分节线：贴在行底部的深蓝色横线，比普通格线更粗更蓝，像日记本的分节记号"""
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_bottom = 1
	style.border_color = SEPARATOR_COLOR
	# HSeparator 会把样式盒在行内垂直居中，样式盒高度需等于整行高度，
	# 这样下边框才会正好压在纸页格线上
	style.content_margin_top = ROW_HEIGHT
	return style


func _make_button_stylebox(
	bg: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 1, corner_radius: int = 4
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _make_focus_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(
		PAPER_ACCENT_COLOR.r, PAPER_ACCENT_COLOR.g, PAPER_ACCENT_COLOR.b, 0.7
	)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style


func _make_line_edit_stylebox(border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.992157, 0.960784, 0.9)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style
