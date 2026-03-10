extends Panel

# 备忘面板 - 显示和编辑某一天的备忘

signal memo_saved(year: int, month: int, day: int, memo_text: String)
signal panel_closed

@onready var date_label = $VBox/DateLabel
@onready var memo_text_edit = $VBox/MemoTextEdit
@onready var save_btn = $VBox/Buttons/SaveBtn

var current_year: int
var current_month: int
var current_day: int
var is_showing: bool = false

func _ready():
	# 连接信号
	save_btn.pressed.connect(_on_save_pressed)

func show_for_date(year: int, month: int, day: int, memo: String):
	"""显示指定日期的备忘"""
	# 如果当前正在显示其他日期，先保存
	if is_showing:
		_save_current_memo()
	
	current_year = year
	current_month = month
	current_day = day
	
	# 更新标题
	date_label.text = "%d年%d月%d日" % [year, month, day]
	
	# 加载备忘内容
	memo_text_edit.text = memo
	
	# 显示面板
	show()
	is_showing = true
	
	# 聚焦到文本框
	memo_text_edit.grab_focus()

func _on_save_pressed():
	"""保存备忘并关闭"""
	_save_current_memo()
	_close_panel()

func _save_current_memo():
	"""保存当前备忘内容"""
	if is_showing:
		var memo_text = memo_text_edit.text
		memo_saved.emit(current_year, current_month, current_day, memo_text)

func _close_panel():
	"""关闭面板"""
	is_showing = false
	hide()
	panel_closed.emit()

func close_and_save():
	"""外部调用：保存并关闭面板"""
	_save_current_memo()
	_close_panel()
