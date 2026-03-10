extends Node

# 物品上传功能模块

signal item_selected(item_data: Dictionary)
signal item_cleared()

var parent_dialog: Panel
var add_button: Button  # "+"按钮（实际上是pic_button）
var input_field: LineEdit

var selected_item_data: Dictionary = {}  # {item_id: String, count: int}
var image_input_node: Node = null  # 图片输入模块的引用

const ICON_ADD = "res://assets/images/chat/image.png"  # 使用原有的图片图标作为默认

func setup(dialog: Panel, btn: Button, input_fld: LineEdit):
	parent_dialog = dialog
	add_button = btn
	input_field = input_fld
	
	# 获取图片输入模块的引用
	image_input_node = parent_dialog.get_node_or_null("ImageInput")
	
	# 替换原有的按钮点击事件
	if add_button:
		# 断开原有的连接
		if image_input_node and add_button.pressed.is_connected(image_input_node._on_pic_button_pressed):
			add_button.pressed.disconnect(image_input_node._on_pic_button_pressed)
		
		# 连接新的事件
		add_button.pressed.connect(_on_add_button_pressed)
		_update_button_icon()

func _on_add_button_pressed():
	# 检查是否有选中的图片或物品
	var has_image = image_input_node and image_input_node.has_selected_image()
	var has_item = has_selected_item()
	
	if has_image or has_item:
		# 清除选中的内容
		if has_image:
			image_input_node.clear_selected_image()
		if has_item:
			clear_selected_item()
	else:
		# 显示上传菜单
		_show_upload_menu()

func _show_upload_menu():
	"""显示上传菜单（图片/物品）"""
	var popup = PopupMenu.new()
	popup.name = "UploadMenu"
	popup.add_item("🖼️图片", 0)
	popup.add_item("📦物品", 1)
	
	popup.id_pressed.connect(_on_menu_item_selected.bind(popup))
	popup.popup_hide.connect(func(): popup.queue_free())
	
	parent_dialog.add_child(popup)
	
	# 1. 设置菜单项字体大小
	var font = popup.get_theme_font("font")
	if font:
		popup.add_theme_font_size_override("font_size", 28)  # 增大字体大小
	
	# 在按钮上方显示菜单
	var button_pos = add_button.global_position
	
	# 2. 往左移动并调整大小
	var menu_width = 120  # 增大宽度
	var menu_height = 80  # 增大高度
	var left_offset = 75  # 往左移动的偏移量
	
	# 调整位置：往左移动，向上显示
	var menu_pos = Vector2(
		button_pos.x - left_offset,          # 往左移动
		button_pos.y - menu_height - 15      # 保持在上方显示
	)
	
	# 3. 使用调整后的尺寸
	popup.popup(Rect2(menu_pos, Vector2(menu_width, menu_height)))
func _on_menu_item_selected(id: int, popup: PopupMenu):
	popup.hide()
	
	if id == 0:
		# 图片
		_show_image_picker()
	elif id == 1:
		# 物品
		_show_item_picker()

func _show_image_picker():
	"""显示图片选择器（调用原有的图片上传功能）"""
	if image_input_node and image_input_node.has_method("_show_file_dialog"):
		image_input_node._show_file_dialog()

func _show_item_picker():
	"""显示物品选择UI"""
	# 创建通用背包UI实例
	var inventory_ui_scene = load("res://scenes/universal_inventory_ui.tscn")
	var inventory_ui = inventory_ui_scene.instantiate()
	inventory_ui.name = "ItemPickerUI"
	
	# 设置为只显示玩家背包，中间容器显示单个格子
	var inventory_mgr = get_node("/root/InventoryManager")
	if not inventory_mgr:
		push_error("InventoryManager 未找到")
		return
	
	# 添加到场景树
	get_tree().root.add_child(inventory_ui)
	
	# 配置UI
	inventory_ui.setup_player_inventory(inventory_mgr.inventory_container, "选择要送出的物品")
	
	# 创建临时容器（单格）用于放置选中的物品
	var temp_container = StorageContainer.new(1, inventory_mgr.items_config, false)
	inventory_ui.setup_other_container(temp_container, "送出物品")
	
	# 修改容器标题下方添加提交按钮
	var container_panel = inventory_ui.get_node_or_null("Panel/HBoxContainer/ContainerPanel")
	if container_panel:
		var vbox = container_panel.get_node_or_null("VBox")
		if vbox:
			var submit_button = Button.new()
			submit_button.text = "确认选择"
			submit_button.custom_minimum_size = Vector2(100, 40)

			# 创建绿色背景样式
			var button_style = StyleBoxFlat.new()
			button_style.bg_color = Color.GREEN  # 绿色背景
			button_style.border_color = Color.DARK_GREEN  # 深绿色边框
			button_style.border_width_left = 2
			button_style.border_width_top = 2
			button_style.border_width_right = 2
			button_style.border_width_bottom = 2
			button_style.corner_radius_top_left = 6
			button_style.corner_radius_top_right = 6
			button_style.corner_radius_bottom_left = 6
			button_style.corner_radius_bottom_right = 6

			# 应用样式到正常状态
			submit_button.add_theme_stylebox_override("normal", button_style)

			# 也可以为悬停和按下状态设置不同颜色
			var hover_style = button_style.duplicate()
			hover_style.bg_color = Color.GREEN
			submit_button.add_theme_stylebox_override("hover", hover_style)

			var pressed_style = button_style.duplicate()
			pressed_style.bg_color = Color.GREEN.darkened(0.2)  # 暗一点的绿色
			submit_button.add_theme_stylebox_override("pressed", pressed_style)

			# 设置字体颜色
			submit_button.add_theme_color_override("font_color", Color.WHITE)
			submit_button.add_theme_color_override("font_hover_color", Color.WHITE)
			submit_button.add_theme_color_override("font_pressed_color", Color.WHITE)

			# 设置字体大小
			submit_button.add_theme_font_size_override("font_size", 28)

			submit_button.pressed.connect(_on_submit_item.bind(inventory_ui, temp_container))
			vbox.add_child(submit_button)
			vbox.move_child(submit_button, vbox.get_child_count() - 1)
	
	# 连接关闭信号 - 关闭时返还物品
	inventory_ui.closed.connect(_on_item_picker_closed.bind(inventory_ui, temp_container))
	
	# 显示UI
	inventory_ui.open_with_container()

func _on_submit_item(inventory_ui: Control, temp_container: StorageContainer):
	"""提交选中的物品"""
	# 检查临时容器中是否有物品
	if temp_container.storage.is_empty() or temp_container.storage[0] == null:
		push_warning("请先将物品放入送出格子")
		return
	
	var item = temp_container.storage[0]
	
	# 保存选中的物品数据
	selected_item_data = {
		"item_id": item.item_id,
		"count": item.count
	}
	
	# 从玩家背包中移除该物品（已经通过拖拽转移到临时容器了）
	# 临时容器的物品不需要保存，关闭UI时会自动丢弃
	
	# 更新按钮图标
	_update_button_icon()
	
	# 发送信号
	item_selected.emit(selected_item_data)
	
	# 断开关闭信号，避免重复返还物品
	if inventory_ui.closed.is_connected(_on_item_picker_closed):
		inventory_ui.closed.disconnect(_on_item_picker_closed)
	
	# 关闭UI
	inventory_ui.close_inventory()
	
	print("选中物品: ", selected_item_data)

func _on_item_picker_closed(inventory_ui: Control, temp_container: StorageContainer):
	"""物品选择UI关闭时的处理 - 返还临时容器中的物品"""
	# 检查临时容器中是否有物品
	if temp_container.storage.is_empty() or temp_container.storage[0] == null:
		inventory_ui.queue_free()
		return
	
	var item = temp_container.storage[0]
	
	# 将物品放回玩家背包
	var inventory_mgr = get_node("/root/InventoryManager")
	if inventory_mgr:
		inventory_mgr.add_item_to_inventory(item.item_id, item.count)
		print("物品选择UI关闭，物品已返还: %s*%d" % [item.item_id, item.count])
	
	inventory_ui.queue_free()

func has_selected_item() -> bool:
	return not selected_item_data.is_empty()

func get_selected_item() -> Dictionary:
	return selected_item_data

func clear_selected_item():
	"""清除选中的物品（放回背包）"""
	if selected_item_data.is_empty():
		return
	
	# 将物品放回玩家背包
	var inventory_mgr = get_node("/root/InventoryManager")
	if inventory_mgr:
		inventory_mgr.add_item_to_inventory(selected_item_data.item_id, selected_item_data.count)
	
	selected_item_data.clear()
	_update_button_icon()
	item_cleared.emit()

func _update_button_icon():
	"""更新按钮图标"""
	if not add_button:
		return
	
	# 检查是否有选中的图片
	var has_image = image_input_node and image_input_node.has_selected_image()
	
	if has_selected_item():
		# 显示物品图标
		var inventory_mgr = get_node("/root/InventoryManager")
		if inventory_mgr:
			var item_config = inventory_mgr.get_item_config(selected_item_data.item_id)
			if item_config.has("icon"):
				var icon_path = "res://assets/images/items/" + item_config.icon
				if ResourceLoader.exists(icon_path):
					add_button.icon = load(icon_path)
				else:
					add_button.icon = load("res://assets/images/error.png")
			else:
				add_button.icon = load("res://assets/images/error.png")
	elif has_image:
		# 显示图片上传图标
		add_button.icon = load("res://assets/images/chat/image_upload.png")
	else:
		# 显示默认"+"图标
		if ResourceLoader.exists(ICON_ADD):
			add_button.icon = load(ICON_ADD)
		else:
			add_button.text = "➕"
			add_button.icon = null
	
	if add_button.icon:
		add_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func hide_for_history():
	if add_button:
		add_button.visible = false

func show_after_history():
	if add_button:
		add_button.visible = true

