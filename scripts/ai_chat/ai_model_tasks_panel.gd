extends MarginContainer

# 模型任务配置面板
# 显示所有模型任务，每个任务可以选择要使用的模型

signal config_changed  # 配置变更，需要重新加载

@onready var tasks_container = $ScrollContainer/VBoxContainer/TasksContainer
@onready var status_label = $ScrollContainer/VBoxContainer/StatusLabel

var config_manager: Node
var task_option_buttons: Dictionary = {}  # { task_id: OptionButton }
var task_original_models: Dictionary = {}  # { task_id: String } 存储原始模型名称


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
	task_original_models.clear()
	
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
	var current_model = task.get("model", "")
	for i in range(model_names.size()):
		option.add_item(model_names[i])
		if model_names[i] == current_model:
			selected_index = i + 1
	
	option.selected = selected_index
	# 存储原始模型名称
	task_original_models[task_id] = current_model
	
	# 连接信号，传递 task_id 和 OptionButton 自身
	option.item_selected.connect(_on_task_option_selected.bind(task_id, option))
	hbox.add_child(option)
	var popup = option.get_popup()
	popup.max_size = Vector2(300, 200)
	
	task_option_buttons[task_id] = option
	
	return item

func _on_task_option_selected(index: int, task_id: String, option: OptionButton):
	"""当选择模型时触发"""
	var selected_text = option.get_item_text(index)
	var original_model = task_original_models.get(task_id, "")
	
	# 获取任务信息，检查是否是嵌入模型任务
	var tasks = config_manager.get_model_tasks()
	var task = tasks.get(task_id, {})
	var task_name = task.get("name", "")
	
	# 检查是否选择了嵌入模型（根据任务名称判断）
	var is_embedding_task = task_name == "embedding" or task_id == "embedding" or "embedding" in task_id.to_lower()
	
	# 如果当前选中的是嵌入模型，且与之前不同，需要确认
	if is_embedding_task and selected_text != original_model and selected_text != "未选择":
		# 弹出确认对话框
		_show_embedding_change_confirmation(task_id, option, selected_text, original_model)
	else:
		# 非嵌入模型或未改变，直接保存
		_auto_save()

func _show_embedding_change_confirmation(task_id: String, option: OptionButton, new_model: String, old_model: String):
	"""显示嵌入模型更换确认对话框"""
	# 创建确认对话框
	var dialog = ConfirmationDialog.new()
	dialog.title = "确认更换嵌入模型"
	dialog.dialog_text = "⚠\n修改嵌入模型可能导致已有的记忆完全失效\n确定更换吗？\n"
	dialog.ok_button_text = "确定更换"
	dialog.cancel_button_text = "取消"
	
	# 添加到场景
	add_child(dialog)
	
	# 连接信号
	dialog.confirmed.connect(_on_embedding_change_confirmed.bind(task_id, option, new_model))
	dialog.canceled.connect(_on_embedding_change_canceled.bind(task_id, option, old_model))
	
	# 显示对话框
	dialog.popup_centered()

func _on_embedding_change_confirmed(task_id: String, option: OptionButton, new_model: String):
	"""确认更换嵌入模型"""
	# 更新存储的原始模型
	task_original_models[task_id] = new_model
	# 自动保存
	_auto_save()
	# 显示成功状态
	_show_status("已更换嵌入模型", true)

func _on_embedding_change_canceled(task_id: String, option: OptionButton, old_model: String):
	"""取消更换嵌入模型 - 恢复原选择"""
	# 恢复选择到原始模型
	var original_index = 0
	if old_model != "":
		# 找到原始模型的索引（+1 是因为第一项是"未选择"）
		var model_index = 0
		for i in range(1, option.item_count):
			if option.get_item_text(i) == old_model:
				model_index = i
				break
		option.select(model_index)
	else:
		option.select(0)  # 选择"未选择"
	
	_show_status("已取消更换", true)

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
		config_changed.emit()
	else:
		_show_status("保存失败", false)

func _show_status(message: String, success: bool):
	status_label.text = message
	status_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3) if success else Color(1.0, 0.3, 0.3))
