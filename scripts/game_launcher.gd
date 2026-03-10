extends Node

# 游戏启动器 - 检查资源并决定进入开场还是主游戏

var progress_bar: ProgressBar
var status_label: Label
var canvas: CanvasLayer

func _ready():
	# 检查是否需要转移资源
	var rm = get_node_or_null("/root/ResourceManager")
	if not rm:
		_proceed_to_game()
		return
	
	# 检查资源是否已准备好（如果没有存档且从未转移过资源，则需要转移）
	if not _is_resource_transfer_needed(rm):
		_proceed_to_game()
		return
		
	# 如果需要转移，显示进度 UI 并开始异步转移
	_show_progress_ui()
	rm.progress_updated.connect(_on_rm_progress_updated)
	rm.transfer_completed.connect(_on_rm_transfer_completed)
	rm.transfer_failed.connect(_on_rm_transfer_failed)
	
	# 开始异步转移
	rm.transfer_all_resources_async()

func _is_resource_transfer_needed(rm) -> bool:
	# 简单的检查：如果没有任何已安装资源且没有存档，则认为需要转移
	var installed = rm.get_transferred_resources()
	if installed.is_empty() and not _has_save_file():
		return true
	
	# 或者，检查是否还有需要更新的资源
	var config_path = "res://config/resources.json"
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var resources = json.data.get("resources", [])
			for res in resources:
				if rm.should_transfer_resource(res):
					return true
	
	return false

func _on_rm_progress_updated(percent: float, current_item: String):
	if progress_bar:
		progress_bar.value = percent
	if status_label:
		status_label.text = current_item

func _on_rm_transfer_completed():
	print("[GameLauncher] 资源初始化完成")
	if status_label:
		status_label.text = "初始化完成，正在进入游戏..."
	
	# 给一点点时间让文件系统同步（特别是Android设备）
	await get_tree().create_timer(0.5).timeout
	
	# 移除 UI
	if canvas:
		canvas.queue_free()
	
	# 继续进入游戏
	_proceed_to_game()

func _on_rm_transfer_failed(error: String):
	print("[GameLauncher] 资源初始化失败: ", error)
	if status_label:
		status_label.text = "初始化失败: " + error + "\n请检查存储空间并尝试重启应用"
	
	# 如果失败了，强行进入游戏，因为资源不是必须
	var timer = get_tree().create_timer(1.0)
	await timer.timeout
	_proceed_to_game()

func _proceed_to_game():
	# 再次检查关键文件是否存在
	var main_scene = "res://scripts/main.tscn"
	if not ResourceLoader.exists(main_scene):
		print("[GameLauncher] 严重错误: 找不到主场景文件: ", main_scene)
		if status_label:
			status_label.text = "文件损坏，请重新安装应用"
		return

	# 检查存档是否存在
	if _has_save_file():
		print("[GameLauncher] 检测到存档，直接进入游戏")
		_load_main_game.call_deferred()
	else:
		print("[GameLauncher] 首次进入游戏，播放开场动画")
		_load_intro_story.call_deferred()

func _show_progress_ui():
	# 创建一个简单的 UI 容器
	canvas = CanvasLayer.new()
	add_child(canvas)
	
	# 背景
	var panel = ColorRect.new()
	panel.color = Color(0.1, 0.1, 0.1, 1.0)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(panel)
	
	# 居中容器
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 0)
	center.add_child(vbox)
	
	status_label = Label.new()
	status_label.text = "正在初始化内置资源，请稍候..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)
	
	# 添加一些间距
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(400, 30)
	vbox.add_child(progress_bar)
	
	var hint = Label.new()
	hint.text = "\n首次启动需要解压资源 (约80MB)\n手机端可能耗时较长，请勿退出应用"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color.GRAY)
	vbox.add_child(hint)

func _has_save_file() -> bool:
	"""检查是否存在存档文件"""
	var save_path = "user://saves/save_slot_1.json"
	return FileAccess.file_exists(save_path)

func _load_intro_story():
	"""加载开场故事场景"""
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").change_scene_with_fade("res://scenes/intro_scene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/intro_scene.tscn")

func _load_main_game():
	"""加载主游戏场景"""
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").change_scene_with_fade("res://scripts/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scripts/main.tscn")
