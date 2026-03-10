# AI 回复设置模块
# 负责：回复模式（语言表达/情景叙事）的设置

extends Node

var config_manager: Node
var response_buttons: Dictionary = {}
var response_status_label: Label
var tab_container: TabContainer
var expression_diff_checkbutton: CheckButton
var generation_options_checkbutton: CheckButton
var top_input_checkbutton: CheckButton
var call_trigger_dialog_checkbutton: CheckButton

# 回复风格配置
var response_styles: Dictionary = {
	"verbal": {
		"name": "语言表达",
		"description": "简洁的对话，保持自然交流风格",
		"status": "当前: 语言表达模式"
	},
	"narrative": {
		"name": "情景叙事", 
		"description": "详细的叙述，包含动作、神态等",
		"status": "当前: 情景叙事模式"
	},
	"story": {
		"name": "长篇叙述",
		"description": "长对话，内容更加丰富完整",
		"status": "当前: 长篇叙述模式"
	}
}

func _init(cfg_mgr: Node) -> void:
	config_manager = cfg_mgr

## 创建回复设置选项卡
func setup_response_settings_tab() -> void:
	# 创建选项卡
	var response_tab = MarginContainer.new()
	response_tab.name = "聊天设置"
	response_tab.add_theme_constant_override("margin_left", 10)
	response_tab.add_theme_constant_override("margin_top", 10)
	response_tab.add_theme_constant_override("margin_right", 10)
	response_tab.add_theme_constant_override("margin_bottom", 10)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	response_tab.add_child(vbox)
	
	# 标题
	var title_label = Label.new()
	title_label.text = "回复风格"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(title_label)
	
	# 按钮组
	var button_group = ButtonGroup.new()
	
	# 创建水平容器放置三个回复风格
	var styles_hbox = HBoxContainer.new()
	styles_hbox.add_theme_constant_override("separation", 10)
	styles_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# 动态创建风格选项（横向排列）
	for style_key in ["verbal", "narrative", "story"]:
		_create_style_option_compact(style_key, response_styles[style_key], button_group, styles_hbox)
	
	vbox.add_child(styles_hbox)
	
	# 状态标签
	response_status_label = Label.new()
	response_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	response_status_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(response_status_label)
	
	# 添加分隔线
	var separator1 = HSeparator.new()
	vbox.add_child(separator1)
	
	# 表情差分设置（紧凑布局）
	var expression_container = VBoxContainer.new()
	expression_container.add_theme_constant_override("separation", 3)
	
	expression_diff_checkbutton = CheckButton.new()
	expression_diff_checkbutton.text = "启用表情差分"
	expression_diff_checkbutton.toggled.connect(_on_expression_diff_toggled)
	expression_diff_checkbutton.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	expression_container.add_child(expression_diff_checkbutton)
	
	var expression_desc = Label.new()
	expression_desc.text = "更丰富的表情变化"
	expression_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	expression_desc.add_theme_font_size_override("font_size", 12)
	expression_desc.add_theme_constant_override("margin_left", 20)
	expression_container.add_child(expression_desc)
	
	vbox.add_child(expression_container)
	
	# 生成选项设置（紧凑布局）
	var generation_container = VBoxContainer.new()
	generation_container.add_theme_constant_override("separation", 3)
	
	generation_options_checkbutton = CheckButton.new()
	generation_options_checkbutton.text = "生成回复选项"
	generation_options_checkbutton.toggled.connect(_on_generation_options_toggled)
	generation_options_checkbutton.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	generation_container.add_child(generation_options_checkbutton)
	
	var generation_desc = Label.new()
	generation_desc.text = "旮旯给木里就是这样的"
	generation_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	generation_desc.add_theme_font_size_override("font_size", 12)
	generation_desc.add_theme_constant_override("margin_left", 20)
	generation_container.add_child(generation_desc)
	
	vbox.add_child(generation_container)
	
	# 上方输入框设置（紧凑布局）
	var top_input_container = VBoxContainer.new()
	top_input_container.add_theme_constant_override("separation", 3)
	
	top_input_checkbutton = CheckButton.new()
	top_input_checkbutton.text = "上方输入区域"
	top_input_checkbutton.toggled.connect(_on_top_input_toggled)
	top_input_checkbutton.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top_input_container.add_child(top_input_checkbutton)
	
	var top_input_desc = Label.new()
	top_input_desc.text = "或许对移动端会更友好一些"
	top_input_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	top_input_desc.add_theme_font_size_override("font_size", 12)
	top_input_desc.add_theme_constant_override("margin_left", 20)
	top_input_container.add_child(top_input_desc)
	
	vbox.add_child(top_input_container)
	
	# 呼唤触发对话设置（紧凑布局）
	var call_trigger_container = VBoxContainer.new()
	call_trigger_container.add_theme_constant_override("separation", 3)
	
	call_trigger_dialog_checkbutton = CheckButton.new()
	call_trigger_dialog_checkbutton.text = "呼唤触发对话"
	call_trigger_dialog_checkbutton.toggled.connect(_on_call_trigger_dialog_toggled)
	call_trigger_dialog_checkbutton.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	call_trigger_container.add_child(call_trigger_dialog_checkbutton)
	
	var call_trigger_desc = Label.new()
	call_trigger_desc.text = "跨场景呼唤角色时触发对话"
	call_trigger_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	call_trigger_desc.add_theme_font_size_override("font_size", 12)
	call_trigger_desc.add_theme_constant_override("margin_left", 20)
	call_trigger_container.add_child(call_trigger_desc)
	
	vbox.add_child(call_trigger_container)
	
	# 添加到TabContainer（在"语音设置"之后）
	tab_container.add_child(response_tab)
	# 将回复设置移到第二个位置（快速配置之后）
	tab_container.move_child(response_tab, 2)
	
	# 加载设置
	load_response_settings()

## 创建单个风格选项（紧凑版，用于横向排列）
func _create_style_option_compact(style_key: String, style_data: Dictionary, button_group: ButtonGroup, parent: Control) -> void:
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 3)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# 创建复选框
	var check_button = CheckBox.new()
	check_button.text = style_data.name
	check_button.button_group = button_group
	check_button.toggled.connect(_on_response_mode_changed.bind(style_key))
	check_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	container.add_child(check_button)
	
	# 创建描述标签（更小字体）
	var desc_label = Label.new()
	desc_label.text = style_data.description
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(desc_label)
	
	parent.add_child(container)
	response_buttons[style_key] = check_button

## 加载回复设置
func load_response_settings() -> void:
	var response_mode = config_manager.load_response_mode()
	
	# 确保模式有效，否则使用默认值
	if not response_styles.has(response_mode):
		response_mode = "verbal"
	
	# 设置按钮状态
	for style_key in response_buttons:
		response_buttons[style_key].button_pressed = (style_key == response_mode)
	
	# 更新状态标签
	response_status_label.text = response_styles[response_mode].status
	response_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	
	# 加载表情差分设置
	expression_diff_checkbutton.button_pressed = config_manager.load_expression_diff()
	
	# 加载生成选项设置
	generation_options_checkbutton.button_pressed = config_manager.load_generation_options()
	
	# 加载顶部输入设置
	var top_input_enabled = config_manager.load_top_input_box()
	top_input_checkbutton.button_pressed = top_input_enabled
	print("AIResponseSettings: 加载顶部输入设置 = %s" % top_input_enabled)
	
	# 加载呼唤触发对话设置
	call_trigger_dialog_checkbutton.button_pressed = config_manager.load_call_trigger_dialog()

## 回复模式改变
func _on_response_mode_changed(enabled: bool, mode: String) -> void:
	if not enabled:
		return
	
	# 保存设置
	if config_manager.save_response_mode(mode):
		response_status_label.text = "✓ 已切换到" + response_styles[mode].name
		response_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		response_status_label.text = "✗ 保存失败"
		response_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

## 获取当前回复风格配置
func get_current_response_style() -> Dictionary:
	var current_mode = config_manager.load_response_mode()
	if not response_styles.has(current_mode):
		current_mode = "verbal"
	return response_styles[current_mode]

## 获取所有可用风格（用于其他模块）
func get_available_styles() -> Array:
	return response_styles.keys()

## 表情差分开关切换
func _on_expression_diff_toggled(enabled: bool) -> void:
	config_manager.save_expression_diff(enabled)
	print("表情差分已%s" % ("开启" if enabled else "关闭"))

## 生成选项开关切换
func _on_generation_options_toggled(enabled: bool) -> void:
	config_manager.save_generation_options(enabled)
	print("生成选项已%s" % ("开启" if enabled else "关闭"))

## 顶部输入开关切换
func _on_top_input_toggled(enabled: bool) -> void:
	config_manager.save_top_input_box(enabled)
	print("顶部输入已%s" % ("开启" if enabled else "关闭"))
	
	# 通知聊天对话框更新顶部输入框状态
	var main_scene = get_tree().current_scene
	if main_scene:
		var chat_dialog = main_scene.get_node_or_null("ChatDialog")
		if chat_dialog and chat_dialog.has_method("set_top_input_enabled"):
			chat_dialog.set_top_input_enabled(enabled)

## 呼唤触发对话开关切换
func _on_call_trigger_dialog_toggled(enabled: bool) -> void:
	config_manager.save_call_trigger_dialog(enabled)
	print("呼唤触发对话已%s" % ("开启" if enabled else "关闭"))