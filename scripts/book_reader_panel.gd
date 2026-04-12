extends Control

# 图书阅览面板 - 管理三个子页面：选书、目录、正文

signal panel_closed()

# 三个子页面
@onready var book_list_page = $BookListPage
@onready var book_toc_page = $BookTocPage
@onready var book_content_page = $BookContentPage

var books_config: Array = []
var current_book: Dictionary = {}

func _ready():
	_load_books_config()
	# 连接子页面信号
	book_list_page.book_selected.connect(show_book_toc)
	book_list_page.close_requested.connect(close_panel)
	book_toc_page.chapter_selected.connect(show_book_content)
	book_toc_page.back_requested.connect(_show_book_list)
	book_content_page.back_requested.connect(func(): show_book_toc(current_book))
	hide()

func _load_books_config():
	var path = "res://config/books.json"
	if not FileAccess.file_exists(path):
		push_error("books.json 不存在")
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		books_config = json.data.get("books", [])
	file.close()

func open_panel():
	show()
	_show_book_list()
	if has_node("/root/UIManager"):
		get_node("/root/UIManager").disable_all()

func close_panel():
	hide()
	panel_closed.emit()
	if has_node("/root/UIManager"):
		get_node("/root/UIManager").enable_all()

func _show_book_list():
	book_list_page.show()
	book_toc_page.hide()
	book_content_page.hide()
	book_list_page.setup(books_config)

func show_book_toc(book: Dictionary):
	current_book = book
	book_list_page.hide()
	book_toc_page.show()
	book_content_page.hide()
	book_toc_page.setup(book)

func show_book_content(book: Dictionary, chapter_index: int):
	book_list_page.hide()
	book_toc_page.hide()
	book_content_page.show()
	book_content_page.setup(book, chapter_index)
