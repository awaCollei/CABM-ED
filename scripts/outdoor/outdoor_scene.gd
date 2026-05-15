extends Control

@onready var background: TextureRect = $Background
@onready var character: TextureButton = $Background/Character
@onready var time_label: Label = $TimeLabel
@onready var open_map_button: Button = $OpenMapButton
@onready var floating_bar: PanelContainer = $FloatingBar
@onready var floating_header: HBoxContainer = $FloatingBar/MarginContainer/VBox/Header
@onready var collapse_input_button: Button = $FloatingBar/MarginContainer/VBox/Header/CollapseInputButton
@onready var costume_button: Button = $FloatingBar/MarginContainer/VBox/Header/CostumeButton
@onready var music_panel_button: Button = $FloatingBar/MarginContainer/VBox/Header/MusicPanelButton
@onready var settings_button: Button = $FloatingBar/MarginContainer/VBox/Header/SettingsButton
@onready var history_button: Button = $FloatingBar/MarginContainer/VBox/Header/HistoryButton
@onready var send_button: Button = $FloatingBar/MarginContainer/VBox/Header/SendButton
@onready var input_text_edit: TextEdit = $FloatingBar/MarginContainer/VBox/InputTextEdit
@onready var costume_panel: PanelContainer = $CostumePanel
@onready var costume_list: ItemList = $CostumePanel/MarginContainer/VBox/CostumeList
@onready var costume_close_button: Button = $CostumePanel/MarginContainer/VBox/CloseButton
@onready var drag_hint_label: Label = $DragHint
@onready var dialogue_controller: Node = $OutdoorDialogueController

# 历史记录面板相关变量
var history_panel: PanelContainer
var history_content: VBoxContainer
var history_scroll: ScrollContainer

const MusicPlayerPanelScene = preload("res://scenes/music_player_panel.tscn")
const AIConfigPanelScene = preload("res://scenes/ai_config_panel.tscn")
const OmikujiPanelScene = preload("res://scenes/omikuji_panel.tscn")

var outdoor_id: String = "beach"
var current_time_id: String = ""
var outdoor_config: Dictionary = {}
var costume_entries: Array = []
var selected_costume_id: String = ""
var selected_costume_data: Dictionary = {}
var current_pose_index: int = -1
var rng := RandomNumberGenerator.new()
var blue_theme = preload("res://theme/blue_button.tres")
var bar_dragging: bool = false
var bar_drag_offset: Vector2 = Vector2.ZERO
var bar_is_expanded: bool = true

var function_buttons: Array = []
var function_config: Array = []

const FLOATING_BAR_DEFAULT_POS := Vector2(810.0, 100.0)
const FLOATING_BAR_EXPANDED_HEIGHT := 200.0
const FLOATING_BAR_COLLAPSED_HEIGHT := 40.0

func _ready():
	rng.randomize()
	_resolve_outdoor_id()
	_load_outdoor_config()
	_init_selected_costume()
	call_deferred("_init_scene_safe")
	_setup_character()
	character.gui_input.connect(_on_character_gui_input)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_by_system_time()
	open_map_button.pressed.connect(_on_open_map_pressed)
	music_panel_button.pressed.connect(_on_music_panel_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	collapse_input_button.pressed.connect(_on_collapse_input_pressed)
	costume_button.pressed.connect(_on_costume_button_pressed)
	costume_close_button.pressed.connect(func(): costume_panel.visible = false)
	costume_list.item_selected.connect(_on_costume_item_selected)
	floating_header.gui_input.connect(_on_floating_header_gui_input)
	_connect_dialogue_signals()
	
	# 初始化历史记录面板
	_init_history_panel()
	
	var refresh_timer = Timer.new()
	refresh_timer.wait_time =1.0
	refresh_timer.autostart = true
	refresh_timer.timeout.connect(_update_by_system_time)
	add_child(refresh_timer)
	_update_drag_hint()
	_restore_floating_bar_state()
	_init_function_buttons()
	# 执行淡入动画
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").fade_in()

func _init_scene_safe():
	_setup_character()
	_update_by_system_time()
	_randomize_initial_pose()
	_play_outdoor_audio()

func _randomize_initial_pose():
	var poses = _get_pose_list()
	if poses.is_empty():
		return
	
	var index = rng.randi_range(0, poses.size() - 1)
	_apply_pose_by_index(index)

func _resolve_outdoor_id():
	if not has_node("/root/SaveManager"):
		return
	var sm = get_node("/root/SaveManager")
	if sm.has_meta("outdoor_current_id"):
		outdoor_id = str(sm.get_meta("outdoor_current_id"))
	if sm.has_meta("outdoor_target_id"):
		outdoor_id = str(sm.get_meta("outdoor_target_id"))
	sm.set_meta("outdoor_current_id", outdoor_id)

func _update_drag_hint():
	var scene_name = outdoor_id
	
	# 如果配置里有名字，用配置名字
	if outdoor_config.has("name"):
		scene_name = str(outdoor_config.get("name"))
	
	drag_hint_label.text = scene_name

func _load_outdoor_config():
	outdoor_config.clear()
	costume_entries.clear()
	var config_path = "res://config/outdoor_presets/%s.json" % outdoor_id
	if not FileAccess.file_exists(config_path):
		return
	var f = FileAccess.open(config_path, FileAccess.READ)
	var js = f.get_as_text()
	f.close()
	var j = JSON.new()
	if j.parse(js) != OK:
		return
	outdoor_config = j.data
	costume_entries = outdoor_config.get("presets", [])

func _init_selected_costume():
	var fallback_id = ""
	if not costume_entries.is_empty():
		fallback_id = str(costume_entries[0].get("id", ""))
	
	var saved_id = ""
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		saved_id = sm.get_outdoor_scene_costume(outdoor_id)
	
	if saved_id != "" and _find_costume_by_id(saved_id).size() > 0:
		selected_costume_id = saved_id
	else:
		selected_costume_id = fallback_id
	
	selected_costume_data = _find_costume_by_id(selected_costume_id)
	if has_node("/root/SaveManager") and selected_costume_id != "":
		var sm2 = get_node("/root/SaveManager")
		sm2.set_outdoor_scene_costume(outdoor_id, selected_costume_id)
	
	_rebuild_costume_list_ui()

func _setup_character():
	if character.has_method("set_background_reference"):
		character.set_background_reference(background)
	_apply_pose_by_index(0)

func _on_viewport_size_changed():
	if current_pose_index >= 0:
		_apply_pose_by_index(current_pose_index)

func _update_by_system_time():
	var time_dict = Time.get_time_dict_from_system()
	var hour = int(time_dict.get("hour", 12))
	var minute = int(time_dict.get("minute", 0)) 
	var time_id = TimeUtil.get_time_period_from_hour(hour)
	if time_id != current_time_id:
		current_time_id = time_id
		_apply_background()
		_update_outdoor_audio()

	_update_time_label(hour, minute)

func _update_time_label(hour: int, minute: int):
	var time_name := TimeUtil.get_time_period(hour)
	time_label.text = "%02d:%02d  %s" % [hour, minute, time_name]

func _apply_background():
	var time_path = "res://assets/images/scenes_outdoor/%s/%s.png" % [outdoor_id, current_time_id]
	var fallback_path = "res://assets/images/scenes_outdoor/%s/day.png" % outdoor_id
	var load_path = time_path if ResourceLoader.exists(time_path) else fallback_path
	if ResourceLoader.exists(load_path):
		background.texture = load(load_path)
	else:
		background.texture = null

func _find_costume_by_id(costume_id: String) -> Dictionary:
	for entry in costume_entries:
		if str(entry.get("id", "")) == costume_id:
			return entry
	return {}

func _get_pose_list() -> Array:
	return selected_costume_data.get("presets", [])

func _apply_pose_by_index(index: int):
	var poses = _get_pose_list()
	if poses.is_empty():
		character.visible = false
		return
	
	if index < 0 or index >= poses.size():
		index = 0
	
	current_pose_index = index
	var pose = poses[index]
	var texture = _load_character_texture(selected_costume_id, str(pose.get("image", "")))
	
	if texture == null:
		character.visible = false
		return
	
	# ⭐淡出
	var tween = create_tween()
	tween.tween_property(character, "modulate:a", 0.0, 0.15)
	
	tween.tween_callback(func():
		character.texture_normal = texture
		character.texture_hover = texture
		character.texture_pressed = texture
		character.scale = Vector2(pose.get("scale", 1.0), pose.get("scale", 1.0))
		_apply_character_position(pose.get("position", {}))
	)
	
	# ⭐淡入
	tween.tween_property(character, "modulate:a", 1.0, 0.15)


func _load_character_texture(costume_id: String, image_name: String) -> Texture2D:
	var path = "res://assets/images/character_outdoor/%s/%s" % [costume_id, image_name]
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _apply_character_position(position_data: Dictionary):
	var ratio_x = float(position_data.get("x", 0.5))
	var ratio_y = float(position_data.get("y", 0.5))
	var bg_rect = character._get_actual_background_rect()
	var actual_bg_size: Vector2 = bg_rect.get("size", Vector2.ZERO)
	var bg_offset: Vector2 = bg_rect.get("offset", Vector2.ZERO)
	if actual_bg_size.x <= 0 or actual_bg_size.y <= 0 or character.texture_normal == null:
		return
	
	var center_pos = Vector2(ratio_x * actual_bg_size.x, ratio_y * actual_bg_size.y) + bg_offset
	var tex_size = character.texture_normal.get_size() * character.scale
	character.position = center_pos - tex_size / 2.0

func _on_character_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
			_on_character_pressed()

func _on_character_pressed():
	var poses = _get_pose_list()
	if poses.is_empty():
		return
	if poses.size() == 1:
		_apply_pose_by_index(0)
		return
	
	var next_index = current_pose_index
	if next_index < 0:
		next_index = 0
	while next_index == current_pose_index:
		next_index = rng.randi_range(0, poses.size() - 1)
	_apply_pose_by_index(next_index)

func _on_collapse_input_pressed():
	_apply_floating_bar_expanded(not bar_is_expanded, true, true)

func _on_costume_button_pressed():
	costume_panel.visible = true
	_rebuild_costume_list_ui()

func _rebuild_costume_list_ui():
	costume_list.clear()
	var selected_idx = -1
	for i in range(costume_entries.size()):
		var entry = costume_entries[i]
		var cid = str(entry.get("id", ""))
		var cname = str(entry.get("name", cid))
		var line = "%s (%s)" % [cname, cid]
		costume_list.add_item(line)
		costume_list.set_item_metadata(i, cid)
		if cid == selected_costume_id:
			selected_idx = i
	if selected_idx >= 0:
		costume_list.select(selected_idx)

func _on_costume_item_selected(index: int):
	var cid = str(costume_list.get_item_metadata(index))
	if cid == "" or cid == selected_costume_id:
		return
	selected_costume_id = cid
	selected_costume_data = _find_costume_by_id(selected_costume_id)
	current_pose_index = -1
	_apply_pose_by_index(0)
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		sm.set_outdoor_scene_costume(outdoor_id, selected_costume_id)

func _on_floating_header_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			bar_dragging = true
			bar_drag_offset = event.global_position - floating_bar.global_position
		else:
			bar_dragging = false
			_save_floating_bar_state()
	elif event is InputEventMouseMotion and bar_dragging:
		var new_pos = event.global_position - bar_drag_offset
		floating_bar.global_position = _clamp_floating_bar_position(new_pos)

func _on_open_map_pressed():
	var dialog := ConfirmationDialog.new()
	dialog.title = "打开地图"
	dialog.dialog_text = "确定要离开这里了吗？"
	dialog.ok_button_text = "离开"
	if dialog.get_cancel_button():
		dialog.get_cancel_button().text = "取消"
	add_child(dialog)
	dialog.popup_centered()
	
	# 直接连接 confirmed 信号到退出逻辑
	dialog.confirmed.connect(_perform_open_map)
	# canceled 不需要做任何事情，只是关闭对话框

func _on_history_button_pressed():
	"""历史按钮被点击时的处理逻辑"""
	_toggle_history_panel()

func _perform_open_map():
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		sm.set_meta("open_map_on_load", true)
		sm.set_meta("map_origin", "outdoor")
		sm.set_meta("outdoor_current_id", outdoor_id)

	if has_node("/root/SceneTransition"):
		var st = get_node("/root/SceneTransition")
		# 先淡出到黑屏，再进行总结，黑屏期间用户看不到等待过程
		await st.fade_out()
		if dialogue_controller and dialogue_controller.has_method("end_and_summarize"):
			await dialogue_controller.end_and_summarize()
		# 总结完成后直接加载（已处于黑屏，跳过重复淡出）
		st.change_scene_already_faded("res://scripts/main.tscn")
	else:
		if dialogue_controller and dialogue_controller.has_method("end_and_summarize"):
			await dialogue_controller.end_and_summarize()
		get_tree().change_scene_to_file("res://scripts/main.tscn")

func _connect_dialogue_signals():
	if dialogue_controller == null:
		return
	if dialogue_controller.has_signal("dialog_reply_started"):
		dialogue_controller.connect("dialog_reply_started", _on_dialog_reply_started)
	if dialogue_controller.has_signal("dialog_reply_finished"):
		dialogue_controller.connect("dialog_reply_finished", _on_dialog_reply_finished)

func _on_dialog_reply_started():
	_apply_floating_bar_expanded(false, true, false)
	collapse_input_button.disabled = true

func _on_dialog_reply_finished():
	collapse_input_button.disabled = false
	_apply_floating_bar_expanded(true, true, false)

func _apply_floating_bar_expanded(expanded: bool, animate: bool = true, save_state: bool = true):
	bar_is_expanded = expanded
	
	# ⭐ 先改变可见性
	input_text_edit.visible = expanded
	send_button.disabled = not expanded
	
	# ⭐ 等一帧让布局更新
	await get_tree().process_frame
	
	var target_height = FLOATING_BAR_EXPANDED_HEIGHT if expanded else FLOATING_BAR_COLLAPSED_HEIGHT
	
	if animate:
		var tween = create_tween()
		tween.tween_property(floating_bar, "size:y", target_height, 0.2)
	else:
		floating_bar.size.y = target_height
	
	collapse_input_button.text = "🔼" if expanded else "💬"
	if save_state:
		_save_floating_bar_state()

func _restore_floating_bar_state():
	var target_pos = FLOATING_BAR_DEFAULT_POS
	var expanded = true
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		var state = sm.get_outdoor_floating_bar_state(outdoor_id)
		if state is Dictionary and not state.is_empty():
			target_pos.x = float(state.get("x", FLOATING_BAR_DEFAULT_POS.x))
			target_pos.y = float(state.get("y", FLOATING_BAR_DEFAULT_POS.y))
			expanded = bool(state.get("expanded", true))
	floating_bar.global_position = _clamp_floating_bar_position(target_pos)
	_apply_floating_bar_expanded(expanded, false, false)

func _save_floating_bar_state():
	if not has_node("/root/SaveManager"):
		return
	var sm = get_node("/root/SaveManager")
	sm.set_outdoor_floating_bar_state(outdoor_id, {
		"x": floating_bar.global_position.x,
		"y": floating_bar.global_position.y,
		"expanded": bar_is_expanded
	})

func _clamp_floating_bar_position(pos: Vector2) -> Vector2:
	var viewport_size = get_viewport_rect().size
	var bar_size = floating_bar.size
	return Vector2(
		clamp(pos.x, 0.0, max(0.0, viewport_size.x - bar_size.x)),
		clamp(pos.y, 0.0, max(0.0, viewport_size.y - bar_size.y))
	)

func _on_music_panel_pressed():
	"""音乐面板按钮被点击：打开或关闭音乐设置面板"""

	# 先关闭AI配置面板
	for child in get_tree().root.get_children():
		if child is Panel and child.name == "AIConfigPanel":
			child.queue_free()
			break

	# 查找现有的音乐面板
	var existing_panel = get_tree().root.find_child("MusicPlayerPanel", true, false)
	
	if existing_panel:
		# 如果音乐面板存在，关闭它
		existing_panel._on_close_pressed()
	else:
		# 使用预加载的场景实例化
		var music_panel = MusicPlayerPanelScene.instantiate()
		get_tree().root.add_child(music_panel)
		music_panel.show_panel()
		
		# 设置当前场景为户外场景
		if music_panel.has_method("_set_current_outdoor_scene"):
			music_panel._set_current_outdoor_scene(outdoor_id)
		
func _on_settings_pressed():
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
	
	# 使用预加载的场景实例化
	var config_panel = AIConfigPanelScene.instantiate()
	config_panel.name = "AIConfigPanel"  # 设置一个固定的名称便于识别
	get_tree().root.add_child(config_panel)
	config_panel.position = (get_viewport_rect().size - config_panel.size) / 2

func _play_outdoor_audio():
	"""播放户外场景的BGM和环境音"""
	# 查找AudioManager
	var audio_manager = null
	if has_node("/root/Main/AudioManager"):
		audio_manager = get_node("/root/Main/AudioManager")
	elif has_node("/root/AudioManager"):
		audio_manager = get_node("/root/AudioManager")
	else:
		# 尝试从场景树中查找
		var root = get_tree().root
		for child in root.get_children():
			var am = child.find_child("AudioManager", true, false)
			if am:
				audio_manager = am
				break
	
	if audio_manager and audio_manager.has_method("play_background_music"):
		# 获取当前天气（默认晴天）
		var weather_id = "sunny"  # 默认晴天，实际应该从天气系统获取
		
		# 播放户外场景的BGM和环境音
		# 注意：户外场景ID直接使用，不需要加"outdoor_"前缀
		# current_time_id 已经在 _update_by_system_time() 中设置
		audio_manager.play_background_music(outdoor_id, current_time_id, weather_id)
		print("🎵 播放户外场景音频: ", outdoor_id, " (时间: ", current_time_id, ", 天气: ", weather_id, ")")

func _update_outdoor_audio():
	"""更新户外场景音频（当时间变化时）"""
	# 查找AudioManager
	var audio_manager = null
	if has_node("/root/Main/AudioManager"):
		audio_manager = get_node("/root/Main/AudioManager")
	elif has_node("/root/AudioManager"):
		audio_manager = get_node("/root/AudioManager")
	else:
		# 尝试从场景树中查找
		var root = get_tree().root
		for child in root.get_children():
			var am = child.find_child("AudioManager", true, false)
			if am:
				audio_manager = am
				break
	
	if audio_manager and audio_manager.has_method("play_background_music"):
		# 获取当前天气（默认晴天）
		var weather_id = "sunny"  # 实际应该从天气系统获取
		
		# 更新户外场景的BGM和环境音
		# 注意：如果用户锁定了BGM，audio_manager会自动处理不切换音乐
		audio_manager.play_background_music(outdoor_id, current_time_id, weather_id)
		print("🔄 更新户外场景音频: ", outdoor_id, " (时间: ", current_time_id, ", 天气: ", weather_id, ")")
# === 功能按钮方法 ===

func _init_function_buttons():
	"""初始化功能按钮"""
	# 清除旧按钮
	for btn in function_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	function_buttons.clear()
	
	# 从配置加载功能按钮
	function_config = outdoor_config.get("functions", [])
	
	for func_data in function_config:
		var btn = Button.new()
		btn.text = str(func_data.get("text", "功能"))
		btn.theme = blue_theme
		btn.pressed.connect(_on_function_button_pressed.bind(func_data))
		
		# 设置位置
		var pos = func_data.get("position", {"x": 0.5, "y": 0.5})
		var ratio_x = float(pos.get("x", 0.5))
		var ratio_y = float(pos.get("y", 0.5))
		
		var viewport_size = get_viewport_rect().size
		btn.position = Vector2(
			ratio_x * viewport_size.x,
			ratio_y * viewport_size.y
		)
		
		add_child(btn)
		function_buttons.append(btn)

func _on_function_button_pressed(func_data: Dictionary):
	var func_id = str(func_data.get("id", ""))
	match func_id:
		"omikuji":
			_show_omikuji_panel()
		_:
			print("未知功能: ", func_id)

const HistoryPanelScene = preload("res://scenes/history_panel.tscn")

func _init_history_panel():
	"""初始化历史记录面板（从 tscn 文件加载）"""
	var panel_scene = HistoryPanelScene.instantiate()
	panel_scene.name = "HistoryPanel"
	add_child(panel_scene)
	
	# 获取面板节点引用
	history_panel = panel_scene
	history_scroll = panel_scene.get_node_or_null("MarginContainer/VBox/ScrollContainer")
	history_content = panel_scene.get_node_or_null("MarginContainer/VBox/ScrollContainer/HistoryContent")
	
	var close_button = panel_scene.get_node_or_null("MarginContainer/VBox/Header/CloseButton")
	if close_button:
		close_button.pressed.connect(hide_history_panel)
	
	# 绑定历史按钮事件
	history_button.pressed.connect(_on_history_button_pressed)

func _toggle_history_panel():
	"""切换历史记录面板显示"""
	if history_panel.visible:
		hide_history_panel()
	else:
		show_history_panel()

func show_history_panel():
	"""显示历史记录面板"""
	if not history_panel.visible:
		history_panel.visible = true
		_update_history_content()
		call_deferred("_scroll_to_bottom")
		
func hide_history_panel():
	"""隐藏历史记录面板"""
	history_panel.visible = false

func _scroll_to_bottom():
	"""滚动到历史记录面板底部"""
	if history_scroll and history_content:
		await get_tree().process_frame
		history_scroll.scroll_vertical = history_scroll.get_v_scroll_bar().max_value

func _update_history_content():
	"""更新历史记录内容显示"""
	# 清空现有内容
	for child in history_content.get_children():
		child.queue_free()
	
	# 获取对话历史数据
	var history_data = _get_conversation_history()
	
	if history_data.is_empty():
		var empty_label = Label.new()
		empty_label.text = "暂无对话历史"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		history_content.add_child(empty_label)
		return
	
	# 处理历史数据并显示
	var role_labels = {"user": get_user_name(), "assistant": get_character_name(), "system": "系统"}
	for message in history_data:
		var msg_container = HBoxContainer.new()
		msg_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		msg_container.add_theme_constant_override("separation", 5)
		
		var role_name = role_labels.get(message.role, message.role)
		var role_color = Color(0.2, 0.6, 1.0) if message.role == "user" else Color(0.6, 0.2, 1.0) if message.role == "assistant" else Color(0.8, 0.8, 0.2)
		
		var role_label = Label.new()
		role_label.text = "[" + role_name + "] "
		role_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		role_label.add_theme_color_override("font_color", role_color)
		msg_container.add_child(role_label)
		
		var content_label = Label.new()
		content_label.text = message.content
		content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content_label.clip_text = false
		content_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		msg_container.add_child(content_label)
		
		history_content.add_child(msg_container)

func get_character_name() -> String:
	"""获取角色名称"""
	if not has_node("/root/SaveManager"):
		return "角色"
	
	var save_mgr = get_node("/root/SaveManager")
	return save_mgr.get_character_name()

func get_user_name() -> String:
	"""获取用户名称"""
	if not has_node("/root/SaveManager"):
		return "用户"
	
	var save_mgr = get_node("/root/SaveManager")
	return save_mgr.get_user_name()

func _get_conversation_history() -> Array:
	"""获取对话历史（来自对话控制器）"""
	if dialogue_controller == null:
		return []
	
	# 从对话控制器获取对话历史，这里需要实际提供的方法从AI系统中获取历史
	var history = []
	
	# 如果有可以获取历史的方法，则返回其内容
	if dialogue_controller.has_method("get_display_history"):
		history = dialogue_controller.get_display_history()
	elif dialogue_controller.has_method("get_conversation_history"):
		history = dialogue_controller.get_conversation_history()
		
	return history

func _show_omikuji_panel():
	"""显示求签面板"""
	var omikuji_panel = OmikujiPanelScene.instantiate()
	get_tree().root.add_child(omikuji_panel)
	omikuji_panel.show_panel(outdoor_id)
