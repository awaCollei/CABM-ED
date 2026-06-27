extends PanelContainer

# 厂商编辑对话框
# 支持新建和编辑厂商

signal provider_saved(provider_name: String, provider_data: Dictionary)
signal cancelled

@onready var title_label = $MarginContainer/VBoxContainer/TitleLabel
@onready var name_input = $MarginContainer/VBoxContainer/NameContainer/NameInput
@onready var url_input = $MarginContainer/VBoxContainer/URLContainer/URLInput
@onready var url_options = $MarginContainer/VBoxContainer/URLContainer/URLOptions
@onready var key_input = $MarginContainer/VBoxContainer/KeyContainer/KeyInput
@onready var status_label = $MarginContainer/VBoxContainer/StatusLabel
@onready var cancel_button = $MarginContainer/VBoxContainer/ButtonContainer/CancelButton
@onready var confirm_button = $MarginContainer/VBoxContainer/ButtonContainer/ConfirmButton

var edit_mode: bool = false
var original_name: String = ""
var existing_providers: Dictionary = {}

func _ready():
	cancel_button.pressed.connect(_on_cancel_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	url_options.item_selected.connect(_on_url_option_selected)

func setup_for_create(providers: Dictionary):
	"""设置为新建模式"""
	edit_mode = false
	original_name = ""
	existing_providers = providers
	title_label.text = "新建厂商"
	confirm_button.text = "创建"
	name_input.text = ""
	url_input.text = ""
	key_input.text = ""
	status_label.text = ""

func setup_for_edit(provider_name: String, provider_data: Dictionary, providers: Dictionary):
	"""设置为编辑模式"""
	edit_mode = true
	original_name = provider_name
	existing_providers = providers
	title_label.text = "编辑厂商"
	confirm_button.text = "保存"
	name_input.text = provider_name
	url_input.text = provider_data.get("base_url", "")
	key_input.text = provider_data.get("api_key", "")
	status_label.text = ""

func _on_cancel_pressed():
	cancelled.emit()
	queue_free()

func _on_confirm_pressed():
	var provider_name = name_input.text.strip_edges()
	var base_url = url_input.text.strip_edges()
	var api_key = key_input.text.strip_edges()
	
	# 验证
	if provider_name.is_empty():
		_show_status("请输入厂商名称", false)
		return
	
	# 检查名称唯一性（编辑时排除自己）
	if not edit_mode and existing_providers.has(provider_name):
		_show_status("厂商名称已存在", false)
		return
	
	if edit_mode and provider_name != original_name and existing_providers.has(provider_name):
		_show_status("厂商名称已存在", false)
		return
	
	if base_url.is_empty():
		_show_status("请输入URL", false)
		return
	
	# 构建厂商数据
	var provider_data = {
		"base_url": base_url,
		"api_key": api_key
	}
	
	provider_saved.emit(provider_name, provider_data)
	queue_free()

func _on_url_option_selected(index: int):
	var suffix = url_options.get_item_text(index)
	var base_url = url_input.text.strip_edges()
	
	# 如果URL已经有路径，先移除
	var existing_suffixes = ["/chat/completions", "/audio/speech", "/embeddings"]
	for existing_suffix in existing_suffixes:
		if base_url.ends_with(existing_suffix):
			base_url = base_url.substr(0, base_url.length() - existing_suffix.length())
			break
	
	# 添加新后缀
	if not suffix.is_empty():
		base_url += suffix
	
	url_input.text = base_url

func _show_status(message: String, success: bool):
	status_label.text = message
	status_label.add_theme_color_override("font_color",
		Color(0.3, 1.0, 0.3) if success else Color(1.0, 0.3, 0.3))