extends Control

## 主菜单场景
## 提供进入游戏和退出游戏的选项

@onready var enter_game_button: Button = $CenterContainer/VBoxContainer/EnterGameButton
@onready var exit_game_button: Button = $CenterContainer/VBoxContainer/ExitGameButton

func _ready():
	# 连接按钮信号
	enter_game_button.pressed.connect(_on_enter_game_pressed)
	exit_game_button.pressed.connect(_on_exit_game_pressed)
	
	print("[MainMenu] 主菜单已加载")
	
	# 执行淡入动画
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		await transition.fade_in()

func _on_enter_game_pressed():
	"""进入游戏按钮按下"""
	print("[MainMenu] 进入游戏")
	
	# 使用场景过渡管理器切换到主场景
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		transition.change_scene_with_fade("res://scripts/main.tscn")
	else:
		# 如果没有过渡管理器，直接切换
		get_tree().change_scene_to_file("res://scripts/main.tscn")

func _on_exit_game_pressed():
	"""退出游戏按钮按下"""
	print("[MainMenu] 退出游戏")
	get_tree().quit()
