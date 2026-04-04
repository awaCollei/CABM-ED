extends Control

## 开发者选项面板
## 用于开发者调试和测试功能

# UI节点引用
@onready var identity_text_edit: TextEdit = $MarginContainer/VBoxContainer/TabContainer/基础设定/ScrollContainer/VBoxContainer/IdentityTextEdit
@onready var user_name_line_edit: LineEdit = $MarginContainer/VBoxContainer/TabContainer/基础设定/ScrollContainer/VBoxContainer/UserNameLineEdit
@onready var character_name_line_edit: LineEdit = $MarginContainer/VBoxContainer/TabContainer/基础设定/ScrollContainer/VBoxContainer/CharacterNameLineEdit
@onready var uuid_line_edit: LineEdit = $MarginContainer/VBoxContainer/TabContainer/存档/ScrollContainer/VBoxContainer/UUIDLineEdit
@onready var save_status_label: Label = $MarginContainer/VBoxContainer/BottomPanel/SaveStatusLabel
@onready var save_button: Button = $MarginContainer/VBoxContainer/BottomPanel/SaveButton
@onready var back_button: Button = $MarginContainer/VBoxContainer/BottomPanel/BackButton
@onready var confirm_dialog: ConfirmationDialog = $ConfirmDialog
@onready var dont_save_button: Button = $ConfirmDialog/DontSaveButton

# 状态变量
var original_identity: String = ""
var original_uuid: String = ""
var original_user_name: String = ""
var original_character_name: String = ""
var has_unsaved_changes: bool = false

func _ready():
	# 连接按钮信号
	save_button.pressed.connect(_on_save_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	
	# 连接文本编辑信号
	identity_text_edit.text_changed.connect(_on_text_changed)
	uuid_line_edit.text_changed.connect(_on_uuid_changed)
	user_name_line_edit.text_changed.connect(_on_text_field_changed)
	character_name_line_edit.text_changed.connect(_on_text_field_changed)
	
	# 连接确认对话框信号
	confirm_dialog.confirmed.connect(_on_confirm_save)
	confirm_dialog.canceled.connect(_on_confirm_cancel)
	dont_save_button.pressed.connect(_on_dont_save)
	
	# 关闭窗口时触发取消
	confirm_dialog.close_requested.connect(_on_confirm_cancel)
	
	# 加载数据
	_load_identity_data()
	_load_uuid_data()
	_load_name_data()
	
	print("[DeveloperPanel] 开发者选项面板已加载")
	
	# 执行淡入动画
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.fade_in()

func _load_identity_data():
	"""从存档加载基础提示词"""
	var identity_loader = get_node_or_null("/root/CharacterIdentityLoader")
	if identity_loader:
		original_identity = identity_loader.get_identity()
		identity_text_edit.text = original_identity
	else:
		push_error("[DeveloperPanel] CharacterIdentityLoader未找到")
	_update_save_status()

func _load_uuid_data():
	"""从文件加载UUID"""
	var uuid_path = "user://uuid.txt"
	if FileAccess.file_exists(uuid_path):
		var file = FileAccess.open(uuid_path, FileAccess.READ)
		if file:
			original_uuid = file.get_as_text().strip_edges()
			uuid_line_edit.text = original_uuid
			file.close()
		else:
			push_error("[DeveloperPanel] 无法打开UUID文件")
	else:
		print("[DeveloperPanel] UUID文件不存在")
	_update_save_status()

func _load_name_data():
	"""从存档加载用户名和角色名"""
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		original_user_name = save_mgr.get_user_name()
		original_character_name = save_mgr.get_character_name()
		user_name_line_edit.text = original_user_name
		character_name_line_edit.text = original_character_name
	else:
		push_error("[DeveloperPanel] SaveManager未找到")
	_update_save_status()

func _on_text_changed():
	"""文本内容改变时"""
	_check_changes()

func _on_uuid_changed(_new_text: String):
	"""UUID改变时"""
	_check_changes()

func _on_text_field_changed(_new_text: String):
	"""单行文本字段改变时"""
	_check_changes()

func _check_changes():
	"""检查是否有未保存的更改"""
	var identity_changed = (identity_text_edit.text != original_identity)
	var uuid_changed = (uuid_line_edit.text != original_uuid)
	var user_name_changed = (user_name_line_edit.text != original_user_name)
	var character_name_changed = (character_name_line_edit.text != original_character_name)
	has_unsaved_changes = identity_changed or uuid_changed or user_name_changed or character_name_changed
	_update_save_status()

func _update_save_status():
	"""更新保存状态显示"""
	if has_unsaved_changes:
		save_status_label.text = "● 未保存"
		save_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		save_status_label.text = "● 已保存"
		save_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))

func _on_save_button_pressed():
	"""保存按钮按下"""
	_save_changes()

func _save_changes():
	"""保存更改"""
	# 保存基础提示词
	var identity_loader = get_node_or_null("/root/CharacterIdentityLoader")
	if identity_loader:
		var new_identity = identity_text_edit.text
		var current_relationship = identity_loader.get_relationship()
		identity_loader.set_identity(new_identity, current_relationship)
		original_identity = new_identity
	else:
		push_error("[DeveloperPanel] CharacterIdentityLoader未找到")
	
	# 保存UUID
	var uuid_path = "user://uuid.txt"
	var file = FileAccess.open(uuid_path, FileAccess.WRITE)
	if file:
		var new_uuid = uuid_line_edit.text
		file.store_string(new_uuid)
		file.close()
		original_uuid = new_uuid
		print("[DeveloperPanel] UUID已保存")
	else:
		push_error("[DeveloperPanel] 无法写入UUID文件")
	
	# 保存用户名和角色名
	var save_mgr2 = get_node_or_null("/root/SaveManager")
	if save_mgr2:
		save_mgr2.set_user_name(user_name_line_edit.text)
		save_mgr2.set_character_name(character_name_line_edit.text)
		original_user_name = user_name_line_edit.text
		original_character_name = character_name_line_edit.text
		save_mgr2.save_game()
	else:
		push_error("[DeveloperPanel] SaveManager未找到，无法保存用户名/角色名")
	
	# 更新状态
	has_unsaved_changes = false
	_update_save_status()
	
	print("[DeveloperPanel] 所有更改已保存")

func _on_back_button_pressed():
	"""返回按钮按下"""
	if has_unsaved_changes:
		# 显示确认对话框
		confirm_dialog.popup_centered()
	else:
		# 直接返回
		_return_to_main_menu()

func _on_confirm_save():
	"""确认对话框 - 保存"""
	confirm_dialog.hide()
	_save_changes()
	_return_to_main_menu()

func _on_dont_save():
	"""确认对话框 - 不保存"""
	confirm_dialog.hide()
	_return_to_main_menu()

func _on_confirm_cancel():
	"""确认对话框 - 取消"""
	confirm_dialog.hide()

func _return_to_main_menu():
	"""返回主菜单"""
	print("[DeveloperPanel] 返回主菜单")
	
	# 使用场景过渡管理器切换回主菜单
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		transition.change_scene_with_fade("res://scenes/main_menu.tscn")
	else:
		# 如果没有过渡管理器，直接切换
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
