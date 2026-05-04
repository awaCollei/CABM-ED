extends Control

@onready var background: TextureRect = $Background
@onready var character: TextureButton = $Background/Character
@onready var time_label: Label = $TimeLabel
@onready var open_map_button: Button = $OpenMapButton
@onready var floating_bar: PanelContainer = $FloatingBar
@onready var floating_header: HBoxContainer = $FloatingBar/MarginContainer/VBox/Header
@onready var collapse_input_button: Button = $FloatingBar/MarginContainer/VBox/Header/CollapseInputButton
@onready var costume_button: Button = $FloatingBar/MarginContainer/VBox/Header/CostumeButton
@onready var send_button: Button = $FloatingBar/MarginContainer/VBox/Header/SendButton
@onready var input_text_edit: TextEdit = $FloatingBar/MarginContainer/VBox/InputTextEdit
@onready var costume_panel: PanelContainer = $CostumePanel
@onready var costume_list: ItemList = $CostumePanel/MarginContainer/VBox/CostumeList
@onready var costume_close_button: Button = $CostumePanel/MarginContainer/VBox/CloseButton
@onready var drag_hint_label: Label = $FloatingBar/MarginContainer/VBox/Header/DragHint
@onready var dialogue_controller: Node = $OutdoorDialogueController

var outdoor_id: String = "beach"
var current_time_id: String = ""
var outdoor_config: Dictionary = {}
var costume_entries: Array = []
var selected_costume_id: String = ""
var selected_costume_data: Dictionary = {}
var current_pose_index: int = -1
var rng := RandomNumberGenerator.new()

var bar_dragging: bool = false
var bar_drag_offset: Vector2 = Vector2.ZERO
var bar_is_expanded: bool = true

const FLOATING_BAR_DEFAULT_POS := Vector2(810.0, 100.0)
const FLOATING_BAR_EXPANDED_HEIGHT := 200.0
const FLOATING_BAR_COLLAPSED_HEIGHT := 40.0

func _ready():
	rng.randomize()
	_resolve_outdoor_id()
	_load_outdoor_config()
	_init_selected_costume()
	call_deferred("_init_scene_safe")
	_setup_character()
	character.gui_input.connect(_on_character_gui_input)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_by_system_time()
	open_map_button.pressed.connect(_on_open_map_pressed)
	collapse_input_button.pressed.connect(_on_collapse_input_pressed)
	costume_button.pressed.connect(_on_costume_button_pressed)
	costume_close_button.pressed.connect(func(): costume_panel.visible = false)
	costume_list.item_selected.connect(_on_costume_item_selected)
	floating_header.gui_input.connect(_on_floating_header_gui_input)
	_connect_dialogue_signals()
	
	var refresh_timer = Timer.new()
	refresh_timer.wait_time =1.0
	refresh_timer.autostart = true
	refresh_timer.timeout.connect(_update_by_system_time)
	add_child(refresh_timer)
	_update_drag_hint()
	_restore_floating_bar_state()
	# 执行淡入动画
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").fade_in()

func _init_scene_safe():
	_setup_character()
	_update_by_system_time()
	_randomize_initial_pose()

func _randomize_initial_pose():
	var poses = _get_pose_list()
	if poses.is_empty():
		return
	
	var index = rng.randi_range(0, poses.size() - 1)
	_apply_pose_by_index(index)

func _resolve_outdoor_id():
	if not has_node("/root/SaveManager"):
		return
	var sm = get_node("/root/SaveManager")
	if sm.has_meta("outdoor_current_id"):
		outdoor_id = str(sm.get_meta("outdoor_current_id"))
	if sm.has_meta("outdoor_target_id"):
		outdoor_id = str(sm.get_meta("outdoor_target_id"))
	sm.set_meta("outdoor_current_id", outdoor_id)

func _update_drag_hint():
	var scene_name = outdoor_id
	
	# 如果配置里有名字，用配置名字
	if outdoor_config.has("name"):
		scene_name = str(outdoor_config.get("name"))
	
	drag_hint_label.text = scene_name

func _load_outdoor_config():
	outdoor_config.clear()
	costume_entries.clear()
	var config_path = "res://config/outdoor_presets/%s.json" % outdoor_id
	if not FileAccess.file_exists(config_path):
		return
	var f = FileAccess.open(config_path, FileAccess.READ)
	var js = f.get_as_text()
	f.close()
	var j = JSON.new()
	if j.parse(js) != OK:
		return
	outdoor_config = j.data
	costume_entries = outdoor_config.get("presets", [])

func _init_selected_costume():
	var fallback_id = ""
	if not costume_entries.is_empty():
		fallback_id = str(costume_entries[0].get("id", ""))
	
	var saved_id = ""
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		saved_id = sm.get_outdoor_scene_costume(outdoor_id)
	
	if saved_id != "" and _find_costume_by_id(saved_id).size() > 0:
		selected_costume_id = saved_id
	else:
		selected_costume_id = fallback_id
	
	selected_costume_data = _find_costume_by_id(selected_costume_id)
	if has_node("/root/SaveManager") and selected_costume_id != "":
		var sm2 = get_node("/root/SaveManager")
		sm2.set_outdoor_scene_costume(outdoor_id, selected_costume_id)
	
	_rebuild_costume_list_ui()

func _setup_character():
	if character.has_method("set_background_reference"):
		character.set_background_reference(background)
	_apply_pose_by_index(0)

func _on_viewport_size_changed():
	if current_pose_index >= 0:
		_apply_pose_by_index(current_pose_index)

func _update_by_system_time():
	var time_dict = Time.get_time_dict_from_system()
	var hour = int(time_dict.get("hour", 12))
	var minute = int(time_dict.get("minute", 0)) 
	var time_id = TimeUtil.get_time_period_from_hour(hour)
	if time_id != current_time_id:
		current_time_id = time_id
		_apply_background()

	_update_time_label(hour, minute)

func _update_time_label(hour: int, minute: int):
	var time_name := TimeUtil.get_time_period(hour)
	time_label.text = "%02d:%02d  %s" % [hour, minute, time_name]

func _apply_background():
	var time_path = "res://assets/images/scenes_outdoor/%s/%s.png" % [outdoor_id, current_time_id]
	var fallback_path = "res://assets/images/scenes_outdoor/%s/day.png" % outdoor_id
	var load_path = time_path if ResourceLoader.exists(time_path) else fallback_path
	if ResourceLoader.exists(load_path):
		background.texture = load(load_path)
	else:
		background.texture = null

func _find_costume_by_id(costume_id: String) -> Dictionary:
	for entry in costume_entries:
		if str(entry.get("id", "")) == costume_id:
			return entry
	return {}

func _get_pose_list() -> Array:
	return selected_costume_data.get("presets", [])

func _apply_pose_by_index(index: int):
	var poses = _get_pose_list()
	if poses.is_empty():
		character.visible = false
		return
	
	if index < 0 or index >= poses.size():
		index = 0
	
	current_pose_index = index
	var pose = poses[index]
	var texture = _load_character_texture(selected_costume_id, str(pose.get("image", "")))
	
	if texture == null:
		character.visible = false
		return
	
	# ⭐淡出
	var tween = create_tween()
	tween.tween_property(character, "modulate:a", 0.0, 0.15)
	
	tween.tween_callback(func():
		character.texture_normal = texture
		character.texture_hover = texture
		character.texture_pressed = texture
		character.scale = Vector2(pose.get("scale", 1.0), pose.get("scale", 1.0))
		_apply_character_position(pose.get("position", {}))
	)
	
	# ⭐淡入
	tween.tween_property(character, "modulate:a", 1.0, 0.15)


func _load_character_texture(costume_id: String, image_name: String) -> Texture2D:
	var path = "res://assets/images/character_outdoor/%s/%s" % [costume_id, image_name]
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _apply_character_position(position_data: Dictionary):
	var ratio_x = float(position_data.get("x", 0.5))
	var ratio_y = float(position_data.get("y", 0.5))
	var bg_rect = character._get_actual_background_rect()
	var actual_bg_size: Vector2 = bg_rect.get("size", Vector2.ZERO)
	var bg_offset: Vector2 = bg_rect.get("offset", Vector2.ZERO)
	if actual_bg_size.x <= 0 or actual_bg_size.y <= 0 or character.texture_normal == null:
		return
	
	var center_pos = Vector2(ratio_x * actual_bg_size.x, ratio_y * actual_bg_size.y) + bg_offset
	var tex_size = character.texture_normal.get_size() * character.scale
	character.position = center_pos - tex_size / 2.0

func _on_character_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
			_on_character_pressed()

func _on_character_pressed():
	var poses = _get_pose_list()
	if poses.is_empty():
		return
	if poses.size() == 1:
		_apply_pose_by_index(0)
		return
	
	var next_index = current_pose_index
	if next_index < 0:
		next_index = 0
	while next_index == current_pose_index:
		next_index = rng.randi_range(0, poses.size() - 1)
	_apply_pose_by_index(next_index)

func _on_collapse_input_pressed():
	_apply_floating_bar_expanded(not bar_is_expanded, true, true)

func _on_costume_button_pressed():
	costume_panel.visible = true
	_rebuild_costume_list_ui()

func _rebuild_costume_list_ui():
	costume_list.clear()
	var selected_idx = -1
	for i in range(costume_entries.size()):
		var entry = costume_entries[i]
		var cid = str(entry.get("id", ""))
		var cname = str(entry.get("name", cid))
		var line = "%s (%s)" % [cname, cid]
		costume_list.add_item(line)
		costume_list.set_item_metadata(i, cid)
		if cid == selected_costume_id:
			selected_idx = i
	if selected_idx >= 0:
		costume_list.select(selected_idx)

func _on_costume_item_selected(index: int):
	var cid = str(costume_list.get_item_metadata(index))
	if cid == "" or cid == selected_costume_id:
		return
	selected_costume_id = cid
	selected_costume_data = _find_costume_by_id(selected_costume_id)
	current_pose_index = -1
	_apply_pose_by_index(0)
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		sm.set_outdoor_scene_costume(outdoor_id, selected_costume_id)

func _on_floating_header_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			bar_dragging = true
			bar_drag_offset = event.global_position - floating_bar.global_position
		else:
			bar_dragging = false
			_save_floating_bar_state()
	elif event is InputEventMouseMotion and bar_dragging:
		var new_pos = event.global_position - bar_drag_offset
		floating_bar.global_position = _clamp_floating_bar_position(new_pos)

func _on_open_map_pressed():
	var dialog := ConfirmationDialog.new()
	dialog.title = "打开地图"
	dialog.dialog_text = "确定要离开这里了吗？"
	dialog.ok_button_text = "离开"
	if dialog.get_cancel_button():
		dialog.get_cancel_button().text = "取消"
	add_child(dialog)
	dialog.popup_centered()
	
	# 直接连接 confirmed 信号到退出逻辑
	dialog.confirmed.connect(_perform_open_map)
	# canceled 不需要做任何事情，只是关闭对话框

func _perform_open_map():
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		sm.set_meta("open_map_on_load", true)
		sm.set_meta("map_origin", "outdoor")
		sm.set_meta("outdoor_current_id", outdoor_id)
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").change_scene_with_fade("res://scripts/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scripts/main.tscn")

func _connect_dialogue_signals():
	if dialogue_controller == null:
		return
	if dialogue_controller.has_signal("dialog_reply_started"):
		dialogue_controller.connect("dialog_reply_started", _on_dialog_reply_started)
	if dialogue_controller.has_signal("dialog_reply_finished"):
		dialogue_controller.connect("dialog_reply_finished", _on_dialog_reply_finished)

func _on_dialog_reply_started():
	_apply_floating_bar_expanded(false, true, false)
	collapse_input_button.disabled = true

func _on_dialog_reply_finished():
	collapse_input_button.disabled = false
	_apply_floating_bar_expanded(true, true, false)

func _apply_floating_bar_expanded(expanded: bool, animate: bool = true, save_state: bool = true):
	bar_is_expanded = expanded
	
	# ⭐ 先改变可见性
	input_text_edit.visible = expanded
	send_button.disabled = not expanded
	
	# ⭐ 等一帧让布局更新
	await get_tree().process_frame
	
	var target_height = FLOATING_BAR_EXPANDED_HEIGHT if expanded else FLOATING_BAR_COLLAPSED_HEIGHT
	
	if animate:
		var tween = create_tween()
		tween.tween_property(floating_bar, "size:y", target_height, 0.2)
	else:
		floating_bar.size.y = target_height
	
	collapse_input_button.text = "🔼" if expanded else "🔽"
	if save_state:
		_save_floating_bar_state()

func _restore_floating_bar_state():
	var target_pos = FLOATING_BAR_DEFAULT_POS
	var expanded = true
	if has_node("/root/SaveManager"):
		var sm = get_node("/root/SaveManager")
		var state = sm.get_outdoor_floating_bar_state(outdoor_id)
		if state is Dictionary and not state.is_empty():
			target_pos.x = float(state.get("x", FLOATING_BAR_DEFAULT_POS.x))
			target_pos.y = float(state.get("y", FLOATING_BAR_DEFAULT_POS.y))
			expanded = bool(state.get("expanded", true))
	floating_bar.global_position = _clamp_floating_bar_position(target_pos)
	_apply_floating_bar_expanded(expanded, false, false)

func _save_floating_bar_state():
	if not has_node("/root/SaveManager"):
		return
	var sm = get_node("/root/SaveManager")
	sm.set_outdoor_floating_bar_state(outdoor_id, {
		"x": floating_bar.global_position.x,
		"y": floating_bar.global_position.y,
		"expanded": bar_is_expanded
	})

func _clamp_floating_bar_position(pos: Vector2) -> Vector2:
	var viewport_size = get_viewport_rect().size
	var bar_size = floating_bar.size
	return Vector2(
		clamp(pos.x, 0.0, max(0.0, viewport_size.x - bar_size.x)),
		clamp(pos.y, 0.0, max(0.0, viewport_size.y - bar_size.y))
	)
