# AI 模板处理模块
# 负责：模板选择、更新和应用

extends Node

var config_manager: Node
var selected_template: String = "standard"

# UI引用
var quick_template_free: Button
var quick_template_standard: Button
var quick_template_alternate: Button
var quick_description_label: Label

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
		# 自定义配置：取消所有按钮选择
		quick_template_free.button_pressed = false
		quick_template_standard.button_pressed = false
		quick_template_alternate.button_pressed = false
		quick_description_label.text = "当前使用自定义配置"
	elif config_manager.CONFIG_TEMPLATES.has(selected_template):
		# 模板配置：更新按钮状态和描述
		quick_template_free.button_pressed = (selected_template == "free")
		quick_template_standard.button_pressed = (selected_template == "standard")
		quick_template_alternate.button_pressed = (selected_template == "alternate")
		
		var template_data = config_manager.CONFIG_TEMPLATES[selected_template]
		quick_description_label.text = template_data.description
	else:
		# 未知模板，默认为标准
		selected_template = "standard"
		quick_template_free.button_pressed = false
		quick_template_standard.button_pressed = true
		quick_template_alternate.button_pressed = false
		quick_description_label.text = config_manager.CONFIG_TEMPLATES["standard"].description

## 加载模板选择
func load_selected_template() -> void:
	var config = config_manager.load_config()
	if config.has("template"):
		selected_template = config.template
		update_template_selection()
	else:
		# 默认选择标准
		selected_template = "standard"
		update_template_selection()

## 建立快速配置应用配置
func apply_quick_config(api_key: String) -> Dictionary:
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
	
	quick_template_standard.add_theme_stylebox_override("normal", style_box_standard)
	quick_template_standard.add_theme_stylebox_override("pressed", style_box_standard_pressed)
	quick_template_standard.add_theme_stylebox_override("hover", style_box_standard_pressed)
	
	quick_template_alternate.add_theme_stylebox_override("normal", style_box_alternate)
	quick_template_alternate.add_theme_stylebox_override("pressed", style_box_alternate_pressed)
	quick_template_alternate.add_theme_stylebox_override("hover", style_box_alternate_pressed)
