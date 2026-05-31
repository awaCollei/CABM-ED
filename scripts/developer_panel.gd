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

# 记忆检索节点引用
@onready var memory_query_line_edit: LineEdit = $MarginContainer/VBoxContainer/TabContainer/记忆检索/VBoxContainer/SearchHBox/MemoryQueryLineEdit
@onready var memory_search_button: Button = $MarginContainer/VBoxContainer/TabContainer/记忆检索/VBoxContainer/SearchHBox/MemorySearchButton
@onready var memory_status_label: Label = $MarginContainer/VBoxContainer/TabContainer/记忆检索/VBoxContainer/MemoryStatusLabel
@onready var memory_results_container: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/记忆检索/VBoxContainer/MemoryResultsScroll/MemoryResultsContainer

# 日记生成节点引用
@onready var rules_list: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/日记生成/ScrollContainer/VBoxContainer/RulesContainer/RulesList
@onready var add_rule_button: Button = $MarginContainer/VBoxContainer/TabContainer/日记生成/ScrollContainer/VBoxContainer/AddRuleButton

# 状态变量
var original_identity: String = ""
var original_uuid: String = ""
var original_user_name: String = ""
var original_character_name: String = ""
var has_unsaved_changes: bool = false
var diary_rules: Array = []
var original_diary_rules: Array = []

func _ready():
	# 连接按钮信号
	save_button.pressed.connect(_on_save_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	memory_search_button.pressed.connect(_on_memory_search_pressed)
	memory_query_line_edit.text_submitted.connect(_on_memory_query_submitted)
	add_rule_button.pressed.connect(_on_add_rule_pressed)
	
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
	_load_diary_rules()
	
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
	var rules_changed = not _diary_rules_equal(diary_rules, original_diary_rules)
	has_unsaved_changes = identity_changed or uuid_changed or user_name_changed or character_name_changed or rules_changed
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
	
	_save_diary_rules_to_data()
	
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

# ---- 记忆检索 ----

func _on_memory_query_submitted(text: String):
	_start_memory_search(text)

func _on_memory_search_pressed():
	_start_memory_search(memory_query_line_edit.text)

func _start_memory_search(query: String):
	query = query.strip_edges()
	if query.is_empty():
		memory_status_label.text = "请输入查询词"
		return
	memory_search_button.disabled = true
	memory_status_label.text = "检索中..."
	_clear_memory_results()
	_do_memory_search(query)

func _do_memory_search(query: String):
	var memory_mgr = get_node_or_null("/root/MemoryManager")
	if not memory_mgr:
		memory_status_label.text = "✗ MemoryManager 未找到"
		memory_search_button.disabled = false
		return

	# 等待记忆系统就绪
	if not memory_mgr.is_initialized:
		memory_status_label.text = "等待记忆系统就绪..."
		await memory_mgr.memory_system_ready

	var memory_system = memory_mgr.memory_system
	if not memory_system:
		memory_status_label.text = "✗ memory_system 未找到"
		memory_search_button.disabled = false
		return

	var results = await memory_system.search(query, 10, 0.3)
	memory_search_button.disabled = false

	if results.is_empty():
		memory_status_label.text = "未找到相关记忆"
		return

	memory_status_label.text = "找到 %d 条结果" % results.size()
	_show_memory_results(results)

func _clear_memory_results():
	for child in memory_results_container.get_children():
		child.queue_free()

func _show_memory_results(results: Array):
	for result in results:
		var panel = PanelContainer.new()
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		panel.add_child(vbox)

		# 相似度 + 时间戳
		var meta_label = Label.new()
		var ts = result.get("timestamp", "")
		var sim = result.get("similarity", 0.0)
		meta_label.text = "[相似度：%.1f%%]  %s" % [sim*100, ts]
		meta_label.add_theme_font_size_override("font_size", 16)
		meta_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		vbox.add_child(meta_label)

		# 正文
		var text_label = Label.new()
		text_label.text = result.get("text", "")
		text_label.add_theme_font_size_override("font_size", 20)
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(text_label)

		memory_results_container.add_child(panel)

# ---- 日记生成规则 ----

const DEFAULT_DIARY_RULES: Array = [
	{"min_seconds": 0, "max_seconds": 300, "min_count": 0, "max_count": 0},
	{"min_seconds": 300, "max_seconds": 10800, "min_count": 0, "max_count": 2},
	{"min_seconds": 10800, "max_seconds": 86400, "min_count": 3, "max_count": 5},
	{"min_seconds": 86400, "max_seconds": -1, "min_count": 6, "max_count": 10}
]

func _load_diary_rules():
	"""从存档加载日记生成规则"""
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr and save_mgr.save_data.has("diary_generation_rules"):
		diary_rules = save_mgr.save_data.diary_generation_rules.duplicate(true)
	else:
		diary_rules = DEFAULT_DIARY_RULES.duplicate(true)
	original_diary_rules = _clone_rules(diary_rules)
	_rebuild_rules_ui()

func _clone_rules(rules: Array) -> Array:
	var result = []
	for rule in rules:
		result.append(rule.duplicate())
	return result

func _diary_rules_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var ra = a[i]
		var rb = b[i]
		for key in ra.keys():
			if not rb.has(key) or ra[key] != rb[key]:
				return false
		for key in rb.keys():
			if not ra.has(key):
				return false
	return true

func _save_diary_rules_to_data():
	"""将日记生成规则保存到存档"""
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		save_mgr.save_data.diary_generation_rules = _clone_rules(diary_rules)
		original_diary_rules = _clone_rules(diary_rules)
		save_mgr.save_game()
		print("[DeveloperPanel] 日记生成规则已保存")

func _rebuild_rules_ui():
	"""重建规则列表UI"""
	for child in rules_list.get_children():
		child.queue_free()
	await get_tree().process_frame
	for i in range(diary_rules.size()):
		_create_rule_row(i, diary_rules[i])

func _create_rule_row(index: int, rule: Dictionary):
	"""创建一行规则UI"""
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	rules_list.add_child(hbox)

	var min_time_spin = SpinBox.new()
	min_time_spin.custom_minimum_size = Vector2(0, 40)
	min_time_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	min_time_spin.min_value = 0
	min_time_spin.max_value = 999999
	min_time_spin.step = 1
	min_time_spin.value = rule.get("min_seconds", 0)
	min_time_spin.add_theme_font_size_override("font_size", 20)
	min_time_spin.value_changed.connect(_on_rule_min_time_changed.bind(index))
	hbox.add_child(min_time_spin)

	var max_time_spin = SpinBox.new()
	max_time_spin.custom_minimum_size = Vector2(0, 40)
	max_time_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_time_spin.min_value = -1
	max_time_spin.max_value = 999999
	max_time_spin.step = 1
	max_time_spin.value = rule.get("max_seconds", -1)
	max_time_spin.add_theme_font_size_override("font_size", 20)
	max_time_spin.value_changed.connect(_on_rule_max_time_changed.bind(index))
	hbox.add_child(max_time_spin)

	var min_count_spin = SpinBox.new()
	min_count_spin.custom_minimum_size = Vector2(0, 40)
	min_count_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	min_count_spin.min_value = 0
	min_count_spin.max_value = 999
	min_count_spin.step = 1
	min_count_spin.value = rule.get("min_count", 0)
	min_count_spin.add_theme_font_size_override("font_size", 20)
	min_count_spin.value_changed.connect(_on_rule_min_count_changed.bind(index))
	hbox.add_child(min_count_spin)

	var max_count_spin = SpinBox.new()
	max_count_spin.custom_minimum_size = Vector2(0, 40)
	max_count_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_count_spin.min_value = 0
	max_count_spin.max_value = 999
	max_count_spin.step = 1
	max_count_spin.value = rule.get("max_count", 0)
	max_count_spin.add_theme_font_size_override("font_size", 20)
	max_count_spin.value_changed.connect(_on_rule_max_count_changed.bind(index))
	hbox.add_child(max_count_spin)

	var remove_btn = Button.new()
	remove_btn.custom_minimum_size = Vector2(60, 40)
	remove_btn.text = "-"
	remove_btn.add_theme_font_size_override("font_size", 24)
	remove_btn.pressed.connect(_on_remove_rule_pressed.bind(index))
	hbox.add_child(remove_btn)

func _on_rule_min_time_changed(value: float, index: int):
	diary_rules[index].min_seconds = int(value)
	_check_changes()

func _on_rule_max_time_changed(value: float, index: int):
	diary_rules[index].max_seconds = int(value)
	_check_changes()

func _on_rule_min_count_changed(value: float, index: int):
	diary_rules[index].min_count = int(value)
	_check_changes()

func _on_rule_max_count_changed(value: float, index: int):
	diary_rules[index].max_count = int(value)
	_check_changes()

func _on_add_rule_pressed():
	"""添加新规则"""
	var last = diary_rules.back() if not diary_rules.is_empty() else null
	var new_min = 0
	if last:
		new_min = last.max_seconds if last.max_seconds > 0 else last.min_seconds + 3600
	diary_rules.append({"min_seconds": new_min, "max_seconds": new_min + 3600, "min_count": 1, "max_count": 3})
	_rebuild_rules_ui()
	_check_changes()

func _on_remove_rule_pressed(index: int):
	"""移除规则"""
	if diary_rules.size() <= 1:
		return
	diary_rules.remove_at(index)
	_rebuild_rules_ui()
	_check_changes()
