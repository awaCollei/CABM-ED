## 卡牌游戏主页面 - 角色选择与入口
extends Control

const CardDatabaseClass = preload("res://scripts/game/card/card_database.gd")
const CharacterCardScene = preload("res://scenes/card/character_card.tscn")

const MAX_SLOTS = 3

var _selected_slots: Array = [null, null, null]
var _character_cards: Array = []
var _editing_slot: int = -1

@onready var slot_buttons: Array = [
	$SlotArea/Slot0,
	$SlotArea/Slot1,
	$SlotArea/Slot2,
]
@onready var start_button: Button = $BottomButtons/StartButton
@onready var collection_button: Button = $BottomButtons/CollectionButton
@onready var select_popup: Control = $SelectPopup
@onready var popup_grid: GridContainer = $SelectPopup/PopupBG/VBox/ScrollContainer/PopupGrid
@onready var popup_close: Button = $SelectPopup/PopupBG/VBox/CloseButton

signal start_game_pressed
signal collection_pressed

func _ready():
	_character_cards = CardDatabaseClass.get_character_cards()
	start_button.pressed.connect(func(): start_game_pressed.emit())
	collection_button.pressed.connect(func(): collection_pressed.emit())
	popup_close.pressed.connect(_close_popup)
	select_popup.visible = false

	for i in MAX_SLOTS:
		slot_buttons[i].pressed.connect(_on_slot_pressed.bind(i))

	_refresh_slots()

func _on_slot_pressed(slot_idx: int):
	if _selected_slots[slot_idx] != null:
		_selected_slots[slot_idx] = null
		_refresh_slots()
		return
	_editing_slot = slot_idx
	_open_select_popup()

func _open_select_popup():
	for child in popup_grid.get_children():
		child.queue_free()

	for card in _character_cards:
		popup_grid.add_child(_create_popup_card(card))

	select_popup.visible = true

func _create_popup_card(card) -> Control:
	var card_view = CharacterCardScene.instantiate()
	card_view.setup(card)

	var already_selected = _selected_slots.any(func(s): return s != null and s.card_name == card.card_name)
	if already_selected:
		card_view.modulate = Color(0.4, 0.4, 0.4, 0.7)
	else:
		card_view.card_pressed.connect(_on_popup_card_selected.bind(card))

	return card_view

func _on_popup_card_selected(card):
	if _editing_slot >= 0:
		_selected_slots[_editing_slot] = card
		_refresh_slots()
	_close_popup()

func _close_popup():
	select_popup.visible = false
	_editing_slot = -1

func _refresh_slots():
	for i in MAX_SLOTS:
		var slot_btn: Button = slot_buttons[i]
		var card = _selected_slots[i]

		for child in slot_btn.get_children():
			child.queue_free()

		if card == null:
			slot_btn.text = "+"
			slot_btn.add_theme_font_size_override("font_size", 28)
			slot_btn.remove_theme_stylebox_override("normal")
		else:
			slot_btn.text = ""
			slot_btn.clip_contents = true

			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.15, 0.15, 0.2)
			style.corner_radius_top_left = 10; style.corner_radius_top_right = 10
			style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
			style.border_width_left = 2; style.border_width_right = 2
			style.border_width_top = 2; style.border_width_bottom = 2
			style.border_color = Color(0.5, 0.6, 0.8)
			slot_btn.add_theme_stylebox_override("normal", style)

			var card_view = CharacterCardScene.instantiate()
			card_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			slot_btn.add_child(card_view)
			card_view.setup(card)
			# 让卡牌所有子节点都不拦截鼠标，事件透传给卡槽按钮
			for node in card_view.find_children("*", "Control", true, false):
				node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
