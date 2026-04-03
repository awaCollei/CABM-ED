extends Control

## 开发者选项面板
## 用于开发者调试和测试功能

@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton

func _ready():
	# 连接返回按钮信号
	back_button.pressed.connect(_on_back_button_pressed)
	
	print("[DeveloperPanel] 开发者选项面板已加载")
	# 执行淡入动画
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.fade_in()

func _on_back_button_pressed():
	"""返回主菜单按钮按下"""
	print("[DeveloperPanel] 返回主菜单")
	
	# 使用场景过渡管理器切换回主菜单
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		transition.change_scene_with_fade("res://scenes/main_menu.tscn")
	else:
		# 如果没有过渡管理器，直接切换
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
