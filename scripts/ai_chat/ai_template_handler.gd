# AI 模板处理模块
# 负责：模板选择、更新和应用

extends Node

var config_manager: Node
var selected_template: String = "standard"
var custom_template_json: String = ""  # 保存自定义模板内容
var is_editing_template: bool = false  # 是否正在编辑模板

# UI引用
var quick_template_free: Button
var quick_template_standard: Button
var quick_template_alternate: Button
var quick_template_custom: Button
var quick_description_label: Label
var custom_buttons_container: Control
var template_text_edit_container: Control
var template_text_edit: TextEdit
var hint_label: Label

func _init(cfg_mgr: Node) -> void:
	config_manager = cfg_mgr

## 选择配置模板
func select_template(template: String) -> void:
	selected_template = template
	update_template_selection()

## 获取当前选择的模板
func get_selected_template() -> String:
	return selected_template

## 更新模板选择的UI显示
func update_template_selection() -> void:
	if selected_template == "custom":
		# 自定义配置：取消所有按钮选择，选中自定义按钮
		quick_template_free.button_pressed = false
		quick_template_standard.button_pressed = false
		quick_template_alternate.button_pressed = false
		quick_template_custom.button_pressed = true
		
		# 显示自定义按钮区域
		custom_buttons_container.visible = true
		quick_description_label.visible = false
		
		# 更新提示标签
		if hint_label:
			hint_label.text = "可以直接粘贴模板一键导入"
	elif config_manager.CONFIG_TEMPLATES.has(selected_template):
		# 模板配置：更新按钮状态和描述
		quick_template_free.button_pressed = (selected_template == "free")
		quick_template_standard.button_pressed = (selected_template == "standard")
		quick_template_alternate.button_pressed = (selected_template == "alternate")
		quick_template_custom.button_pressed = false
		
		# 显示描述标签，隐藏自定义按钮区域
		custom_buttons_container.visible = false
		template_text_edit_container.visible = false
		quick_description_label.visible = true
		
		# 恢复提示标签
		if hint_label:
			hint_label.text = "选择配置模板（仅限硅基流动，其他平台请使用详细配置）"
		
		var template_data = config_manager.CONFIG_TEMPLATES[selected_template]
		quick_description_label.text = template_data.description
	else:
		# 未知模板，默认为标准
		selected_template = "standard"
		quick_template_free.button_pressed = false
		quick_template_standard.button_pressed = true
		quick_template_alternate.button_pressed = false
		quick_template_custom.button_pressed = false
		
		# 显示描述标签，隐藏自定义按钮区域
		custom_buttons_container.visible = false
		template_text_edit_container.visible = false
		quick_description_label.visible = true
		
		# 恢复提示标签
		if hint_label:
			hint_label.text = "选择配置模板（仅限硅基流动，其他平台请使用详细配置）"
		
		quick_description_label.text = config_manager.CONFIG_TEMPLATES["standard"].description

## 加载模板选择
func load_selected_template() -> void:
	var config = config_manager.load_config()
	
	# 加载自定义模板内容
	if config.has("custom_template_json"):
		custom_template_json = config.custom_template_json
		if template_text_edit:
			template_text_edit.text = custom_template_json
	
	if config.has("template"):
		selected_template = config.template
		update_template_selection()
	else:
		# 默认选择标准
		selected_template = "standard"
		update_template_selection()

## 应用快速配置（支持自定义模板）
func apply_quick_config(api_key: String) -> Dictionary:
	if selected_template == "custom":
		# 自定义模板应用
		if custom_template_json.is_empty():
			return {"success": false, "message": "请先编辑或粘贴模板"}
		
		# 尝试导入模板，传递快速配置密钥
		var result = config_manager.import_template(custom_template_json, api_key)
		if result.success:
			# 保存模板标记
			var config = config_manager.load_config()
			config["template"] = "custom"
			config["custom_template_json"] = custom_template_json
			config["api_key"] = api_key
			config_manager.save_config(config)
			return {"success": true, "message": "已应用自定义配置"}
		elif result.has("conflicts"):
			# 有冲突，返回冲突信息并保存模板和密钥
			result["custom_template_json"] = custom_template_json
			result["api_key"] = api_key
			return result
		else:
			return result
	else:
		# 标准模板应用
		if api_key.strip_edges().is_empty():
			return {"success": false, "message": "请先输入API密钥"}
		
		var template = config_manager.get_template(selected_template)
		if template.is_empty():
			return {"success": false, "message": "模板不存在"}
		
		# 保存厂商API密钥到"硅基流动"厂商
		var providers = config_manager.get_all_providers()
		if providers.has("硅基流动"):
			var siliconflow = providers["硅基流动"].duplicate()
			siliconflow["api_key"] = api_key
			config_manager.save_provider("硅基流动", siliconflow)
		
		# 保存模型任务配置（引用预设模型名）
		var tasks = {}
		var task_model_map = template.models
		for task_id in task_model_map.keys():
			tasks[task_id] = {
				"model": task_model_map[task_id]
			}
		config_manager.save_model_tasks(tasks)
		
		# 保存模板标记
		var config = config_manager.load_config()
		config["template"] = selected_template
		config["api_key"] = api_key
		config_manager.save_config(config)
		
		return {"success": true, "message": "已应用「%s」配置" % template.name}

## 样式化模板按钮
func style_template_buttons() -> void:
	var style_box_free = StyleBoxFlat.new()
	style_box_free.bg_color = Color(0.2, 0.2, 0.2, 0.3)
	style_box_free.border_width_left = 2
	style_box_free.border_width_top = 2
	style_box_free.border_width_right = 2
	style_box_free.border_width_bottom = 2
	style_box_free.border_color = Color(0.5, 0.5, 0.5, 0.8)
	style_box_free.corner_radius_top_left = 5
	style_box_free.corner_radius_top_right = 5
	style_box_free.corner_radius_bottom_left = 5
	style_box_free.corner_radius_bottom_right = 5
	style_box_free.content_margin_left = 10
	style_box_free.content_margin_right = 10
	style_box_free.content_margin_top = 5
	style_box_free.content_margin_bottom = 5
	
	var style_box_free_pressed = style_box_free.duplicate()
	style_box_free_pressed.bg_color = Color(0.3, 0.5, 0.8, 0.5)
	style_box_free_pressed.border_color = Color(0.4, 0.6, 1.0, 1.0)
	
	quick_template_free.add_theme_stylebox_override("normal", style_box_free)
	quick_template_free.add_theme_stylebox_override("pressed", style_box_free_pressed)
	quick_template_free.add_theme_stylebox_override("hover", style_box_free_pressed)
	
	var style_box_standard = style_box_free.duplicate()
	var style_box_standard_pressed = style_box_free_pressed.duplicate()
	var style_box_alternate = style_box_free.duplicate()
	var style_box_alternate_pressed = style_box_free_pressed.duplicate()
	var style_box_custom = style_box_free.duplicate()
	var style_box_custom_pressed = style_box_free_pressed.duplicate()
	
	quick_template_standard.add_theme_stylebox_override("normal", style_box_standard)
	quick_template_standard.add_theme_stylebox_override("pressed", style_box_standard_pressed)
	quick_template_standard.add_theme_stylebox_override("hover", style_box_standard_pressed)
	
	quick_template_alternate.add_theme_stylebox_override("normal", style_box_alternate)
	quick_template_alternate.add_theme_stylebox_override("pressed", style_box_alternate_pressed)
	quick_template_alternate.add_theme_stylebox_override("hover", style_box_alternate_pressed)
	
	quick_template_custom.add_theme_stylebox_override("normal", style_box_custom)
	quick_template_custom.add_theme_stylebox_override("pressed", style_box_custom_pressed)
	quick_template_custom.add_theme_stylebox_override("hover", style_box_custom_pressed)

## 编辑模板
func edit_template() -> void:
	is_editing_template = true
	template_text_edit_container.visible = true
	
	# 加载当前自定义模板
	if custom_template_json.is_empty():
		# 如果没有自定义模板，尝试导出当前配置
		custom_template_json = config_manager.export_template()
	
	template_text_edit.text = custom_template_json

## 复制当前配置为模板
func copy_current_config_as_template() -> void:
	custom_template_json = config_manager.export_template()
	template_text_edit.text = custom_template_json
	
	# 保存到配置
	var config = config_manager.load_config()
	config["custom_template_json"] = custom_template_json
	config_manager.save_config(config)
	
	# 复制到剪贴板
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(custom_template_json)

## 保存自定义模板内容
func save_custom_template() -> void:
	if template_text_edit:
		custom_template_json = template_text_edit.text
		var config = config_manager.load_config()
		config["custom_template_json"] = custom_template_json
		config_manager.save_config(config)
