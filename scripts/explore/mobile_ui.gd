extends Control
class_name MobileUI

# 移动端UI - 包含摇杆和射击/换弹控制

@onready var joystick: VirtualJoystick = $VirtualJoystick
@onready var shoot_area: Control = $ShootArea
@onready var shoot_area2: Control = $ShootArea2
@onready var reload_area: Control = $ReloadArea
@onready var chat_button: Button = $ChatButton

@onready var auto_aim_area: Control = $AutoAimArea
@onready var switch_target_area: Control = $SwitchTargetArea
@onready var auto_aim_bg: Panel = $AutoAimArea/Background
@onready var switch_target_bg: Panel = $SwitchTargetArea/Background
@onready var auto_aim_label: Label = $AutoAimArea/AutoAimLabel

# 按钮背景面板引用
@onready var shoot_bg: Panel = $ShootArea/Background
@onready var shoot_bg2: Panel = $ShootArea2/Background
@onready var reload_bg: Panel = $ReloadArea/Background

# 触摸追踪
var shoot_touches: Dictionary = {}  # touch_index -> true
var reload_touch_index: int = -1
var auto_aim_touch_index: int = -1
var switch_touch_index: int = -1

signal shoot_started()
signal shoot_stopped()
signal reload_pressed()
signal chat_button_pressed()

signal auto_aim_toggled(enabled: bool)
signal switch_target_pressed()

var is_shooting: bool = false
var auto_aim_enabled: bool = true

func _ready():
	# 只在移动设备上显示
	visible = PlatformManager.is_mobile_platform()
	
	# 存储原始样式
	_store_original_styles()
	
	# 连接聊天按钮
	if chat_button:
		chat_button.pressed.connect(_on_chat_button_pressed)

	# 初始化自动瞄准按钮文本
	_update_auto_aim_label()

func get_joystick() -> VirtualJoystick:
	"""获取摇杆引用"""
	return joystick

func set_auto_aim_enabled(enabled: bool):
	"""由外部设置自动瞄准开关（用于初始化/同步存档）"""
	auto_aim_enabled = enabled
	_update_auto_aim_label()

func _input(event: InputEvent):
	if not visible:
		return
	
	if event is InputEventScreenTouch:
		var touch_pos = event.position
		
		if event.pressed:
			# 检查射击区域1
			if shoot_area and _is_point_in_control(touch_pos, shoot_area):
				shoot_touches[event.index] = true
				_apply_press_feedback(shoot_bg)
				if not is_shooting:
					is_shooting = true
					shoot_started.emit()
				get_viewport().set_input_as_handled()
			
			# 检查射击区域2
			elif shoot_area2 and _is_point_in_control(touch_pos, shoot_area2):
				shoot_touches[event.index] = true
				_apply_press_feedback(shoot_bg2)
				if not is_shooting:
					is_shooting = true
					shoot_started.emit()
				get_viewport().set_input_as_handled()
			
			# 检查换弹区域
			elif reload_area and _is_point_in_control(touch_pos, reload_area):
				reload_touch_index = event.index
				_apply_press_feedback(reload_bg)
				reload_pressed.emit()
				get_viewport().set_input_as_handled()
			
			# 检查自动瞄准区域（点击即切换开关）
			elif auto_aim_area and _is_point_in_control(touch_pos, auto_aim_area):
				auto_aim_touch_index = event.index
				_apply_press_feedback(auto_aim_bg)
				auto_aim_enabled = not auto_aim_enabled
				_update_auto_aim_label()
				auto_aim_toggled.emit(auto_aim_enabled)
				get_viewport().set_input_as_handled()

			# 检查切换目标区域
			elif switch_target_area and _is_point_in_control(touch_pos, switch_target_area):
				switch_touch_index = event.index
				_apply_press_feedback(switch_target_bg)
				switch_target_pressed.emit()
				get_viewport().set_input_as_handled()
		else:
			# 释放触摸
			if shoot_touches.has(event.index):
				shoot_touches.erase(event.index)
				_apply_release_feedback(shoot_bg)
				_apply_release_feedback(shoot_bg2)
				if shoot_touches.is_empty() and is_shooting:
					is_shooting = false
					shoot_stopped.emit()
				get_viewport().set_input_as_handled()
			
			if reload_touch_index == event.index:
				reload_touch_index = -1
				_apply_release_feedback(reload_bg)
				get_viewport().set_input_as_handled()

			if auto_aim_touch_index == event.index:
				auto_aim_touch_index = -1
				_apply_release_feedback(auto_aim_bg)
				get_viewport().set_input_as_handled()

			if switch_touch_index == event.index:
				switch_touch_index = -1
				_apply_release_feedback(switch_target_bg)
				get_viewport().set_input_as_handled()

func _is_point_in_control(point: Vector2, control: Control) -> bool:
	"""检查点是否在控件内"""
	if not control or not control.visible:
		return false
	
	var rect = control.get_global_rect()
	return rect.has_point(point)

func is_shooting_active() -> bool:
	"""是否正在射击"""
	return is_shooting

func is_auto_aim_enabled() -> bool:
	"""是否开启自动瞄准"""
	return auto_aim_enabled

func _on_chat_button_pressed():
	"""聊天按钮点击（移动端）"""
	chat_button_pressed.emit()

# 点击反馈相关
var original_styles: Dictionary = {}

func _store_original_styles():
	"""存储原始样式"""
	if shoot_bg:
		original_styles["shoot"] = shoot_bg.get_theme_stylebox("panel").duplicate()
	if shoot_bg2:
		original_styles["shoot2"] = shoot_bg2.get_theme_stylebox("panel").duplicate()
	if reload_bg:
		original_styles["reload"] = reload_bg.get_theme_stylebox("panel").duplicate()
	if auto_aim_bg:
		original_styles["auto_aim"] = auto_aim_bg.get_theme_stylebox("panel").duplicate()
	if switch_target_bg:
		original_styles["switch"] = switch_target_bg.get_theme_stylebox("panel").duplicate()

func _update_auto_aim_label():
	"""根据状态更新自动瞄准按钮文本"""
	if auto_aim_label:
		auto_aim_label.text = "自动瞄准：开" if auto_aim_enabled else "自动瞄准：关"

func _apply_press_feedback(panel: Panel):
	"""应用按下反馈效果"""
	if not panel:
		return
	
	var style = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var pressed_style = style.duplicate()
		pressed_style.bg_color = Color(0.7, 0.7, 0.7, 0.5)  # 更亮
		panel.add_theme_stylebox_override("panel", pressed_style)
		
		# 缩放动画
		var tween = create_tween()
		tween.tween_property(panel, "scale", Vector2(0.95, 0.95), 0.1)

func _apply_release_feedback(panel: Panel):
	"""应用释放反馈效果"""
	if not panel:
		return
	
	# 恢复原始样式
	var key = ""
	if panel == shoot_bg:
		key = "shoot"
	elif panel == shoot_bg2:
		key = "shoot2"
	elif panel == reload_bg:
		key = "reload"
	elif panel == auto_aim_bg:
		key = "auto_aim"
	elif panel == switch_target_bg:
		key = "switch"
	
	if key in original_styles:
		panel.add_theme_stylebox_override("panel", original_styles[key].duplicate())
	
	# 恢复缩放
	var tween = create_tween()
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.1)
