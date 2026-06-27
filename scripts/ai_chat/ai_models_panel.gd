extends MarginContainer

# 模型列表面板
# 显示所有模型，支持新建、编辑、删除

signal models_changed

@onready var add_button = $VBoxContainer/TopBar/AddButton
@onready var models_container = $VBoxContainer/ScrollContainer/ModelsContainer
@onready var status_label = $VBoxContainer/StatusLabel

var config_manager: Node
var dialog_scene = preload("res://scenes/ai_model_dialog.tscn")

func _ready():
	add_button.pressed.connect(_on_add_pressed)

func initialize(cfg_mgr: Node):
	"""初始化面板"""
	config_manager = cfg_mgr
	_refresh_list()

func refresh():
	"""外部调用刷新"""
	_refresh_list()

func _refresh_list():
	"""刷新模型列表"""
	# 清空现有内容
	for child in models_container.get_children():
		child.queue_free()
	
	var models = config_manager.get_all_models()
	
	for model_name in models.keys():
		var model_data = models[model_name]
		var item = _create_model_item(model_name, model_data)
		models_container.add_child(item)

func _create_model_item(model_name: String, model_data: Dictionary) -> PanelContainer:
	"""创建单个模型项"""
	var item = PanelContainer.new()
	item.custom_minimum_size = Vector2(0, 80)
	
	# 添加样式
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.5)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.4, 0.5, 0.6)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_right = 5
	style.corner_radius_bottom_left = 5
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	item.add_theme_stylebox_override("panel", style)
	
	var hbox = HBoxContainer.new()
	item.add_child(hbox)
	item.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# 模型信息
	var vbox_info = VBoxContainer.new()
	vbox_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox_info)
	
	var name_label = Label.new()
	name_label.text = model_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.clip_text = true
	vbox_info.add_child(name_label)
	
	var provider_label = Label.new()
	provider_label.text = "提供商: " + model_data.get("provider", "未知")
	provider_label.add_theme_font_size_override("font_size", 14)
	provider_label.clip_text = true
	provider_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox_info.add_child(provider_label)
	
	var identifier_label = Label.new()
	identifier_label.text = "标识符: " + model_data.get("identifier", "")
	identifier_label.add_theme_font_size_override("font_size", 14)
	identifier_label.clip_text = true
	identifier_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox_info.add_child(identifier_label)
	
	# 按钮容器
	var btn_container = HBoxContainer.new()
	hbox.add_child(btn_container)
	
	# 编辑按钮
	var edit_button = Button.new()
	edit_button.text = "编辑"
	edit_button.pressed.connect(_on_edit_pressed.bind(model_name, model_data))
	btn_container.add_child(edit_button)
	
	# 删除按钮
	var delete_button = Button.new()
	delete_button.text = "删除"
	delete_button.pressed.connect(_on_delete_pressed.bind(model_name))
	btn_container.add_child(delete_button)
	
	return item

func _on_add_pressed():
	"""新建模型"""
	var dialog = dialog_scene.instantiate()
	add_child(dialog)
	dialog.setup_for_create(config_manager.get_all_providers(), config_manager.get_all_models())
	dialog.model_saved.connect(_on_model_saved)
	dialog.cancelled.connect(_on_dialog_cancelled)

func _on_edit_pressed(model_name: String, model_data: Dictionary):
	"""编辑模型"""
	var dialog = dialog_scene.instantiate()
	add_child(dialog)
	dialog.setup_for_edit(model_name, model_data, config_manager.get_all_providers(), config_manager.get_all_models())
	dialog.model_saved.connect(_on_model_saved.bind(model_name))
	dialog.cancelled.connect(_on_dialog_cancelled)

func _on_delete_pressed(model_name: String):
	"""删除模型"""
	# 检查是否有任务使用此模型
	var tasks = config_manager.get_model_tasks()
	for task_id in tasks.keys():
		if tasks[task_id].get("model", "") == model_name:
			_show_status("无法删除：有任务正在使用此模型", false)
			return
	
	if config_manager.delete_model(model_name):
		_show_status("模型已删除", true)
		_refresh_list()
		models_changed.emit()
	else:
		_show_status("删除失败", false)

func _on_model_saved(model_name: String, model_data: Dictionary, old_name: String = ""):
	"""保存模型"""
	# 如果是编辑模式，先删除旧的
	if not old_name.is_empty() and old_name != model_name:
		config_manager.delete_model(old_name)
	
	if config_manager.save_model(model_name, model_data):
		_show_status("模型已保存", true)
		_refresh_list()
		models_changed.emit()
	else:
		_show_status("保存失败", false)

func _on_dialog_cancelled():
	"""对话框取消"""
	pass

func _show_status(message: String, success: bool):
	status_label.text = message
	status_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3) if success else Color(1.0, 0.3, 0.3))