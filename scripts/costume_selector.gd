extends Control

signal costume_selected(costume_id: String)
signal close_requested

@onready var costume_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ScrollContainer/CostumeList
@onready var add_button: Button = $Panel/MarginContainer/VBoxContainer/ActionButtons/AddButton
@onready var delete_button: Button = $Panel/MarginContainer/VBoxContainer/ActionButtons/DeleteButton
@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/ActionButtons/CloseButton
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var file_dialog: FileDialog = $FileDialog
@onready var confirm_dialog: ConfirmationDialog = $ConfirmDialog
@onready var result_dialog: AcceptDialog = $ResultDialog

var available_costumes: Array = []
var _current_selection_id: String = ""

func _ready():
	add_button.pressed.connect(_on_add_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	close_button.pressed.connect(_on_close_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	confirm_dialog.confirmed.connect(_on_delete_confirmed)
	_load_costumes()

func _load_costumes():
	"""加载所有可用的服装配置"""
	available_costumes.clear()
	
	# 初始化当前选中的ID为正在穿着的ID
	_current_selection_id = _get_current_costume_id()
	
	# 定义所有需要扫描的配置目录
	var config_dirs = [
		"res://config/character_presets",
		"user://clothes/configs"
	]
	
	# 记录已加载的ID，防止重复
	var loaded_ids = []
	
	for config_dir_path in config_dirs:
		if not DirAccess.dir_exists_absolute(config_dir_path):
			continue
			
		var dir = DirAccess.open(config_dir_path)
		if not dir:
			push_error("无法打开服装配置目录: " + config_dir_path)
			continue
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				var config_path = config_dir_path + "/" + file_name
				var costume_data = _load_costume_config(config_path)
				if costume_data.size() > 0:
					var costume_id = costume_data.get("id", "")
					if costume_id != "" and not loaded_ids.has(costume_id):
						available_costumes.append(costume_data)
						loaded_ids.append(costume_id)
			file_name = dir.get_next()
		
		dir.list_dir_end()
	
	# 如果没有任何配置，尝试回退到默认
	if available_costumes.is_empty():
		var default_config = _load_costume_config("res://config/character_presets/default.json")
		if default_config.size() > 0:
			available_costumes.append(default_config)
	
	# 按ID排序
	available_costumes.sort_custom(func(a, b): return a.id < b.id)
	
	# 创建UI元素
	_populate_costume_list()

func _load_costume_config(config_path: String) -> Dictionary:
	"""加载单个服装配置"""
	if not FileAccess.file_exists(config_path):
		return {}
	
	var file = FileAccess.open(config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		push_error("解析服装配置失败: " + config_path)
		return {}
	
	var data = json.data
	if not data.has("id") or not data.has("name"):
		push_error("服装配置缺少必要字段: " + config_path)
		return {}
	
	return data

func _populate_costume_list():
	"""填充服装列表"""
	# 清空现有列表
	for child in costume_list.get_children():
		child.queue_free()
	
	# 如果当前选中的ID为空（第一次加载），初始化它
	if _current_selection_id == "":
		_current_selection_id = _get_current_costume_id()
	
	# 更新底部删除按钮状态：如果是default则不可删除
	delete_button.disabled = (_current_selection_id == "default")
	
	# 获取当前正在穿着的ID（用于显示“当前使用中”标签）
	var active_costume_id = _get_current_costume_id()
	
	# 为每个服装创建按钮
	for costume_data in available_costumes:
		var is_selected = (costume_data.id == _current_selection_id)
		var is_active = (costume_data.id == active_costume_id)
		var costume_button = _create_costume_button(costume_data, is_active, is_selected)
		costume_list.add_child(costume_button)

func _get_costume_image_path(costume_id: String) -> String:
	"""获取预览图片路径"""
	# 优先从内置资源加载预览图
	var res_preview_path = "res://assets/images/character/%s/preview.png" % costume_id
	if ResourceLoader.exists(res_preview_path):
		return res_preview_path
		
	# 如果是默认服装且没有预览图，回退到第一个场景图
	if costume_id == "default":
		return "res://assets/images/character/default/livingroom/1.png"
	
	# 其次从 user 路径加载预览图
	var user_preview_path = "user://clothes/images/%s/preview.png" % costume_id
	if FileAccess.file_exists(user_preview_path):
		return user_preview_path
	
	return ""

func _load_texture(path: String) -> Texture2D:
	"""加载纹理"""
	if path == "":
		return null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			return load(path)
	elif FileAccess.file_exists(path):
		var image = Image.load_from_file(path)
		if image:
			return ImageTexture.create_from_image(image)
	return null

func _create_costume_button(costume_data: Dictionary, is_active: bool, is_selected: bool) -> Button:
	"""创建服装按钮"""
	var button = Button.new()
	button.custom_minimum_size = Vector2(0, 100) # 稍微增加高度以容纳图片
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# 设置按钮样式
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.18, 0.18, 0.18, 0.8)
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.content_margin_left = 20
	style_normal.content_margin_right = 10
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.25, 0.25, 0.25, 0.9)
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	
	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	style_disabled.border_width_left = 4
	style_disabled.border_color = Color(0.4, 0.7, 1.0, 0.8) # 蓝色边框表示当前
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("disabled", style_disabled)
	
	# 使用 MarginContainer 确保内容不贴边
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.mouse_filter = Control.MOUSE_FILTER_PASS
	margin_container.add_theme_constant_override("margin_left", 20)
	margin_container.add_theme_constant_override("margin_right", 20)
	margin_container.add_theme_constant_override("margin_top", 10)
	margin_container.add_theme_constant_override("margin_bottom", 10)
	button.add_child(margin_container)
	
	# 使用 HBoxContainer 管理内部布局
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_theme_constant_override("separation", 15)
	margin_container.add_child(hbox)
	
	# 左侧文字部分
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(vbox)
	
	var name_label = Label.new()
	name_label.text = costume_data.name
	name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(name_label)
	
	if costume_data.has("description") and costume_data.description != "":
		var desc_label = Label.new()
		desc_label.text = costume_data.description
		desc_label.add_theme_font_size_override("font_size", 14)
		desc_label.modulate = Color(0.7, 0.7, 0.7)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)
	
	if is_active:
		var current_label = Label.new()
		current_label.text = "[当前使用中]"
		current_label.add_theme_font_size_override("font_size", 12)
		current_label.modulate = Color(0.4, 0.7, 1.0)
		vbox.add_child(current_label)
		# 正在穿着的服装不需要再次点击切换
		button.disabled = true
	
	# 右侧图片预览
	var img_path = _get_costume_image_path(costume_data.id)
	var texture = _load_texture(img_path)
	if texture:
		var preview_rect = TextureRect.new()
		preview_rect.texture = texture
		preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview_rect.custom_minimum_size = Vector2(100, 80)
		preview_rect.mouse_filter = Control.MOUSE_FILTER_PASS
		hbox.add_child(preview_rect)
	
	# 连接信号
	if not is_active:
		button.pressed.connect(func(): _on_costume_button_pressed(costume_data.id))
	
	return button

func _get_current_costume_id() -> String:
	"""获取当前服装ID"""
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		return save_mgr.get_costume_id()
	return "default"

func _on_add_pressed():
	"""添加按钮点击"""
	file_dialog.popup_centered()

func _on_file_selected(path: String):
	"""文件选择完成"""
	# 延迟处理以避免与 FileDialog 的排他性冲突
	_process_zip.call_deferred(path)

func _process_zip(zip_path: String):
	"""处理上传的ZIP文件"""
	var reader = ZIPReader.new()
	var err = reader.open(zip_path)
	if err != OK:
		_show_result("错误", "无法打开ZIP文件: " + str(err))
		return
	
	var files = reader.get_files()
	var total_count = 0
	var success_count = 0
	var failed_reasons = []
	
	# 收集所有配置文件
	var config_files = []
	for file_path in files:
		if file_path.begins_with("configs/") and file_path.ends_with(".json") and not file_path.ends_with("/"):
			config_files.append(file_path)
	
	total_count = config_files.size()
	if total_count == 0:
		_show_result("提示", "ZIP中未找到任何服装配置(configs/*.json)")
		reader.close()
		return

	# 确保目标目录存在
	DirAccess.make_dir_recursive_absolute("user://clothes/configs")
	DirAccess.make_dir_recursive_absolute("user://clothes/images")
	
	for config_file in config_files:
		var file_name = config_file.get_file()
		var costume_id = file_name.get_basename()
		
		# 1. 校验ID是否已存在 (内置ID以 default 或 preset 开头)
		if costume_id == "default" or costume_id.begins_with("preset") or FileAccess.file_exists("user://clothes/configs/" + file_name):
			failed_reasons.append("%s: ID已存在或为保留ID" % costume_id)
			continue
		
		# 读取JSON内容进行校验
		var json_data = reader.read_file(config_file)
		var json = JSON.new()
		if json.parse(json_data.get_string_from_utf8()) != OK:
			failed_reasons.append("%s: JSON解析失败" % costume_id)
			continue
		
		var data = json.data
		# 2. 校验JSON内的id字段
		if not data.has("id") or data.id != costume_id:
			failed_reasons.append("%s: JSON内的id字段与文件名不一致" % costume_id)
			continue
		
		# 3. 校验images/下是否存在对应文件夹
		var image_dir = "images/%s/" % costume_id
		var has_images = false
		for f in files:
			if f.begins_with(image_dir):
				has_images = true
				break
		
		if not has_images:
			failed_reasons.append("%s: 未找到对应的图片文件夹 %s" % [costume_id, image_dir])
			continue
		
		# 校验通过，开始移动文件
		# 移动配置 (保存到 user 路径)
		var fa = FileAccess.open("user://clothes/configs/" + file_name, FileAccess.WRITE)
		if fa:
			fa.store_buffer(json_data)
			fa.close()
		else:
			failed_reasons.append("%s: 无法写入配置文件" % costume_id)
			continue
			
		# 移动图片
		var target_image_root = "user://clothes/images/" + costume_id
		DirAccess.make_dir_recursive_absolute(target_image_root)
		for f in files:
			if f.begins_with(image_dir) and not f.ends_with("/"):
				var relative_path = f.trim_prefix(image_dir)
				var target_path = target_image_root + "/" + relative_path
				
				# 确保子目录存在
				var target_dir = target_path.get_base_dir()
				if not DirAccess.dir_exists_absolute(target_dir):
					DirAccess.make_dir_recursive_absolute(target_dir)
					
				var img_data = reader.read_file(f)
				var out_fa = FileAccess.open(target_path, FileAccess.WRITE)
				if out_fa:
					out_fa.store_buffer(img_data)
					out_fa.close()
		
		success_count += 1
	
	reader.close()
	
	# 显示反馈
	var message = "共 %d 个服装，成功 %d 个，失败 %d 个。" % [total_count, success_count, total_count - success_count]
	if failed_reasons.size() > 0:
		message += "\n\n失败原因：\n" + "\n".join(failed_reasons)
	
	_show_result("添加结果", message)
	_load_costumes()

func _on_delete_pressed():
	"""删除按钮点击"""
	if _current_selection_id == "" or _current_selection_id == "default":
		return
		
	confirm_dialog.dialog_text = "确定要删除当前服装 [%s] 吗？" % _current_selection_id
	confirm_dialog.popup_centered()
	# 默认选中取消按钮
	confirm_dialog.get_cancel_button().grab_focus()

func _on_delete_confirmed():
	"""确认删除"""
	if _current_selection_id == "" or _current_selection_id == "default":
		return
	
	var deleting_id = _current_selection_id
	
	# 检查是否是内置资源 (内置ID以 default 或 preset 开头)
	if deleting_id == "default" or deleting_id.begins_with("preset"):
		_show_result("提示", "内置服装无法删除（不是我不让你删，底层逻辑就是删不了）")
		return
	
	# 1. 删除配置文件
	var config_path = "user://clothes/configs/%s.json" % deleting_id
	if FileAccess.file_exists(config_path):
		DirAccess.remove_absolute(config_path)
	
	# 2. 删除图片文件夹
	var image_dir = "user://clothes/images/%s" % deleting_id
	if DirAccess.dir_exists_absolute(image_dir):
		_remove_recursive(image_dir)
	
	# 3. 删除后切换回 default
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		save_mgr.set_costume_id("default")
		costume_selected.emit("default")
	
	_current_selection_id = "default"
	_load_costumes()

func _remove_recursive(path: String):
	"""递归删除目录"""
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name == "." or file_name == "..":
				file_name = dir.get_next()
				continue
			
			var full_path = path + "/" + file_name
			if dir.current_is_dir():
				_remove_recursive(full_path)
			else:
				DirAccess.remove_absolute(full_path)
			file_name = dir.get_next()
		
		DirAccess.remove_absolute(path)

func _show_result(title: String, message: String):
	"""显示结果对话框"""
	result_dialog.title = title
	result_dialog.dialog_text = message
	result_dialog.popup_centered()

func _on_costume_button_pressed(costume_id: String):
	"""服装按钮点击"""
	print("选择服装: ", costume_id)
	costume_selected.emit(costume_id)
	_current_selection_id = costume_id
	_populate_costume_list()

func _on_close_pressed():
	"""关闭按钮点击"""
	close_requested.emit()
	_close()

func _close():
	"""关闭界面"""
	queue_free()
