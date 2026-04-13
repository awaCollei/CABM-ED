extends Control

# 第三页：正文阅读

signal back_requested()

@onready var chapter_label = $MarginContainer/VBoxContainer/TopBar/ChapterLabel
@onready var book_title_label = $MarginContainer/VBoxContainer/TopBar/BookTitleLabel
@onready var back_btn = $MarginContainer/VBoxContainer/TopBar/BackButton
@onready var content_label = $MarginContainer/VBoxContainer/ScrollContainer/ContentLabel
@onready var prev_btn = $MarginContainer/VBoxContainer/NavBar/PrevButton
@onready var next_btn = $MarginContainer/VBoxContainer/NavBar/NextButton
@onready var page_label = $MarginContainer/VBoxContainer/NavBar/PageLabel
@onready var decrease_btn = $FontSizeControl/DecreaseButton
@onready var increase_btn = $FontSizeControl/IncreaseButton

var current_book: Dictionary = {}
var current_index: int = 1
var total_chapters: int = 1
var font_size: int = 17  # 默认字体大小
const MIN_FONT_SIZE: int = 12
const MAX_FONT_SIZE: int = 32

func _ready():
	back_btn.pressed.connect(func(): back_requested.emit())
	prev_btn.pressed.connect(_on_prev)
	next_btn.pressed.connect(_on_next)
	decrease_btn.pressed.connect(_on_decrease_font)
	increase_btn.pressed.connect(_on_increase_font)
	_update_font_size()

func setup(book: Dictionary, chapter_index: int):
	current_book = book
	current_index = chapter_index
	total_chapters = book.get("chapters", []).size()
	
	# 显示书名
	book_title_label.text = book.get("title", "")
	
	_load_chapter(chapter_index)

func _load_chapter(index: int):
	current_index = index
	var book_id = current_book.get("id", "")
	var path = "res://config/books/%s/%d.txt" % [book_id, index]

	var chapters = current_book.get("chapters", [])
	var ch_title = "第%d章" % index
	for ch in chapters:
		if ch.get("index", 0) == index:
			ch_title = ch.get("title", ch_title)
			break

	chapter_label.text = ch_title

	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		content_label.text = file.get_as_text()
		file.close()
	else:
		content_label.text = "（本章内容暂未收录）"

	page_label.text = "%d / %d" % [current_index, total_chapters]
	prev_btn.disabled = (current_index <= 1)
	next_btn.disabled = (current_index >= total_chapters)

	# 滚动到顶部
	await get_tree().process_frame
	var scroll = $MarginContainer/VBoxContainer/ScrollContainer
	scroll.scroll_vertical = 0

func _on_prev():
	if current_index > 1:
		_load_chapter(current_index - 1)

func _on_next():
	if current_index < total_chapters:
		_load_chapter(current_index + 1)

func _on_decrease_font():
	if font_size > MIN_FONT_SIZE:
		font_size -= 2
		_update_font_size()

func _on_increase_font():
	if font_size < MAX_FONT_SIZE:
		font_size += 2
		_update_font_size()

func _update_font_size():
	content_label.add_theme_font_size_override("normal_font_size", font_size)
	decrease_btn.disabled = (font_size <= MIN_FONT_SIZE)
	increase_btn.disabled = (font_size >= MAX_FONT_SIZE)
