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

func _create_book_card(book: Dictionary) -> Control:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(160, 240)
	btn.pressed.connect(func(): book_selected.emit(book))

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	btn.add_child(vbox)

	# 封面图
	var icon_path = book.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex = load(icon_path) as Texture2D
		if tex:
			var img = TextureRect.new()
			img.texture = tex
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.custom_minimum_size = Vector2(100, 130)
			img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vbox.add_child(img)

	# 书名
	var title_lbl = Label.new()
	title_lbl.text = book.get("title", "")
	title_lbl.custom_minimum_size=Vector2(160,40)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	title_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title_lbl)

	# 作者
	var author_lbl = Label.new()
	author_lbl.text = book.get("author", "")
	author_lbl.custom_minimum_size=Vector2(160,40)
	author_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	author_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	author_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	author_lbl.add_theme_font_size_override("font_size", 11)
	author_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(author_lbl)

	return btn
