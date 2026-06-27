extends MarginContainer

# 模型任务配置面板
# 显示所有模型任务，每个任务可以选择要使用的模型

@onready var tasks_container = $ScrollContainer/VBoxContainer/TasksContainer
@onready var status_label = $ScrollContainer/VBoxContainer/StatusLabel

var config_manager: Node
var task_option_buttons: Dictionary = {}  # { task_id: OptionButton }

func initialize(cfg_mgr: Node):
	"""初始化面板"""
	config_manager = cfg_mgr
	_build_task_list()

func _build_task_list():
	"""构建任务列表"""
	# 清空现有内容
	for child in tasks_container.get_children():
		child.queue_free()
	task_option_buttons.clear()
	
	var tasks = config_manager.get_model_tasks()
	var models = config_manager.get_all_models()
	var model_names = models.keys()
	model_names.sort()
	
	for task_id in tasks.keys():
		var task = tasks[task_id]
		var item = _create_task_item(task_id, task, model_names)
		tasks_container.add_child(item)

func _create_task_item(task_id: String, task: Dictionary, model_names: Array) -> PanelContainer:
	"""创建单个任务项"""
	var item = PanelContainer.new()
	# item.custom_minimum_size = Vector2(0, 80)
	item.mouse_filter = Control.MOUSE_FILTER_PASS
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
	
	# 左侧：任务名称和描述
	var vbox_left = VBoxContainer.new()
	vbox_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox_left)
	
	var name_label = Label.new()
	name_label.text = task.name
	name_label.add_theme_font_size_override("font_size", 22)
	vbox_left.add_child(name_label)
	
	var desc_label = Label.new()
	desc_label.text = task.description
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox_left.add_child(desc_label)
	
	# 右侧：模型选择下拉框
	var option = OptionButton.new()
	option.custom_minimum_size = Vector2(200, 0)
	option.add_item("未选择")
	
	var selected_index = 0
	for i in range(model_names.size()):
		option.add_item(model_names[i])
		if model_names[i] == task.model:
			selected_index = i + 1
	
	option.selected = selected_index
	option.item_selected.connect(_on_task_option_changed.bind(task_id))
	hbox.add_child(option)
	
	task_option_buttons[task_id] = option
	
	return item

func _on_task_option_changed(_index: int, task_id: String):
	"""选择后自动保存"""
	_auto_save()

func _auto_save():
	"""自动保存所有任务配置"""
	var tasks = {}
	
	for task_id in task_option_buttons.keys():
		var option = task_option_buttons[task_id]
		var selected_text = option.get_item_text(option.selected)
		
		tasks[task_id] = {
			"model": "" if selected_text == "未选择" else selected_text
		}
	
	if config_manager.save_model_tasks(tasks):
		_show_status("已自动保存", true)
	else:
		_show_status("保存失败", false)

func _show_status(message: String, success: bool):
	status_label.text = message
	status_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3) if success else Color(1.0, 0.3, 0.3))