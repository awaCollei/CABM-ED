extends Control

signal result_closed(dish_name: String)

@onready var color_rect: ColorRect = $ColorRect
@onready var panel_container: PanelContainer = $PanelContainer
@onready var title_input: LineEdit = $PanelContainer/VBox/TitleInput
@onready var result_container: Control = $PanelContainer/VBox/ResultContainer
@onready var bowl_bg: TextureRect = $PanelContainer/VBox/ResultContainer/BowlBackground
@onready var confirm_button: Button = $PanelContainer/VBox/ConfirmButton

var items_config: Dictionary = {}
var cook_manager = null
var ingredients: Array = []
var default_dish_name: String = "谜之炖菜"

func setup(p_ingredients: Array, p_items_config: Dictionary, p_cook_manager, p_default_name: String = "谜之炖菜"):
	ingredients = p_ingredients
	items_config = p_items_config
	cook_manager = p_cook_manager
	default_dish_name = p_default_name
	
	if is_node_ready():
		_update_ui()

func _ready():
	confirm_button.pressed.connect(_on_confirm_pressed)
	if ingredients.size() > 0:
		_update_ui()

func _update_ui():
	title_input.text = default_dish_name
	title_input.placeholder_text = default_dish_name
	
	# Clear previous ingredients if any
	for child in result_container.get_children():
		if child != bowl_bg:
			child.queue_free()
	
	# Wait a frame for container size to be correct
	await get_tree().process_frame
	
	var bowl_rect = _get_bowl_rect(result_container)
	
	for ingredient in ingredients:
		var sprite = Control.new()
		sprite.custom_minimum_size = Vector2(150, 150)
		sprite.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)

		var icon = TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var item_config = items_config.get(ingredient.item_id, {})
		if item_config.has("icon"):
			var icon_path = "res://assets/images/items/" + item_config.icon
			if ResourceLoader.exists(icon_path):
				icon.texture = load(icon_path)

		sprite.add_child(icon)

		var rand_pos = Vector2(
			randf_range(bowl_rect.position.x, bowl_rect.position.x + bowl_rect.size.x),
			randf_range(bowl_rect.position.y, bowl_rect.position.y + bowl_rect.size.y)
		)
		var rand_rot = randf() * PI * 2

		sprite.position = rand_pos - Vector2(75, 75)
		sprite.pivot_offset = Vector2(75, 75)
		sprite.rotation = rand_rot
		if cook_manager:
			sprite.modulate = cook_manager.get_ingredient_color(ingredient)
		result_container.add_child(sprite)

func _get_bowl_rect(bowl_container: Control) -> Rect2:
	if not bowl_container:
		return Rect2()
	var margin = bowl_container.size * 0.38
	return Rect2(margin, bowl_container.size - margin * 2)

func _on_confirm_pressed():
	var dish_name = title_input.text.strip_edges()
	if dish_name.is_empty():
		dish_name = default_dish_name
	result_closed.emit(dish_name)
	queue_free()
