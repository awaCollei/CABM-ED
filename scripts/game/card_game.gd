## 卡牌游戏主控制器
extends Control

signal game_ended

const BattleSceneClass = preload("res://scenes/card/battle_scene.tscn")

enum Screen { HOME, COLLECTION, BATTLE }

var _current_screen: Screen = Screen.HOME
var _battle_scene: Control = null

@onready var home_panel: Control = $HomePanel
@onready var collection_panel: Control = $CollectionPanel
@onready var back_button: Button = $HomePanel/BackButton

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
	
	if _battle_scene:
		_battle_scene.visible = screen == Screen.BATTLE

func _on_start_game():
	var selected_cards = home_panel.get_selected_cards()
	
	if selected_cards.size() < 3:
		MessageDisplay.show_failure_message("请选择3个角色")
		return
	
	# 创建战斗场景
	if _battle_scene:
		_battle_scene.queue_free()
	
	_battle_scene = BattleSceneClass.instantiate()
	add_child(_battle_scene)
	_battle_scene.battle_ended.connect(_on_battle_ended)
	
	# 开始战斗
	_battle_scene.start_battle(selected_cards)
	_show_screen(Screen.BATTLE)

func _on_battle_ended(victory: bool):
	if victory:
		MessageDisplay.show_info_message("战斗胜利！")
	else:
		MessageDisplay.show_failure_message("战斗失败...")
	
	_show_screen(Screen.HOME)

func _on_open_collection():
	_show_screen(Screen.COLLECTION)

func _on_collection_back():
	_show_screen(Screen.HOME)

func _on_back_pressed():
	if _current_screen == Screen.BATTLE:
		MessageDisplay.show_failure_message("战斗中无法退出")
		return
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	game_ended.emit()
