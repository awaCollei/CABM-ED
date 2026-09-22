extends Node

# 触摸模拟器（Autoload）
# 仅在移动平台启用：将"单指长按（按住且不怎么移动）"全局映射为鼠标右键。
# 通过 Input.parse_input_event() 合成 InputEventMouseButton(RIGHT)，
# 因此现有监听 MOUSE_BUTTON_RIGHT 的逻辑（如 inventory_slot、character_debug）无需改动。

const LONG_PRESS_TIME: float = 0.45  # 长按触发时长（秒）
const MOVE_THRESHOLD: float = 10.0  # 允许的最大位移（逻辑像素），超过视为拖拽/滑动

var _enabled: bool = false

# 当前跟踪中的触摸点: index -> { "position": Vector2, "fired": bool }
var _touches: Dictionary = {}


func _ready() -> void:
	# 仅移动平台启用；PlatformManager 先于本 Autoload 注册
	_enabled = PlatformManager.is_mobile_platform()
	if _enabled:
		print("TouchEmulator: 已启用长按映射右键")


func _input(event: InputEvent) -> void:
	if not _enabled:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_start(event.index, event.position)
		else:
			_on_touch_end(event)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event)


func _on_touch_start(index: int, pos: Vector2) -> void:
	# 第二指落下：取消所有待触发的长按（避免与双指缩放手势冲突）
	if not _touches.is_empty() and not _touches.has(index):
		_cancel_all_pending()

	_touches[index] = {
		"position": pos,
		"fired": false,
	}
	var idx := index
	var p := pos
	var timer := get_tree().create_timer(LONG_PRESS_TIME, false, false, false)
	timer.timeout.connect(func() -> void: _on_long_press(idx, p), CONNECT_ONE_SHOT)


func _on_touch_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var touch: Dictionary = _touches[event.index]
	if touch["fired"]:
		# 长按已触发：让事件继续派发给控件（LineEdit/RichTextLabel 需要靠 drag 调整选区手柄）。
		# 不做 set_input_as_handled，否则原生文本选择流程会被打断导致选区丢失。
		return
	var start_pos: Vector2 = touch["position"]
	if event.position.distance_to(start_pos) > MOVE_THRESHOLD:
		_cancel_touch(event.index)


func _on_touch_end(event: InputEventScreenTouch) -> void:
	if not _touches.has(event.index):
		return
	var touch: Dictionary = _touches[event.index]
	if touch["fired"]:
		# 长按已触发：只补发右键释放；
		# 触摸结束事件必须继续派发给 LineEdit/RichTextLabel，否则选区会在抬手时被清除。
		_emit_right_button(false, event.position)
	_touches.erase(event.index)


func _on_long_press(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var touch: Dictionary = _touches[index]
	if touch["fired"]:
		return
	# 多指情况下不触发
	if _touches.size() > 1:
		_touches.erase(index)
		return
	touch["fired"] = true
	_emit_right_button(true, pos)


func _emit_right_button(pressed: bool, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.device = -1
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)


func _cancel_touch(index: int) -> void:
	# 从跟踪表移除后，超时回调检查到 index 不存在即自动失效，无需断开信号
	_touches.erase(index)


func _cancel_all_pending() -> void:
	for index in _touches.keys():
		var touch: Dictionary = _touches[index]
		if not touch["fired"]:
			_touches.erase(index)
