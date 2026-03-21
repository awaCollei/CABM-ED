# AI 回复设置模块
# 负责：回复模式（语言表达/情景叙事）的设置

extends MarginContainer

var config_manager: Node
var response_buttons: Dictionary = {}
var typing_speed_seconds: float = 0.05
var _typing_preview_generation: int = 0
var _is_loading_typing_speed: bool = false
const TYPING_PREVIEW_TEXT = "这是一段示例文本，你可以拖动滑杆观察输出速度的变化。"

@onready var response_status_label = $VBoxContainer/ResponseStatusLabel
@onready var verbal_checkbox = $VBoxContainer/StylesHBox/VerbalContainer/VerbalCheckBox
@onready var narrative_checkbox = $VBoxContainer/StylesHBox/NarrativeContainer/NarrativeCheckBox
@onready var story_checkbox = $VBoxContainer/StylesHBox/StoryContainer/StoryCheckBox
@onready var expression_diff_checkbutton = $VBoxContainer/HBoxContainer/LeftContainer/ExpressionContainer/ExpressionDiffCheckButton
@onready var generation_options_checkbutton = $VBoxContainer/HBoxContainer/LeftContainer/GenerationContainer/GenerationOptionsCheckButton
@onready var top_input_checkbutton = $VBoxContainer/HBoxContainer/LeftContainer/TopInputContainer/TopInputCheckButton
@onready var call_trigger_dialog_checkbutton = $VBoxContainer/HBoxContainer/LeftContainer/CallTriggerContainer/CallTriggerDialogCheckButton
@onready var typing_speed_slider: HSlider = $VBoxContainer/HBoxContainer/RightContainer/HSlider
@onready var typing_speed_preview_text_edit: TextEdit = $VBoxContainer/HBoxContainer/RightContainer/TextEdit

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

func set_config_manager(cfg_mgr: Node) -> void:
	config_manager = cfg_mgr

func _ready() -> void:
	# 设置按钮组
	var button_group = ButtonGroup.new()
	verbal_checkbox.button_group = button_group
	narrative_checkbox.button_group = button_group
	story_checkbox.button_group = button_group
	
	# 存储按钮引用
	response_buttons["verbal"] = verbal_checkbox
	response_buttons["narrative"] = narrative_checkbox
	response_buttons["story"] = story_checkbox
	
	# 连接信号
	verbal_checkbox.toggled.connect(_on_response_mode_changed.bind("verbal"))
	narrative_checkbox.toggled.connect(_on_response_mode_changed.bind("narrative"))
	story_checkbox.toggled.connect(_on_response_mode_changed.bind("story"))
	expression_diff_checkbutton.toggled.connect(_on_expression_diff_toggled)
	generation_options_checkbutton.toggled.connect(_on_generation_options_toggled)
	top_input_checkbutton.toggled.connect(_on_top_input_toggled)
	call_trigger_dialog_checkbutton.toggled.connect(_on_call_trigger_dialog_toggled)
	typing_speed_slider.value_changed.connect(_on_typing_speed_slider_changed)
	
	# 加载设置
	if config_manager:
		load_response_settings()
	
	_restart_typing_speed_preview()

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
	
	# 加载文本输出速度设置
	_is_loading_typing_speed = true
	typing_speed_seconds = config_manager.load_typing_speed()
	typing_speed_slider.value = typing_speed_seconds
	_is_loading_typing_speed = false
	_apply_typing_speed_to_chat_dialog(typing_speed_seconds)
	_restart_typing_speed_preview()

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

func _on_typing_speed_slider_changed(value: float) -> void:
	typing_speed_seconds = clampf(value, 0.01, 0.09)
	if _is_loading_typing_speed:
		return
	
	config_manager.save_typing_speed(typing_speed_seconds)
	_apply_typing_speed_to_chat_dialog(typing_speed_seconds)
	# _restart_typing_speed_preview()

func _apply_typing_speed_to_chat_dialog(speed: float) -> void:
	var main_scene = get_tree().current_scene
	if main_scene == null:
		return
	var chat_dialog = main_scene.get_node_or_null("ChatDialog")
	if chat_dialog and chat_dialog.has_method("set_typing_speed"):
		chat_dialog.set_typing_speed(speed)

func _restart_typing_speed_preview() -> void:
	_typing_preview_generation += 1
	var generation = _typing_preview_generation
	_run_typing_speed_preview_loop(generation)

func _run_typing_speed_preview_loop(generation: int) -> void:
	if typing_speed_preview_text_edit == null:
		return
	
	while generation == _typing_preview_generation and is_inside_tree():
		typing_speed_preview_text_edit.text = ""
		for i in range(TYPING_PREVIEW_TEXT.length()):
			if generation != _typing_preview_generation or not is_inside_tree():
				return
			typing_speed_preview_text_edit.text += TYPING_PREVIEW_TEXT[i]
			await get_tree().create_timer(typing_speed_seconds).timeout
		
		if generation != _typing_preview_generation or not is_inside_tree():
			return
		await get_tree().create_timer(1.0).timeout
		if generation != _typing_preview_generation or not is_inside_tree():
			return
		typing_speed_preview_text_edit.text = ""
