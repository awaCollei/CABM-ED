extends Control

# 信号
signal story_created
signal story_edited
signal story_deleted
signal creation_cancelled

# 编辑模式：非空时表示正在编辑
var editing_story_id: String = ""

# UI节点引用
@onready var back_button: Button = $Panel/VBoxContainer/TopBar/BackButton
@onready var keyword_input: LineEdit = $Panel/VBoxContainer/Content/KeywordSection/KeywordInput
@onready var generate_button: Button = $Panel/VBoxContainer/Content/KeywordSection/GenerateButton
@onready var user_role_input: LineEdit = $Panel/VBoxContainer/Content/CharacterSection/UserRoleContainer/UserRoleInput
@onready var character_role_input: LineEdit = $Panel/VBoxContainer/Content/CharacterSection/CharacterRoleContainer/CharacterRoleInput
@onready var title_input: LineEdit = $Panel/VBoxContainer/Content/TitleSection/TitleInput
@onready var summary_input: TextEdit = $Panel/VBoxContainer/Content/SummarySection/SummaryInput
@onready var temperature_slider: HSlider = $Panel/VBoxContainer/Content/OptionsSection/LeftOptions/TemperatureRow/TemperatureSlider
@onready var temperature_input: LineEdit = $Panel/VBoxContainer/Content/OptionsSection/LeftOptions/TemperatureRow/TemperatureInput
@onready var background_thumbnail: TextureRect = $Panel/VBoxContainer/Content/OptionsSection/RightOptions/BackgroundRow/BackgroundThumbnail
@onready var create_button: Button = $Panel/VBoxContainer/BottomBar/CreateButton
@onready var keyword_section: HBoxContainer = $Panel/VBoxContainer/Content/KeywordSection
@onready var edit_hint_section: HBoxContainer = $Panel/VBoxContainer/Content/EditHintSection
@onready var title_label: Label = $Panel/VBoxContainer/TopBar/TitleLabel

# 删除确认对话框
var _delete_confirmation_dialog: ConfirmationDialog = null

# AI生成器
var ai_generator: Node = null

# 待保存的背景图路径（用户选择后，创建故事时复制到 user://story/background/<story_id>.png）
var pending_background_source_path: String = ""
var _background_file_dialog: FileDialog = null

func _ready():
	"""初始化"""
	# 初始化AI生成器
	_initialize_ai_generator()
	
	# 更新角色标签
	_update_character_labels()

	# 温度：滑杆与输入框同步
	_sync_temperature_ui()
	temperature_slider.value_changed.connect(_on_temperature_slider_changed)
	temperature_input.text_submitted.connect(_on_temperature_input_submitted)
	temperature_input.focus_exited.connect(_on_temperature_input_focus_exited)

func _update_character_labels():
	"""更新角色标签为实际角色名"""
	var save_mgr = get_node("/root/SaveManager")
	var character_name = save_mgr.get_character_name()
	
	# 更新角色身份标签
	var character_role_label_node = $Panel/VBoxContainer/Content/CharacterSection/CharacterRoleContainer/CharacterRoleLabel
	if character_role_label_node:
		character_role_label_node.text = character_name + "的身份："
	
	# 更新输入框占位符
	if user_role_input:
		user_role_input.placeholder_text = "你在故事中的身份（可留空）"
	
	if character_role_input:
		character_role_input.placeholder_text = character_name + "在故事中的身份（可留空）"

func _initialize_ai_generator():
	"""初始化AI生成器"""
	ai_generator = preload("res://scripts/story/story_ai_generator.gd").new()
	add_child(ai_generator)
	ai_generator.set_story_creation_panel(self)

	# 连接AI生成器信号
	ai_generator.generation_started.connect(_on_generation_started)
	ai_generator.generation_completed.connect(_on_generation_completed)
	ai_generator.generation_error.connect(_on_generation_error)

func show_panel():
	"""显示面板（创建模式）"""
	editing_story_id = ""
	_apply_create_mode_ui()
	visible = true
	# 清空输入框
	keyword_input.text = ""
	user_role_input.text = ""
	character_role_input.text = ""
	title_input.text = ""
	summary_input.text = ""
	# 温度默认 1.2
	temperature_slider.value = 1.2
	_sync_temperature_ui()
	# 清除背景选择
	pending_background_source_path = ""
	background_thumbnail.texture = null

func show_panel_for_edit(story_id: String):
	"""显示面板（编辑模式）"""
	editing_story_id = story_id
	_apply_edit_mode_ui()

	var story_data = _load_story_data(story_id)
	if story_data.is_empty():
		push_error("无法加载故事: " + story_id)
		creation_cancelled.emit()
		return

	# 填充表单
	title_input.text = story_data.get("story_title", "")
	summary_input.text = story_data.get("story_summary", "")
	user_role_input.text = story_data.get("user_role", "")
	character_role_input.text = story_data.get("character_role", "")
	var temp = story_data.get("temperature", 1.2)
	temperature_slider.value = clampf(float(temp), 0.0, 2.0)
	_sync_temperature_ui()

	# 背景图（仅显示，不设置 pending，用户选择新图时再设置）
	pending_background_source_path = ""
	var bg_path = story_data.get("background_path", "")
	if not bg_path.is_empty():
		var full_path = "user://story/background/" + bg_path
		if FileAccess.file_exists(full_path):
			var img = Image.new()
			if img.load(full_path) == OK:
				background_thumbnail.texture = ImageTexture.create_from_image(img)
	else:
		background_thumbnail.texture = null

	visible = true

func _apply_create_mode_ui():
	"""应用创建模式UI"""
	if keyword_section:
		keyword_section.visible = true
	if edit_hint_section:
		edit_hint_section.visible = false
	if title_label:
		title_label.text = "创建故事"
	if create_button:
		create_button.text = "创建故事"

func _apply_edit_mode_ui():
	"""应用编辑模式UI"""
	if keyword_section:
		keyword_section.visible = false
	if edit_hint_section:
		edit_hint_section.visible = true
	if title_label:
		title_label.text = "编辑故事"
	if create_button:
		create_button.text = "保存修改"

func _load_story_data(story_id: String) -> Dictionary:
	"""加载故事数据"""
	var file_path = "user://story/" + story_id + ".json"
	if not FileAccess.file_exists(file_path):
		return {}
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	return json.data

func hide_panel():
	"""隐藏面板"""
	visible = false

func _get_temperature() -> float:
	"""从滑杆或输入框获取温度，钳制在 0.0～2.0，默认 1.2"""
	var t = 1.2
	var s = temperature_input.text.strip_edges()
	if s.is_valid_float():
		t = clampf(float(s), 0.0, 2.0)
	else:
		t = clampf(temperature_slider.value, 0.0, 2.0)
	return t

func _sync_temperature_ui():
	"""用滑杆数值同步输入框"""
	temperature_input.text = "%.1f" % temperature_slider.value

func _on_temperature_slider_changed(_value: float):
	_sync_temperature_ui()

func _on_temperature_input_submitted(_new_text: String):
	var t = _get_temperature()
	temperature_slider.value = t
	temperature_input.text = "%.1f" % t

func _on_temperature_input_focus_exited():
	var t = _get_temperature()
	temperature_slider.value = t
	temperature_input.text = "%.1f" % t

func _on_background_upload_pressed():
	"""打开文件选择器选择背景图（Android 下先请求存储权限）"""
	_show_background_file_dialog()

func _show_background_file_dialog():
	"""先请求权限（仅 Android），再弹出图片选择器"""
	if OS.has_feature("android"):
		var ap = get_node_or_null("/root/AndroidPermissions")
		if ap:
			await ap.request_storage_permission()
	if _background_file_dialog != null:
		_background_file_dialog.queue_free()
	_background_file_dialog = FileDialog.new()
	_background_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_background_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_background_file_dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp;图片")
	_background_file_dialog.file_selected.connect(_on_background_file_selected)
	_background_file_dialog.canceled.connect(_on_background_file_dialog_canceled)
	_background_file_dialog.use_native_dialog = true
	if OS.has_feature("android"):
		var pics_paths = [
			"/storage/emulated/0/Pictures",
			"/storage/emulated/0/DCIM/Camera",
			"/storage/emulated/0/Download",
			OS.get_system_dir(OS.SYSTEM_DIR_PICTURES),
			OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		]
		for p in pics_paths:
			if p and not p.is_empty() and DirAccess.dir_exists_absolute(p):
				_background_file_dialog.current_dir = p
				break
	else:
		var pics_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		if not pics_dir.is_empty():
			_background_file_dialog.current_dir = pics_dir
	get_tree().root.add_child(_background_file_dialog)
	_background_file_dialog.popup_centered()

func _on_background_file_selected(path: String):
	"""用户选择了背景图：保存路径并显示缩略图（Android content:// 会先复制到 user://）"""
	var path_to_use := path
	if OS.has_feature("android") and path.begins_with("content://"):
		var tmp_path = "user://tmp/story_bg_%s.png" % Time.get_unix_time_from_system()
		var ap = get_node_or_null("/root/AndroidPermissions")
		if ap and ap.copy_content_uri_to_user_file(path, tmp_path):
			path_to_use = tmp_path
		else:
			push_error("无法复制 content:// 图片")
			_on_background_file_dialog_canceled()
			return
	pending_background_source_path = path_to_use
	var img = Image.new()
	var err = img.load(path_to_use)
	if err != OK:
		push_error("无法加载图片: " + path_to_use)
		pending_background_source_path = ""
		_on_background_file_dialog_canceled()
		return
	var tex = ImageTexture.create_from_image(img)
	background_thumbnail.texture = tex
	_on_background_file_dialog_canceled()

func _on_background_file_dialog_canceled():
	if _background_file_dialog:
		_background_file_dialog.queue_free()
		_background_file_dialog = null

func _on_back_pressed():
	"""返回按钮点击"""
	creation_cancelled.emit()

func _on_delete_story_pressed():
	"""编辑模式下的删除故事按钮"""
	if editing_story_id.is_empty():
		return
	_show_delete_confirmation_dialog()

func _show_delete_confirmation_dialog():
	"""显示删除确认对话框，默认选中"取消"（手滑了）"""
	if _delete_confirmation_dialog:
		_delete_confirmation_dialog.queue_free()

	_delete_confirmation_dialog = ConfirmationDialog.new()
	_delete_confirmation_dialog.title = "确认删除"
	var story_data = _load_story_data(editing_story_id)
	var title = story_data.get("story_title", "未知标题")
	_delete_confirmation_dialog.dialog_text = "确定要删除故事 \"" + title + "\" 吗？\n\n此操作无法撤销！"
	_delete_confirmation_dialog.ok_button_text = "确认删除"
	_delete_confirmation_dialog.cancel_button_text = "手滑了"

	get_tree().root.add_child(_delete_confirmation_dialog)
	_delete_confirmation_dialog.confirmed.connect(_on_delete_confirmed)
	_delete_confirmation_dialog.canceled.connect(_on_delete_canceled)
	# 默认焦点在"取消"上，避免误触
	_delete_confirmation_dialog.about_to_popup.connect(_focus_cancel_button)

	_delete_confirmation_dialog.popup_centered(Vector2(400, 150))

func _focus_cancel_button():
	"""将焦点放到取消按钮上"""
	var cancel_btn = _delete_confirmation_dialog.get_cancel_button()
	if cancel_btn:
		cancel_btn.call_deferred("grab_focus")

func _on_delete_confirmed():
	"""确认删除故事"""
	if editing_story_id.is_empty():
		_cleanup_delete_dialog()
		return

	var file_path = "user://story/" + editing_story_id + ".json"
	if FileAccess.file_exists(file_path):
		var err = DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
		if err != OK:
			print("删除故事文件失败: ", file_path)
			_cleanup_delete_dialog()
			return

	# 删除背景图（如存在）
	var bg_path = "user://story/background/" + editing_story_id + ".png"
	if FileAccess.file_exists(bg_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bg_path))

	_cleanup_delete_dialog()
	print("故事已删除: ", editing_story_id)
	story_deleted.emit()

func _on_delete_canceled():
	"""取消删除"""
	_cleanup_delete_dialog()

func _cleanup_delete_dialog():
	if _delete_confirmation_dialog:
		_delete_confirmation_dialog.queue_free()
		_delete_confirmation_dialog = null

func _on_generate_pressed():
	"""生成故事按钮点击"""
	var keyword = keyword_input.text.strip_edges()

	# 检查关键词是否为空
	if keyword.is_empty():
		print("关键词为空，将生成随机故事")
	else:
		print("生成故事，关键词：", keyword)

	# 使用AI生成器生成故事
	if ai_generator:
		ai_generator.generate_story_from_keywords(keyword)
	else:
		print("错误：AI生成器未初始化")
		_on_generation_error("AI生成器初始化失败")

func _on_create_pressed():
	"""创建/保存按钮点击"""
	var title = title_input.text.strip_edges()
	var summary = summary_input.text.strip_edges()

	# 验证输入
	if title.is_empty():
		print("错误：故事标题不能为空")
		return

	if summary.is_empty():
		print("错误：故事简介不能为空")
		return

	if not editing_story_id.is_empty():
		# 编辑模式：仅更新呈现字段，不修改 nodes
		if _update_story(editing_story_id, title, summary):
			story_edited.emit()
		else:
			print("保存故事失败")
	else:
		# 创建模式
		if _create_story(title, summary):
			story_created.emit()
		else:
			print("创建故事失败")

func _create_story(title: String, summary: String) -> bool:
	"""创建故事文件"""
	# 确保故事目录存在
	var story_dir = DirAccess.open("user://")
	if not story_dir.dir_exists("story"):
		story_dir.make_dir("story")

	# 生成故事ID
	var story_id = _generate_story_id(title)
	if story_id.is_empty():
		return false

	# 获取当前时间戳
	var current_time = Time.get_datetime_dict_from_system()
	var timestamp = "%04d-%02d-%02dT%02d:%02d:%02d" % [
		current_time.year, current_time.month, current_time.day,
		current_time.hour, current_time.minute, current_time.second
	]

	# 获取人物设定
	var user_role = user_role_input.text.strip_edges()
	var character_role = character_role_input.text.strip_edges()

	# 温度与背景：保存到故事数据，背景图复制到 user://story/background/<story_id>.png
	var temperature = _get_temperature()
	var background_filename := ""
	if not pending_background_source_path.is_empty():
		var story_access = DirAccess.open("user://story")
		if story_access:
			if not story_access.dir_exists("background"):
				story_access.make_dir("background")
		var dest_path = "user://story/background/" + story_id + ".png"
		if _copy_file(pending_background_source_path, dest_path):
			background_filename = story_id + ".png"

	# 创建故事数据
	var story_data = {
		"story_id": story_id,
		"story_title": title,
		"story_summary": summary,
		"user_role": user_role,
		"character_role": character_role,
		"temperature": temperature,
		"root_node": "start",
		"last_played_at": timestamp,
		"nodes": {
			"start": {
				"display_text": summary,
				"child_nodes": []
			}
		}
	}
	if not background_filename.is_empty():
		story_data["background_path"] = background_filename

	# 保存到文件
	var file_path = "user://story/" + story_id + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		print("无法创建故事文件: ", file_path)
		return false

	var json_string = JSON.stringify(story_data, "\t")
	file.store_string(json_string)
	file.close()

	print("故事创建成功: ", story_id)
	return true

func _update_story(story_id: String, title: String, summary: String) -> bool:
	"""更新故事：仅修改标题、简介、身份、温度、背景图，不修改 nodes"""
	var story_data = _load_story_data(story_id)
	if story_data.is_empty():
		return false

	# 只更新呈现字段
	story_data["story_title"] = title
	story_data["story_summary"] = summary
	story_data["user_role"] = user_role_input.text.strip_edges()
	story_data["character_role"] = character_role_input.text.strip_edges()
	story_data["temperature"] = _get_temperature()

	# 背景图：用户选择了新图则复制
	if not pending_background_source_path.is_empty():
		var story_access = DirAccess.open("user://story")
		if story_access:
			if not story_access.dir_exists("background"):
				story_access.make_dir("background")
		var dest_path = "user://story/background/" + story_id + ".png"
		if _copy_file(pending_background_source_path, dest_path):
			story_data["background_path"] = story_id + ".png"
	# 若无新选择则保留原 background_path（已在 story_data 中）

	var file_path = "user://story/" + story_id + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		print("无法写入故事文件: ", file_path)
		return false
	file.store_string(JSON.stringify(story_data, "\t"))
	file.close()
	print("故事已更新: ", story_id)
	return true

func _generate_story_id(title: String) -> String:
	"""生成故事ID（时间戳+标题哈希，带冲突检查）"""
	var timestamp = str(Time.get_unix_time_from_system())
	var title_hash = title.hash()
	var base_id = timestamp + str(title_hash).substr(0, 6)  # 取哈希前6位

	# 检查冲突，如果冲突则递增
	var story_id = base_id
	var counter = 1
	while _story_id_exists(story_id):
		story_id = base_id + str(counter)
		counter += 1
		if counter > 1000:  # 防止无限循环
			print("无法生成唯一的故事ID")
			return ""

	return story_id

func _story_id_exists(story_id: String) -> bool:
	"""检查故事ID是否已存在"""
	var file_path = "user://story/" + story_id + ".json"
	return FileAccess.file_exists(file_path)

func _copy_file(src: String, dest: String) -> bool:
	"""复制文件，用于将用户选择的背景图复制到 user://story/background/"""
	var f_in = FileAccess.open(src, FileAccess.READ)
	if f_in == null:
		return false
	var buf = f_in.get_buffer(f_in.get_length())
	f_in.close()
	var f_out = FileAccess.open(dest, FileAccess.WRITE)
	if f_out == null:
		return false
	f_out.store_buffer(buf)
	f_out.close()
	return true

# AI生成器信号处理

func _on_generation_started():
	"""AI生成开始"""
	print("开始生成故事...")
	# 按钮状态已在AI生成器中处理

func _on_generation_completed(title: String, summary: String):
	"""AI生成完成"""
	print("故事生成完成")
	print("标题：", title)
	print("简介：", summary)

func _on_generation_error(error_message: String):
	"""AI生成错误"""
	print("故事生成失败：", error_message)
	# 错误信息已在AI生成器中显示到UI
