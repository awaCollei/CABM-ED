extends RichTextLabel

signal bubble_selected(bubble: RichTextLabel)

var bubble_type: String = "ai"  # "user", "ai", or "system"
var pending_text: String = ""
var pending_type: String = ""
var is_selected: bool = false
var message_index: int = -1  # 在消息数组中的索引

func _ready():
	# 如果有待处理的消息，在节点准备好时设置
	if pending_text != "":
		_set_message_immediate(pending_text, pending_type)
		pending_text = ""
		pending_type = ""
	
	# 连接点击事件
	gui_input.connect(_on_gui_input)

func set_message(content: String, type: String = "ai"):
	# 如果节点还没准备好，先保存消息
	if not is_node_ready():
		pending_text = content
		pending_type = type
		return

	_set_message_immediate(content, type)

func _set_message_immediate(content: String, type: String = "ai"):
	bubble_type = type
	self.text = content
	_update_style()
	# 强制重新绘制
	queue_redraw()

func _update_style():
	# 确保文本不为空，这样fit_content才能工作
	if self.text == "":
		self.text = " "

	# 根据消息类型设置不同的背景颜色和对齐方式
	match bubble_type:
		"user":
			# 用户消息：蓝色背景，左对齐
			var style_user = StyleBoxFlat.new()
			style_user.bg_color = Color(0.8, 0.9, 1.0, 0.8) if not is_selected else Color(0.6, 0.8, 1.0, 1.0)
			style_user.border_color = Color(0.2, 0.6, 1.0, 1.0)
			style_user.border_width_left = 2 if not is_selected else 4
			style_user.border_width_right = 2 if not is_selected else 4
			style_user.border_width_top = 2 if not is_selected else 4
			style_user.border_width_bottom = 2 if not is_selected else 4
			style_user.set_corner_radius_all(8)
			add_theme_stylebox_override("normal", style_user)
			horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

		"ai":
			# AI消息：灰色背景，左对齐
			var style_ai = StyleBoxFlat.new()
			style_ai.bg_color = Color(0.98, 0.96, 0.85, 0.8) if not is_selected else Color(0.95, 0.9, 0.7, 1.0)
			style_ai.border_color = Color(0.9, 0.8, 0.4, 1.0)
			style_ai.border_width_left = 2 if not is_selected else 4
			style_ai.border_width_right = 2 if not is_selected else 4
			style_ai.border_width_top = 2 if not is_selected else 4
			style_ai.border_width_bottom = 2 if not is_selected else 4
			style_ai.set_corner_radius_all(8)
			add_theme_stylebox_override("normal", style_ai)
			horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

		"system":
			# 系统消息：淡灰色背景，居中
			var style_system = StyleBoxFlat.new()
			style_system.bg_color = Color(0.95, 0.95, 0.95, 0.6) if not is_selected else Color(0.85, 0.85, 0.85, 0.8)
			style_system.border_color = Color(0.6, 0.6, 0.6, 1.0)
			style_system.border_width_left = 2 if not is_selected else 4
			style_system.border_width_right = 2 if not is_selected else 4
			style_system.border_width_top = 2 if not is_selected else 4
			style_system.border_width_bottom = 2 if not is_selected else 4
			style_system.set_corner_radius_all(8)
			add_theme_stylebox_override("normal", style_system)
			horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("气泡被点击: type=%s, index=%d, text=%s" % [bubble_type, message_index, text.substr(0, 20)])
			bubble_selected.emit(self)

func set_selected(selected: bool):
	is_selected = selected
	_update_style()
	queue_redraw()
