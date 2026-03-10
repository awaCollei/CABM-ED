extends Control

# 助眠模式主控制器
# 循环播放助眠视频背景和音频

@onready var video_player: VideoStreamPlayer = $VideoPlayer
@onready var exit_button = $ExitButton
@onready var background_toggle = $BackgroundToggle
@onready var static_background: TextureRect = $StaticBackground
@onready var background_player: AudioStreamPlayer = $BackgroundPlayer
@onready var voice_player: AudioStreamPlayer = $VoicePlayer
@onready var trigger_player: AudioStreamPlayer = $TriggerPlayer
@onready var bg_volume_slider: HSlider = $AudioControls/BackgroundVolumeSlider
@onready var voice_volume_slider: HSlider = $AudioControls/VoiceVolumeSlider
@onready var trigger_volume_slider: HSlider = $AudioControls/TriggerVolumeSlider
@onready var left_visualizer: ColorRect = $LeftVisualizer
@onready var right_visualizer: ColorRect = $RightVisualizer
@onready var status_bar: PanelContainer = $StatusBar
@onready var status_toggle: Button = $StatusBar/VBox/Header/ToggleButton
@onready var status_display: TextEdit = $StatusBar/VBox/StatusDisplay
@onready var input_field: LineEdit = $InputPanel/HBox/InputField
@onready var send_button: Button = $InputPanel/HBox/SendButton
@onready var continuous_toggle: CheckButton = $ContinuousToggle
@onready var background_mode_toggle: CheckButton = $BackgroundModeToggle

var exit_confirmation_dialog: ConfirmationDialog = null
var is_dynamic_background: bool = true  # 默认为动态背景
var is_background_mode_enabled: bool = false  # 后台模式开关
var config_path: String = "user://sleep_config.json"

# 后台音频插件
var background_audio_plugin = null

# 音频控制器
var audio_controller: Node = null

# ASMR组件
var asmr_main_flow: Node = null
var asmr_tts_manager: Node = null
var asmr_tool_manager: Node = null

var is_status_bar_expanded: bool = true

# 输入框状态管理
var is_input_enabled: bool = true
var original_input_placeholder: String = ""

func _ready():
	# 初始化后台音频插件（仅 Android）
	if OS.get_name() == "Android" and Engine.has_singleton("BackgroundAudioPlugin"):
		background_audio_plugin = Engine.get_singleton("BackgroundAudioPlugin")
		print("后台音频插件已加载")
	
	# 加载配置
	_load_config()
	
	# 设置背景
	_setup_background()
	
	# 设置音频控制器（异步）
	await _setup_audio_controller()
	
	# 设置ASMR组件
	_setup_asmr_components()
	
	# 连接按钮信号
	exit_button.pressed.connect(_on_exit_button_pressed)
	background_toggle.pressed.connect(_on_background_toggle_pressed)
	background_mode_toggle.toggled.connect(_on_background_mode_toggled)
	status_toggle.pressed.connect(_on_status_toggle_pressed)
	send_button.pressed.connect(_on_send_button_pressed)
	input_field.text_submitted.connect(_on_input_submitted)
	continuous_toggle.toggled.connect(_on_continuous_toggle_changed)
	
	# 保存原始占位符文本
	original_input_placeholder = input_field.placeholder_text
	
	# 连接滑杆信号
	bg_volume_slider.value_changed.connect(_on_bg_volume_changed)
	voice_volume_slider.value_changed.connect(_on_voice_volume_changed)
	trigger_volume_slider.value_changed.connect(_on_trigger_volume_changed)
	
	# 更新切换按钮文本
	_update_toggle_button_text()
	
	# 设置后台模式 CheckButton 的初始状态
	background_mode_toggle.button_pressed = is_background_mode_enabled
	
	# 初始化状态栏显示状态（根据配置）
	if is_status_bar_expanded:
		status_bar.offset_bottom = 200.0
		status_display.modulate.a = 1.0
		status_display.visible = true
		status_toggle.text = "▲"
	else:
		status_bar.offset_bottom = 50.0
		status_display.modulate.a = 0.0
		status_display.visible = false
		status_toggle.text = "▼"
	
	# 应用后台模式设置
	_apply_background_mode()
	
	print("助眠模式已启动")
	
	# 执行淡入动画（使用全局过渡管理器）
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.fade_in()

func _load_config():
	"""加载配置文件"""
	var bg_volume = -5.0
	var voice_volume = -10.0
	var trigger_volume = -5.0
	
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			var parse_result = json.parse(json_string)
			
			if parse_result == OK:
				var data = json.data
				if data.has("is_dynamic_background"):
					is_dynamic_background = data["is_dynamic_background"]
					print("已加载背景配置: ", "动态" if is_dynamic_background else "静态")
				if data.has("is_background_mode_enabled"):
					is_background_mode_enabled = data["is_background_mode_enabled"]
					print("已加载后台模式配置: ", "开启" if is_background_mode_enabled else "关闭")
				if data.has("is_status_bar_expanded"):
					is_status_bar_expanded = data["is_status_bar_expanded"]
					print("已加载状态栏配置: ", "展开" if is_status_bar_expanded else "收起")
				if data.has("bg_volume"):
					bg_volume = data["bg_volume"]
				if data.has("voice_volume"):
					voice_volume = data["voice_volume"]
				if data.has("trigger_volume"):
					trigger_volume = data["trigger_volume"]
			else:
				push_error("解析配置文件失败")
	else:
		print("配置文件不存在，使用默认设置")
	
	# 设置滑杆初始值
	if bg_volume_slider:
		bg_volume_slider.value = bg_volume
	if voice_volume_slider:
		voice_volume_slider.value = voice_volume
	if trigger_volume_slider:
		trigger_volume_slider.value = trigger_volume

func _save_config():
	"""保存配置文件"""
	var data = {
		"is_dynamic_background": is_dynamic_background,
		"is_background_mode_enabled": is_background_mode_enabled,
		"is_status_bar_expanded": is_status_bar_expanded,
		"bg_volume": bg_volume_slider.value,
		"voice_volume": voice_volume_slider.value,
		"trigger_volume": trigger_volume_slider.value
	}
	
	var json_string = JSON.stringify(data, "\t")
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	
	if file:
		file.store_string(json_string)
		file.close()
		print("配置已保存")
	else:
		push_error("无法保存配置文件")

func _setup_background():
	"""根据配置设置背景"""
	if is_dynamic_background:
		# 动态背景：播放视频
		_setup_video()
		video_player.visible = true
		static_background.visible = false
	else:
		# 静态背景：显示图片
		_setup_static_image()
		video_player.visible = false
		static_background.visible = true

func _setup_video():
	"""设置视频播放"""
	var video_path = "res://assets/images/sleep/background.ogv"
	var video_stream = load(video_path)
	
	if video_stream:
		video_player.stream = video_stream
		video_player.loop = true
		video_player.play()
		print("助眠视频已加载并开始播放")
	else:
		push_error("无法加载背景视频: " + video_path)

func _setup_static_image():
	"""设置静态图片背景"""
	var image_path = "res://assets/images/sleep/background.png"
	var texture = load(image_path)
	
	if texture:
		static_background.texture = texture
		print("静态背景图片已加载")
	else:
		push_error("无法加载背景图片: " + image_path)

func _setup_audio_controller():
	"""设置音频控制器"""
	# 加载音频控制器脚本
	var AudioControllerScript = load("res://scripts/sleep/audio_controller.gd")
	audio_controller = AudioControllerScript.new()
	add_child(audio_controller)
	
	# 初始化音频控制器
	await audio_controller.initialize(background_player, left_visualizer, right_visualizer)
	
	# 根据当前天气获取氛围音路径
	var audio_path = _get_ambient_audio_path()
	
	# 如果有氛围音，加载并播放
	if not audio_path.is_empty():
		await audio_controller.load_and_play_audio(audio_path)
	
	# 应用保存的音量设置
	audio_controller.set_volume(bg_volume_slider.value)

func _setup_asmr_components():
	"""设置ASMR组件"""
	# 创建TTS管理器
	var TTSManagerScript = load("res://scripts/sleep/asmr_tts_manager.gd")
	asmr_tts_manager = TTSManagerScript.new()
	add_child(asmr_tts_manager)
	
	# 创建工具管理器
	var ToolManagerScript = load("res://scripts/sleep/asmr_tool_manager.gd")
	asmr_tool_manager = ToolManagerScript.new()
	add_child(asmr_tool_manager)
	asmr_tool_manager.initialize(trigger_player)
	
	# 创建主流程控制器
	var MainFlowScript = load("res://scripts/sleep/asmr_main_flow.gd")
	asmr_main_flow = MainFlowScript.new()
	add_child(asmr_main_flow)
	asmr_main_flow.initialize(asmr_tts_manager, asmr_tool_manager)
	
	# 连接ASMR主流程信号
	asmr_main_flow.status_updated.connect(_on_ai_status_updated)
	asmr_main_flow.error_occurred.connect(_on_ai_error)
	asmr_main_flow.user_message_display.connect(_on_user_message_display)
	asmr_main_flow.input_state_changed.connect(_on_input_state_changed)
	asmr_main_flow.ai_reply_started.connect(_on_ai_reply_started)
	
	# 连接工具管理器信号
	asmr_tool_manager.tool_started.connect(_on_tool_started)
	asmr_tool_manager.tool_completed.connect(_on_tool_completed)
	
	# 应用音量设置
	asmr_tts_manager.set_voice_volume(voice_volume_slider.value)
	asmr_tool_manager.set_volume(trigger_volume_slider.value)

func _on_bg_volume_changed(value: float):
	"""背景音音量滑杆变化"""
	if background_player:
		background_player.volume_db = value
	_save_config()

func _on_voice_volume_changed(value: float):
	"""语音音量滑杆变化"""
	if voice_player:
		voice_player.volume_db = value
	if asmr_tts_manager:
		asmr_tts_manager.set_voice_volume(value)
	_save_config()

func _on_trigger_volume_changed(value: float):
	"""触发音音量滑杆变化"""
	if trigger_player:
		trigger_player.volume_db = value
	if asmr_tool_manager:
		asmr_tool_manager.set_volume(value)
	_save_config()

func _on_background_toggle_pressed():
	"""切换背景模式"""
	is_dynamic_background = !is_dynamic_background
	_setup_background()
	_update_toggle_button_text()
	_save_config()

func _update_toggle_button_text():
	"""更新切换按钮文本"""
	background_toggle.text = "动态" if is_dynamic_background else "静态"

func _on_background_mode_toggled(button_pressed: bool):
	"""后台模式 CheckButton 切换"""
	is_background_mode_enabled = button_pressed
	_apply_background_mode()
	_save_config()

func _apply_background_mode():
	"""应用后台模式设置
	
	在 Android 上实现熄屏播放的两种方案：
	
	方案1（推荐）：使用 Java 插件 + 前台服务
	- 显示通知栏图标
	- 使用 Partial WakeLock
	- 符合 Android 规范，可靠性高
	
	方案2（简化）：仅使用 low_processor_usage_mode
	- 不需要构建插件
	- 可靠性较低，可能被系统杀死
	- 不符合 Android 最佳实践
	"""
	if OS.get_name() == "Android":
		if is_background_mode_enabled:
			# 方案1：使用插件（如果可用）
			if background_audio_plugin:
				var character_name = get_node("/root/SaveManager").get_character_name()
				background_audio_plugin.start_background_mode(
					"助眠模式",
					character_name + " 正在陪伴你入睡"
				)
				print("后台模式已开启（使用前台服务）")
			else:
				# 方案2：简化方案（fallback）
				OS.low_processor_usage_mode = false
				print("后台模式已开启（简化方案，可靠性较低）")
				print("提示：安装 BackgroundAudioPlugin 可获得更好的后台播放体验")
		else:
			# 关闭后台模式
			if background_audio_plugin:
				background_audio_plugin.stop_background_mode()
				print("后台模式已关闭（前台服务）")
			else:
				OS.low_processor_usage_mode = true
				print("后台模式已关闭")

func _on_exit_button_pressed():
	"""退出助眠模式 - 显示确认对话框"""
	_show_exit_confirmation()

func _show_exit_confirmation():
	"""显示退出确认对话框"""
	# 清理旧对话框
	if exit_confirmation_dialog:
		exit_confirmation_dialog.queue_free()
	
	# 创建确认对话框
	exit_confirmation_dialog = ConfirmationDialog.new()
	exit_confirmation_dialog.title = "退出助眠模式"
	exit_confirmation_dialog.dialog_text = "确定要退出助眠模式吗？"
	exit_confirmation_dialog.ok_button_text = "确定"
	exit_confirmation_dialog.cancel_button_text = "取消"
	
	# 连接信号
	exit_confirmation_dialog.confirmed.connect(_on_exit_confirmed)
	
	# 添加到场景并显示
	add_child(exit_confirmation_dialog)
	exit_confirmation_dialog.popup_centered()

func _on_exit_confirmed():
	"""确认退出助眠模式"""
	print("退出助眠模式")
	
	# 关闭后台模式
	if is_background_mode_enabled and OS.get_name() == "Android":
		if background_audio_plugin:
			background_audio_plugin.stop_background_mode()
		else:
			OS.low_processor_usage_mode = true
		print("已关闭后台播放模式")
	
	# 停止视频播放
	if video_player:
		video_player.stop()
	
	# 清理音频控制器
	if audio_controller:
		audio_controller.cleanup()
		audio_controller.queue_free()
		audio_controller = null
	
	# 清理ASMR组件
	if asmr_main_flow:
		asmr_main_flow.cleanup()
		asmr_main_flow.queue_free()
		asmr_main_flow = null
	
	if asmr_tts_manager:
		asmr_tts_manager.clear_all()
		asmr_tts_manager.queue_free()
		asmr_tts_manager = null
	
	if asmr_tool_manager:
		asmr_tool_manager.cleanup()
		asmr_tool_manager.queue_free()
		asmr_tool_manager = null
	
	# 开始过渡淡出效果
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		# 先淡出到黑屏
		await transition.fade_out()
		
		# 在黑屏期间保存记忆
		await _save_sleep_memory()
		
		# 切换场景（change_scene_with_fade 会自动处理淡入）
		await transition.change_scene_with_fade("res://scripts/main.tscn")
	else:
		# 没有过渡效果时，直接保存并切换
		await _save_sleep_memory()
		get_tree().change_scene_to_file("res://scripts/main.tscn")

func _on_status_toggle_pressed():
	"""切换状态栏显示/隐藏"""
	is_status_bar_expanded = !is_status_bar_expanded
	
	# 禁用按钮防止重复点击
	status_toggle.disabled = true
	
	# 创建动画
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	if is_status_bar_expanded:
		# 展开状态栏
		status_toggle.text = "▲"
		status_display.visible = true
		status_display.modulate.a = 0.0
		# 同时动画StatusBar的offset_bottom和StatusDisplay的透明度
		tween.tween_property(status_bar, "offset_bottom", 200.0, 0.2)
		tween.parallel().tween_property(status_display, "modulate:a", 1.0, 0.15).set_delay(0.05)
	else:
		# 收起状态栏
		status_toggle.text = "▼"
		tween.tween_property(status_display, "modulate:a", 0.0, 0.12)
		tween.parallel().tween_property(status_bar, "offset_bottom", 50.0, 0.2)
	
	# 动画完成后的处理
	tween.finished.connect(func(): 
		if not is_status_bar_expanded:
			status_display.visible = false
		status_toggle.disabled = false
	)
	
	# 保存状态栏状态
	_save_config()

func _on_send_button_pressed():
	"""发送按钮点击"""
	_send_message()

func _on_input_submitted(_text: String):
	"""输入框回车"""
	_send_message()

func _on_continuous_toggle_changed(button_pressed: bool):
	"""连续模式开关切换"""
	if asmr_main_flow:
		asmr_main_flow.set_continuous_mode(button_pressed)

func _process(_delta):
	"""每帧检查连续模式状态，同步UI"""
	if asmr_main_flow and continuous_toggle:
		# 如果主流程的连续模式被关闭，同步UI
		if not asmr_main_flow.is_continuous_mode and continuous_toggle.button_pressed:
			continuous_toggle.button_pressed = false

func _send_message():
	"""发送消息给AI"""
	var message = input_field.text.strip_edges()
	if message.is_empty():
		return
	
	# 重置当前AI回复状态
	current_ai_reply = ""
	
	# 清空输入框
	input_field.text = ""
	
	# 发送给ASMR主流程（会自动关闭连续模式并清空计数）
	if asmr_main_flow:
		asmr_main_flow.send_message(message)

func _on_input_state_changed(enabled: bool, placeholder: String):
	"""输入框状态变化"""
	is_input_enabled = enabled
	input_field.editable = enabled
	send_button.disabled = not enabled
	input_field.placeholder_text = placeholder

var current_ai_reply: String = ""  # 用于跟踪当前AI回复

func _on_ai_status_updated(status: String):
	"""AI状态更新 - 流式输出增量文本"""
	# 过滤掉空内容
	if status.strip_edges().is_empty():
		return
	
	# 获取角色名
	var save_mgr = get_node("/root/SaveManager")
	var character_name = save_mgr.get_character_name()
	
	# 保存当前滚动位置
	var scroll_pos = status_display.scroll_vertical
	
	# 检查是否是新的AI回复开始
	if current_ai_reply.is_empty():
		# 新回复开始，添加换行和角色名前缀
		status_display.text += "\n" + character_name + ": "
	
	# 追加增量文本
	status_display.text += status
	current_ai_reply += status
	
	# 立即恢复滚动位置（防止跳到开头）
	status_display.scroll_vertical = scroll_pos
	
	# 然后在下一帧检查是否需要滚动到底部
	call_deferred("_smart_scroll_to_bottom")

func _on_tool_started(_tool_name: String, display_name: String):
	"""工具开始执行"""
	_append_to_status("\n[动作]: " + display_name)

func _on_tool_completed(_tool_name: String, feedback: String):
	"""工具执行完成"""
	current_ai_reply = ""
	_append_to_status("\n[完成] " + feedback)
	
	# 通知主流程：状态栏更新已完成
	if asmr_main_flow:
		asmr_main_flow._on_status_display_updated()

func _on_ai_error(error: String):
	"""AI错误"""
	current_ai_reply = ""
	_append_to_status("\n[错误] " + error)

func _on_user_message_display(message: String):
	"""显示用户消息（不触发AI回复逻辑）"""
	_append_to_status(message)

func _on_ai_reply_started():
	"""AI开始新回复时重置状态"""
	current_ai_reply = ""
	print("AI回复状态已重置")

func _append_to_status(text: String):
	"""追加文本到状态显示框"""
	# 保存当前滚动位置
	var scroll_pos = status_display.scroll_vertical
	
	# 添加文本
	status_display.text += text
	
	# 立即恢复滚动位置（防止跳到开头）
	status_display.scroll_vertical = scroll_pos
	
	# 然后在下一帧检查是否需要滚动到底部
	call_deferred("_smart_scroll_to_bottom")

func _smart_scroll_to_bottom():
	"""智能滚动到底部 - 只在用户已经在底部时才滚动"""
	if not status_display or not status_display.get_v_scroll_bar():
		return
	
	var v_scroll = status_display.get_v_scroll_bar()
	var max_scroll = v_scroll.max_value
	var current_scroll = status_display.scroll_vertical
	var viewport_height = v_scroll.page
	
	# 如果用户在底部附近（容差30像素），则滚动到底部
	if max_scroll - current_scroll <= viewport_height + 30:
		status_display.scroll_vertical = int(max_scroll)

func _get_ambient_audio_path() -> String:
	"""根据当前天气获取氛围音路径（参考audio_manager.gd的逻辑）"""
	# 获取当前天气
	var save_mgr = get_node("/root/SaveManager")
	var weather_id = save_mgr.get_current_weather()
	
	# 根据天气返回氛围音路径
	if weather_id in ["rainy", "storm"]:
		return "res://assets/audio/rain.mp3"
	elif weather_id in ["snowy"]:
		return "res://assets/audio/snow.mp3"
	
	# 默认返回空字符串（无氛围音）
	return ""

# 记录进入助眠模式的时间
var sleep_start_time: float = 0.0

func _enter_tree():
	"""进入场景树时记录开始时间"""
	sleep_start_time = Time.get_unix_time_from_system()

func _save_sleep_memory():
	"""保存助眠模式记忆"""
	var memory_saver = get_node_or_null("/root/UnifiedMemorySaver")
	if not memory_saver:
		return
	
	# 计算总时长（分钟）
	var current_time = Time.get_unix_time_from_system()
	var duration_seconds = current_time - sleep_start_time
	var duration_minutes = int(round(duration_seconds / 60.0))
	
	# 获取状态栏显示的历史记录（直接使用显示文本）
	var display_history = status_display.text if status_display else ""
	
	# 检查是否有聊天记录（排除空白和纯换行）
	var has_chat_history = not display_history.strip_edges().is_empty()
	
	# 如果没有历史记录且时长小于3分钟，不保存记忆
	if not has_chat_history and duration_minutes < 3:
		print("助眠时长不足3分钟且无聊天记录，跳过记忆保存")
		return
	# 获取用户名和角色名
	var save_mgr = get_node("/root/SaveManager")
	var user_name = save_mgr.get_user_name() if save_mgr else "玩家"
	
	# 构建前缀（包含总时长）
	var prefix = "我陪伴%s进行了%d分钟的助眠。" % [user_name, duration_minutes]
	
	# 如果有聊天记录，调用AI总结
	var summary_content = ""
	if has_chat_history:
		# 获取角色名
		var character_name = save_mgr.get_character_name()
		
		# 调用助眠聊天总结管理器进行总结
		var summary_manager_script = load("res://scripts/sleep/sleep_summary.gd")
		var summary_manager = summary_manager_script.new()
		add_child(summary_manager)
		summary_manager.setup()
		
		# 直接传递display_history作为用户提示词
		var ai_summary = await summary_manager.call_sleep_summary_api(display_history, character_name)
		
		if not ai_summary.is_empty():
			summary_content = ai_summary.strip_edges()
		
		# 清理总结管理器
		summary_manager.queue_free()
	
	# 组合最终记忆内容
	var memory_content = prefix + summary_content
	
	# 构建元数据
	var meta = {
		"type": "sleep",
		"duration_minutes": duration_minutes,
		"display_history": display_history
	}
	
	# 保存记忆
	print("保存助眠记忆: ", memory_content)
	await memory_saver.save_memory(memory_content, memory_saver.MemoryType.SLEEP, null, "", meta)
	print("助眠记忆保存完成")
