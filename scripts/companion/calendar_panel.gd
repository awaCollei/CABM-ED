extends Panel

# 日历面板 - 显示月历，可选择日期查看/编辑备忘

signal panel_closed

@onready var month_label = $VBox/Header/MonthLabel
@onready var prev_month_btn = $VBox/Header/PrevMonthBtn
@onready var next_month_btn = $VBox/Header/NextMonthBtn
@onready var close_btn = $VBox/Header/CloseBtn
@onready var calendar_grid = $VBox/CalendarGrid
@onready var memo_panel = $MemoPanel

# 当前显示的年月
var current_year: int
var current_month: int

# 日历数据文件路径
const CALENDAR_DATA_PATH = "user://companion/calendar.json"

# 日历数据 {日期字符串: {memo: 备忘内容}}
var calendar_data: Dictionary = {}

# 星期标题
const WEEKDAY_NAMES = ["日", "一", "二", "三", "四", "五", "六"]

func _ready():
	# 初始化为当前月份
	var time_dict = Time.get_datetime_dict_from_system()
	current_year = time_dict["year"]
	current_month = time_dict["month"]
	
	# 加载日历数据
	_load_calendar_data()
	
	# 连接信号
	prev_month_btn.pressed.connect(_on_prev_month_pressed)
	next_month_btn.pressed.connect(_on_next_month_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	
	# 连接备忘面板信号
	memo_panel.memo_saved.connect(_on_memo_saved)
	memo_panel.panel_closed.connect(_on_memo_panel_closed)
	
	# 初始隐藏备忘面板
	memo_panel.hide()

func show_panel():
	"""显示日历面板"""
	show()
	_refresh_calendar()

func _refresh_calendar():
	"""刷新日历显示"""
	# 更新月份标题
	month_label.text = "%d年%d月" % [current_year, current_month]
	
	# 清空现有日历格子
	for child in calendar_grid.get_children():
		child.queue_free()
	
	# 添加星期标题
	for weekday in WEEKDAY_NAMES:
		var label = Label.new()
		label.text = weekday
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(60, 40)
		label.add_theme_color_override("font_color", Color(0.2, 0.15, 0.1))  # 深棕色
		label.add_theme_font_size_override("font_size", 16)
		calendar_grid.add_child(label)
	
	# 获取本月第一天是星期几（0=周日）
	var first_day_weekday = _get_weekday(current_year, current_month, 1)
	
	# 获取本月天数
	var days_in_month = _get_days_in_month(current_year, current_month)
	
	# 填充空白（第一天之前）
	for i in range(first_day_weekday):
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(60, 60)
		calendar_grid.add_child(spacer)
	
	# 填充日期按钮
	for day in range(1, days_in_month + 1):
		var day_btn = Button.new()
		day_btn.text = str(day)
		day_btn.custom_minimum_size = Vector2(60, 60)
		
		# 检查是否有备忘
		var date_key = _get_date_key(current_year, current_month, day)
		if calendar_data.has(date_key) and calendar_data[date_key].has("memo") and calendar_data[date_key]["memo"] != "":
			# 有备忘的日期用不同颜色标记
			day_btn.modulate = Color(1.0, 0.9, 0.6)
		
		# 如果是今天，高亮显示
		var today = Time.get_datetime_dict_from_system()
		if current_year == today["year"] and current_month == today["month"] and day == today["day"]:
			day_btn.modulate = Color(0.6, 1.0, 0.6)
		
		day_btn.pressed.connect(_on_day_selected.bind(day))
		calendar_grid.add_child(day_btn)

func _on_day_selected(day: int):
	"""选择某一天"""
	var date_key = _get_date_key(current_year, current_month, day)
	
	# 获取该天的数据
	var day_data = calendar_data.get(date_key, {})
	var memo = day_data.get("memo", "")
	
	# 显示备忘面板
	memo_panel.show_for_date(current_year, current_month, day, memo)

func _on_prev_month_pressed():
	"""上一个月"""
	current_month -= 1
	if current_month < 1:
		current_month = 12
		current_year -= 1
	_refresh_calendar()

func _on_next_month_pressed():
	"""下一个月"""
	current_month += 1
	if current_month > 12:
		current_month = 1
		current_year += 1
	_refresh_calendar()

func _on_close_pressed():
	"""关闭面板"""
	# 先保存备忘面板的内容（如果正在显示）
	if memo_panel.visible:
		memo_panel.close_and_save()
	
	hide()
	panel_closed.emit()

func _on_memo_saved(year: int, month: int, day: int, memo_text: String):
	"""保存备忘"""
	var date_key = _get_date_key(year, month, day)
	
	if memo_text.strip_edges() == "":
		# 如果备忘为空，删除该条目
		calendar_data.erase(date_key)
	else:
		# 保存备忘
		calendar_data[date_key] = {"memo": memo_text}
	
	# 保存到文件
	_save_calendar_data()
	
	# 刷新日历显示
	_refresh_calendar()

func _on_memo_panel_closed():
	"""备忘面板关闭"""
	pass

func _load_calendar_data():
	"""从文件加载日历数据"""
	if not FileAccess.file_exists(CALENDAR_DATA_PATH):
		calendar_data = {}
		return
	
	var file = FileAccess.open(CALENDAR_DATA_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			calendar_data = json.data
			print("日历数据已加载: %d 条记录" % calendar_data.size())
		else:
			push_error("解析日历数据失败: " + json.get_error_message())
			calendar_data = {}
	else:
		push_error("无法打开日历数据文件")
		calendar_data = {}

func _save_calendar_data():
	"""保存日历数据到文件"""
	# 确保目录存在
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("companion"):
		dir.make_dir("companion")
	
	var file = FileAccess.open(CALENDAR_DATA_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(calendar_data, "\t")
		file.store_string(json_string)
		file.close()
		print("日历数据已保存")
	else:
		push_error("无法保存日历数据")

func _get_date_key(year: int, month: int, day: int) -> String:
	"""生成日期键"""
	return "%04d-%02d-%02d" % [year, month, day]

func _get_weekday(year: int, month: int, day: int) -> int:
	"""获取某日是星期几（0=周日，1=周一...6=周六）"""
	var date_dict = {
		"year": year,
		"month": month,
		"day": day
	}
	var unix_time = Time.get_unix_time_from_datetime_dict(date_dict)
	var datetime = Time.get_datetime_dict_from_unix_time(unix_time)
	return datetime["weekday"]

func _get_days_in_month(year: int, month: int) -> int:
	"""获取某月的天数"""
	var days_in_months = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	
	# 闰年2月有29天
	if month == 2 and _is_leap_year(year):
		return 29
	
	return days_in_months[month - 1]

func _is_leap_year(year: int) -> bool:
	"""判断是否为闰年"""
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)
