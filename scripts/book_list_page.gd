extends Control

# 第一页：书本列表

signal book_selected(book: Dictionary)
signal close_requested()

@onready var grid = $MarginContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var close_btn = $MarginContainer/VBoxContainer/TopBar/CloseButton

func _ready():
	close_btn.pressed.connect(func(): close_requested.emit())

func setup(books: Array):
	for child in grid.get_children():
		child.queue_free()
	for book in books:
		grid.add_child(_create_book_card(book))

func _format_author_short(authors) -> String:
	if authors is String:
		return authors
	if authors.size() == 0:
		return ""
	if authors.size() == 1:
		return authors[0]
	if authors.size() == 2:
		return authors[0] + " & " + authors[1]
	return authors[0] + " et al."

func _create_book_card(book: Dictionary) -> Control:
	# 使用按钮作为主容器，这样悬停效果才能正常工作
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(180, 260)
	btn.pressed.connect(func(): book_selected.emit(book))
	
	# 普通状态样式
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.18, 1)
	normal_style.corner_radius_top_left = 12
	normal_style.corner_radius_top_right = 12
	normal_style.corner_radius_bottom_left = 12
	normal_style.corner_radius_bottom_right = 12
	normal_style.shadow_color = Color(0, 0, 0, 0.3)
	normal_style.shadow_size = 3
	normal_style.shadow_offset = Vector2(3, 3)
	normal_style.border_width_left = 2
	normal_style.border_width_top = 2
	normal_style.border_width_right = 2
	normal_style.border_width_bottom = 2
	normal_style.border_color = Color(0.3, 0.3, 0.35, 0.5)
	btn.add_theme_stylebox_override("normal", normal_style)
	
	# 悬停状态样式
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.2, 0.25, 0.3, 1)  # 更亮的背景
	hover_style.corner_radius_top_left = 12
	hover_style.corner_radius_top_right = 12
	hover_style.corner_radius_bottom_left = 12
	hover_style.corner_radius_bottom_right = 12
	hover_style.shadow_color = Color(0, 0, 0, 0.5)
	hover_style.shadow_size = 5
	hover_style.shadow_offset = Vector2(5, 5)
	hover_style.border_width_left = 2
	hover_style.border_width_top = 2
	hover_style.border_width_right = 2
	hover_style.border_width_bottom = 2
	hover_style.border_color = Color(0.4, 0.5, 0.6, 0.8)  # 更亮的边框
	btn.add_theme_stylebox_override("hover", hover_style)
	
	# 按下状态样式
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.18, 0.22, 0.28, 1)
	pressed_style.corner_radius_top_left = 12
	pressed_style.corner_radius_top_right = 12
	pressed_style.corner_radius_bottom_left = 12
	pressed_style.corner_radius_bottom_right = 12
	pressed_style.shadow_color = Color(0, 0, 0, 0.2)
	pressed_style.shadow_size = 4
	pressed_style.shadow_offset = Vector2(0, 2)
	pressed_style.border_width_left = 2
	pressed_style.border_width_top = 2
	pressed_style.border_width_right = 2
	pressed_style.border_width_bottom = 2
	pressed_style.border_color = Color(0.35, 0.4, 0.5, 0.7)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	btn.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# 封面图容器（带边框和阴影）
	var icon_path = book.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex = load(icon_path) as Texture2D
		if tex:
			var img_container = PanelContainer.new()
			img_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
			var img_style = StyleBoxFlat.new()
			img_style.bg_color = Color(0.1, 0.1, 0.12, 1)
			img_style.corner_radius_top_left = 8
			img_style.corner_radius_top_right = 8
			img_style.corner_radius_bottom_left = 8
			img_style.corner_radius_bottom_right = 8
			img_style.border_width_left = 1
			img_style.border_width_top = 1
			img_style.border_width_right = 1
			img_style.border_width_bottom = 1
			img_style.border_color = Color(0.4, 0.4, 0.45, 0.6)
			img_container.add_theme_stylebox_override("panel", img_style)
			
			var img = TextureRect.new()
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
			img.texture = tex
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.custom_minimum_size = Vector2(120, 140)
			img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			img_container.add_child(img)
			vbox.add_child(img_container)

	# 书名（带渐变效果）
	var title_lbl = Label.new()
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
	title_lbl.text = book.get("title", "")
	title_lbl.custom_minimum_size = Vector2(156, 0)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	title_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1, 1))
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	title_lbl.add_theme_constant_override("outline_size", 2)
	vbox.add_child(title_lbl)

	# 作者（更柔和的颜色）
	var author_lbl = Label.new()
	author_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 让鼠标事件穿透
	author_lbl.text = _format_author_short(book.get("author", []))
	author_lbl.custom_minimum_size = Vector2(156, 0)
	author_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	author_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	author_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	author_lbl.add_theme_font_size_override("font_size", 12)
	author_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 0.9))
	vbox.add_child(author_lbl)

	return btn
