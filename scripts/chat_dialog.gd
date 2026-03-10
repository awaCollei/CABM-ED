extends Panel

signal chat_ended

@onready var margin_container: MarginContainer = $MarginContainer
@onready var vbox: VBoxContainer = $MarginContainer/VBoxContainer
@onready var character_name_label: Label = $MarginContainer/VBoxContainer/CharacterNameLabel
@onready var message_label: Label = $MarginContainer/VBoxContainer/MessageLabel
@onready var end_button: Button = $MarginContainer/VBoxContainer/EndButton
@onready var auto_button: Button = get_parent().get_node("AutoButton")
@onready var continue_indicator: Label = $ContinueIndicator

# 这些节点可能不存在，需要动态创建
var input_container: HBoxContainer
var input_field: LineEdit
var send_button: Button
var mic_button: Button
var pic_button: Button  # 现在作为"+"按钮使用

# 顶部辅助输入框
var top_input_field: TextEdit = null
var top_input_enabled: bool = false

var is_input_mode: bool = true
var waiting_for_continue: bool = false
var auto_continue_enabled: bool = false
var auto_continue_timer: Timer = null
var auto_button_tween: Tween = null

# 选项相关
var options_container: VBoxContainer = null
var option_buttons: Array = []
var pending_options: Array = []  # 暂存待显示的选项

# 模块化组件
var input_handler: Node
var ui_manager: Node
var history_manager: Node
var typing_manager: Node
var voice_input: Node

# goto相关
const GOTO_COOLDOWN_DURATION = 60.0
var goto_cooldown_end_time: float = 0.0
var goto_notification_label: Label = null

func _ensure_ui_structure():
	"""简化的UI结构检查"""
	input_container = vbox.get_node("InputContainer")
	input_field = input_container.get_node("InputField")
	send_button = input_container.get_node("SendButton")
	mic_button = input_container.get_node("MicButton")
	pic_button = input_container.get_node("PicButton")
	# 确保有结束按钮（历史按钮已重命名为结束按钮）
	if not vbox.has_node("EndButton"):
		print("警告: 场景中缺少 EndButton 节点")
	auto_button.pressed.connect(_on_auto_button_pressed)

func _ready():
	_ensure_ui_structure()
	
	# 初始化自动播放定时器
	auto_continue_timer = Timer.new()
	auto_continue_timer.one_shot = true
	auto_continue_timer.timeout.connect(_on_continue_clicked)
	add_child(auto_continue_timer)
	
	# 初始化模块
	_init_modules()
	
	# 连接信号
	if end_button:
		end_button.pressed.connect(_on_history_toggle_pressed)
	if send_button:
		send_button.pressed.connect(_on_send_button_pressed)
	if mic_button:
		mic_button.pressed.connect(_on_mic_button_pressed)
	if input_field:
		input_field.text_submitted.connect(_on_input_submitted)
		input_field.text_changed.connect(_on_input_text_changed)
		_apply_android_input_workaround_to_line_edit(input_field)
	
	_load_config()
	
	# 创建顶部输入框
	_create_top_input_field()
	
	# 连接 AI 服务信号
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		ai_service.chat_response_received.connect(_on_ai_response)
		ai_service.chat_response_completed.connect(_on_ai_response_completed)
		ai_service.chat_error.connect(_on_ai_error)
		ai_service.options_generated.connect(_on_options_generated)
	
	# 连接事件管理器信号
	if has_node("/root/EventManager"):
		var event_mgr = get_node("/root/EventManager")
		event_mgr.event_completed.connect(_on_event_completed)
	
	visible = false
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)
	_update_top_input_visibility(false)
	
	# 初始隐藏自动播放按钮
	if auto_button:
		auto_button.visible = false
	
	_setup_input_mode()

func _apply_android_input_workaround_to_line_edit(le: LineEdit):
	if has_node("/root/PlatformManager"):
		var pm = get_node("/root/PlatformManager")
		if pm.is_android():
			le.context_menu_enabled = false
			le.shortcut_keys_enabled = false
			if le.has_method("set_selecting_enabled"):
				le.selecting_enabled = false

func _init_modules():
	# 输入处理模块
	input_handler = preload("res://scripts/chat_dialog_input_handler.gd").new()
	input_handler.name = "InputHandler"
	add_child(input_handler)
	input_handler.setup(self)
	input_handler.continue_requested.connect(_on_continue_clicked)
	
	# UI管理模块
	ui_manager = preload("res://scripts/chat_dialog_ui_manager.gd").new()
	ui_manager.name = "UIManager"
	add_child(ui_manager)
	ui_manager.setup(self, character_name_label, message_label, input_container,
					 input_field, send_button, end_button, continue_indicator)
	
	# 打字机效果模块
	typing_manager = preload("res://scripts/chat_dialog_typing.gd").new()
	typing_manager.name = "TypingManager"
	add_child(typing_manager)
	typing_manager.setup(self, message_label)
	typing_manager.sentence_ready_for_tts.connect(_on_sentence_ready_for_tts)
	typing_manager.sentence_completed.connect(_on_sentence_completed)
	typing_manager.all_sentences_completed.connect(_on_all_sentences_completed)
	
	# 历史记录模块
	history_manager = preload("res://scripts/chat_dialog_history.gd").new()
	history_manager.name = "HistoryManager"
	add_child(history_manager)
	# 延迟初始化，等待所有UI元素准备好
	call_deferred("_init_history_manager")
	
	# 语音输入模块
	voice_input = null
	if ResourceLoader.exists("res://scripts/chat_dialog_voice_input.gd"):
		voice_input = preload("res://scripts/chat_dialog_voice_input.gd").new()
	voice_input.name = "VoiceInput"
	add_child(voice_input)
	# 延迟初始化，等待mic_button创建
	call_deferred("_init_voice_input")

	# 图片输入模块
	if ResourceLoader.exists("res://scripts/chat_dialog_image_input.gd"):
		var image_input = preload("res://scripts/chat_dialog_image_input.gd").new()
		image_input.name = "ImageInput"
		add_child(image_input)
		call_deferred("_init_image_input")
	
	# 物品输入模块
	if ResourceLoader.exists("res://scripts/chat_dialog_item_input.gd"):
		var item_input = preload("res://scripts/chat_dialog_item_input.gd").new()
		item_input.name = "ItemInput"
		add_child(item_input)
		call_deferred("_init_item_input")

func _init_history_manager():
	history_manager.setup(self, vbox, input_container, input_field,
					  send_button, end_button)

func _init_voice_input():
	if mic_button and input_field:
		voice_input.setup(self, mic_button, input_field)

func _init_image_input():
	var image_node = get_node_or_null("ImageInput")
	if image_node and pic_button and input_field:
		image_node.setup(self, pic_button, input_field)

func _init_item_input():
	var item_node = get_node_or_null("ItemInput")
	if item_node and pic_button and input_field:
		item_node.setup(self, pic_button, input_field)

func _load_config():
	# app_config.json已废弃，不再需要加载配置
	# 加载顶部输入框设置
	if has_node("/root/AIConfigManager"):
		var config_mgr = get_node("/root/AIConfigManager")
		top_input_enabled = config_mgr.load_top_input_box()
		print("ChatDialog: 加载顶部输入框设置 = %s" % top_input_enabled)
		
		# 加载自动播放设置
		auto_continue_enabled = config_mgr.load_auto_continue()
		_update_auto_button_style()
		print("ChatDialog: 加载自动播放设置 = %s" % auto_continue_enabled)
	else:
		print("ChatDialog: 警告 - AIConfigManager未找到，使用默认值 false")
		top_input_enabled = false

func _on_auto_button_pressed():
	auto_continue_enabled = not auto_continue_enabled
	_update_auto_button_style()
	
	if has_node("/root/AIConfigManager"):
		var config_mgr = get_node("/root/AIConfigManager")
		config_mgr.save_auto_continue(auto_continue_enabled)
	
	# 如果当前正在等待继续，且开启了自动，立即检查是否可以继续
	if auto_continue_enabled and waiting_for_continue:
		_check_auto_continue()

func _update_auto_button_style():
	if not auto_button:
		return
		
	if auto_continue_enabled:
		auto_button.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5)) # 浅黄色
		print("样式")
		auto_button.text = "播放中"
		_start_auto_button_effect()
	else:
		auto_button.remove_theme_color_override("font_color")
		print("移除样式")
		auto_button.text = " 自动 "
		_stop_auto_button_effect()

func _start_auto_button_effect():
	if auto_button_tween:
		auto_button_tween.kill()
	
	auto_button_tween = create_tween().set_loops()
	auto_button_tween.tween_property(auto_button, "modulate:a", 0.6, 0.8).set_trans(Tween.TRANS_SINE)
	auto_button_tween.tween_property(auto_button, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

func _stop_auto_button_effect():
	if auto_button_tween:
		auto_button_tween.kill()
		auto_button_tween = null
	auto_button.modulate.a = 1.0

func on_voice_finished():
	"""由 TTSService 调用，语音播放完毕"""
	if auto_continue_enabled and waiting_for_continue:
		print("ChatDialog: 语音播放完毕，触发自动继续")
		_on_continue_clicked()

func _check_auto_continue():
	"""检查是否应该自动继续"""
	if not auto_continue_enabled or not waiting_for_continue:
		return
		
	# 检查当前句子的 TTS 需求
	var current_sentence = typing_manager.get_current_sentence_data()
	var no_tts = current_sentence != null and current_sentence.get("no_tts", false)
	var sentence_hash = current_sentence.get("sentence_hash", "") if current_sentence else ""
	
	# 检查TTS状态
	var tts_enabled = false
	if has_node("/root/TTSService"):
		var tts = get_node("/root/TTSService")
		tts_enabled = tts.is_enabled
		
		# 如果开启了 TTS 且当前句子需要播放 TTS
		if tts_enabled and not no_tts:
			# 如果正在播放语音，或者音频正在准备中，则等待 on_voice_finished() 调用
			# 我们认为 TTS 正在工作中，如果不工作（失败/无音频），TTSService 应该最终通过 on_voice_finished 通知
			print("ChatDialog: 句子 hash:%s 需要 TTS，将等待语音结束信号..." % sentence_hash.substr(0,8))
			return

	# 如果没开 TTS，或者当前句子无需 TTS，则等待 1 秒后继续
	print("ChatDialog: 无需等待语音 (no_tts=%s, tts_enabled=%s)，1秒后自动继续" % [no_tts, tts_enabled])
	auto_continue_timer.start(1.0)

func _setup_input_mode():
	is_input_mode = true
	waiting_for_continue = false
	character_name_label.visible = false
	message_label.visible = false
	input_container.visible = true
	input_field.visible = true
	send_button.visible = true
	# 确保mic_button也被正确设置
	if mic_button:
		mic_button.visible = true
		mic_button.modulate.a = 1.0
	# 确保pic_button也被正确设置
	if pic_button:
		pic_button.visible = true
		pic_button.modulate.a = 1.0
	continue_indicator.visible = false
	end_button.visible = true
	input_field.text = ""
	input_field.placeholder_text = "输入消息..."
	input_field.modulate.a = 1.0
	input_container.modulate.a = 1.0
	custom_minimum_size.y = 120.0
	_update_action_button_state()
	
	# 更新顶部输入框可见性
	_update_top_input_visibility(visible and is_input_mode and top_input_enabled)

func show_dialog(mode: String = "passive"):
	"""显示对话框
	mode: "passive" = 用户先说（输入模式）, "active" = 角色先说（回复模式）, 
		  "called" = 被呼唤来到场景（角色先说）, "called_here" = 被呼唤但已在场景（角色先说）
	"""
	# 如果已经可见，忽略重复调用
	if visible:
		print("聊天对话框已显示，忽略重复调用")
		return
	
	visible = true
	pivot_offset = size / 2.0
	
	# 显示自动播放按钮
	if auto_button:
		auto_button.visible = true
	
	if mode == "active" or mode == "called" or mode == "called_here":
		_setup_reply_mode()
		message_label.text = ""
	else:
		_setup_input_mode()
	
	# 如果开启了自动播放，恢复特效
	if auto_continue_enabled:
		_start_auto_button_effect()
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await tween.finished
	
	# 更新顶部输入框可见性
	_update_top_input_visibility(visible and is_input_mode and top_input_enabled)
	
	if mode == "active" or mode == "called" or mode == "called_here":
		if has_node("/root/AIService"):
			var ai_service = get_node("/root/AIService")
			ai_service.start_chat("", mode)
	else:
		if is_input_mode:
			input_field.grab_focus()

func _setup_reply_mode():
	is_input_mode = false
	character_name_label.visible = true
	message_label.visible = true
	input_container.visible = false
	# 确保mic_button也被隐藏
	if mic_button:
		mic_button.visible = false
	end_button.visible = false
	character_name_label.modulate.a = 1.0
	message_label.modulate.a = 1.0
	character_name_label.text = _get_character_name()
	custom_minimum_size.y = 200.0
	
	# 更新顶部输入框可见性（回复模式下隐藏）
	_update_top_input_visibility(false)

func hide_dialog():
	# 如果已经隐藏，忽略重复调用
	if not visible:
		print("聊天对话框已隐藏，忽略重复调用")
		return
	
	# 清除选项
	_clear_options()
	
	pivot_offset = size / 2.0
	
	typing_manager.stop()
	
	# 停止自动播放相关
	if auto_continue_timer:
		auto_continue_timer.stop()
	_stop_auto_button_effect()
	
	# 隐藏自动播放按钮
	if auto_button:
		auto_button.visible = false
	
	if has_node("/root/TTSService"):
		var tts = get_node("/root/TTSService")
		tts.clear_queue()
	
	if continue_indicator:
		continue_indicator.visible = false
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	await tween.finished
	visible = false
	
	# 隐藏顶部输入框
	_update_top_input_visibility(false)
	
	waiting_for_continue = false
	_setup_input_mode()

func _on_end_button_pressed():
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		var pending_goto = ai_service.get_pending_goto()
		if pending_goto >= 0:
			print("ChatDialog: 用户主动结束聊天，恢复暂存的goto字段")
			ai_service.response_parser.extracted_fields["goto"] = pending_goto
			ai_service.clear_pending_goto()
			_hide_goto_notification()
			_set_goto_cooldown()
	
	var turn_count = 0
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		for msg in ai_service.current_conversation:
			if msg.role == "user":
				turn_count += 1
		ai_service.end_chat()
	
	if has_node("/root/EventManager"):
		var event_mgr = get_node("/root/EventManager")
		event_mgr.on_chat_session_end(turn_count)
	
	hide_dialog()
	await get_tree().create_timer(0.3).timeout
	chat_ended.emit()

func _on_ai_response(response: String):
	"""AI 响应回调 - 接收流式增量内容"""
	if not typing_manager.is_receiving_stream:
		typing_manager.start_stream()
	
	typing_manager.add_stream_content(response)

func _on_ai_response_completed():
	"""AI 流式响应完成回调"""
	if not typing_manager.has_content():
		var character_name = _get_character_name()
		_handle_empty_msg_response(character_name + "欲言又止")
		return
	
	typing_manager.end_stream()

func _on_options_generated(options: Array):
	"""选项生成完成回调"""
	print("收到生成的选项: ", options)
	# 暂存选项，等待用户点击继续后再显示
	pending_options = options
	
	# 如果已经是输入模式（即用户已经看完了所有对话，正在等待输入），则立即显示
	if is_input_mode:
		_show_options(pending_options)
		pending_options.clear()

func _on_ai_error(error_message: String):
	"""AI 错误回调 - 撤回用户消息"""
	print("AI 错误: ", error_message)
	
	# 撤回用户消息：从历史中删除最后一条用户消息，并恢复到输入框
	_retract_last_user_message()
	
	# 显示错误提示
	var error_text = ""
	if error_message.contains("超时"):
		error_text = "请求超时（错误代码：408）"
	else:
		error_text = "请求出错：" + error_message
	
	await _show_error_notification(error_text)

func _update_action_button_state():
	var has_text = not input_field.text.strip_edges().is_empty()
	if has_text:
		send_button.text = "发送"
		send_button.modulate = Color(0.2, 0.5, 1.0, 0.8)
	else:
		send_button.text = "结束"
		send_button.modulate = Color(1.0, 0.2, 0.2, 0.8)

func _on_event_completed(event_name: String, result):
	"""处理事件完成信号"""
	if event_name == "idle_timeout":
		if result.message == "timeout_to_input":
			if history_manager.is_history_visible:
				await history_manager.hide_history()
			elif waiting_for_continue:
				waiting_for_continue = false
				continue_indicator.visible = false
				await ui_manager.transition_to_input_mode()
			
			await get_tree().create_timer(0.5).timeout
			_on_end_button_pressed()
		elif result.message == "chat_idle_timeout":
			# 输入模式下长时间无操作，确保UI状态正确后再结束
			if history_manager.is_history_visible:
				await history_manager.hide_history()
			elif not is_input_mode:
				# 如果不在输入模式（例如在回复模式），先恢复到输入模式
				waiting_for_continue = false
				continue_indicator.visible = false
				await ui_manager.transition_to_input_mode()
			
			await get_tree().create_timer(0.3).timeout
			_on_end_button_pressed()

func _on_send_button_pressed():
	var text = input_field.text
	if text.strip_edges().is_empty():
		_on_end_button_pressed()
	else:
		_on_input_submitted(text)

func _on_mic_button_pressed():
	if not voice_input:
		return
	
	if not voice_input.is_recording:
		voice_input.start_recording()
		_update_action_button_state()
	else:
		voice_input.stop_recording()
		_update_action_button_state()

func _on_input_submitted(text: String):
	if text.strip_edges().is_empty():
		return
	
	print("用户输入: ", text)
	
	# 清除选项（用户手动输入时）
	_clear_options()
	
	# 清空顶部输入框
	if top_input_field != null:
		top_input_field.text = ""
	
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		var pending_goto = ai_service.get_pending_goto()
		if pending_goto >= 0:
			print("ChatDialog: 用户输入消息，放弃暂存的goto字段")
			ai_service.clear_pending_goto()
			_hide_goto_notification()
	
	await ui_manager.transition_to_reply_mode(_get_character_name())
	
	if has_node("/root/EventManager"):
		var event_mgr = get_node("/root/EventManager")
		var result = event_mgr.on_chat_turn_end()
		
		if not result.success:
			_handle_reply_refusal(text, result.message)
			return
	else:
		print("警告: EventManager未找到，默认允许回复")
	
	var final_text = text
	var item_data = {}
	
	# 检查是否有选中的图片
	var img_node = get_node_or_null("ImageInput")
	if img_node and img_node.has_selected_image():
		var desc = await img_node.describe_selected_image()
		if not String(desc).strip_edges().is_empty():
			final_text = "【图片：" + String(desc).strip_edges() + "】" + final_text
		img_node.clear_selected_image()
	
	# 检查是否有选中的物品
	var item_node = get_node_or_null("ItemInput")
	if item_node and item_node.has_selected_item():
		item_data = item_node.get_selected_item()
		# 注意：不在这里清除物品，等AI响应后根据结果处理
	
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		ai_service.start_chat(final_text, "passive", item_data)

func _on_sentence_ready_for_tts(text: String):
	"""句子准备好进行TTS处理 - 立即发送到TTS服务
	这发生在句子从流中提取时，不等待显示完成
	这样可以在用户等待时预先进行翻译和语音合成
	"""
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	if tts.is_enabled and not text.is_empty():
		tts.synthesize_speech(text)
		print("ChatDialog: 发送TTS（早期处理） - ", text)

func _on_sentence_completed():
	"""单个句子显示完成"""
	waiting_for_continue = true
	input_handler.set_waiting_for_continue(true)
	ui_manager.show_continue_indicator()
	
	# 检查TTS状态
	var tts_enabled = false
	if has_node("/root/TTSService"):
		var tts = get_node("/root/TTSService")
		tts_enabled = tts.is_enabled
	
	if not tts_enabled:
		if has_node("/root/EventManager"):
			var event_mgr = get_node("/root/EventManager")
			event_mgr.reset_idle_timer()
			print("TTS未启用，文本输出完毕，重置空闲计时器")
	
	# 如果开启了自动播放，检查是否继续
	if auto_continue_enabled:
		_check_auto_continue()

func _on_all_sentences_completed():
	"""所有句子显示完成"""
	waiting_for_continue = true
	input_handler.set_waiting_for_continue(true)
	ui_manager.show_continue_indicator()
	
	# 检查TTS状态
	var tts_enabled = false
	if has_node("/root/TTSService"):
		var tts = get_node("/root/TTSService")
		tts_enabled = tts.is_enabled
	
	if not tts_enabled:
		if has_node("/root/EventManager"):
			var event_mgr = get_node("/root/EventManager")
			event_mgr.reset_idle_timer()
			print("TTS未启用，所有文本输出完毕，重置空闲计时器")
	
	# 如果开启了自动播放，检查是否继续
	if auto_continue_enabled:
		_check_auto_continue()

func _on_continue_clicked():
	if not waiting_for_continue:
		print("警告: 不在等待继续状态，忽略点击")
		return
	
	# 停止自动播放计时器，防止手动点击后再次触发
	if auto_continue_timer:
		auto_continue_timer.stop()
	
	# 立即设置为false，防止重复触发
	waiting_for_continue = false
	input_handler.set_waiting_for_continue(false)
	ui_manager.hide_continue_indicator()
	
	if typing_manager.has_more_sentences():
		# 有更多句子，显示下一句
		# 切换表情（随机选择当前mood的一个图片）
		var character = get_tree().current_scene.get_node_or_null("Background/Character")
		if character and character.has_method("switch_expression_randomly"):
			character.switch_expression_randomly()
		
		var next_sentence_hash = typing_manager.show_next_sentence()
		if next_sentence_hash != "":
			print("显示句子 hash:%s" % next_sentence_hash.substr(0,8))
			# 通知 TTS 系统用户显示了新句子
			if has_node("/root/TTSService"):
				var tts = get_node("/root/TTSService")
				tts.on_new_sentence_displayed(next_sentence_hash)
				print("已通知TTS系统显示句子 hash:%s" % next_sentence_hash.substr(0,8))
	elif typing_manager.is_receiving_stream:
		# 流还在继续，但暂时没有新句子
		# 重新设置等待状态，等待新句子到来
		print("流式接收中，暂无新句子，继续等待...")
		waiting_for_continue = true
		input_handler.set_waiting_for_continue(true)
		ui_manager.show_continue_indicator()
	else:
		# 流已结束，所有句子都显示完了
		var goto_action = _check_and_handle_goto()
		
		if goto_action == "immediate":
			await ui_manager.transition_to_input_mode()
			await get_tree().process_frame
			_on_end_button_pressed()
		elif goto_action == "pending":
			await ui_manager.transition_to_input_mode()
			# 显示暂存的选项（如果有）
			if not pending_options.is_empty():
				_show_options(pending_options)
				pending_options.clear()
		else:
			await ui_manager.transition_to_input_mode()
			# 显示暂存的选项（如果有）
			if not pending_options.is_empty():
				_show_options(pending_options)
				pending_options.clear()

func _check_and_handle_goto() -> String:
	"""检查并处理goto字段"""
	if not has_node("/root/AIService"):
		return "none"
	
	var ai_service = get_node("/root/AIService")
	var goto_index = ai_service.get_goto_field()
	
	if goto_index < 0:
		return "none"
	
	if not has_node("/root/PromptBuilder") or not has_node("/root/SaveManager"):
		return "none"
	
	var prompt_builder = get_node("/root/PromptBuilder")
	var target_scene = prompt_builder.get_scene_id_by_index(goto_index)
	
	if target_scene == "":
		print("ChatDialog: 无效的goto索引: ", goto_index)
		ai_service.clear_goto_field()
		return "none"
	
	if not _is_valid_scene(target_scene):
		print("ChatDialog: goto场景 '%s' 不合法，忽略" % target_scene)
		ai_service.clear_goto_field()
		return "none"
	
	var save_mgr = get_node("/root/SaveManager")
	var character_scene = save_mgr.get_character_scene()
	
	if target_scene == character_scene:
		print("ChatDialog: goto场景与角色当前场景相同，忽略: ", target_scene)
		ai_service.clear_goto_field()
		return "none"
	
	if not has_node("/root/EventHelpers"):
		return "immediate"
	
	var helpers = get_node("/root/EventHelpers")
	var willingness = helpers.get_willingness()
	var base_willingness = 150
	var success_chance = helpers.calculate_success_chance(base_willingness)
	
	print("ChatDialog: goto字段处理 - 回复意愿: %d, 成功率: %.2f" % [willingness, success_chance])
	
	if _is_goto_on_cooldown():
		print("ChatDialog: goto在冷却中，抛弃goto字段")
		ai_service.clear_goto_field()
		ai_service.remove_goto_from_history()
		return "discarded"
	
	var rand_value = randf()
	var is_willing = rand_value < success_chance
	
	print("ChatDialog: 随机值: %.2f, 判定: %s" % [rand_value, "愿意留下" if is_willing else "想要离开"])
	
	if is_willing:
		print("ChatDialog: 角色愿意暂时留下，暂存goto字段")
		ai_service.set_pending_goto(goto_index)
		ai_service.clear_goto_field()
		_show_goto_notification(target_scene)
		return "pending"
	else:
		print("ChatDialog: 角色想要离开，立即触发场景变化")
		_set_goto_cooldown()
		return "immediate"

func _get_costume_config_path(costume_id: String) -> String:
	"""获取服装配置文件路径"""
	# 优先从内置配置路径加载
	var res_config_path = "res://config/character_presets/%s.json" % costume_id
	if ResourceLoader.exists(res_config_path):
		return res_config_path
		
	# 其次从用户配置路径加载
	var user_config_path = "user://clothes/configs/%s.json" % costume_id
	if FileAccess.file_exists(user_config_path):
		return user_config_path
		
	return ""

func _is_valid_scene(scene_id: String) -> bool:
	"""验证场景ID是否合法（同时存在于scenes.json和当前服装的配置中）"""
	# 检查scenes.json
	var scenes_path = "res://config/scenes.json"
	if not FileAccess.file_exists(scenes_path):
		print("ChatDialog: scenes.json 不存在")
		return false
	
	var scenes_file = FileAccess.open(scenes_path, FileAccess.READ)
	var scenes_json_string = scenes_file.get_as_text()
	scenes_file.close()
	
	var scenes_json = JSON.new()
	if scenes_json.parse(scenes_json_string) != OK:
		print("ChatDialog: scenes.json 解析失败")
		return false
	
	var scenes_data = scenes_json.data
	if not scenes_data.has("scenes") or not scenes_data.scenes.has(scene_id):
		print("ChatDialog: 场景 '%s' 不在 scenes.json 中" % scene_id)
		return false
	
	# 获取当前服装ID
	var costume_id = "default"
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		costume_id = save_mgr.get_costume_id()
	
	# 检查当前服装的配置文件
	var presets_path = _get_costume_config_path(costume_id)
	if not FileAccess.file_exists(presets_path):
		print("ChatDialog: 服装配置 %s 不存在" % presets_path)
		return false
	
	var file = FileAccess.open(presets_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		print("ChatDialog: 服装配置 %s 解析错误" % presets_path)
		return false
	
	var presets_config = json.data
	if not presets_config.has(scene_id):
		print("ChatDialog: 场景 '%s' 不在服装 %s 的配置中" % [scene_id, costume_id])
		return false
	
	# 确保是数组类型（场景配置）而不是字符串（id/name/description）
	if not presets_config[scene_id] is Array:
		print("ChatDialog: 场景 '%s' 在服装 %s 中不是有效的场景配置" % [scene_id, costume_id])
		return false
	
	if presets_config[scene_id].size() == 0:
		print("ChatDialog: 场景 '%s' 在服装 %s 中没有角色预设" % [scene_id, costume_id])
		return false
	
	print("ChatDialog: 场景 '%s' 验证通过" % scene_id)
	return true

func _is_goto_on_cooldown() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_time < goto_cooldown_end_time

func _set_goto_cooldown():
	var current_time = Time.get_ticks_msec() / 1000.0
	goto_cooldown_end_time = current_time + GOTO_COOLDOWN_DURATION
	print("ChatDialog: 设置goto冷却时间，将在 %.1f 秒后解除" % GOTO_COOLDOWN_DURATION)

func _get_scene_name(scene_id: String) -> String:
	var scenes_path = "res://config/scenes.json"
	if not FileAccess.file_exists(scenes_path):
		return scene_id
	
	var file = FileAccess.open(scenes_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return scene_id
	
	var scenes_config = json.data
	if not scenes_config.has("scenes"):
		return scene_id
	
	if scenes_config.scenes.has(scene_id) and scenes_config.scenes[scene_id].has("name"):
		return scenes_config.scenes[scene_id].name
	
	return scene_id

func _show_goto_notification(target_scene: String):
	var character_name = _get_character_name()
	var scene_name = _get_scene_name(target_scene)
	var notification_text = "%s将前往%s" % [character_name, scene_name]
	
	if goto_notification_label != null:
		goto_notification_label.queue_free()
		goto_notification_label = null
	
	goto_notification_label = Label.new()
	goto_notification_label.name = "GotoNotificationLabel"
	goto_notification_label.text = notification_text
	goto_notification_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	goto_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	goto_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	goto_notification_label.modulate.a = 0.0
	
	goto_notification_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	goto_notification_label.offset_left = -200
	goto_notification_label.offset_top = -30
	goto_notification_label.offset_right = -10
	goto_notification_label.offset_bottom = -10
	
	add_child(goto_notification_label)
	
	var fade_in = create_tween()
	fade_in.tween_property(goto_notification_label, "modulate:a", 0.8, 0.5)
	
	print("ChatDialog: 显示goto提示 - %s" % notification_text)

func _hide_goto_notification():
	if goto_notification_label == null:
		return
	
	var fade_out = create_tween()
	fade_out.tween_property(goto_notification_label, "modulate:a", 0.0, 0.3)
	await fade_out.finished
	
	goto_notification_label.queue_free()
	goto_notification_label = null
	print("ChatDialog: 隐藏goto提示")

func _handle_reply_refusal(user_message: String, refusal_message: String):
	typing_manager.start_stream()
	typing_manager.add_stream_content("……")
	typing_manager.end_stream()
	
	while not typing_manager.is_showing_sentence:
		await get_tree().process_frame
	
	await _show_refusal_message(refusal_message)
	
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		ai_service.add_to_history("user", user_message)
		ai_service.add_to_history("assistant", "……")

func _handle_empty_msg_response(message: String):
	typing_manager.start_stream()
	typing_manager.add_stream_content("……")
	typing_manager.end_stream()
	
	while not typing_manager.is_showing_sentence:
		await get_tree().process_frame
	
	await _show_refusal_message(message)
	
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		ai_service.add_to_history("assistant", "……")

func _show_refusal_message(message: String = ""):
	var character_name = _get_character_name()
	var refusal_text = message if not message.is_empty() else (character_name + "似乎不想说话")
	
	var refusal_label = Label.new()
	refusal_label.name = "RefusalLabel"
	refusal_label.text = refusal_text
	refusal_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	refusal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	refusal_label.modulate.a = 0.0
	
	var message_index = message_label.get_index()
	vbox.add_child(refusal_label)
	vbox.move_child(refusal_label, message_index + 1)
	
	var fade_in = create_tween()
	fade_in.tween_property(refusal_label, "modulate:a", 1.0, 0.3)
	await fade_in.finished
	
	await get_tree().create_timer(2.0).timeout
	
	var fade_out = create_tween()
	fade_out.tween_property(refusal_label, "modulate:a", 0.0, 0.3)
	await fade_out.finished
	
	refusal_label.queue_free()

func _retract_last_user_message():
	"""撤回最后一条用户消息，恢复到输入框"""
	if not has_node("/root/AIService"):
		return
	
	var ai_service = get_node("/root/AIService")
	var conversation = ai_service.current_conversation
	
	# 从后往前查找最后一条用户消息
	var last_user_message = ""
	var last_user_index = -1
	
	for i in range(conversation.size() - 1, -1, -1):
		if conversation[i].role == "user":
			last_user_message = conversation[i].content
			last_user_index = i
			break
	
	# 删除最后一条用户消息
	if last_user_index >= 0:
		conversation.remove_at(last_user_index)
		print("撤回用户消息: ", last_user_message)
	
	# 切换回输入模式
	await ui_manager.transition_to_input_mode()
	
	# 恢复消息到输入框
	if not last_user_message.is_empty():
		input_field.text = last_user_message
		input_field.grab_focus()
		# 将光标移到末尾
		input_field.caret_column = last_user_message.length()
		# 更新发送按钮状态
		_update_action_button_state()

func _show_error_notification(error_text: String):
	"""显示错误通知"""
	var error_label = Label.new()
	error_label.name = "ErrorNotificationLabel"
	error_label.text = error_text
	error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.modulate.a = 0.0
	
	var message_index = message_label.get_index()
	vbox.add_child(error_label)
	vbox.move_child(error_label, message_index + 1)
	
	var fade_in_tween = create_tween()
	fade_in_tween.tween_property(error_label, "modulate:a", 1.0, 0.3)
	await fade_in_tween.finished
	
	await get_tree().create_timer(5.0).timeout
	
	var fade_out_tween = create_tween()
	fade_out_tween.tween_property(error_label, "modulate:a", 0.0, 0.3)
	await fade_out_tween.finished
	
	error_label.queue_free()

func _on_history_toggle_pressed():
	history_manager.toggle_history()

func _get_character_name() -> String:
	"""获取角色名称"""
	if not has_node("/root/SaveManager"):
		return "角色"
	
	var save_mgr = get_node("/root/SaveManager")
	return save_mgr.get_character_name()


func _show_options(options: Array):
	"""在屏幕右侧中上部显示三个选项"""
	# 清除旧的选项
	_clear_options()
	
	# 创建选项容器
	options_container = VBoxContainer.new()
	options_container.name = "OptionsContainer"
	options_container.add_theme_constant_override("separation", 20)
	
	# 设置位置：屏幕右侧，偏上位置（从中心往上偏移）
	options_container.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	options_container.offset_left = -210  # 距离右边缘20px，宽度190px
	options_container.offset_right = -20
	options_container.offset_top = -110  # 往上偏移110px
	options_container.offset_bottom = -180
	options_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	
	# 添加到场景根节点（而不是对话框内部）
	var main_scene = get_tree().current_scene
	main_scene.add_child(options_container)
	
	# 创建三个选项按钮
	for i in range(options.size()):
		var option_text = options[i]
		var button = Button.new()
		button.text = option_text
		button.custom_minimum_size = Vector2(250, 35)
		button.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		
		# 设置按钮样式 - 使用更小的字体和更显眼的颜色
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))  # 白色文本
		button.add_theme_color_override("font_hover_color", Color(0.5, 0.6, 1.0, 1.0))  # 悬停时蓝色
		button.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9, 1.0))  # 按下时浅灰色
		# button.self_modulate = Color(0.4, 0.55, 0.75, 0.85)  # 柔和的蓝色背景，稍微透明（只影响背景不影响文本）
		
		# 连接点击事件
		button.pressed.connect(_on_option_selected.bind(option_text))
		
		options_container.add_child(button)
		option_buttons.append(button)
	
	# 淡入动画
	options_container.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(options_container, "modulate:a", 1.0, 0.3)
	
	print("选项已显示在屏幕右侧中上部")

func _clear_options():
	"""清除显示的选项"""
	if options_container != null:
		options_container.queue_free()
		options_container = null
	
	option_buttons.clear()

func _on_option_selected(option_text: String):
	"""选项被点击时的处理"""
	print("用户选择了选项: ", option_text)
	
	# 清除选项
	_clear_options()
	
	# 将选项文本填入输入框并发送
	if input_field:
		input_field.text = option_text
		_on_input_submitted(option_text)

## 创建顶部辅助输入框
func _create_top_input_field():
	"""在屏幕右侧创建辅助输入框，支持自动换行"""
	if top_input_field != null:
		return
	
	top_input_field = TextEdit.new()
	top_input_field.name = "TopInputField"
	top_input_field.placeholder_text = "输入消息..."
	top_input_field.custom_minimum_size = Vector2(300, 100)
	
	# 设置较小的字号
	top_input_field.add_theme_font_size_override("font_size", 16)
	
	# 启用自动换行
	top_input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	
	# 设置位置：屏幕右侧中上部
	top_input_field.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	top_input_field.offset_left = -420 
	top_input_field.offset_right = -120
	top_input_field.offset_top = -260
	top_input_field.offset_bottom = -160
	top_input_field.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	
	# 连接信号以实现双向同步
	top_input_field.text_changed.connect(_on_top_input_text_changed)
	
	# 添加到主场景（而不是对话框内部）
	var main_scene = get_tree().current_scene
	main_scene.add_child.call_deferred(top_input_field)
	
	# 初始状态：隐藏，等待对话框显示时再根据状态显示
	top_input_field.visible = false
	
	print("右侧辅助输入框已创建（支持自动换行），初始状态：隐藏")

## 更新顶部输入框的可见性
func _update_top_input_visibility(show: bool):
	if top_input_field == null:
		return
	top_input_field.visible = show
	print("顶部输入框可见性更新: %s" % show)

## 主输入框文本变化时同步到顶部输入框
func _on_input_text_changed(new_text: String):
	"""输入框文本变化时重置空闲计时器"""
	if has_node("/root/EventManager"):
		var event_mgr = get_node("/root/EventManager")
		event_mgr.reset_idle_timer()
	_update_action_button_state()
	
	# 同步到顶部输入框（避免循环）
	if top_input_field != null and top_input_field.text != new_text:
		top_input_field.text = new_text

## 顶部输入框文本变化时同步到主输入框
func _on_top_input_text_changed():
	"""顶部输入框文本变化时同步到主输入框"""
	if top_input_field == null or input_field == null:
		return
	
	var new_text = top_input_field.text
	if input_field.text != new_text:
		input_field.text = new_text
	
	# 触发主输入框的文本变化逻辑（但不再次同步）
	if has_node("/root/EventManager"):
		var event_mgr = get_node("/root/EventManager")
		event_mgr.reset_idle_timer()
	_update_action_button_state()

## 设置顶部输入框开关状态（由设置面板调用）
func set_top_input_enabled(enabled: bool):
	top_input_enabled = enabled
	_update_top_input_visibility(visible and enabled and is_input_mode)
	print("顶部输入框已%s" % ("启用" if enabled else "禁用"))
