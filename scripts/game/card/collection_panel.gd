## 卡牌图鉴面板
extends Control

const CardDataClass = preload("res://scripts/game/card/card_data.gd")
const CardDatabaseClass = preload("res://scripts/game/card/card_database.gd")

var _all_cards: Array = []
var _selected_card = null
var _current_tab: int = 0  # 0=角色牌 1=手牌
var _selected_btn: Button = null

@onready var tab_character: Button = $TabBar/TabCharacter
@onready var tab_hand: Button = $TabBar/TabHand
@onready var card_grid: GridContainer = $MainArea/CardScroll/CardGrid
@onready var info_panel: Control = $MainArea/InfoPanel
@onready var info_name: Label = $MainArea/InfoPanel/InfoVBox/InfoName
@onready var info_type: Label = $MainArea/InfoPanel/InfoVBox/InfoType
@onready var info_rarity: Label = $MainArea/InfoPanel/InfoVBox/InfoRarity
@onready var info_cost: Label = $MainArea/InfoPanel/InfoVBox/StatRow/InfoCost
@onready var info_attack: Label = $MainArea/InfoPanel/InfoVBox/StatRow/InfoAttack
@onready var info_defense: Label = $MainArea/InfoPanel/InfoVBox/StatRow/InfoDefense
@onready var info_desc: Label = $MainArea/InfoPanel/InfoVBox/InfoDesc
@onready var info_flavor: Label = $MainArea/InfoPanel/InfoVBox/InfoFlavor
@onready var info_image: TextureRect = $MainArea/InfoPanel/InfoVBox/InfoImage
@onready var info_emoji: Label = $MainArea/InfoPanel/InfoVBox/InfoEmoji
@onready var back_button: Button = $TopBar/BackButton

signal back_pressed

func _ready():
	_all_cards = CardDatabaseClass.get_all_cards()
	tab_character.pressed.connect(_on_tab_character)
	tab_hand.pressed.connect(_on_tab_hand)
	back_button.pressed.connect(func(): back_pressed.emit())
	_set_tab(0)

func _set_tab(tab: int):
	_current_tab = tab
	_selected_card = null
	_selected_btn = null
	_clear_info()
	tab_character.modulate = Color.WHITE if tab == 0 else Color(0.6, 0.6, 0.6)
	tab_hand.modulate = Color.WHITE if tab == 1 else Color(0.6, 0.6, 0.6)
	_populate_grid()

func _on_tab_character():
	_set_tab(0)

func _on_tab_hand():
	_set_tab(1)

func _populate_grid():
	for child in card_grid.get_children():
		child.queue_free()

	for card in _all_cards:
		if card.card_type != _current_tab:
			continue
		var item = _create_card_item(card)
		card_grid.add_child(item)

func _create_card_item(card) -> Control:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(90, 130)
	btn.clip_contents = true

	var bg_color = Color(0.25, 0.35, 0.55) if card.card_type == 0 else Color(0.35, 0.25, 0.45)
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 8; style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8; style.corner_radius_bottom_right = 8
	style.border_width_left = 2; style.border_width_right = 2
	style.border_width_top = 2; style.border_width_bottom = 2
	style.border_color = card.get_rarity_color()
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = bg_color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover_style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	btn.add_child(vbox)

	var img_area = Control.new()
	img_area.custom_minimum_size = Vector2(0, 70)
	img_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(img_area)

	if card.card_type == 0:  # CHARACTER
		var img_full_path = "res://assets/images/cards/" + card.image_path
		if ResourceLoader.exists(img_full_path):
			var tex_rect = TextureRect.new()
			tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.texture = load(img_full_path)
			img_area.add_child(tex_rect)
		else:
			var ph = Label.new()
			ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ph.text = "🧙"; ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			ph.add_theme_font_size_override("font_size", 28)
			img_area.add_child(ph)
	else:
		var emoji_label = Label.new()
		emoji_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		emoji_label.text = card.emoji
		emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emoji_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		emoji_label.add_theme_font_size_override("font_size", 32)
		img_area.add_child(emoji_label)

	var name_label = Label.new()
	name_label.text = card.card_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_label)

	var cost_label = Label.new()
	cost_label.text = "费用: %d" % card.cost
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 10)
	cost_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	vbox.add_child(cost_label)

	btn.pressed.connect(_on_card_selected.bind(card, btn))
	return btn

func _on_card_selected(card, btn: Button):
	_selected_card = card
	if _selected_btn:
		_selected_btn.modulate = Color.WHITE
	_selected_btn = btn
	btn.modulate = Color(1.2, 1.2, 0.6)
	_show_info(card)

func _show_info(card):
	info_panel.visible = true
	info_name.text = card.card_name
	info_type.text = "类型: " + ("角色牌" if card.card_type == 0 else "手牌")
	info_rarity.text = "稀有度: " + card.get_rarity_name()
	info_rarity.add_theme_color_override("font_color", card.get_rarity_color())
	info_cost.text = "费用: %d" % card.cost
	info_attack.text = "攻击: %d" % card.attack
	info_defense.text = "防御: %d" % card.defense
	info_desc.text = card.description
	info_flavor.text = card.flavor_text

	if card.card_type == 0:  # CHARACTER
		info_image.visible = true
		info_emoji.visible = false
		var img_full_path = "res://assets/images/cards/" + card.image_path
		info_image.texture = load(img_full_path) if ResourceLoader.exists(img_full_path) else null
	else:
		info_image.visible = false
		info_emoji.visible = true
		info_emoji.text = card.emoji

func _clear_info():
	info_panel.visible = false
