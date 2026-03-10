extends Control

# 计时器显示组件
# 圆盘样式，带指针和时间显示

signal pause_requested()
signal cancel_requested()

@onready var timer_node = $Timer
@onready var time_label = $CenterContainer/TimeLabel
@onready var name_label = $CenterContainer/NameLabel
@onready var action_button = $ActionButton
@onready var hide_action_timer = $HideActionTimer
@onready var blink_timer = $BlinkTimer

var total_duration: int = 0  # 总时长（秒）
var remaining_time: int = 0  # 剩余时间（秒）
var overtime: int = 0  # 超时时间（秒）
var timer_name: String = "计时器"
var is_paused: bool = false
var is_finished: bool = false
var is_blinking: bool = false

# 双击检测
var last_click_time: float = 0.0
const DOUBLE_CLICK_TIME: float = 0.3

# 圆盘绘制参数
var circle_radius: float = 60.0  # 放大圆盘
var circle_center: Vector2 = Vector2(70, 70)  # 调整中心点
var elapsed_color: Color = Color(0.3, 0.6, 0.9, 0.8)  # 已过时间颜色（正常状态）
var elapsed_color_paused: Color = Color(0.2, 0.8, 0.4, 0.8)  # 已过时间颜色（暂停状态-绿色）
var remaining_color: Color = Color(0.2, 0.2, 0.3, 0.6)  # 剩余时间颜色
var warning_color: Color = Color(0.9, 0.2, 0.2, 0.8)  # 警告颜色（<10%）
var border_color: Color = Color(0.8, 0.8, 0.8, 1.0)  # 边框颜色
var border_width: float = 2.0  # 边框宽度
var pointer_color: Color = Color.BLACK  # 指针颜色（正常状态）
var pointer_color_paused: Color = Color(0.5, 0.7, 0.9, 1.0)  # 指针颜色（暂停状态-淡蓝色）

func _ready():
	custom_minimum_size = Vector2(140, 140)  # 放大尺寸
	
	# 连接信号
	if timer_node:
		timer_node.timeout.connect(_on_timer_timeout)
	if action_button:
		action_button.pressed.connect(_on_action_button_pressed)
	if hide_action_timer:
		hide_action_timer.timeout.connect(_on_hide_action_timer_timeout)
	if blink_timer:
		blink_timer.timeout.connect(_on_blink_timer_timeout)
	
	# 初始隐藏操作按钮
	if action_button:
		action_button.hide()
	
	# 连接点击事件
	gui_input.connect(_on_gui_input)
	
	# 设置鼠标过滤，允许点击
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(duration: int, timer_name_param: String):
	"""设置计时器"""
	total_duration = duration
	remaining_time = duration
	overtime = 0
	timer_name = timer_name_param
	if name_label:
		name_label.text = timer_name_param
	
	_update_display()
	queue_redraw()
	
	# 开始计时
	if timer_node:
		timer_node.start()

func _on_timer_timeout():
	"""每秒更新"""
	if is_paused:
		return
	
	if not is_finished:
		# 正常倒计时
		remaining_time -= 1
		
		if remaining_time <= 0:
			remaining_time = 0
			is_finished = true
			_on_timer_finished()
	else:
		# 超时后正计时
		overtime += 1
	
	_update_display()
	queue_redraw()

func _update_display():
	"""更新时间显示"""
	if not time_label:
		return
	
	var display_time = remaining_time if not is_finished else overtime
	var hours = int(display_time / 3600)
	var minutes = int((display_time % 3600) / 60)
	var seconds = int(display_time % 60)
	
	# 根据时长选择显示格式
	if hours > 0:
		time_label.text = "%02d:%02d:%02d" % [hours, minutes, seconds]
	else:
		time_label.text = "%02d:%02d" % [minutes, seconds]
	
	# 数字始终为白色
	time_label.add_theme_color_override("font_color", Color.WHITE)

func _draw():
	"""绘制圆盘和指针"""
	if total_duration <= 0:
		return
	
	if is_finished:
		# 超时状态：绘制完整的红色圆盘，无指针
		draw_circle(circle_center, circle_radius, warning_color)
	else:
		# 正常倒计时状态
		var progress = float(remaining_time) / float(total_duration)
		var elapsed_progress = 1.0 - progress
		
		# 根据暂停状态选择颜色
		var current_elapsed_color = elapsed_color_paused if is_paused else elapsed_color
		var current_pointer_color = pointer_color_paused if is_paused else pointer_color
		
		if progress < 0.1 and not is_paused:
			current_elapsed_color = warning_color
		
		# 绘制剩余时间部分（灰色背景）
		draw_circle(circle_center, circle_radius, remaining_color)
		
		# 绘制已过时间部分（扇形）
		if elapsed_progress > 0:
			var start_angle = -PI / 2  # 从12点钟方向开始
			var end_angle = start_angle + elapsed_progress * TAU
			_draw_circle_arc(circle_center, circle_radius, start_angle, end_angle, current_elapsed_color)
		
		# 绘制指针（根据暂停状态选择颜色）
		var pointer_angle = -PI / 2 + elapsed_progress * TAU
		var pointer_end = circle_center + Vector2(cos(pointer_angle), sin(pointer_angle)) * (circle_radius - 5)
		draw_line(circle_center, pointer_end, current_pointer_color, 2.0)
		
		# 绘制中心圆点（根据暂停状态选择颜色）
		draw_circle(circle_center, 4.0, current_pointer_color)
	
	# 绘制边框
	draw_arc(circle_center, circle_radius, 0, TAU, 64, border_color, border_width, true)

func _draw_circle_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color):
	"""绘制圆弧扇形"""
	var points = PackedVector2Array()
	points.append(center)
	
	var num_segments = 32
	var angle_step = (end_angle - start_angle) / num_segments
	
	for i in range(num_segments + 1):
		var angle = start_angle + i * angle_step
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		points.append(point)
	
	draw_colored_polygon(points, color)

func _on_gui_input(event: InputEvent):
	"""处理点击事件"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var current_time = Time.get_ticks_msec() / 1000.0
		
		# 检测双击
		if current_time - last_click_time < DOUBLE_CLICK_TIME:
			# 双击：暂停/继续
			_toggle_pause()
			last_click_time = 0.0  # 重置，避免三击触发
		else:
			# 单击：显示操作按钮
			_show_action_button()
			last_click_time = current_time

func _toggle_pause():
	"""切换暂停/继续状态"""
	is_paused = !is_paused
	
	# 暂停时停止闪烁
	if is_paused and is_blinking:
		if blink_timer:
			blink_timer.stop()
		modulate.a = 1.0
	elif not is_paused and is_blinking:
		if blink_timer:
			blink_timer.start()
	
	# 重绘以更新颜色
	queue_redraw()
	
	pause_requested.emit()
	print("计时器 %s: %s" % [timer_name, "暂停" if is_paused else "继续"])

func _show_action_button():
	"""显示操作按钮"""
	if action_button:
		# 根据状态设置按钮文字
		if is_finished:
			action_button.text = "关
闭"
		else:
			action_button.text = "取
消"
		
		action_button.show()
	if hide_action_timer:
		hide_action_timer.start(3.0)  # 3秒后自动隐藏

func _on_hide_action_timer_timeout():
	"""隐藏操作按钮"""
	if action_button:
		action_button.hide()

func _on_action_button_pressed():
	"""操作按钮点击"""
	if is_finished:
		# 超时状态：关闭计时器
		cancel_requested.emit()
		queue_free()
	else:
		# 正常状态：取消计时器
		cancel_requested.emit()
		queue_free()

func _on_timer_finished():
	"""计时完成，开始闪烁和正计时"""
	print("计时器完成: ", timer_name)
	
	# 开始闪烁
	is_blinking = true
	if blink_timer:
		blink_timer.start()
	
	# 继续计时（正计时）
	overtime = 0
	# timer_node 继续运行

func _on_blink_timer_timeout():
	"""闪烁效果"""
	if not is_finished or not is_blinking:
		return
	
	# 切换可见性实现闪烁
	modulate.a = 0.3 if modulate.a > 0.5 else 1.0
