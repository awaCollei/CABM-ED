## 卡牌游戏主页面 - 角色选择与入口
extends Control

const CardDatabaseClass = preload("res://scripts/game/card/card_database.gd")

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
	_editing_slot = slot_idx
	_open_select_popup()

func _open_select_popup():
	for child in popup_grid.get_children():
		child.queue_free()

	for card in _character_cards:
		popup_grid.add_child(_create_popup_card(card))

	select_popup.visible = true

func _create_popup_card(card) -> Control:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(100, 140)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.3, 0.5)
	style.corner_radius_top_left = 8; style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8; style.corner_radius_bottom_right = 8
	style.border_width_left = 2; style.border_width_right = 2
	style.border_width_top = 2; style.border_width_bottom = 2
	style.border_color = card.get_rarity_color()
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.3, 0.4, 0.65)
	btn.add_theme_stylebox_override("hover", hover_style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_child(vbox)

	var img_area = Control.new()
	img_area.custom_minimum_size = Vector2(0, 80)
	img_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(img_area)

	var img_full_path = "res://assets/images/cards/" + card.image_path
	if ResourceLoader.exists(img_full_path):
		var tex = TextureRect.new()
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture = load(img_full_path)
		img_area.add_child(tex)
	else:
		var ph = Label.new()
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ph.text = "🧙"; ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.add_theme_font_size_override("font_size", 30)
		img_area.add_child(ph)

	var name_lbl = Label.new()
	name_lbl.text = card.card_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_lbl)

	var rarity_lbl = Label.new()
	rarity_lbl.text = card.get_rarity_name()
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_lbl.add_theme_font_size_override("font_size", 10)
	rarity_lbl.add_theme_color_override("font_color", card.get_rarity_color())
	vbox.add_child(rarity_lbl)

	btn.pressed.connect(_on_popup_card_selected.bind(card))
	return btn

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
		else:
			slot_btn.text = ""
			var vbox = VBoxContainer.new()
			vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			slot_btn.add_child(vbox)

			var img_area = Control.new()
			img_area.custom_minimum_size = Vector2(0, 80)
			img_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.add_child(img_area)

			var img_full_path = "res://assets/images/cards/" + card.image_path
			if ResourceLoader.exists(img_full_path):
				var tex = TextureRect.new()
				tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex.texture = load(img_full_path)
				img_area.add_child(tex)
			else:
				var ph = Label.new()
				ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				ph.text = "🧙"; ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				ph.add_theme_font_size_override("font_size", 26)
				img_area.add_child(ph)

			var name_lbl = Label.new()
			name_lbl.text = card.card_name
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.add_theme_font_size_override("font_size", 11)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.add_child(name_lbl)
