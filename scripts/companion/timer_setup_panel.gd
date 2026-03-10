extends Panel

# 计时器设置面板
# 提供预设选项和自定义时间选择

signal timer_started(duration: int, timer_name: String)
signal panel_closed()

@onready var preset_container = $MarginContainer/VBoxContainer/PresetContainer
@onready var custom_container = $MarginContainer/VBoxContainer/CustomContainer
@onready var hour_spinbox = $MarginContainer/VBoxContainer/CustomContainer/TimeSelector/HourSpinBox
@onready var minute_spinbox = $MarginContainer/VBoxContainer/CustomContainer/TimeSelector/MinuteSpinBox
@onready var second_spinbox = $MarginContainer/VBoxContainer/CustomContainer/TimeSelector/SecondSpinBox
@onready var name_input = $MarginContainer/VBoxContainer/NameContainer/NameInput
@onready var start_button = $MarginContainer/VBoxContainer/ButtonContainer/StartButton
@onready var cancel_button = $MarginContainer/VBoxContainer/ButtonContainer/CancelButton

# 预设时间（秒）
var presets = [
	{"name": "5分钟", "duration": 300},
	{"name": "15分钟", "duration": 900},
	{"name": "25分钟", "duration": 1500},  # 番茄钟
	{"name": "30分钟", "duration": 1800},
	{"name": "45分钟", "duration": 2700},
	{"name": "1小时", "duration": 3600}
]

func _ready():
	# 创建预设按钮
	_create_preset_buttons()
	
	# 设置默认名称
	name_input.text = "计时器"
	
	# 连接信号
	start_button.pressed.connect(_on_start_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)
	
	# 设置SpinBox范围
	hour_spinbox.min_value = 0
	hour_spinbox.max_value = 23
	minute_spinbox.min_value = 0
	minute_spinbox.max_value = 59
	second_spinbox.min_value = 0
	second_spinbox.max_value = 59

func _create_preset_buttons():
	"""创建预设时间按钮"""
	for preset in presets:
		var button = Button.new()
		button.text = preset["name"]
		button.custom_minimum_size = Vector2(100, 40)
		button.pressed.connect(_on_preset_selected.bind(preset["duration"]))
		preset_container.add_child(button)

func _on_preset_selected(duration: int):
	"""选择预设时间"""
	var hours = int(duration / 3600)
	var minutes = int((duration % 3600) / 60)
	var seconds = int(duration % 60)
	
	hour_spinbox.value = hours
	minute_spinbox.value = minutes
	second_spinbox.value = seconds

func _on_start_button_pressed():
	"""开始计时"""
	var total_seconds = int(hour_spinbox.value) * 3600 + int(minute_spinbox.value) * 60 + int(second_spinbox.value)
	
	if total_seconds <= 0:
		push_warning("计时时间必须大于0")
		return
	
	var timer_name = name_input.text.strip_edges()
	if timer_name == "":
		timer_name = "计时器"
	
	timer_started.emit(total_seconds, timer_name)
	hide()

func _on_cancel_button_pressed():
	"""取消"""
	panel_closed.emit()
	hide()

func show_panel():
	"""显示面板"""
	show()
	
	# 重置为默认值
	hour_spinbox.value = 0
	minute_spinbox.value = 5
	second_spinbox.value = 0
	name_input.text = "计时器"
