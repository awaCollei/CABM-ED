extends Control

# 陪伴模式主控制器
# 复用主场景的背景和角色素材，但禁用所有交互

@onready var background: TextureRect = $Background
@onready var character = $Background/Character
@onready var exit_button = $ExitButton
@onready var position_timer = $PositionTimer
@onready var clock_label = $ClockLabel
@onready var clock_timer = $ClockTimer
@onready var settings_button = $SideButtons/SettingsButton
@onready var timer_button = $SideButtons/TimerButton
@onready var notes_button = $SideButtons/NotesButton
@onready var music_player_panel = $MusicPlayerPanel
@onready var audio_manager = $AudioManager
@onready var timer_setup_panel = $TimerSetupPanel
@onready var timer_container = $TimerContainer
@onready var calendar_panel = $CalendarPanel
@onready var notes_list_panel = $NotesListPanel
@onready var note_editor_panel = $NoteEditorPanel

var scene_manager: Node = null
var companion_mode_manager: CompanionModeManager = null
var exit_confirmation_dialog: ConfirmationDialog = null

# 面板状态管理
enum PanelType { NONE, MUSIC, TIMER, CALENDAR, NOTES, NOTE_EDITOR }
var current_open_panel: PanelType = PanelType.NONE

# 计时器管理
var active_timers: Array = []
const MAX_TIMERS = 4
var timer_display_scene = preload("res://scenes/timer_display.tscn")

# 位置变化间隔（秒）
var position_change_interval: float = 300.0  # 5分钟

# 时间更新定时器
var time_update_timer: Timer = null
var current_time_id: String = "day"
var current_weather_id: String = "sunny"

func _ready():
	# 初始化管理器
	_setup_managers()
	
	# 设置角色引用
	character.set_background_reference(background)
	
	# 加载书房场景（陪伴模式固定在书房）
	await _load_studyroom_scene()
	
	# 加载角色
	character.load_character_for_scene("studyroom")
	
	# 初始化音乐播放
	_initialize_audio()
	
	# 启动位置变化定时器
	position_timer.wait_time = position_change_interval
	position_timer.start()
	
	# 启动时间更新定时器（每分钟检查一次）
	time_update_timer = Timer.new()
	time_update_timer.wait_time = 300.0  # 每5分钟检查一次
	time_update_timer.timeout.connect(_on_time_update_timer_timeout)
	add_child(time_update_timer)
	time_update_timer.start()
	
	# 初始化电子钟显示
	_update_clock_display()
	
	# 连接计时器面板信号
	timer_setup_panel.timer_started.connect(_on_timer_started)
	timer_setup_panel.panel_closed.connect(_on_timer_panel_closed)
	
	# 连接日历面板信号
	calendar_panel.panel_closed.connect(_on_calendar_panel_closed)
	
	# 连接笔记面板信号
	notes_list_panel.panel_closed.connect(_on_notes_list_panel_closed)
	notes_list_panel.note_selected.connect(_on_note_selected)
	notes_list_panel.new_note_requested.connect(_on_new_note_requested)
	note_editor_panel.panel_closed.connect(_on_note_editor_panel_closed)
	note_editor_panel.note_saved.connect(_on_note_saved)
	
	print("陪伴模式已启动")
	
	# 执行淡入动画（使用全局过渡管理器或本地遮罩）
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.fade_in()

func _setup_managers():
	"""初始化管理器"""
	# 创建场景管理器（用于加载背景）
	scene_manager = preload("res://scripts/scene_manager.gd").new()
	var save_mgr = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
	scene_manager.initialize(background, character, save_mgr)
	add_child(scene_manager)
	
	# 创建陪伴模式管理器（用于数据管理）
	companion_mode_manager = CompanionModeManager.new()
	add_child(companion_mode_manager)
	
	# 进入陪伴模式
	companion_mode_manager.enter_companion_mode()

func _load_studyroom_scene():
	"""加载书房场景背景"""
	if not scene_manager:
		return
	
	# 获取当前天气和时间（使用正确的方法）
	current_weather_id = "sunny"
	current_time_id = "day"
	
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		# 使用 SaveManager 的方法获取天气
		current_weather_id = save_mgr.get_current_weather()
		if current_weather_id == "":
			current_weather_id = "sunny"
		print("从存档加载天气: ", current_weather_id)
	
	# 获取当前系统时间并转换为时间段
	var time_dict = Time.get_time_dict_from_system()
	var hour = time_dict["hour"]
	current_time_id = _get_time_period_from_hour(hour)
	print("根据系统时间设置时间段: ", current_time_id, " (当前小时: ", hour, ")")
	
	# 加载书房场景
	await scene_manager.load_scene("studyroom", current_weather_id, current_time_id)
	print("书房场景已加载: 天气=%s, 时间=%s" % [current_weather_id, current_time_id])

func _get_time_period_from_hour(hour: int) -> String:
	"""根据小时数获取时间段"""
	# 7:00-16:59 = 白天 (day)
	# 17:00-18:59 = 黄昏 (dusk)
	# 19:00-3:59 = 夜晚 (night)
	# 4:00-6:59 (凌晨) = 黄昏 (dusk)
	if hour >= 4 and hour < 7:
		return "dusk" # 凌晨算作黄昏
	elif hour >= 7 and hour < 17:
		return "day"
	elif hour >= 17 and hour < 19:
		return "dusk"
	else:
		return "night"

func _on_time_update_timer_timeout():
	"""定时检查时间变化，自动更新背景"""
	var time_dict = Time.get_time_dict_from_system()
	var hour = time_dict["hour"]
	var new_time_id = _get_time_period_from_hour(hour)
	
	# 如果时间段发生变化，重新加载场景
	if new_time_id != current_time_id:
		print("陪伴模式：时间段变化 %s -> %s" % [current_time_id, new_time_id])
		current_time_id = new_time_id
		
		# 重新加载场景背景
		if scene_manager:
			await scene_manager.load_scene("studyroom", current_weather_id, current_time_id)
			print("背景已更新为新时间段: ", current_time_id)

func _on_exit_button_pressed():
	"""退出陪伴模式 - 显示确认对话框"""
	_show_exit_confirmation()

func _show_exit_confirmation():
	"""显示退出确认对话框"""
	# 清理旧对话框
	if exit_confirmation_dialog:
		exit_confirmation_dialog.queue_free()
	
	# 创建确认对话框
	exit_confirmation_dialog = ConfirmationDialog.new()
	exit_confirmation_dialog.title = "退出陪伴模式"
	exit_confirmation_dialog.dialog_text = "确定要退出陪伴模式吗？"
	exit_confirmation_dialog.ok_button_text = "确定"
	exit_confirmation_dialog.cancel_button_text = "取消"
	
	# 连接信号
	exit_confirmation_dialog.confirmed.connect(_on_exit_confirmed)
	
	# 添加到场景并显示
	add_child(exit_confirmation_dialog)
	exit_confirmation_dialog.popup_centered()

func _on_exit_confirmed():
	"""确认退出陪伴模式"""
	print("退出陪伴模式")
	
	# 结束陪伴模式会话
	var summary = {}
	if companion_mode_manager:
		summary = companion_mode_manager.exit_companion_mode()
		print("陪伴模式会话总结: ", summary)
	
	# 开始过渡淡出效果
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		# 先淡出到黑屏
		await transition.fade_out()
		
		# 在黑屏期间保存记忆（如果陪伴时间大于3分钟）
		if summary.has("duration") and summary.duration > 180:
			await _save_companion_memory(summary.duration)
		
		# 切换场景（使用 change_scene_with_fade 会自动处理淡入）
		await transition.change_scene_with_fade("res://scripts/main.tscn")
	else:
		# 没有过渡效果时，直接保存并切换
		if summary.has("duration") and summary.duration > 180:
			await _save_companion_memory(summary.duration)
		get_tree().change_scene_to_file("res://scripts/main.tscn")

func _save_companion_memory(duration_seconds: float):
	"""保存陪伴模式记忆"""
	# 获取用户名
	var username = "你"
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		username = save_mgr.get_user_name()
	
	# 计算时长（小时和分钟）
	var hours = int(duration_seconds / 3600)
	var minutes = int((duration_seconds - hours * 3600) / 60)
	
	# 构建记忆内容
	var memory_content = ""
	if hours > 0:
		memory_content = "我在书房陪伴了%s%d小时%d分钟" % [username, hours, minutes]
	else:
		memory_content = "我在书房陪伴了%s%d分钟" % [username, minutes]
	
	# 使用统一记忆保存器保存
	var memory_saver = get_node_or_null("/root/UnifiedMemorySaver")
	if not memory_saver:
		# 如果不存在，创建一个临时实例
		memory_saver = preload("res://scripts/unified_memory_saver.gd").new()
		add_child(memory_saver)
	
	await memory_saver.save_memory(
		memory_content,
		memory_saver.MemoryType.STUDY,
		null,  # 使用当前时间
		"",    # 无对话文本
		{}     # 无额外元数据
	)
	
	print("✓ 陪伴模式记忆已保存: ", memory_content)

func _on_position_timer_timeout():
	"""定时器触发，随机改变角色位置"""
	print("陪伴模式：角色位置变化")
	
	# 先淡出
	var fade_out_tween = create_tween()
	fade_out_tween.tween_property(character, "modulate:a", 0.0, 0.3)
	await fade_out_tween.finished
	
	# 等待一小段时间
	await get_tree().create_timer(0.2).timeout
	
	# 重新加载角色到随机位置（会自动淡入）
	character.load_character_for_scene("studyroom")

func _update_clock_display():
	"""更新电子钟显示"""
	var time_dict = Time.get_time_dict_from_system()
	var hour = time_dict["hour"]
	var minute = time_dict["minute"]
	
	clock_label.text = "%02d:%02d" % [hour, minute]

func _on_clock_timer_timeout():
	"""电子钟定时器触发，每秒更新一次"""
	_update_clock_display()

func _on_settings_button_pressed():
	"""设置按钮点击 - 打开/关闭音乐播放器面板"""
	_toggle_panel(PanelType.MUSIC)

func _on_timer_button_pressed():
	"""计时器按钮点击 - 打开计时器设置面板"""
	if active_timers.size() >= MAX_TIMERS:
		print("已达到最大计时器数量（%d个）" % MAX_TIMERS)
		return
	
	_toggle_panel(PanelType.TIMER)

func _on_calendar_button_pressed():
	"""日历按钮点击 - 打开日历面板"""
	_toggle_panel(PanelType.CALENDAR)

func _on_notes_button_pressed():
	"""笔记按钮点击 - 打开笔记列表"""
	_toggle_panel(PanelType.NOTES)

func _toggle_panel(panel_type: PanelType):
	"""统一的面板切换逻辑"""
	# 如果点击的是当前已打开的面板，关闭它
	if current_open_panel == panel_type:
		_close_current_panel()
		return
	
	# 如果有其他面板打开，先关闭
	if current_open_panel != PanelType.NONE:
		_close_current_panel()
	
	# 打开新面板
	_open_panel(panel_type)

func _open_panel(panel_type: PanelType):
	"""打开指定面板"""
	match panel_type:
		PanelType.MUSIC:
			_open_music_panel()
		PanelType.TIMER:
			timer_setup_panel.show_panel()
		PanelType.CALENDAR:
			calendar_panel.show_panel()
		PanelType.NOTES:
			notes_list_panel.show_panel()
	
	current_open_panel = panel_type

func _close_current_panel():
	"""关闭当前打开的面板"""
	match current_open_panel:
		PanelType.MUSIC:
			_close_music_panel()
		PanelType.TIMER:
			timer_setup_panel.hide()
		PanelType.CALENDAR:
			# 关闭日历面板前，先保存备忘内容
			if calendar_panel.memo_panel.visible:
				calendar_panel.memo_panel.close_and_save()
			calendar_panel.hide()
		PanelType.NOTES:
			notes_list_panel.hide()
		PanelType.NOTE_EDITOR:
			# 保存并关闭笔记编辑器（不返回列表）
			note_editor_panel.save_and_close_without_return()
	
	current_open_panel = PanelType.NONE

func _open_music_panel():
	"""打开音乐播放器面板"""
	# 检查面板是否有 show_panel 方法
	if music_player_panel.has_method("show_panel"):
		music_player_panel.show_panel()
	else:
		# 如果没有该方法，直接显示
		music_player_panel.show()
		# 居中显示
		var viewport_size = get_viewport_rect().size
		music_player_panel.position = (viewport_size - music_player_panel.size) / 2.0
	
	print("音乐播放器面板已打开")

func _close_music_panel():
	"""关闭音乐播放器面板"""
	music_player_panel.hide()
	print("音乐播放器面板已关闭")

func _on_music_panel_closed():
	"""音乐面板关闭回调"""
	if current_open_panel == PanelType.MUSIC:
		current_open_panel = PanelType.NONE

func _initialize_audio():
	"""初始化音频播放"""
	if not audio_manager:
		push_error("❌ AudioManager未找到，无法初始化音频")
		return
	
	# 恢复BGM播放列表（从存档）
	audio_manager.restore_bgm_playlist_sync()
	
	# 播放书房场景的背景音乐和氛围音
	audio_manager.play_background_music("studyroom", current_time_id, current_weather_id)
	
	print("✅ 陪伴模式音频已初始化")

func _on_timer_started(duration: int, timer_name: String):
	"""创建新计时器"""
	if active_timers.size() >= MAX_TIMERS:
		print("已达到最大计时器数量")
		return
	
	# 创建计时器显示
	var timer_display = timer_display_scene.instantiate()
	timer_container.add_child(timer_display)
	
	# 设置计时器
	timer_display.setup(duration, timer_name)
	
	# 连接信号
	timer_display.cancel_requested.connect(_on_timer_cancelled.bind(timer_display))
	
	# 添加到活动列表
	active_timers.append(timer_display)
	
	# 重新排列计时器位置
	_arrange_timers()
	
	# 计时器面板在开始计时后会自动关闭，更新状态
	if current_open_panel == PanelType.TIMER:
		current_open_panel = PanelType.NONE
	
	print("计时器已创建: %s (%d秒)" % [timer_name, duration])

func _on_timer_cancelled(timer_display):
	"""移除计时器"""
	if timer_display in active_timers:
		active_timers.erase(timer_display)
	
	# 重新排列剩余计时器
	_arrange_timers()

func _arrange_timers():
	"""排列计时器位置（单列布局）"""
	var viewport_size = get_viewport_rect().size
	var start_x = viewport_size.x * 0.15  # 左侧15%位置
	var start_y = viewport_size.y * 0.15  # 顶部15%位置
	var spacing_y = 130  # 垂直间距
	
	for i in range(active_timers.size()):
		var timer = active_timers[i]
		timer.position = Vector2(
			start_x,
			start_y + i * spacing_y
		)

func _on_timer_panel_closed():
	"""计时器面板关闭"""
	if current_open_panel == PanelType.TIMER:
		current_open_panel = PanelType.NONE

func _on_calendar_panel_closed():
	"""日历面板关闭"""
	if current_open_panel == PanelType.CALENDAR:
		current_open_panel = PanelType.NONE

func _on_notes_list_panel_closed():
	"""笔记列表面板关闭"""
	if current_open_panel == PanelType.NOTES:
		current_open_panel = PanelType.NONE

func _on_note_selected(note_id: String):
	"""笔记被选中，打开编辑器"""
	print("打开笔记编辑器: ", note_id)
	notes_list_panel.hide()  # 隐藏列表面板
	note_editor_panel.show_panel_for_note(note_id)
	current_open_panel = PanelType.NOTE_EDITOR  # 更新当前面板状态

func _on_new_note_requested():
	"""请求新建笔记"""
	print("新建笔记")
	notes_list_panel.hide()  # 隐藏列表面板
	note_editor_panel.show_panel_for_new_note()
	current_open_panel = PanelType.NOTE_EDITOR  # 更新当前面板状态

func _on_note_editor_panel_closed():
	"""笔记编辑器关闭，返回笔记列表"""
	print("笔记编辑器关闭，返回列表")
	note_editor_panel.hide()  # 确保编辑器隐藏
	notes_list_panel.show_panel()  # 重新显示并刷新列表
	current_open_panel = PanelType.NOTES  # 返回到笔记列表面板

func _on_note_saved(note_id: String):
	"""笔记保存后"""
	print("笔记已保存: ", note_id)
