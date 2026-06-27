extends PanelContainer

# 模型编辑对话框
# 支持新建和编辑模型

signal model_saved(model_name: String, model_data: Dictionary)
signal cancelled

@onready var title_label = $MarginContainer/VBoxContainer/TitleLabel
@onready var name_input = $MarginContainer/VBoxContainer/NameContainer/NameInput
@onready var provider_option = $MarginContainer/VBoxContainer/ProviderContainer/ProviderOption
@onready var identifier_input = $MarginContainer/VBoxContainer/IdentifierContainer/IdentifierInput
@onready var params_input = $MarginContainer/VBoxContainer/ParamsContainer/ParamsInput
@onready var params_status = $MarginContainer/VBoxContainer/ParamsContainer/ParamsStatus
@onready var status_label = $MarginContainer/VBoxContainer/StatusLabel
@onready var cancel_button = $MarginContainer/VBoxContainer/ButtonContainer/CancelButton
@onready var confirm_button = $MarginContainer/VBoxContainer/ButtonContainer/ConfirmButton

var edit_mode: bool = false
var original_name: String = ""
var existing_models: Dictionary = {}
var providers: Dictionary = {}

func _ready():
	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	params_input.text_changed.connect(_on_params_changed)

func setup_for_create(providers_data: Dictionary, models: Dictionary):
	"""设置为新建模式"""
	edit_mode = false
	original_name = ""
	existing_models = models
	providers = providers_data
	title_label.text = "新建模型"
	confirm_button.text = "创建"
	name_input.text = ""
	identifier_input.text = ""
	params_input.text = ""
	status_label.text = ""
	_update_provider_options()

func setup_for_edit(model_name: String, model_data: Dictionary, providers_data: Dictionary, models: Dictionary):
	"""设置为编辑模式"""
	edit_mode = true
	original_name = model_name
	existing_models = models
	providers = providers_data
	title_label.text = "编辑模型"
	confirm_button.text = "保存"
	name_input.text = model_name
	identifier_input.text = model_data.get("identifier", "")
	
	# 设置参数
	var params = model_data.get("params", {})
	if not params.is_empty():
		params_input.text = JSON.stringify(params, "\t")
	else:
		params_input.text = ""
	
	status_label.text = ""
	_update_provider_options()
	
	# 选择对应的提供商
	var provider_name = model_data.get("provider", "")
	for i in range(provider_option.item_count):
		if provider_option.get_item_text(i) == provider_name:
			provider_option.selected = i
			break

func _update_provider_options():
	"""更新提供商下拉选项"""
	provider_option.clear()
	provider_option.add_item("选择厂商")
	
	var provider_names = providers.keys()
	provider_names.sort()
	for provider_name in provider_names:
		provider_option.add_item(provider_name)

func _on_cancel_pressed():
	cancelled.emit()
	queue_free()

func _on_confirm_pressed():
	var model_name = name_input.text.strip_edges()
	var provider_name = provider_option.get_item_text(provider_option.selected)
	var identifier = identifier_input.text.strip_edges()
	var params_text = params_input.text.strip_edges()
	
	# 验证
	if model_name.is_empty():
		_show_status("请输入模型名称", false)
		return
	
	# 检查名称唯一性（编辑时排除自己）
	if not edit_mode and existing_models.has(model_name):
		_show_status("模型名称已存在", false)
		return
	
	if edit_mode and model_name != original_name and existing_models.has(model_name):
		_show_status("模型名称已存在", false)
		return
	
	if provider_name == "选择厂商":
		_show_status("请选择提供商", false)
		return
	
	if identifier.is_empty():
		_show_status("请输入模型标识符", false)
		return
	
	# 解析参数JSON
	var params = {}
	if not params_text.is_empty():
		var json = JSON.new()
		if json.parse(params_text) != OK:
			_show_status("参数JSON格式错误", false)
			return
		params = json.data
	
	# 构建模型数据
	var model_data = {
		"provider": provider_name,
		"identifier": identifier,
		"params": params
	}
	
	model_saved.emit(model_name, model_data)
	queue_free()

func _on_params_changed():
	"""实时检查JSON格式"""
	var params_text = params_input.text.strip_edges()
	if params_text.is_empty():
		params_status.text = ""
		return
	
	var json = JSON.new()
	if json.parse(params_text) == OK:
		params_status.text = "✓ JSON格式正确"
		params_status.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		params_status.text = "✗ JSON格式错误"
		params_status.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

func _show_status(message: String, success: bool):
	status_label.text = message
	status_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3) if success else Color(1.0, 0.3, 0.3))