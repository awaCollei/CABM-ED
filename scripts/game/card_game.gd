## 卡牌游戏主控制器
extends Control

signal game_ended

enum Screen { HOME, COLLECTION }

var _current_screen: Screen = Screen.HOME

@onready var home_panel: Control = $HomePanel
@onready var collection_panel: Control = $CollectionPanel
@onready var back_button: Button = $BackButton

func _ready():
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)

	back_button.pressed.connect(_on_back_pressed)
	home_panel.start_game_pressed.connect(_on_start_game)
	home_panel.collection_pressed.connect(_on_open_collection)
	collection_panel.back_pressed.connect(_on_collection_back)

	_show_screen(Screen.HOME)

func _show_screen(screen: Screen):
	_current_screen = screen
	home_panel.visible = screen == Screen.HOME
	collection_panel.visible = screen == Screen.COLLECTION

func _on_start_game():
	# TODO: 进入实际游戏逻辑
	pass

func _on_open_collection():
	_show_screen(Screen.COLLECTION)

func _on_collection_back():
	_show_screen(Screen.HOME)

func _on_back_pressed():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	game_ended.emit()
