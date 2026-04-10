## 角色牌组件 - 通过 setup() 传入 CardData 初始化
extends PanelContainer

@onready var button: Button = $Button
@onready var card_image: TextureRect = $InnerPanel/CardImage
@onready var image_placeholder: Label = $InnerPanel/ImagePlaceholder
@onready var name_bar: ColorRect = $InnerPanel/NameBar
@onready var name_label: Label = $InnerPanel/NameLabel
@onready var hp_icon: Label = $InnerPanel/HpIcon
@onready var hp_label: Label = $InnerPanel/HpIcon/HpLabel
@onready var atk_icon: Label = $InnerPanel/AtkIcon
@onready var atk_label: Label = $InnerPanel/AtkIcon/AtkLabel

@export var border_normal_color: Color = Color(0.5, 0.6, 0.8)
@export var border_hover_color: Color = Color(0.8, 0.9, 1.0)

signal card_pressed

var _pending_card = null

func setup(card) -> void:
	_pending_card = card
	if is_node_ready():
		_apply_card_data(card)

func _ready() -> void:
	button.mouse_entered.connect(func(): set_hover(true))
	button.mouse_exited.connect(func(): set_hover(false))
	button.pressed.connect(func(): card_pressed.emit())
	if _pending_card != null:
		_apply_card_data(_pending_card)

func _apply_card_data(card) -> void:
	name_label.text = card.card_name
	hp_label.text = "%d" % card.defense
	atk_label.text = "%d" % card.attack

	var img_full_path = "res://assets/images/cards/" + card.image_path
	if ResourceLoader.exists(img_full_path):
		card_image.texture = load(img_full_path)
		card_image.visible = true
		image_placeholder.visible = false
	else:
		card_image.visible = false
		image_placeholder.visible = true

func set_hover(hovered: bool) -> void:
	var style = get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style = style.duplicate()
		style.border_color = border_hover_color if hovered else border_normal_color
		add_theme_stylebox_override("panel", style)
