extends Control

# 第二页：书本目录

signal chapter_selected(book: Dictionary, chapter_index: int)
signal back_requested()

@onready var title_label = $MarginContainer/VBoxContainer/TopBar/TitleLabel
@onready var back_btn = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var author_label = $MarginContainer/VBoxContainer/AuthorLabel
@onready var desc_label = $MarginContainer/VBoxContainer/DescLabel
@onready var chapter_list = $MarginContainer/VBoxContainer/ScrollContainer/ChapterList

var current_book: Dictionary = {}
var _cover_rect: TextureRect = null

func _ready():
	back_btn.pressed.connect(func(): back_requested.emit())

func setup(book: Dictionary):
	current_book = book
	title_label.text = book.get("title", "")
	author_label.text = "作者：" + book.get("author", "")
	desc_label.text = book.get("description", "")

	# 封面图
	var vbox = $MarginContainer/VBoxContainer
	if _cover_rect:
		_cover_rect.queue_free()
		_cover_rect = null
	var icon_path = book.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex = load(icon_path) as Texture2D
		if tex:
			_cover_rect = TextureRect.new()
			_cover_rect.texture = tex
			_cover_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_cover_rect.custom_minimum_size = Vector2(80, 110)
			_cover_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_cover_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			# 插到 TopBar 之后（index 1）
			vbox.add_child(_cover_rect)
			vbox.move_child(_cover_rect, 1)

	for child in chapter_list.get_children():
		child.queue_free()

	var chapters = book.get("chapters", [])
	for ch in chapters:
		var btn = Button.new()
		btn.text = ch.get("title", "第%d章" % ch.get("index", 1))
		btn.custom_minimum_size=Vector2(0,45)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx = ch.get("index", 1)
		btn.pressed.connect(func(): chapter_selected.emit(current_book, idx))
		chapter_list.add_child(btn)
