extends MarginContainer

# 厂商列表面板
# 显示所有厂商，支持新建、编辑、删除

signal providers_changed
signal config_changed  # 配置变更，需要重新加载

@onready var add_button = $VBoxContainer/TopBar/AddButton
@onready var providers_container = $VBoxContainer/ScrollContainer/ProvidersContainer
@onready var status_label = $VBoxContainer/StatusLabel

var config_manager: Node
var dialog_scene = preload("res://scenes/ai_provider_dialog.tscn")

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
	"""刷新厂商列表"""
	# 清空现有内容
	for child in providers_container.get_children():
		child.queue_free()
	
	var providers = config_manager.get_all_providers()
	
	for provider_name in providers.keys():
		var provider_data = providers[provider_name]
		var item = _create_provider_item(provider_name, provider_data)
		providers_container.add_child(item)

func _create_provider_item(provider_name: String, provider_data: Dictionary) -> PanelContainer:
	"""创建单个厂商项"""
	var item = PanelContainer.new()
	item.custom_minimum_size = Vector2(0, 60)
	
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
	
	# 厂商信息
	var vbox_info = VBoxContainer.new()
	vbox_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox_info)
	
	var name_label = Label.new()
	name_label.text = provider_name
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 22)
	vbox_info.add_child(name_label)
	
	var url_label = Label.new()
	url_label.text = provider_data.get("base_url", "")
	url_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	url_label.add_theme_font_size_override("font_size", 14)
	url_label.clip_text = true
	vbox_info.add_child(url_label)
	
	# 按钮容器
	var btn_container = HBoxContainer.new()
	hbox.add_child(btn_container)
	
	# 编辑按钮
	var edit_button = Button.new()
	edit_button.text = "编辑"
	edit_button.pressed.connect(_on_edit_pressed.bind(provider_name, provider_data))
	btn_container.add_child(edit_button)
	
	# 删除按钮
	var delete_button = Button.new()
	delete_button.text = "删除"
	delete_button.pressed.connect(_on_delete_pressed.bind(provider_name))
	btn_container.add_child(delete_button)
	
	return item

func _on_add_pressed():
	"""新建厂商"""
	var dialog = dialog_scene.instantiate()
	add_child(dialog)
	dialog.setup_for_create(config_manager.get_all_providers())
	dialog.provider_saved.connect(_on_provider_saved)
	dialog.cancelled.connect(_on_dialog_cancelled)

func _on_edit_pressed(provider_name: String, provider_data: Dictionary):
	"""编辑厂商"""
	var dialog = dialog_scene.instantiate()
	add_child(dialog)
	dialog.setup_for_edit(provider_name, provider_data, config_manager.get_all_providers())
	dialog.provider_saved.connect(_on_provider_saved.bind(provider_name))
	dialog.cancelled.connect(_on_dialog_cancelled)

func _on_delete_pressed(provider_name: String):
	"""删除厂商"""
	# 检查是否有模型使用此厂商
	var models = config_manager.get_all_models()
	for model_name in models.keys():
		if models[model_name].get("provider", "") == provider_name:
			_show_status("无法删除：有模型正在使用此厂商", false)
			return
	
	if config_manager.delete_provider(provider_name):
		_show_status("厂商已删除", true)
		_refresh_list()
		providers_changed.emit()
		config_changed.emit()
	else:
		_show_status("删除失败", false)

func _on_provider_saved(provider_name: String, provider_data: Dictionary, old_name: String = ""):
	"""保存厂商"""
	# 如果是编辑模式，先删除旧的
	if not old_name.is_empty() and old_name != provider_name:
		config_manager.delete_provider(old_name)
	
	if config_manager.save_provider(provider_name, provider_data):
		_show_status("厂商已保存", true)
		_refresh_list()
		providers_changed.emit()
		config_changed.emit()
	else:
		_show_status("保存失败", false)

func _on_dialog_cancelled():
	"""对话框取消"""
	pass

func _show_status(message: String, success: bool):
	status_label.text = message
	status_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3) if success else Color(1.0, 0.3, 0.3))
