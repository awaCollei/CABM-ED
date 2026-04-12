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

func setup(book: Dictionary):
	current_book = book
	title_label.text = book.get("title", "")
	author_label.text = "作者：" + book.get("author", "")
	desc_label.text = book.get("description", "")

	title_label2.text = book.get("title", "")
	# 封面图
	var icon_path = book.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex = load(icon_path) as Texture2D
		cover_rect.texture = tex
		cover_rect.visible = true
	else:
		cover_rect.visible = false

	for child in chapter_list.get_children():
		child.queue_free()

	var chapters = book.get("chapters", [])
	for ch in chapters:
		var btn = Button.new()
		btn.text = ch.get("title", "第%d章" % ch.get("index", 1))
		btn.custom_minimum_size = Vector2(0, 45)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx = ch.get("index", 1)
		btn.pressed.connect(func(): chapter_selected.emit(current_book, idx))
		chapter_list.add_child(btn)
