extends TextureButton

# 陪伴模式角色控制器
# 复用主场景角色的核心功能，但移除所有交互

var current_scene: String = "studyroom"
var original_preset: Dictionary
var background_node: TextureRect

func set_background_reference(bg: TextureRect):
	"""设置背景引用"""
	background_node = bg

func _get_costume_config_path(costume_id: String) -> String:
	"""获取服装配置文件路径"""
	# 优先从内置配置路径加载
	var res_config_path = "res://config/character_presets/%s.json" % costume_id
	if ResourceLoader.exists(res_config_path):
		return res_config_path
		
	# 其次从用户配置路径加载
	var user_config_path = "user://clothes/configs/%s.json" % costume_id
	if FileAccess.file_exists(user_config_path):
		return user_config_path
		
	return ""

func _get_character_image_path(costume_id: String, scene_id: String, image_name: String) -> String:
	"""获取角色图片路径"""
	# 优先从内置资源加载
	var res_path = "res://assets/images/character/%s/%s/%s" % [costume_id, scene_id, image_name]
	if ResourceLoader.exists(res_path):
		return res_path
		
	# 其次从 user 路径加载
	var user_path = "user://clothes/images/%s/%s/%s" % [costume_id, scene_id, image_name]
	if FileAccess.file_exists(user_path):
		return user_path
		
	# 最后回退到默认
	return "res://assets/images/character/default/%s/%s" % [scene_id, image_name]

func _load_texture_at_path(path: String) -> Texture2D:
	"""从指定路径加载纹理（处理 res:// 和 user:// 的差异）"""
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			return load(path)
		return null
	else:
		if FileAccess.file_exists(path):
			var image = Image.load_from_file(path)
			if image:
				return ImageTexture.create_from_image(image)
		return null

func _load_json_at_path(path: String) -> Dictionary:
	"""从指定路径加载JSON配置"""
	if not FileAccess.file_exists(path):
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		print("解析配置失败: ", path)
		return {}
	
	return json.data

func load_character_for_scene(scene_id: String):
	"""加载角色到指定场景"""
	current_scene = scene_id
	
	# 验证 background_node 是否有效
	if not background_node:
		print("错误: background_node 为空，无法加载角色")
		visible = false
		return
	
	# 获取当前服装ID
	var costume_id = _get_costume_id()
	var config_path = _get_costume_config_path(costume_id)
	var config = _load_json_at_path(config_path)
	if config.size() == 0:
		print("角色配置文件不存在或内容为空: ", config_path)
		return
	
	if not config.has(scene_id):
		print("场景 %s 没有角色配置" % scene_id)
		visible = false
		return
	
	var presets = config[scene_id]
	if presets.size() == 0:
		visible = false
		return
	
	# 随机选择一个预设
	original_preset = presets[randi() % presets.size()]
	print("随机选择角色预设")
	
	# 加载角色图片
	var image_path = _get_character_image_path(costume_id, scene_id, original_preset.image)
	var texture = _load_texture_at_path(image_path)
	if texture:
		texture_normal = texture
		
		# 设置按钮大小为纹理大小
		custom_minimum_size = texture_normal.get_size()
		size = texture_normal.get_size()
		
		# 先设置为完全透明
		modulate.a = 0.0
		visible = true
		
		# 等待背景准备好
		await get_tree().process_frame
		await get_tree().process_frame
		
		# 再次验证 background_node
		if not background_node:
			print("错误: 等待后 background_node 为空")
			visible = false
			return
		
		# 验证背景纹理是否已加载
		if not background_node.texture:
			print("警告: 背景纹理未加载，等待加载...")
			await get_tree().process_frame
			await get_tree().process_frame
			if not background_node.texture:
				print("错误: 背景纹理仍未加载")
				visible = false
				return
		
		# 更新位置和缩放
		_update_position_and_scale_from_preset()
		
		# 渐入动画
		var fade_in_tween = create_tween()
		fade_in_tween.tween_property(self, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		print("角色已加载: ", image_path, " 预设位置: ", original_preset.position, " 实际位置: ", position, " 缩放: ", scale)
	else:
		print("角色图片不存在: ", image_path)
		visible = false

func _update_position_and_scale_from_preset():
	"""根据预设更新角色位置和缩放"""
	if not background_node or not background_node.texture or not texture_normal or original_preset.size() == 0:
		return
	
	# 获取实际渲染的背景区域
	var bg_rect = _get_actual_background_rect()
	var actual_bg_size = bg_rect.size
	var bg_offset = bg_rect.offset
	
	# 验证背景区域是否有效
	if actual_bg_size.x <= 0 or actual_bg_size.y <= 0:
		print("错误: 背景区域无效 - size: ", actual_bg_size)
		return
	
	# 使用预设的缩放值
	var final_scale = original_preset.scale
	scale = Vector2(final_scale, final_scale)
	
	# 计算角色中心点应该在的位置
	var char_center_in_bg = Vector2(
		original_preset.position.x * actual_bg_size.x,
		original_preset.position.y * actual_bg_size.y
	)
	
	# 加上偏移
	var char_center_pos = char_center_in_bg + bg_offset
	
	# 计算角色左上角的位置
	var texture_size = texture_normal.get_size()
	var scaled_half_size = texture_size * final_scale / 2.0
	
	position = char_center_pos - scaled_half_size

func _get_actual_background_rect() -> Dictionary:
	"""获取实际渲染的背景图片区域（考虑黑边）"""
	if not background_node or not background_node.texture:
		return {"size": Vector2.ZERO, "offset": Vector2.ZERO, "scale": 1.0}
	
	var container_size = background_node.size
	var texture_size = background_node.texture.get_size()
	
	# 计算保持比例的缩放
	var scale_x = container_size.x / texture_size.x
	var scale_y = container_size.y / texture_size.y
	var bg_scale = min(scale_x, scale_y)
	
	# 计算实际渲染的图片大小
	var actual_size = texture_size * bg_scale
	
	# 计算偏移（居中）
	var offset = (container_size - actual_size) / 2.0
	
	return {
		"size": actual_size,
		"offset": offset,
		"scale": bg_scale
	}

func _get_costume_id() -> String:
	"""获取当前服装ID"""
	if has_node("/root/SaveManager"):
		var save_mgr = get_node("/root/SaveManager")
		return save_mgr.get_costume_id()
	return "default"
