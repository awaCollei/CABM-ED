extends Control

## 主菜单场景
## 提供进入游戏和退出游戏的选项

@onready var enter_game_button: Button = $VBoxContainer/EnterGameButton
@onready var about_button: Button = $VBoxContainer/AbouteButton
@onready var exit_game_button: Button = $VBoxContainer/ExitGameButton
@onready var dev_button: Button = $DevButton

# 关于对话框场景
const ABOUT_DIALOG_SCENE = preload("res://scenes/about_dialog.tscn")
var about_dialog_instance: Node = null

func _ready():
	# 连接按钮信号
	enter_game_button.pressed.connect(_on_enter_game_pressed)
	about_button.pressed.connect(_on_about_button_pressed)
	exit_game_button.pressed.connect(_on_exit_game_pressed)
	dev_button.pressed.connect(_on_dev_button_pressed)
	
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

func _on_about_button_pressed():
	"""关于游戏按钮按下"""
	if about_dialog_instance == null:
		# 显示关于对话框
		about_dialog_instance = ABOUT_DIALOG_SCENE.instantiate()
		add_child(about_dialog_instance)
		
		# 设置位置为屏幕左侧偏中的位置
		about_dialog_instance.position = Vector2(200, 100)
		
		# 监听对话框被删除的信号
		about_dialog_instance.tree_exited.connect(_on_about_dialog_closed)
		print("[MainMenu] 显示关于对话框")
	else:
		# 隐藏关于对话框
		about_dialog_instance.queue_free()
		about_dialog_instance = null
		print("[MainMenu] 隐藏关于对话框")

func _on_about_dialog_closed():
	"""关于对话框关闭时的回调"""
	about_dialog_instance = null

func _on_dev_button_pressed():
	"""开发者选项按钮按下"""
	# 显示确认对话框
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "三思而后行"
	confirm_dialog.dialog_text = "即将进入开发者选项页面，修改其中的内容可能\n对游戏和存档造成不可逆的严重损害！\n\n⚠除非你知道自己在做什么，否则请点击“取消”"
	confirm_dialog.ok_button_text = "我知道我在做什么！"
	confirm_dialog.cancel_button_text = "取消"
	confirm_dialog.get_cancel_button().call_deferred("grab_focus")
	# 连接确认信号
	confirm_dialog.confirmed.connect(_on_dev_confirmed)
	
	# 添加到场景树并显示
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()
	print("[MainMenu] 显示开发者选项确认对话框")

func _on_dev_confirmed():
	"""确认进入开发者选项"""
	print("[MainMenu] 进入开发者选项")
	
	# 切换到开发者页面
	if has_node("/root/SceneTransition"):
		var transition = get_node("/root/SceneTransition")
		transition.change_scene_with_fade("res://scenes/developer_panel.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/developer_panel.tscn")

func _on_exit_game_pressed():
	"""退出游戏按钮按下"""
	print("[MainMenu] 退出游戏")
	get_tree().quit()
