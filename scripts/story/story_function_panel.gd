extends VBoxContainer

# 故事功能面板
# 管理选中消息的详细信息显示和操作按钮

signal play_voice_requested(message_index: int)
signal regenerate_requested(message_index: int)
signal retract_requested(message_index: int)
signal continue_requested(message_index: int)

# UI组件
var message_info_label: RichTextLabel = null
var play_voice_button: Button = null
var regenerate_button: Button = null
var retract_button: Button = null
var continue_button: Button = null

# 状态
var selected_message_index: int = -1
var messages: Array = []
var is_ai_responding: bool = false
var story_dialog_panel: Control = null  # 对话面板引用

func _ready():
	"""初始化功能面板"""
	_create_ui()

func _create_ui():
	"""创建UI组件"""
	# 消息信息标签
	message_info_label = RichTextLabel.new()
	message_info_label.custom_minimum_size = Vector2(0, 200)
	message_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_info_label.bbcode_enabled = true
	message_info_label.text = "[center]请选择一条消息[/center]"
	message_info_label.fit_content = false
	add_child(message_info_label)
	
	# 按钮容器 - 使用GridContainer实现2x2布局
	var button_container = GridContainer.new()
	button_container.columns = 2
	button_container.custom_minimum_size = Vector2(0, 120)
	button_container.add_theme_constant_override("h_separation", 10)
	button_container.add_theme_constant_override("v_separation", 10)
	add_child(button_container)
	
	# 第一行第一列：重新生成按钮
	regenerate_button = Button.new()
	regenerate_button.text = "重新生成"
	regenerate_button.custom_minimum_size = Vector2(0, 50)
	regenerate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	regenerate_button.disabled = true
	regenerate_button.pressed.connect(_on_regenerate_pressed)
	button_container.add_child(regenerate_button)
	
	# 第一行第二列：播放语音按钮
	play_voice_button = Button.new()
	play_voice_button.text = "播放语音"
	play_voice_button.custom_minimum_size = Vector2(0, 50)
	play_voice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_voice_button.disabled = true
	play_voice_button.pressed.connect(_on_play_voice_pressed)
	button_container.add_child(play_voice_button)
	
	# 第二行第一列：撤回消息按钮
	retract_button = Button.new()
	retract_button.text = "撤回消息"
	retract_button.custom_minimum_size = Vector2(0, 50)
	retract_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retract_button.disabled = true
	retract_button.pressed.connect(_on_retract_pressed)
	button_container.add_child(retract_button)
	
	# 第二行第二列：继续生成按钮
	continue_button = Button.new()
	continue_button.text = "继续生成"
	continue_button.custom_minimum_size = Vector2(0, 50)
	continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	continue_button.disabled = true
	continue_button.pressed.connect(_on_continue_pressed)
	button_container.add_child(continue_button)

func set_messages(msg_array: Array):
	"""设置消息数组引用"""
	messages = msg_array

func set_story_dialog_panel(panel: Control):
	"""设置对话面板引用"""
	story_dialog_panel = panel

func set_ai_responding(responding: bool):
	"""设置AI响应状态"""
	is_ai_responding = responding
	update_buttons()

func select_message(message_index: int):
	"""选中消息"""
	selected_message_index = message_index
	update_display()

func deselect_message():
	"""取消选中"""
	selected_message_index = -1
	update_display()

func update_display():
	"""更新显示内容"""
	if selected_message_index < 0 or selected_message_index >= messages.size():
		message_info_label.text = "[center]请选择一条消息[/center]"
		_disable_all_buttons()
		return
	
	var msg = messages[selected_message_index]
	var msg_type = msg.get("type", "")
	var msg_text = msg.get("text", "")
	var type_name="未知"
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		type_name = save_mgr.get_character_name() if msg_type == "ai" else (save_mgr.get_user_name() if msg_type == "user" else "系统")
	else:
		type_name = "AI" if msg_type == "ai" else ('用户' if msg_type == "user" else "系统")
	
	# 显示消息信息
	var info_text = "[b]%s[/b]\n\n%s" % [type_name, msg_text]
	message_info_label.text = info_text
	
	update_buttons()

func update_buttons():
	"""更新按钮状态"""
	if selected_message_index < 0 or selected_message_index >= messages.size():
		_disable_all_buttons()
		return
	
	var msg = messages[selected_message_index]
	var msg_type = msg.get("type", "")
	
	# 判断是否是最新消息
	var is_latest = (selected_message_index == messages.size() - 1)
	
	# 判断是否已存档
	var is_archived = _is_message_archived(selected_message_index)
	
	# 播放语音：仅AI消息可用
	play_voice_button.disabled = (msg_type != "ai") or is_ai_responding
	
	# 重新生成：AI消息，未存档，且AI未响应
	regenerate_button.disabled = (msg_type != "ai") or is_archived or is_ai_responding
	
	# 撤回消息：用户消息，未存档，且AI未响应
	retract_button.disabled = (msg_type != "user") or is_archived or is_ai_responding
	
	# 继续生成：最新的AI消息，未存档，且AI未响应
	continue_button.disabled = (msg_type != "ai") or not is_latest or is_archived or is_ai_responding

func _is_message_archived(message_index: int) -> bool:
	"""判断消息是否已存档
	
	逻辑：创建存档点后，current_node_messages 会被清空。
	因此，如果消息索引超出 current_node_messages 的范围，
	说明该消息是在存档点之前的，属于已存档消息。
	"""
	if not story_dialog_panel or not story_dialog_panel.save_manager:
		return false
	
	# 获取当前节点的消息数量
	var current_messages = story_dialog_panel.save_manager.get_current_node_messages()
	var current_message_count = current_messages.size()
	
	# 如果消息索引在当前节点消息范围之外（即更早的消息），则为已存档
	# messages 数组的后 current_message_count 条是未存档的
	var total_messages = messages.size()
	var first_unsaved_index = total_messages - current_message_count
	
	return message_index < first_unsaved_index

func _disable_all_buttons():
	"""禁用所有按钮"""
	play_voice_button.disabled = true
	regenerate_button.disabled = true
	retract_button.disabled = true
	continue_button.disabled = true

func _on_play_voice_pressed():
	"""播放语音按钮点击"""
	play_voice_requested.emit(selected_message_index)

func _on_regenerate_pressed():
	"""重新生成按钮点击"""
	regenerate_requested.emit(selected_message_index)

func _on_retract_pressed():
	"""撤回消息按钮点击"""
	retract_requested.emit(selected_message_index)

func _on_continue_pressed():
	"""继续生成按钮点击"""
	continue_requested.emit(selected_message_index)
