extends Control

# 资源管理面板 - 以卡片形式展示所有资源

@onready var resource_grid = $VBoxContainer/ScrollContainer/ResourceGrid

const RESOURCE_CONFIG_PATH = "res://config/resources.json"
const RESOURCE_LIST_PATH = "user://ResourceList.json"

# 资源卡片场景（将动态创建）
var resource_card_scene: PackedScene
var file_dialog: FileDialog
var current_import_id: String = ""

func _ready():
	_setup_file_dialog()
	_load_and_display_resources()

func _setup_file_dialog():
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.zip, *.pck ; Resource Packages"]
	file_dialog.file_selected.connect(_on_import_file_selected)
	add_child(file_dialog)

func _load_and_display_resources():
	"""加载并显示所有资源"""
	# 清空现有卡片
	for child in resource_grid.get_children():
		child.queue_free()
	
	# 加载资源配置
	var resources = _load_resource_config()
	if resources.is_empty():
		_show_no_resources_message()
		return
	
	# 加载已安装资源列表
	var installed_resources = _load_installed_resources()
	
	# 为每个资源创建卡片
	for resource in resources:
		_create_resource_card(resource, installed_resources)

func _load_resource_config() -> Array:
	"""加载资源配置文件
	
	返回:
		资源配置数组
	"""
	if not FileAccess.file_exists(RESOURCE_CONFIG_PATH):
		print("[ResourceManagerPanel] 警告: 资源配置文件不存在")
		return []
	
	var file = FileAccess.open(RESOURCE_CONFIG_PATH, FileAccess.READ)
	if not file:
		print("[ResourceManagerPanel] 错误: 无法打开资源配置文件")
		return []
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		print("[ResourceManagerPanel] 错误: 资源配置文件格式错误")
		return []
	
	var config = json.data
	return config.get("resources", [])

func _load_installed_resources() -> Dictionary:
	"""加载已安装资源列表（从ResourceList.json）
	
	返回:
		已安装资源字典，格式: {resource_id: version}
	"""
	if not FileAccess.file_exists(RESOURCE_LIST_PATH):
		return {}
	
	var file = FileAccess.open(RESOURCE_LIST_PATH, FileAccess.READ)
	if not file:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return {}
	
	return json.data

func _create_resource_card(resource: Dictionary, installed_resources: Dictionary):
	"""创建资源卡片
	
	参数:
		resource: 资源配置字典
		installed_resources: 已安装资源字典
	"""
	var card = _build_card_ui(resource, installed_resources)
	resource_grid.add_child(card)

func _build_card_ui(resource: Dictionary, installed_resources: Dictionary) -> Control:
	"""构建资源卡片UI
	
	参数:
		resource: 资源配置字典
		installed_resources: 已安装资源字典
	
	返回:
		卡片控件
	"""
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 100)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# 卡片背景样式
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.25, 1.0)
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	style_box.content_margin_left = 15
	style_box.content_margin_top = 15
	style_box.content_margin_right = 15
	style_box.content_margin_bottom = 15
	card.add_theme_stylebox_override("panel", style_box)
	
	# 主容器：左右布局
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	card.add_child(hbox)
	
	# 左侧：信息区域（三行）
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 5)
	hbox.add_child(left_vbox)
	
	# 第一行：描述
	var description_label = Label.new()
	description_label.text = resource.get("description", "未知资源")
	description_label.add_theme_font_size_override("font_size", 18)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(description_label)
	
	# 第二行：ID
	var resource_id = resource.get("id", "")
	var filesize = resource.get("filesize","")
	var id_label = Label.new()
	id_label.text = "ID: " + resource_id+"  |  约"+filesize
	id_label.add_theme_font_size_override("font_size", 12)
	id_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	left_vbox.add_child(id_label)
	
	# 第三行：版本信息
	var config_version = resource.get("version", "1.0.0")
	var installed_version = installed_resources.get(resource_id, "")
	
	var version_text = "配置版本: " + config_version
	var version_color = Color(1.0, 1.0, 1.0, 1.0)
	
	if installed_version.is_empty():
		version_text += "  |  当前: 未安装"
		version_color = Color(1.0, 0.3, 0.3, 1.0) # 红色 (未安装)
	else:
		version_text += "  |  当前: " + installed_version
		var compare_result = _compare_versions(installed_version, config_version)
		if compare_result < 0:
			version_color = Color(1.0, 0.3, 0.3, 1.0) # 红色 (版本过低)
		elif compare_result == 0:
			version_color = Color(0.3, 1.0, 0.3, 1.0) # 绿色 (正常)
		else:
			version_color = Color(1.0, 0.8, 0.3, 1.0) # 黄色 (版本过高)
	
	var version_label = Label.new()
	version_label.text = version_text
	version_label.add_theme_font_size_override("font_size", 12)
	version_label.add_theme_color_override("font_color", version_color)
	left_vbox.add_child(version_label)
	
	# 第四行：limitation字段（根据资源状态调整颜色）
	var limitation = resource.get("limitation", "")
	if not limitation.is_empty():
		var limitation_label = Label.new()
		limitation_label.text = limitation
		limitation_label.add_theme_font_size_override("font_size", 12)
		limitation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		# 判断资源状态，决定颜色
		var is_complete = false
		if not installed_version.is_empty():
			# 已安装且版本不低于配置版本
			if _compare_versions(installed_version, config_version) >= 0:
				is_complete = true
		
		if is_complete:
			# 资源完整：使用不显眼的灰色
			limitation_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
		else:
			# 资源不完整或版本低：使用警告黄色
			limitation_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3, 1.0))
		
		left_vbox.add_child(limitation_label)
	
	# 右侧：按钮区域（水平排列两个按钮）
	var right_hbox = HBoxContainer.new()
	right_hbox.add_theme_constant_override("separation", 10)
	right_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right_hbox)
	
	# 导入按钮
	var import_button = Button.new()
	import_button.text = "导入"
	import_button.custom_minimum_size = Vector2(90, 40)
	import_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	import_button.disabled = false
	import_button.pressed.connect(_on_import_button_pressed.bind(resource_id))
	right_hbox.add_child(import_button)
	
	# 下载按钮
	var download_button = Button.new()
	download_button.text = "下载"
	download_button.custom_minimum_size = Vector2(90, 40)
	download_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	download_button.disabled = true  # 暂不实现
	right_hbox.add_child(download_button)
	
	return card

func _compare_versions(version1: String, version2: String) -> int:
	"""比较两个版本号
	
	参数:
		version1: 版本号1
		version2: 版本号2
	
	返回:
		-1: version1 < version2
		0: version1 == version2
		1: version1 > version2
	"""
	var v1_parts = version1.split(".")
	var v2_parts = version2.split(".")
	
	var max_length = max(v1_parts.size(), v2_parts.size())
	
	for i in range(max_length):
		var v1_num = int(v1_parts[i]) if i < v1_parts.size() else 0
		var v2_num = int(v2_parts[i]) if i < v2_parts.size() else 0
		
		if v1_num < v2_num:
			return -1
		elif v1_num > v2_num:
			return 1
	
	return 0

func _show_no_resources_message():
	"""显示无资源消息"""
	var label = Label.new()
	label.text = "没有可用的资源"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	resource_grid.add_child(label)

func _on_refresh_button_pressed():
	"""刷新按钮点击事件"""
	_load_and_display_resources()

func _on_import_button_pressed(resource_id: String):
	"""导入按钮点击事件"""
	current_import_id = resource_id
	file_dialog.popup_centered(Vector2(800, 600))

func _on_import_file_selected(path: String):
	"""文件选择回调"""
	if current_import_id.is_empty():
		return
		
	var success = ResourceManager.import_resource(current_import_id, path)
	if success:
		# 刷新列表显示更新后的版本
		_load_and_display_resources()
		
		# 显示成功提示（可选）
		# OS.alert("导入成功", "提示")
	else:
		OS.alert("请检查资源包是否正确", "导入失败")
	
	current_import_id = ""
