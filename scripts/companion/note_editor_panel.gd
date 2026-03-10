extends Panel

# 笔记编辑面板
# 编辑单个笔记的标题和内容

signal panel_closed
signal note_saved(note_id: String)

@onready var back_button = $VBox/TopBar/BackButton
@onready var save_button = $VBox/TopBar/SaveButton
@onready var title_input = $VBox/TopBar/TitleInput
@onready var delete_button = $VBox/TopBar/DeleteButton
@onready var content_input = $VBox/ContentInput

var current_note_id: String = ""
var is_new_note: bool = false

func _ready():
	back_button.pressed.connect(_on_back_pressed)
	save_button.pressed.connect(_on_save_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	
	hide()

func show_panel_for_new_note():
	"""显示面板以创建新笔记"""
	is_new_note = true
	current_note_id = _generate_note_id()
	title_input.text = ""
	content_input.text = ""
	show()

func show_panel_for_note(note_id: String):
	"""显示面板以编辑现有笔记"""
	is_new_note = false
	current_note_id = note_id
	
	var note = _load_note(note_id)
	if note:
		title_input.text = note.get("title", "")
		content_input.text = note.get("content", "")
	else:
		title_input.text = ""
		content_input.text = ""
	
	show()

func _load_note(note_id: String) -> Dictionary:
	"""加载指定笔记"""
	var notes_path = "user://companion/notes.json"
	
	if not FileAccess.file_exists(notes_path):
		return {}
	
	var file = FileAccess.open(notes_path, FileAccess.READ)
	if not file:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK:
		return {}
	
	var data = json.data
	if not data is Array:
		return {}
	
	for note in data:
		if note.get("id", "") == note_id:
			return note
	
	return {}

func _on_back_pressed():
	"""返回（保存并返回）"""
	save_and_close()

func save_and_close():
	"""保存并关闭面板（触发返回列表）"""
	_save_note()
	hide()
	panel_closed.emit()

func save_and_close_without_return():
	"""保存并关闭面板（不触发返回列表）"""
	_save_note()
	hide()
	# 不发送 panel_closed 信号，避免返回列表

func _on_save_pressed():
	"""保存按钮"""
	_save_note()

func _save_note():
	"""保存笔记"""
	var notes_path = "user://companion/notes.json"
	
	# 确保目录存在
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("companion"):
		dir.make_dir("companion")
	
	# 加载现有笔记
	var notes_data: Array = []
	if FileAccess.file_exists(notes_path):
		var file = FileAccess.open(notes_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			var error = json.parse(json_string)
			if error == OK and json.data is Array:
				notes_data = json.data
	
	# 创建或更新笔记
	var note_data = {
		"id": current_note_id,
		"title": title_input.text if title_input.text != "" else "无标题",
		"content": content_input.text,
		"created_at": Time.get_unix_time_from_system(),
		"updated_at": Time.get_unix_time_from_system()
	}
	
	# 查找是否已存在
	var found = false
	for i in range(notes_data.size()):
		if notes_data[i].get("id", "") == current_note_id:
			note_data["created_at"] = notes_data[i].get("created_at", note_data["created_at"])
			notes_data[i] = note_data
			found = true
			break
	
	if not found:
		notes_data.append(note_data)
	
	# 保存到文件
	var file = FileAccess.open(notes_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(notes_data, "\t")
		file.store_string(json_string)
		file.close()
		print("笔记已保存: ", current_note_id)
		note_saved.emit(current_note_id)
	else:
		push_error("无法保存笔记文件")

func _on_delete_pressed():
	"""删除笔记"""
	# 显示确认对话框
	var dialog = ConfirmationDialog.new()
	dialog.title = "删除笔记"
	dialog.dialog_text = "确定要删除这条笔记吗？"
	dialog.ok_button_text = "删除"
	dialog.cancel_button_text = "取消"
	
	dialog.confirmed.connect(_delete_note)
	
	add_child(dialog)
	dialog.popup_centered()

func _delete_note():
	"""执行删除操作"""
	var notes_path = "user://companion/notes.json"
	
	if not FileAccess.file_exists(notes_path):
		hide()
		panel_closed.emit()
		return
	
	# 加载现有笔记
	var file = FileAccess.open(notes_path, FileAccess.READ)
	if not file:
		hide()
		panel_closed.emit()
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK or not json.data is Array:
		hide()
		panel_closed.emit()
		return
	
	var notes_data: Array = json.data
	
	# 删除指定笔记
	for i in range(notes_data.size()):
		if notes_data[i].get("id", "") == current_note_id:
			notes_data.remove_at(i)
			break
	
	# 保存回文件
	file = FileAccess.open(notes_path, FileAccess.WRITE)
	if file:
		json_string = JSON.stringify(notes_data, "\t")
		file.store_string(json_string)
		file.close()
		print("笔记已删除: ", current_note_id)
	
	hide()
	panel_closed.emit()

func _generate_note_id() -> String:
	"""生成唯一笔记ID"""
	return "note_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())
