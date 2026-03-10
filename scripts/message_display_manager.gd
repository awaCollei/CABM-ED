extends Node
class_name MessageDisplayManager

# 消息显示管理器 - 负责各种提示消息的显示
# 此脚本现在被设计为可以作为 AutoLoad (全局单例) 使用

var message_label: Label
var message_tween: Tween
var scene_manager: SceneManager
var canvas_layer: CanvasLayer

func _ready():
	# 如果作为 AutoLoad 运行，自动初始化
	if get_parent() == get_tree().root:
		_setup_ui()

func _setup_ui():
	"""设置UI层级和标签"""
	if canvas_layer:
		return
		
	# 创建 CanvasLayer 并设置高层级，确保在最上层
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 128 # 确保在普通UI之上
	add_child(canvas_layer)
	
	# 创建消息标签
	message_label = Label.new()
	message_label.visible = false
	message_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	message_label.add_theme_constant_override("outline_size", 2)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.z_index = 100
	canvas_layer.add_child(message_label)

func initialize(scene_mgr: SceneManager, _parent: Node = null):
	"""初始化管理器（为了兼容旧代码）"""
	scene_manager = scene_mgr
	_setup_ui()
	
	# 如果传入了 parent 且不是作为单例运行，可以考虑是否需要重新挂载
	# 但作为单例时，它已经挂在 root 下了，不需要处理 parent

func set_scene_manager(mgr: SceneManager):
	"""设置场景管理器，用于获取显示区域"""
	scene_manager = mgr

func show_failure_message(message: String):
	"""显示失败消息（红色）"""
	_show_message(message, Color(1, 0.3, 0.3))

func show_info_message(message: String):
	"""显示信息消息（蓝色）"""
	_show_message(message, Color(0.5, 0.8, 1.0))

func _show_message(message: String, color: Color):
	"""显示消息（通用函数）"""
	if message_label == null:
		_setup_ui()
	
	if message_tween != null and message_tween.is_valid():
		message_tween.kill()
	
	message_label.text = message
	message_label.add_theme_color_override("font_color", color)
	
	var label_pos: Vector2
	if scene_manager and scene_manager.scene_rect:
		var scene_rect = scene_manager.scene_rect
		label_pos = Vector2(
			scene_rect.position.x + scene_rect.size.x / 2,
			scene_rect.position.y + scene_rect.size.y * 0.15
		)
	else:
		# 如果没有 scene_manager，默认在视口上方中央
		var viewport_rect = get_viewport().get_visible_rect()
		label_pos = Vector2(
			viewport_rect.size.x / 2,
			viewport_rect.size.y * 0.15
		)
	
	message_label.position = label_pos
	message_label.size = Vector2.ZERO
	
	await get_tree().process_frame
	message_label.position.x -= message_label.size.x / 2
	
	message_label.modulate.a = 0.0
	message_label.visible = true
	
	message_tween = create_tween()
	message_tween.tween_property(message_label, "modulate:a", 1.0, 0.3)
	message_tween.tween_interval(2.0)
	message_tween.tween_property(message_label, "modulate:a", 0.0, 0.5)
	
	await message_tween.finished
	message_label.visible = false
	message_tween = null
