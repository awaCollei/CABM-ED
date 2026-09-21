extends Control

# 角色位置调试工具
# 按 F1 开启/关闭调试模式
# 在调试模式下，可以拖动角色到想要的位置
# 双击角色：移动到当前场景的下一个预设点位
# 滚轮：以鼠标下角色区域为中心放大/缩小角色
# 按 S 键：把当前位置和缩放写回配置文件
# 控制台会输出对应的配置坐标

var character: TextureButton
var background: TextureRect
var debug_label: Label

var debug_mode: bool = false
var dragging: bool = false
var drag_offset: Vector2

# 当前场景的预设点位信息
var scene_presets: Array = []
var preset_index: int = -1
var loaded_scene_id: String = ""

const SCALE_MIN := 0.05
const SCALE_MAX := 10.0
const SCALE_STEP := 1.02

func _ready():
	# 自身不拦截鼠标，避免影响场景交互；仅承载调试 UI
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 获取节点引用（通过父节点）
	var parent = get_parent()
	if parent:
		background = parent.get_node("Background")
		if background:
			character = background.get_node("Character")

	# 创建调试标签
	debug_label = Label.new()
	debug_label.position = Vector2(10, 10)
	debug_label.visible = false
	add_child(debug_label)

	# 连接角色的输入事件
	if character:
		character.gui_input.connect(_on_character_gui_input)
	else:
		print("警告: 调试工具无法找到角色节点")

func _input(event):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# F1 切换调试模式
	if event.keycode == KEY_F1:
		debug_mode = !debug_mode
		debug_label.visible = debug_mode

		if debug_mode:
			print("\n=== 角色位置调试模式已开启 ===")
			print("拖动角色到想要的位置")
			print("双击角色：切换到当前场景的下一个预设点位")
			print("滚轮：放大/缩小角色")
			print("按 S 键：把当前位置和缩放写回配置文件")
			print("松开鼠标后会在控制台输出配置坐标")
			print("按 F1 关闭调试模式\n")
			_ensure_scene_presets_loaded()
		else:
			print("\n=== 角色位置调试模式已关闭 ===\n")

		_update_debug_info()
		return

	# S 键写回配置文件
	if event.keycode == KEY_S and debug_mode:
		_save_config()

func _on_character_gui_input(event):
	if not debug_mode:
		return

	if event is InputEventMouseButton:
		# 双击：切换到下一个预设点位
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			dragging = false
			_move_to_next_preset()
			return

		# 滚轮：以角色中心为锚点缩放
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var factor: float = SCALE_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / SCALE_STEP
			_zoom_character(factor)
			accept_event()
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 开始拖动
				dragging = true
				drag_offset = event.position
			else:
				# 结束拖动
				if dragging:
					dragging = false
					_print_character_config()

func _process(_delta):
	if not debug_mode or not character or not background:
		return

	if dragging:
		# 更新角色位置
		var bg_local_pos = background.get_local_mouse_position()

		# 计算角色中心应该在的位置
		if character.texture_normal:
			var char_size = character.texture_normal.get_size() * character.scale
			character.position = bg_local_pos - char_size / 2.0

		_sync_original_preset()
		_update_debug_info()

# 加载当前场景的预设点位列表
func _ensure_scene_presets_loaded():
	scene_presets = []
	preset_index = -1
	loaded_scene_id = ""

	if not character or character.current_scene == "":
		print("警告: 当前没有有效的场景，无法加载预设点位")
		return

	var costume_id = character._get_costume_id()
	var config_path = character._get_costume_config_path(costume_id)
	var config = character._load_json_at_path(config_path)
	if config.size() == 0:
		print("警告: 无法加载服装配置: ", config_path)
		return

	if not config.has(character.current_scene) or not config[character.current_scene] is Array:
		print("警告: 场景 %s 没有预设点位" % character.current_scene)
		return

	scene_presets = config[character.current_scene]
	loaded_scene_id = character.current_scene

	# 优先定位到角色当前正在使用的预设（按 image 匹配）
	var current_image = ""
	if character.original_preset.size() > 0:
		current_image = character.original_preset.get("image", "")
	for i in scene_presets.size():
		if current_image != "" and scene_presets[i].get("image", "") == current_image:
			preset_index = i
			break
	if preset_index < 0 and scene_presets.size() > 0:
		preset_index = 0

	print("已加载场景 %s 的 %d 个预设点位，当前索引: %d" % [loaded_scene_id, scene_presets.size(), preset_index])

# 移动到当前场景的下一个预设点位
func _move_to_next_preset():
	if loaded_scene_id != character.current_scene or scene_presets.is_empty():
		_ensure_scene_presets_loaded()

	if scene_presets.is_empty():
		print("警告: 当前场景没有预设点位，无法切换")
		return

	preset_index = (preset_index + 1) % scene_presets.size()
	var preset = scene_presets[preset_index]

	var costume_id = character._get_costume_id()
	var image_path = character._get_character_image_path(costume_id, loaded_scene_id, preset.get("image", "1.png"))
	var texture = character._load_texture_at_path(image_path)
	if texture:
		character.texture_normal = texture
		character.custom_minimum_size = texture.get_size()
		character.size = texture.get_size()

	character.original_preset = preset.duplicate(true)
	character._update_position_and_scale_from_preset()

	print("切换到预设点位 %d/%d: %s" % [preset_index + 1, scene_presets.size(), preset.get("des", "")])
	_update_debug_info()

# 以角色中心为锚点缩放角色
func _zoom_character(factor: float):
	if not character or not character.texture_normal:
		return

	var texture_size = character.texture_normal.get_size()
	var center = character.position + texture_size * character.scale / 2.0

	var new_scale = clamp(character.scale.x * factor, SCALE_MIN, SCALE_MAX)
	character.scale = Vector2(new_scale, new_scale)
	character.position = center - texture_size * new_scale / 2.0

	_sync_original_preset()
	_update_debug_info()

# 把角色当前的位置/缩放同步到 original_preset
func _sync_original_preset():
	if not character:
		return
	var config = _get_current_config()
	if character.original_preset.size() == 0:
		character.original_preset = {"image": "1.png"}
	character.original_preset["scale"] = config.scale
	character.original_preset["position"] = {"x": config.x, "y": config.y}

func _update_debug_info():
	if not debug_mode or not character or not character.texture_normal:
		return

	var config = _get_current_config()

	debug_label.text = "调试模式 (F1关闭)\n"
	debug_label.text += "拖动移动 | 双击切换预设 | 滚轮缩放 | S保存\n"
	debug_label.text += "---\n"
	if scene_presets.size() > 0:
		debug_label.text += "预设: %d/%d\n" % [max(preset_index, 0) + 1, scene_presets.size()]
	debug_label.text += "位置: (%.2f, %.2f)\n" % [config.x, config.y]
	debug_label.text += "缩放: %.2f" % config.scale

func _get_current_config() -> Dictionary:
	if not character or not character.texture_normal or not background or not background.texture:
		return {"x": 0.0, "y": 0.0, "scale": 1.0}

	# 获取实际背景区域
	var bg_rect = character._get_actual_background_rect()
	var actual_bg_size = bg_rect.size
	var bg_offset = bg_rect.offset

	# 计算角色中心位置
	var char_size = character.texture_normal.get_size() * character.scale
	var char_center = character.position + char_size / 2.0

	# 减去偏移，得到在实际背景上的位置
	var pos_in_bg = char_center - bg_offset

	# 转换为比例
	var ratio_x = pos_in_bg.x / actual_bg_size.x if actual_bg_size.x > 0 else 0.0
	var ratio_y = pos_in_bg.y / actual_bg_size.y if actual_bg_size.y > 0 else 0.0

	# 角色缩放直接对应配置中的 scale（见 character.gd）
	return {
		"x": clamp(ratio_x, 0.0, 1.0),
		"y": clamp(ratio_y, 0.0, 1.0),
		"scale": character.scale.x
	}

# 按 S 键：把当前位置和缩放写回配置文件
func _save_config():
	if not character or character.current_scene == "":
		print("错误: 当前没有有效的场景，无法写回配置")
		return

	if loaded_scene_id != character.current_scene or scene_presets.is_empty():
		_ensure_scene_presets_loaded()

	if scene_presets.is_empty() or preset_index < 0:
		print("错误: 当前场景没有可更新的预设点位")
		return

	var costume_id = character._get_costume_id()
	var config_path = character._get_costume_config_path(costume_id)
	var config = character._load_json_at_path(config_path)
	if config.size() == 0:
		print("错误: 无法加载服装配置: ", config_path)
		return

	var current = _get_current_config()

	# 写回当前预设点位
	var preset = scene_presets[preset_index]
	preset["scale"] = current.scale
	preset["position"] = {"x": current.x, "y": current.y}

	# 同步内存中的配置并落盘
	config[loaded_scene_id] = scene_presets
	if _write_json_config(config_path, config):
		character.original_preset = preset.duplicate(true)
		if has_node("/root/SaveManager"):
			get_node("/root/SaveManager").set_character_preset(character.original_preset)

		print("\n--- 已更新配置 ---")
		print("文件: ", config_path)
		print("场景: %s  预设: %d/%d (%s)" % [loaded_scene_id, preset_index + 1, scene_presets.size(), preset.get("des", "")])
		print("位置: (%.2f, %.2f)  缩放: %.2f\n" % [current.x, current.y, current.scale])
	else:
		print("错误: 写回配置文件失败: ", config_path)

	_update_debug_info()

# 将 Dictionary 以 JSON 格式写入配置文件（支持 res:// 和 user://）
func _write_json_config(path: String, data: Dictionary) -> bool:
	var json_string = JSON.stringify(data, "  ")

	var write_path = path
	if path.begins_with("res://"):
		# 导出后 res:// 只读；编辑器内通过物理路径写入
		write_path = ProjectSettings.globalize_path(path)

	var file = FileAccess.open(write_path, FileAccess.WRITE)
	if not file:
		return false

	file.store_string(json_string)
	file.close()
	return true

func _print_character_config():
	var config = _get_current_config()

	print("\n--- 角色配置 ---")
	print('{')
	print('  "image": "1.png",')
	print('  "scale": %.2f,' % config.scale)
	print('  "position": {')
	print('    "x": %.2f,' % config.x)
	print('    "y": %.2f' % config.y)
	print('  }')
	print('}')
	print("--- 复制上面的配置到 config/character_presets/ 下对应服装文件 ---\n")
