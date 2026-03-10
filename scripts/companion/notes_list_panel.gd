extends Panel

# 笔记列表面板
# 显示笔记卡片，支持翻页和新建

signal panel_closed
signal note_selected(note_id: String)
signal new_note_requested

const NOTES_PER_PAGE = 5
const CARD_HEIGHT = 100

@onready var prev_button = $VBox/TopBar/PrevButton
@onready var page_input = $VBox/TopBar/PageInput
@onready var next_button = $VBox/TopBar/NextButton
@onready var new_note_button = $VBox/TopBar/NewNoteButton
@onready var close_button = $VBox/TopBar/CloseButton
@onready var cards_container = $VBox/ScrollContainer/CardsContainer

var notes_data: Array = []  # 所有笔记数据
var current_page: int = 1
var total_pages: int = 1

func _ready():
	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	new_note_button.pressed.connect(_on_new_note_pressed)
	close_button.pressed.connect(_on_close_pressed)
	page_input.text_changed.connect(_on_page_input_changed)
	
	hide()

func show_panel():
	"""显示面板并加载笔记"""
	_load_notes()
	_update_display()
	show()

func _load_notes():
	"""从文件加载笔记数据"""
	var notes_path = "user://companion/notes.json"
	
	if not FileAccess.file_exists(notes_path):
		notes_data = []
		return
	
	var file = FileAccess.open(notes_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		
		if error == OK:
			var data = json.data
			if data is Array:
				notes_data = data
			else:
				notes_data = []
		else:
			print("解析笔记JSON失败: ", json.get_error_message())
			notes_data = []
	else:
		notes_data = []
	
	# 按创建时间倒序排列（最新的在前）
	notes_data.sort_custom(func(a, b): return a.get("created_at", 0) > b.get("created_at", 0))

func _update_display():
	"""更新显示内容"""
	# 计算总页数
	total_pages = max(1, ceili(float(notes_data.size()) / NOTES_PER_PAGE))
	current_page = clampi(current_page, 1, total_pages)
	
	print("笔记列表更新: 共%d条笔记, 第%d/%d页" % [notes_data.size(), current_page, total_pages])
	
	# 更新页码输入框
	page_input.text = str(current_page)
	
	# 更新按钮状态
	prev_button.disabled = (current_page <= 1)
	next_button.disabled = (current_page >= total_pages)
	
	# 清空现有卡片
	for child in cards_container.get_children():
		child.queue_free()
	
	# 显示当前页的笔记卡片
	var start_idx = (current_page - 1) * NOTES_PER_PAGE
	var end_idx = mini(start_idx + NOTES_PER_PAGE, notes_data.size())
	
	print("显示笔记索引: %d 到 %d" % [start_idx, end_idx])
	
	if notes_data.size() == 0:
		# 如果没有笔记，显示提示
		var hint_label = Label.new()
		hint_label.text = "还没有笔记，点击\"新建笔记\"开始记录吧！"
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint_label.add_theme_font_size_override("font_size", 16)
		hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		cards_container.add_child(hint_label)
	else:
		for i in range(start_idx, end_idx):
			var note = notes_data[i]
			_create_note_card(note)

func _create_note_card(note: Dictionary):
	"""创建笔记卡片"""
	# 使用按钮作为基础，这样整个卡片都可以点击
	var button = Button.new()
	button.custom_minimum_size = Vector2(0, CARD_HEIGHT)
	button.flat = false
	button.pressed.connect(_on_card_clicked.bind(note.get("id", "")))
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_FILL
	vbox.size_flags_vertical = Control.SIZE_FILL
	margin.add_child(vbox)
	
	# 标题
	var title_label = Label.new()
	title_label.text = note.get("title", "无标题")
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.size_flags_horizontal = Control.SIZE_FILL
	vbox.add_child(title_label)
	
	# 内容预览
	var content = note.get("content", "")
	var content_label = Label.new()
	content_label.text = content
	content_label.add_theme_font_size_override("font_size", 14)
	content_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content_label.clip_text = true
	content_label.max_lines_visible = 2
	content_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_label.size_flags_horizontal = Control.SIZE_FILL
	content_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_label)
	
	cards_container.add_child(button)

func _on_card_clicked(note_id: String):
	"""卡片被点击"""
	print("笔记卡片被点击: ", note_id)
	note_selected.emit(note_id)

func _on_prev_pressed():
	"""上一页"""
	if current_page > 1:
		current_page -= 1
		_update_display()

func _on_next_pressed():
	"""下一页"""
	if current_page < total_pages:
		current_page += 1
		_update_display()

func _on_page_input_changed(new_text: String):
	"""页码输入框变化"""
	if new_text.is_valid_int():
		var page = new_text.to_int()
		if page >= 1 and page <= total_pages and page != current_page:
			current_page = page
			_update_display()

func _on_new_note_pressed():
	"""新建笔记"""
	new_note_requested.emit()

func _on_close_pressed():
	"""关闭面板"""
	hide()
	panel_closed.emit()
