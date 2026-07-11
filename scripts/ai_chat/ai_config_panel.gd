extends Panel

# AI 配置面板 - 支持快速配置和详细配置
# 该文件作为主控制器，整合各个功能模块

@onready var close_button = $MarginContainer/VBoxContainer/TitleContainer/CloseButton
@onready var tab_container = $MarginContainer/VBoxContainer/TabContainer
@onready var memory_config = $MarginContainer/VBoxContainer/TabContainer/记忆系统
# 快速配置引用
@onready var quick_template_free = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/TemplateContainer/FreeButton
@onready var quick_template_standard = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/TemplateContainer/StandardButton
@onready var quick_template_alternate = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/TemplateContainer/AlternateButton
@onready var quick_template_custom = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/TemplateContainer/CustomButton
@onready var quick_description_label = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/DescriptionLabel
@onready var custom_buttons_container = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/CustomButtonsContainer
@onready var edit_template_button = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/CustomButtonsContainer/EditTemplateButton
@onready var copy_template_button = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/CustomButtonsContainer/CopyTemplateButton
@onready var paste_template_button = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/CustomButtonsContainer/PasteTemplateButton
@onready var template_text_edit_container = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/TemplateTextEditContainer
@onready var template_text_edit = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/TemplateTextEditContainer/TemplateTextEdit
@onready var hint_label = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/HintLabel
@onready var quick_key_input = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/KeyInput
@onready var use_builtin_key_checkbox = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/UseBuiltinKeyContainer/UseBuiltinKeyCheckBox
@onready var quick_apply_button = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/ApplyButton
@onready var quick_status_label = $MarginContainer/VBoxContainer/TabContainer/快速配置/ScrollContainer/VBoxContainer/StatusLabel
# 详细配置引用（二级选项卡）
@onready var providers_panel = $MarginContainer/VBoxContainer/TabContainer/详细配置/DetailTabs/模型厂商
@onready var models_panel = $MarginContainer/VBoxContainer/TabContainer/详细配置/DetailTabs/模型列表
@onready var model_tasks_panel = $MarginContainer/VBoxContainer/TabContainer/详细配置/DetailTabs/模型任务
# 日志导出引用
@onready var log_export_button = $MarginContainer/VBoxContainer/TabContainer/日志导出/VBoxContainer/ExportButton
@onready var log_status_label = $MarginContainer/VBoxContainer/TabContainer/日志导出/VBoxContainer/StatusLabel
# 修复记忆引用
@onready var repair_check_button = $MarginContainer/VBoxContainer/TabContainer/修复记忆/ScrollContainer/VBoxContainer/CheckButton
@onready var repair_check_status_label = $MarginContainer/VBoxContainer/TabContainer/修复记忆/ScrollContainer/VBoxContainer/CheckStatusLabel
@onready var repair_button = $MarginContainer/VBoxContainer/TabContainer/修复记忆/ScrollContainer/VBoxContainer/RepairButton
@onready var repair_progress_label = $MarginContainer/VBoxContainer/TabContainer/修复记忆/ScrollContainer/VBoxContainer/ProgressLabel
@onready var repair_progress_bar = $MarginContainer/VBoxContainer/TabContainer/修复记忆/ScrollContainer/VBoxContainer/ProgressBar
@onready var repair_log_label = $MarginContainer/VBoxContainer/TabContainer/修复记忆/ScrollContainer/VBoxContainer/LogScrollContainer/LogLabel
@onready var voice_panel = $MarginContainer/VBoxContainer/TabContainer/语音设置
@onready var response_settings = $MarginContainer/VBoxContainer/TabContainer/聊天设置
# 各功能模块

var config_manager: Node
var template_handler: Node
var voice_settings: Node
var log_exporter: Node
var memory_repair: Node

func _ready():
	# 初始化配置管理器
	config_manager = Node.new()
	config_manager.script = load("res://scripts/ai_chat/ai_config_manager.gd")
	add_child(config_manager)
	
	# 初始化模板处理器
	template_handler = load("res://scripts/ai_chat/ai_template_handler.gd").new(config_manager)
	template_handler.quick_template_free = quick_template_free
	template_handler.quick_template_standard = quick_template_standard
	template_handler.quick_template_alternate = quick_template_alternate
	template_handler.quick_template_custom = quick_template_custom
	template_handler.quick_description_label = quick_description_label
	template_handler.custom_buttons_container = custom_buttons_container
	template_handler.template_text_edit_container = template_text_edit_container
	template_handler.template_text_edit = template_text_edit
	template_handler.hint_label = hint_label
	add_child(template_handler)
	
	# 初始化日志导出器
	log_exporter = Node.new()
	log_exporter.script = load("res://scripts/ai_chat/ai_log_exporter.gd")
	log_exporter.log_status_label = log_status_label
	log_exporter.log_export_button = log_export_button
	add_child(log_exporter)
	
	
	# 初始化记忆修复模块
	memory_repair = Node.new()
	memory_repair.script = load("res://scripts/ai_chat/ai_memory_repair.gd")
	memory_repair.repair_check_button = repair_check_button
	memory_repair.repair_check_status_label = repair_check_status_label
	memory_repair.repair_button = repair_button
	memory_repair.repair_progress_label = repair_progress_label
	memory_repair.repair_progress_bar = repair_progress_bar
	memory_repair.repair_log_label = repair_log_label
	memory_repair.close_button = close_button
	add_child(memory_repair)
	memory_repair.init_repair_tool()
	
	# 设置回复设置的config_manager
	response_settings.set_config_manager(config_manager)

	# 初始化记忆系统配置
	memory_config.initialize(config_manager)
	
	# 初始化新的配置面板
	providers_panel.initialize(config_manager)
	models_panel.initialize(config_manager)
	model_tasks_panel.initialize(config_manager)
	
	# 级联刷新：厂商变更 -> 刷新模型列表，模型变更 -> 刷新任务列表
	providers_panel.providers_changed.connect(models_panel.refresh)
	models_panel.models_changed.connect(model_tasks_panel._build_task_list)
	
	# 配置变更时重新加载AI服务
	providers_panel.config_changed.connect(_reload_ai_service)
	models_panel.config_changed.connect(_reload_ai_service)
	model_tasks_panel.config_changed.connect(_reload_ai_service)
	
	# 连接信号
	close_button.pressed.connect(_on_close_pressed)
	quick_template_free.pressed.connect(_on_template_selected.bind("free"))
	quick_template_standard.pressed.connect(_on_template_selected.bind("standard"))
	quick_template_alternate.pressed.connect(_on_template_selected.bind("alternate"))
	quick_template_custom.pressed.connect(_on_template_selected.bind("custom"))
	edit_template_button.pressed.connect(_on_edit_template_pressed)
	copy_template_button.pressed.connect(_on_copy_template_pressed)
	paste_template_button.pressed.connect(_on_paste_template_pressed)
	template_text_edit.text_changed.connect(_on_template_text_changed)
	use_builtin_key_checkbox.toggled.connect(_on_use_builtin_key_toggled)
	quick_apply_button.pressed.connect(_on_quick_apply_pressed)
	log_export_button.pressed.connect(log_exporter.on_log_export_pressed)
	repair_check_button.pressed.connect(memory_repair.on_repair_check_pressed)
	repair_button.pressed.connect(memory_repair.on_repair_start_pressed)
	
	# 应用样式
	template_handler.style_template_buttons()

	# 加载现有配置
	_load_builtin_key_setting()  # 先加载内置密钥设置
	_load_existing_config()
	template_handler.load_selected_template()
	voice_panel._load_settings()
	response_settings.load_response_settings()
	_apply_android_input_workaround()

func _on_close_pressed():
	"""关闭面板"""
	queue_free()

func _apply_android_input_workaround():
	if has_node("/root/PlatformManager"):
		var pm = get_node("/root/PlatformManager")
		if pm.is_android():
			var inputs: Array = [
				quick_key_input
			]
			for le in inputs:
				if le and le is LineEdit:
					le.context_menu_enabled = false
					le.shortcut_keys_enabled = false
					if le.has_method("set_selecting_enabled"):
						le.selecting_enabled = false

func _on_template_selected(template: String):
	"""选择配置模板"""
	template_handler.select_template(template)

func _on_edit_template_pressed():
	"""编辑模板"""
	template_handler.edit_template()

func _on_copy_template_pressed():
	"""复制当前配置为模板"""
	template_handler.copy_current_config_as_template()
	_update_quick_status(true, "已将当前配置复制为模板并保存到剪贴板")

func _on_paste_template_pressed():
	"""粘贴模板按钮点击"""
	# 创建确认对话框
	var dialog = AcceptDialog.new()
	dialog.title = "粘贴模板"
	dialog.dialog_text = "将粘贴剪切板的内容？"
	dialog.ok_button_text = "粘贴"
	
	# 添加取消按钮
	dialog.add_button("取消", false, "取消")
	
	dialog.confirmed.connect(func():
		# 用户确认粘贴
		if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			var clipboard_content = DisplayServer.clipboard_get()
			if not clipboard_content.is_empty():
				template_text_edit.text = clipboard_content
				template_text_edit_container.visible = true
				template_handler.custom_template_json = clipboard_content
				template_handler.save_custom_template()
				_update_quick_status(true, "已粘贴模板到编辑器")
			else:
				_update_quick_status(false, "剪切板为空")
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	
	add_child(dialog)
	dialog.popup_centered()

func _on_template_text_changed():
	"""模板文本改变时保存"""
	template_handler.save_custom_template()

func _on_quick_apply_pressed():
	"""应用快速配置模板"""
	var api_key = quick_key_input.text.strip_edges()
	
	# 如果启用了内置密钥且输入框为空，使用占位符
	if use_builtin_key_checkbox.button_pressed and api_key.is_empty():
		api_key = "sk-ahaucanseeitbutthisisaplaceholderapikeyforcabmed"
		# 更新输入框显示占位符
		quick_key_input.text = api_key
	
	# 保存当前的内置密钥启用状态
	var use_builtin_key = use_builtin_key_checkbox.button_pressed
	
	var result = template_handler.apply_quick_config(api_key)
	if result.success:
		# 恢复内置密钥设置（防止被覆盖）
		config_manager.save_use_builtin_key(use_builtin_key)
		
		_update_quick_status(true, result.message)
		_reload_ai_service()
		_reload_tts_service()
		voice_panel._load_settings()
		# 刷新所有配置面板
		providers_panel.refresh()
		models_panel.refresh()
		model_tasks_panel._build_task_list()
	elif result.has("conflicts"):
		# 有冲突，询问用户是否覆盖
		_show_conflict_dialog(result)
	else:
		_update_quick_status(false, result.message)

func _show_conflict_dialog(result: Dictionary):
	"""显示冲突确认对话框"""
	var conflict_message = "有重名且内容不一样的厂商/模型：\n"
	
	if not result.conflicts.providers.is_empty():
		conflict_message += "\n厂商：\n"
		for n in result.conflicts.providers:
			conflict_message += "- " + n + "\n"
	
	if not result.conflicts.models.is_empty():
		conflict_message += "\n模型：\n"
		for n in result.conflicts.models:
			conflict_message += "- " + n + "\n"
	
	conflict_message += "\n是否要覆盖这些项？"
	
	# 创建确认对话框
	var dialog = AcceptDialog.new()
	dialog.title = "确认覆盖"
	dialog.dialog_text = conflict_message
	dialog.ok_button_text = "覆盖"
	dialog.cancel_button_text = "取消"
	
	# 获取保存的密钥
	var quick_config_key = result.get("api_key", "")
	
	# 添加取消按钮
	dialog.add_button("取消", false, "取消")
	
	dialog.confirmed.connect(func():
		# 用户确认覆盖
		var force_result = config_manager.force_import_template(result.template, quick_config_key)
		if force_result.success:
			config_manager.save_use_builtin_key(use_builtin_key_checkbox.button_pressed)
			# 保存模板和密钥到配置
			var config = config_manager.load_config()
			config["template"] = "custom"
			if result.has("custom_template_json"):
				config["custom_template_json"] = result.custom_template_json
			config["api_key"] = quick_config_key
			config_manager.save_config(config)
			
			_update_quick_status(true, force_result.message)
			_reload_ai_service()
			_reload_tts_service()
			voice_panel._load_settings()
			# 刷新所有配置面板
			providers_panel.refresh()
			models_panel.refresh()
			model_tasks_panel._build_task_list()
		else:
			_update_quick_status(false, force_result.message)
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	
	add_child(dialog)
	dialog.popup_centered()

func _load_existing_config():
	"""加载现有的AI配置"""
	var config = config_manager.load_config()
	
	if config.is_empty():
		return
	
	# 加载API密钥到快速配置
	if config.has("api_key"):
		quick_key_input.text = config.api_key
		_update_quick_status(true, "当前密钥: " + config_manager.mask_key(config.api_key))
	
	# 重新加载内置密钥设置，确保状态同步
	_load_builtin_key_setting()

func _reload_ai_service():
	"""重新加载AI服务"""
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		ai_service.reload_config()
		print("AI服务已重新加载配置")

func _reload_tts_service():
	"""重新加载TTS服务"""
	if has_node("/root/TTSService"):
		var tts_service = get_node("/root/TTSService")
		tts_service.reload_settings()
		print("TTS服务已重新加载配置")

func _update_quick_status(success: bool, message: String):
	"""更新快速配置状态"""
	quick_status_label.text = ("✓ " if success else "✗ ") + message
	quick_status_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3) if success else Color(1.0, 0.3, 0.3))

# 别折腾了，给我交点PR随便你用
func _load_builtin_key_setting():
	"""加载使用内置密钥的设置"""
	if config_manager and config_manager.has_method("load_use_builtin_key"):
		var use_builtin = config_manager.load_use_builtin_key()
		use_builtin_key_checkbox.button_pressed = use_builtin
		_update_key_input_state(use_builtin)

func _on_use_builtin_key_toggled(toggled: bool):
	"""处理使用内置密钥勾选框的切换"""
	if config_manager and config_manager.has_method("save_use_builtin_key"):
		config_manager.save_use_builtin_key(toggled)
	_update_key_input_state(toggled)
	_reload_ai_service()

func _update_key_input_state(use_builtin: bool):
	"""更新密钥输入框的启用/禁用状态"""
	quick_key_input.editable = not use_builtin
	if use_builtin:
		quick_key_input.placeholder_text = "点击“应用配置”使用内置密钥（功能受限）"
	else:
		quick_key_input.placeholder_text = "sk-..."
