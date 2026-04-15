extends Control

# 第二页：书本目录（左右布局）

signal chapter_selected(book: Dictionary, chapter_index: int)
signal back_requested()

@onready var title_label = $MarginContainer/VBoxContainer/TopBar/TitleLabel
@onready var back_btn = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var author_label = $MarginContainer/VBoxContainer/HBoxContainer/LeftPanel/AuthorLabel
@onready var desc_label = $MarginContainer/VBoxContainer/HBoxContainer/LeftPanel/DescLabel
@onready var cover_rect = $MarginContainer/VBoxContainer/HBoxContainer/LeftPanel/CoverRect
@onready var title_label2 = $MarginContainer/VBoxContainer/HBoxContainer/LeftPanel/TitleLabel
@onready var chapter_list = $MarginContainer/VBoxContainer/HBoxContainer/RightPanel/ScrollContainer/ChapterList

var current_book: Dictionary = {}

func _ready():
	back_btn.pressed.connect(func(): back_requested.emit())

func _format_author_full(authors) -> String:
	if authors is String:
		return authors
	if authors.size() == 0:
		return ""
	return "、".join(authors)

func setup(book: Dictionary):
	current_book = book
	title_label.text = book.get("title", "")
	author_label.text = "作者：" + _format_author_full(book.get("author", []))
	desc_label.text = book.get("description", "")

	title_label2.text = book.get("title", "")
	
	# 封面图（带样式）
	var icon_path = book.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex = load(icon_path) as Texture2D
		cover_rect.texture = tex
		cover_rect.visible = true
		
		# 为封面添加边框效果
		if not cover_rect.has_theme_stylebox_override("panel"):
			var cover_style = StyleBoxFlat.new()
			cover_style.bg_color = Color(0.1, 0.1, 0.12, 1)
			cover_style.corner_radius_top_left = 10
			cover_style.corner_radius_top_right = 10
			cover_style.corner_radius_bottom_left = 10
			cover_style.corner_radius_bottom_right = 10
			cover_style.border_width_left = 2
			cover_style.border_width_top = 2
			cover_style.border_width_right = 2
			cover_style.border_width_bottom = 2
			cover_style.border_color = Color(0.4, 0.4, 0.5, 0.7)
			cover_style.shadow_color = Color(0, 0, 0, 0.4)
			cover_style.shadow_size = 10
			cover_style.shadow_offset = Vector2(0, 5)
	else:
		cover_rect.visible = false

	for child in chapter_list.get_children():
		child.queue_free()

	var chapters = book.get("chapters", [])
	for i in range(chapters.size()):
		var ch = chapters[i]
		var chapter_card = _create_chapter_card(ch, i)
		chapter_list.add_child(chapter_card)

func _create_chapter_card(chapter: Dictionary, index: int) -> Control:
	# 使用按钮作为主容器
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 60)
	
	# 普通状态样式
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.12, 0.15, 1)
	normal_style.corner_radius_top_left = 8
	normal_style.corner_radius_top_right = 8
	normal_style.corner_radius_bottom_left = 8
	normal_style.corner_radius_bottom_right = 8
	normal_style.border_width_left = 1
	normal_style.border_width_top = 1
	normal_style.border_width_right = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = Color(0.25, 0.25, 0.3, 0.5)
	normal_style.shadow_color = Color(0, 0, 0, 0.2)
	normal_style.shadow_size = 4
	normal_style.shadow_offset = Vector2(0, 2)
	btn.add_theme_stylebox_override("normal", normal_style)
	
	# 悬停状态样式
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.18, 0.22, 0.28, 1)  # 更亮的背景
	hover_style.corner_radius_top_left = 8
	hover_style.corner_radius_top_right = 8
	hover_style.corner_radius_bottom_left = 8
	hover_style.corner_radius_bottom_right = 8
	hover_style.border_width_left = 2
	hover_style.border_width_top = 2
	hover_style.border_width_right = 2
	hover_style.border_width_bottom = 2
	hover_style.border_color = Color(0.4, 0.5, 0.6, 0.8)  # 更亮的边框
	hover_style.shadow_color = Color(0, 0, 0, 0.3)
	hover_style.shadow_size = 6
	hover_style.shadow_offset = Vector2(0, 3)
	btn.add_theme_stylebox_override("hover", hover_style)
	
	# 按下状态样式
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.15, 0.18, 0.22, 1)
	pressed_style.corner_radius_top_left = 8
	pressed_style.corner_radius_top_right = 8
	pressed_style.corner_radius_bottom_left = 8
	pressed_style.corner_radius_bottom_right = 8
	pressed_style.border_width_left = 2
	pressed_style.border_width_top = 2
	pressed_style.border_width_right = 2
	pressed_style.border_width_bottom = 2
	pressed_style.border_color = Color(0.3, 0.4, 0.5, 0.7)
	pressed_style.shadow_color = Color(0, 0, 0, 0.1)
	pressed_style.shadow_size = 2
	pressed_style.shadow_offset = Vector2(0, 1)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	
	var idx = chapter.get("index", 1)
	btn.pressed.connect(func(): chapter_selected.emit(current_book, idx))
	
	# 内容容器
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	btn.add_child(margin)
	
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)
	
	# 章节序号（带圆形背景）
	var number_panel = PanelContainer.new()
	number_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
	var number_style = StyleBoxFlat.new()
	number_style.bg_color = Color(0.3, 0.4, 0.6, 0.8)
	number_style.corner_radius_top_left = 20
	number_style.corner_radius_top_right = 20
	number_style.corner_radius_bottom_left = 20
	number_style.corner_radius_bottom_right = 20
	number_panel.add_theme_stylebox_override("panel", number_style)
	number_panel.custom_minimum_size = Vector2(40, 40)
	
	var number_label = Label.new()
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
	number_label.text = str(index + 1)
	number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_label.add_theme_font_size_override("font_size", 18)
	number_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	number_panel.add_child(number_label)
	hbox.add_child(number_panel)
	
	# 章节标题
	var chapter_title_label = Label.new()
	chapter_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
	chapter_title_label.text = chapter.get("title", "第%d章" % idx)
	chapter_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chapter_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chapter_title_label.add_theme_font_size_override("font_size", 24)
	chapter_title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	hbox.add_child(chapter_title_label)
	
	return btn
