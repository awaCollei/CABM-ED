## 卡牌图鉴面板
extends Control

const CardDataClass = preload("res://scripts/game/card/card_data.gd")
const CardDatabaseClass = preload("res://scripts/game/card/card_database.gd")
const CharacterCardScene = preload("res://scenes/card/character_card.tscn")

var _all_cards: Array = []
var _selected_card = null
var _current_tab: int = 0  # 0=角色牌 1=手牌
var _selected_btn: Control = null

@onready var tab_character: Button = $TabBar/TabCharacter
@onready var tab_hand: Button = $TabBar/TabHand
@onready var card_grid: GridContainer = $MainArea/CardScroll/CardGrid
@onready var info_panel: Control = $MainArea/InfoPanel
@onready var info_name: Label = $MainArea/InfoPanel/InfoVBox/InfoName
@onready var info_type: Label = $MainArea/InfoPanel/InfoVBox/TopRow/TopRightVBox/InfoType

# 角色牌专用标签
@onready var info_attack: Label = $MainArea/InfoPanel/InfoVBox/TopRow/TopRightVBox/InfoAttack
@onready var info_defense: Label = $MainArea/InfoPanel/InfoVBox/TopRow/TopRightVBox/InfoDefense

# 手牌专用标签
@onready var info_category: Label = $MainArea/InfoPanel/InfoVBox/TopRow/TopRightVBox/InfoCategory
@onready var info_cost: Label = $MainArea/InfoPanel/InfoVBox/TopRow/TopRightVBox/InfoCost

@onready var info_skill_name: Label = $MainArea/InfoPanel/InfoVBox/InfoSkillName
@onready var info_desc: Label = $MainArea/InfoPanel/InfoVBox/InfoDesc
@onready var info_flavor: Label = $MainArea/InfoPanel/InfoVBox/InfoFlavor
@onready var info_image: TextureRect = $MainArea/InfoPanel/InfoVBox/TopRow/InfoImage
@onready var info_emoji: Label = $MainArea/InfoPanel/InfoVBox/TopRow/InfoEmoji
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
	# 选中的 tab 置灰，未选中的正常显示
	tab_character.modulate = Color(0.6, 0.6, 0.6) if tab == 0 else Color.WHITE
	tab_hand.modulate = Color(0.6, 0.6, 0.6) if tab == 1 else Color.WHITE
	_show_empty_info()
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
	if card.card_type == 0:
		return _create_character_card_item(card)
	else:
		return _create_hand_card_item(card)

# 角色牌：使用 CharacterCard 场景（卡片自带 Button）
func _create_character_card_item(card) -> Control:
	var card_view = CharacterCardScene.instantiate()
	card_view.setup(card)
	card_view.card_pressed.connect(_on_card_selected.bind(card, card_view))
	return card_view

func _create_hand_card_item(card) -> Control:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(120, 180)
	btn.clip_contents = true

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.25, 0.45)
	style.corner_radius_top_left = 8; style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8; style.corner_radius_bottom_right = 8
	style.border_width_left = 2; style.border_width_right = 2
	style.border_width_top = 2; style.border_width_bottom = 2
	style.border_color = Color(0.6, 0.4, 0.8)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.45, 0.35, 0.55)
	btn.add_theme_stylebox_override("hover", hover_style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	btn.add_child(vbox)

	# 类型图标（顶部）
	var category_icon = Label.new()
	category_icon.text = card.get_category_icon()
	category_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	category_icon.add_theme_font_size_override("font_size", 20)
	category_icon.custom_minimum_size = Vector2(0, 24)
	category_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(category_icon)

	var emoji_area = Control.new()
	emoji_area.custom_minimum_size = Vector2(0, 60)
	emoji_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	emoji_area.mouse_filter=Control.MOUSE_FILTER_IGNORE
	vbox.add_child(emoji_area)

	var emoji_label = Label.new()
	emoji_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	emoji_label.text = card.emoji
	emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	emoji_label.add_theme_font_size_override("font_size", 42)
	emoji_area.add_child(emoji_label)

	var name_label = Label.new()
	name_label.text = card.card_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_label)

	var cost_label = Label.new()
	cost_label.text = "💎 %d" % card.cost
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 22)
	cost_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	vbox.add_child(cost_label)

	btn.pressed.connect(_on_card_selected.bind(card, btn))
	return btn

func _on_card_selected(card, btn: Control):
	# 再次点击已选中的卡牌 -> 取消选中
	if _selected_card == card:
		_selected_btn.modulate = Color.WHITE
		_selected_card = null
		_selected_btn = null
		_show_empty_info()
		return
	if _selected_btn:
		_selected_btn.modulate = Color.WHITE
	_selected_card = card
	_selected_btn = btn
	btn.modulate = Color(1.2, 1.2, 0.6)
	_show_info(card)

func _show_info(card):
	info_panel.visible = true
	info_name.text = card.card_name
	info_type.text = "角色牌" if card.card_type == 0 else "手牌"

	if card.card_type == 0:
		# 角色牌：显示攻击/防御，隐藏类型/费用
		info_attack.visible = true
		info_defense.visible = true
		info_category.visible = false
		info_cost.visible = false
		
		info_attack.text = "🗡 %d" % card.attack
		info_defense.text = "♥ %d" % card.defense
		
		info_skill_name.visible = true
		info_skill_name.text = "【%s】" % card.skill_name if card.skill_name != "" else ""
		info_image.visible = true
		info_emoji.visible = false
		var img_full_path = "res://assets/images/cards/" + card.image_path
		info_image.texture = load(img_full_path) if ResourceLoader.exists(img_full_path) else null
	else:
		# 手牌：显示类型/费用，隐藏攻击/防御
		info_attack.visible = false
		info_defense.visible = false
		info_category.visible = true
		info_cost.visible = true
		
		info_category.text = "%s %s" % [card.get_category_icon(), card.get_category_name()]
		info_cost.text = "💎 %d" % card.cost
		
		info_skill_name.visible = false
		info_image.visible = false
		info_emoji.visible = true
		info_emoji.text = card.emoji

	info_desc.text = card.description
	info_flavor.text = card.flavor_text

func _show_empty_info():
	info_panel.visible = true
	info_name.text = "选择卡牌查看详细信息"
	info_type.text = ""
	info_attack.visible = false
	info_defense.visible = false
	info_category.visible = false
	info_cost.visible = false
	info_skill_name.visible = false
	info_image.visible = false
	info_emoji.visible = false
	info_desc.text = ""
	info_flavor.text = ""

func _clear_info():
	info_panel.visible = false
