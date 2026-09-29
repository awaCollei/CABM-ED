extends Button

# 右上角背包按钮
const UIStyleFactory = preload("res://scripts/ui/ui_style_factory.gd")
const INVENTORY_SCENE = preload("res://scenes/inventory_ui.tscn")

var inventory_ui: Control = null
var current_ui_style: String = UIStyleFactory.STYLE_NOTEBOOK


func _ready():
	pressed.connect(_on_pressed)
	if has_node("/root/UIStyleManager"):
		var style_manager = get_node("/root/UIStyleManager")
		current_ui_style = style_manager.load_ui_style()
		style_manager.ui_style_changed.connect(_apply_ui_style)
		style_manager.ui_opacity_changed.connect(_on_ui_opacity_changed)
	_apply_ui_style(current_ui_style)

	# 延迟加载背包UI
	call_deferred("_setup_inventory_ui")


func _apply_ui_style(style_id: String) -> void:
	current_ui_style = UIStyleFactory.normalize_style(style_id)
	var button_alpha := 1.0
	if has_node("/root/UIStyleManager"):
		button_alpha = (
			get_node("/root/UIStyleManager").load_ui_style_opacity(current_ui_style).buttons
		)
	theme = UIStyleFactory.create_theme(current_ui_style, button_alpha)
	modulate.a = button_alpha if current_ui_style == UIStyleFactory.STYLE_DEFAULT else 1.0


func _on_ui_opacity_changed(
	style_id: String, _sidebar: float, _dialog: float, _buttons: float
) -> void:
	if style_id == current_ui_style:
		_apply_ui_style(current_ui_style)


func _setup_inventory_ui():
	"""延迟设置背包UI"""
	inventory_ui = INVENTORY_SCENE.instantiate()
	var tree = get_tree()
	if tree != null and tree.root != null:
		tree.root.add_child(inventory_ui)
	else:
		var parent = get_parent()
		if parent != null:
			parent.add_child(inventory_ui)
		else:
			add_child(inventory_ui)
	inventory_ui.hide()


func _on_pressed():
	"""点击按钮"""
	if inventory_ui:
		inventory_ui.toggle_visibility()
