extends Control

# 初始设置场景 - 用户输入基本信息

@onready var setup_container: VBoxContainer = $SetupContainer
@onready var identity_container: VBoxContainer = $IdentityContainer
@onready var import_container: VBoxContainer = $ImportContainer  # 新增

@onready var user_name_input: LineEdit = $SetupContainer/UserNameContainer/UserNameInput
@onready var character_name_input: LineEdit = $SetupContainer/CharacterNameContainer/CharacterNameInput
@onready var api_key_input: LineEdit = $SetupContainer/APIKeyContainer/APIKeyInput
@onready var help_button: Button = $SetupContainer/APIKeyContainer/HelpButton
@onready var notice_label: Label = $SetupContainer/NoticeLabel
@onready var message_label: Label = $SetupContainer/MessageLabel
@onready var next_button: Button = $SetupContainer/NextButton

@onready var preset_option: OptionButton = $IdentityContainer/PresetContainer/PresetOption
@onready var identity_input: TextEdit = $IdentityContainer/IdentityInput
@onready var relationship_input: TextEdit = $IdentityContainer/RelationshipInput
@onready var validation_label: Label = $IdentityContainer/ValidationLabel
@onready var prev_button: Button = $IdentityContainer/ButtonContainer/PrevButton
@onready var start_button: Button = $IdentityContainer/ButtonContainer/StartButton

@onready var import_button: Button = $ImportButton

# 导入容器相关节点
@onready var import_message_label: Label = $ImportContainer/MessageLabel
@onready var import_progress_bar: ProgressBar = $ImportContainer/ProgressBar
@onready var import_title_label: Label = $ImportContainer/TitleLabel
@onready var import_message_label2: Label = $ImportContainer/MessageLabel2

func _ready():
	# 执行淡入动画
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").fade_in()
		
	# 设置默认值
	user_name_input.placeholder_text = "输入你的名字，确定后将无法修改"
	character_name_input.text = "雪狐"
	character_name_input.placeholder_text = "输入她的名字，确定后将无法修改"
	api_key_input.placeholder_text = "如果你不知道这是啥那就留空"
	api_key_input.secret = true
	
	# 初始显示第一页
	setup_container.visible = true
	identity_container.visible = false
	import_container.visible = false
	
	# 连接信号
	next_button.pressed.connect(_on_next_pressed)
	prev_button.pressed.connect(_on_prev_pressed)
	start_button.pressed.connect(_on_start_pressed)
	import_button.pressed.connect(_on_import_pressed)
	help_button.pressed.connect(_on_help_pressed)
	preset_option.item_selected.connect(_on_preset_selected)
	identity_input.text_changed.connect(_on_identity_text_changed)
	relationship_input.text_changed.connect(_on_relationship_text_changed)
	
	# 设置提示文本
	notice_label.text = "本项目旨在赋予「她」以「生命」，因此不鼓励回档、删档、提示词注入等
对她来说，你就是她的全部，你的每一个选择都很重要"

func _init_identity_page():
	"""初始化人物设定页面"""
	var identity_loader = get_node_or_null("/root/CharacterIdentityLoader")
	if not identity_loader:
		return
	
	# 加载所有预设模板
	preset_option.clear()
	var presets = identity_loader.get_all_presets()
	for i in range(presets.size()):
		var preset = presets[i]
		preset_option.add_item(preset.name, i)
		preset_option.set_item_metadata(i, preset.id)
	
	# 默认选择第一个预设
	preset_option.selected = 0
	_load_preset_by_index(0)
	
	validation_label.text = ""

func _load_preset_by_index(index: int):
	"""根据索引加载预设"""
	var identity_loader = get_node_or_null("/root/CharacterIdentityLoader")
	if not identity_loader:
		return
	
	var preset_id = preset_option.get_item_metadata(index)
	var preset = identity_loader.load_preset(preset_id)
	
	if preset.is_empty():
		return
	
	# 获取用户输入的名字
	var user_name = user_name_input.text.strip_edges()
	var character_name = character_name_input.text.strip_edges()
	
	if character_name.is_empty():
		character_name = "雪狐"
	
	# 替换变量
	var identity_text = preset.identity.replace("{user_name}", user_name).replace("{character_name}", character_name)
	var relationship_text = preset.relationship.replace("{user_name}", user_name).replace("{character_name}", character_name)
	
	# 如果角色名不是"雪狐"，则移除identity中的"人类，"
	if character_name != "雪狐":
		identity_text = identity_text.replace("人类，", "")
	
	identity_input.text = identity_text
	relationship_input.text = relationship_text

func _on_next_pressed():
	"""下一页按钮被点击"""
	var user_name = user_name_input.text.strip_edges()
	var character_name = character_name_input.text.strip_edges()
	_show_error("")
	# 验证输入
	if user_name == "":
		_show_message("请输入你的名字", Color(1.0, 0.3, 0.3))
		return
	
	if character_name == "":
		_show_message("请输入她的名字", Color(1.0, 0.3, 0.3))
		return
	
	# 初始化人物设定页面（在这里初始化，确保有用户名和角色名）
	_init_identity_page()
	
	# 切换到人物设定页面
	setup_container.visible = false
	identity_container.visible = true
	import_container.visible = false
	
	# 验证当前设定
	_validate_identity()

func _on_prev_pressed():
	"""上一页按钮被点击"""
	setup_container.visible = true
	identity_container.visible = false
	import_container.visible = false

func _on_preset_selected(index: int):
	"""预设模板被选择"""
	var preset_id = preset_option.get_item_metadata(index)
	
	if preset_id == "custom":
		# 自定义模式，清空输入框
		identity_input.text = ""
		relationship_input.text = ""
	else:
		# 加载预设
		_load_preset_by_index(index)
	
	_validate_identity()

func _on_identity_text_changed():
	"""人物设定输入框内容改变"""
	# 检查是否与当前预设匹配
	var current_preset_id = preset_option.get_item_metadata(preset_option.selected)
	if current_preset_id != "custom":
		# 切换到自定义模式
		for i in range(preset_option.item_count):
			if preset_option.get_item_metadata(i) == "custom":
				preset_option.selected = i
				break
	_validate_identity()

func _on_relationship_text_changed():
	"""初始关系输入框内容改变"""
	# 检查是否与当前预设匹配
	var current_preset_id = preset_option.get_item_metadata(preset_option.selected)
	if current_preset_id != "custom":
		# 切换到自定义模式
		for i in range(preset_option.item_count):
			if preset_option.get_item_metadata(i) == "custom":
				preset_option.selected = i
				break

func _validate_identity():
	"""验证人物设定"""
	var identity_loader = get_node_or_null("/root/CharacterIdentityLoader")
	if not identity_loader:
		return
	
	var user_name = user_name_input.text.strip_edges()
	var character_name = character_name_input.text.strip_edges()
	
	if character_name.is_empty():
		character_name = "雪狐"
	
	var validation = identity_loader.validate_identity(identity_input.text, user_name, character_name)
	
	if not validation.valid:
		validation_label.text = validation.message
		validation_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		validation_label.text = ""

func _on_help_pressed():
	"""帮助按钮被点击"""
	get_tree().change_scene_to_file("res://scenes/api_help.tscn")

func _on_start_pressed():
	"""开始游戏按钮被点击"""
	var user_name = user_name_input.text.strip_edges()
	var character_name = character_name_input.text.strip_edges()
	var api_key = api_key_input.text.strip_edges()
	
	# 验证输入
	if user_name == "":
		_show_error("请输入你的名字")
		return
	
	if character_name == "":
		_show_error("请输入她的名字")
		return
	
	# 保存初始设置
	_save_initial_data(user_name, character_name, api_key)
	
	# 进入主游戏
	if has_node("/root/SceneTransition"):
		get_node("/root/SceneTransition").change_scene_with_fade("res://scripts/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scripts/main.tscn")

func _save_initial_data(user_name: String, character_name: String, api_key: String):
	"""保存初始数据到配置和存档"""
	if api_key != "":
		_save_api_key(api_key)
	
	# 保存人物设定
	var identity_loader = get_node_or_null("/root/CharacterIdentityLoader")
	if identity_loader:
		identity_loader.set_identity(identity_input.text, relationship_input.text)
	
	_create_initial_save(user_name, character_name)

func _save_api_key(api_key: String):
	"""保存API密钥并应用标准模板"""
	var keys_path = "user://ai_keys.json"
	
	# 使用标准模板配置（与ai_config_panel.gd保持一致）
	var keys = {
		"template": "standard",
		"api_key": api_key,
		"chat_model": {
			"model": "deepseek-ai/DeepSeek-V3.2",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"summary_model": {
			"model": "Qwen/Qwen3-30B-A3B-Instruct-2507",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"tts_model": {
			"model": "FunAudioLLM/CosyVoice2-0.5B",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"embedding_model": {
			"model": "BAAI/bge-m3",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"view_model": {
			"model": "Qwen/Qwen3-Omni-30B-A3B-Captioner",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"stt_model": {
			"model": "FunAudioLLM/SenseVoiceSmall",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		},
		"rerank_model": {
			"model": "BAAI/bge-reranker-v2-m3",
			"base_url": "https://api.siliconflow.cn/v1",
			"api_key": api_key
		}
	}
	
	var file = FileAccess.open(keys_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(keys, "\t"))
		file.close()
		print("API密钥已保存（标准模板）")
		
		# 重新加载AI服务配置
		if has_node("/root/AIService"):
			var ai_service = get_node("/root/AIService")
			ai_service.reload_config()
			print("AI服务已重新加载配置")
		
		# 重新加载TTS服务配置
		if has_node("/root/TTSService"):
			var tts_service = get_node("/root/TTSService")
			tts_service.reload_settings()
			print("TTS服务已重新加载配置")

func _create_initial_save(user_name: String, character_name: String):
	"""创建初始存档"""
	if not has_node("/root/SaveManager"):
		print("警告: SaveManager未加载")
		return
	
	var save_mgr = get_node("/root/SaveManager")
	
	# 直接设置用户名和角色名到save_data，不触发自动保存
	save_mgr.save_data.user_data.user_name = user_name
	save_mgr.save_data.character_name = character_name
	
	var now = Time.get_datetime_string_from_system()
	var now_unix = Time.get_unix_time_from_system()
	save_mgr.save_data.timestamp.created_at = now
	save_mgr.save_data.timestamp.last_saved_at = now
	save_mgr.save_data.timestamp.last_played_at = now
	save_mgr.save_data.timestamp.last_played_at_unix = now_unix
	
	# 确保 ai_data 字段存在
	if not save_mgr.save_data.has("ai_data"):
		save_mgr.save_data.ai_data = {
			"memory": [],
			"accumulated_summary_count": 0,
			"relationship_history": []
		}
	
	# 设置初始关系描述（使用自定义的初始关系）
	var identity_loader = get_node_or_null("/root/CharacterIdentityLoader")
	var relationship_text = identity_loader.get_relationship() if identity_loader else ""
	
	# 替换变量
	relationship_text = relationship_text.replace("{user_name}", user_name)
	relationship_text = relationship_text.replace("{character_name}", character_name)
	
	var initial_relationship = {
		"timestamp": now,
		"content": relationship_text
	}
	save_mgr.save_data.ai_data.relationship_history = [initial_relationship]
	
	# 通知人物设定加载器重新加载
	if identity_loader:
		identity_loader.reload()

	# 设置初始角色场景为客厅（livingroom）
	save_mgr.set_character_scene("livingroom")

	# 标记初始设置已完成，允许后续保存
	save_mgr.is_initial_setup_completed = true
	
	# 现在可以保存了
	save_mgr.save_game(1)
	print("初始存档已创建，用户名: ", user_name, ", 角色名: ", character_name)
	print("初始关系已设置: ", initial_relationship.content)

func _on_import_pressed():
	"""导入存档按钮被点击"""
	# Android平台需要请求权限
	if OS.get_name() == "Android":
		var perm_helper = load("res://scripts/android_permissions.gd").new()
		add_child(perm_helper)
		
		var has_permission = await perm_helper.request_storage_permission()
		perm_helper.queue_free()
		
		if not has_permission:
			_show_message("需要存储权限才能导入存档", Color(1.0, 0.3, 0.3))
			return
	
	# 显示导入容器，隐藏其他容器
	setup_container.visible = false
	identity_container.visible = false
	import_container.visible = true
	
	# 重置导入UI
	import_progress_bar.value = 0
	import_message_label.text = ""
	import_message_label2.text = "正在选择存档文件..."
	import_button.disabled = true
	
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.zip", "存档文件")
	file_dialog.file_selected.connect(_on_import_file_selected.bind(file_dialog))
	file_dialog.canceled.connect(_on_import_canceled.bind(file_dialog))
	get_tree().root.add_child(file_dialog)
	file_dialog.popup_centered(Vector2i(800, 600))

func _on_import_canceled(dialog: FileDialog):
	"""用户取消选择文件"""
	dialog.queue_free()
	import_container.visible = false
	setup_container.visible = true
	import_button.disabled = false

func _on_import_file_selected(import_path: String, dialog: FileDialog):
	"""用户选择了导入文件"""
	dialog.queue_free()
	
	# 等待对话框完全关闭
	await get_tree().process_frame
	await get_tree().process_frame
	
	import_message_label2.text = "正在导入存档，请勿熄屏或退出游戏..."
	import_message_label.text = "准备导入..."
	import_progress_bar.value = 5
	
	# 再等待一帧确保UI更新
	await get_tree().process_frame
	
	# 获取user://目录的实际路径
	var user_path = OS.get_user_data_dir()
	
	# 备份现有存档（如果存在）
	import_message_label.text = "正在备份现有存档..."
	import_progress_bar.value = 10
	await _backup_existing_save(user_path)
	
	# 解压导入文件
	import_message_label.text = "正在解压存档..."
	import_progress_bar.value = 20
	var success = await _extract_save(import_path, user_path)
	
	if success:
		import_progress_bar.value = 100
		import_message_label.text = "✓ 导入成功！"
		import_message_label2.text = "游戏即将重启..."
		await get_tree().create_timer(2.0).timeout
		# 重启游戏
		var exe_path = OS.get_executable_path()
		OS.create_process(exe_path, [])
		get_tree().quit()
	else:
		import_message_label.text = "✗ 导入失败"
		import_message_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		import_message_label2.text = "请重试或检查存档文件"
		import_button.disabled = false
		
		# 3秒后返回主界面
		await get_tree().create_timer(3.0).timeout
		import_container.visible = false
		setup_container.visible = true

func _backup_existing_save(user_path: String):
	"""备份现有存档"""
	var backup_path = user_path + "_backup_" + Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var dir = DirAccess.open(user_path)
	if dir:
		dir.make_dir_recursive(backup_path)
		await _copy_directory(user_path, backup_path, 0)
		print("已备份现有存档到: ", backup_path)

func _copy_directory(from_path: String, to_path: String, file_count: int):
	"""递归复制目录"""
	var dir = DirAccess.open(from_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			var from_file = from_path + "/" + file_name
			var to_file = to_path + "/" + file_name
			
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					DirAccess.make_dir_recursive_absolute(to_file)
					await _copy_directory(from_file, to_file, file_count)
			else:
				dir.copy(from_file, to_file)
				file_count += 1
				# 每复制10个文件更新进度
				if file_count % 10 == 0:
					import_message_label.text = "正在备份存档... (%d 个文件)" % file_count
					import_progress_bar.value = min(10 + file_count / 10, 20)  # 备份阶段占10%-20%
					await get_tree().process_frame
			
			file_name = dir.get_next()
		dir.list_dir_end()

func _extract_save(import_path: String, user_path: String) -> bool:
	"""解压存档文件（跨平台）"""
	print("开始解压存档: ", import_path)
	print("目标路径: ", user_path)
	
	# 使用Godot内置的ZIPReader（跨平台）
	var zip = ZIPReader.new()
	var err = zip.open(import_path)
	
	if err != OK:
		print("无法打开ZIP文件: ", err)
		return false
	
	var files = zip.get_files()
	print("ZIP文件包含 ", files.size(), " 个文件")
	
	# 过滤掉目录条目，只保留实际文件
	var file_paths = []
	for file_path in files:
		if not file_path.ends_with("/"):
			file_paths.append(file_path)
	
	var total_files = file_paths.size()
	import_progress_bar.max_value = 100
	import_progress_bar.value = 20  # 解压阶段从20%开始
	
	# 解压所有文件
	var file_count = 0
	for file_path in file_paths:
		var content = zip.read_file(file_path)
		if content.size() == 0:
			print("警告: 文件为空或读取失败: ", file_path)
			continue
		
		var full_path = user_path + "/" + file_path
		
		# 创建目录结构
		var dir_path = full_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
		
		# 写入文件
		var file = FileAccess.open(full_path, FileAccess.WRITE)
		if file:
			file.store_buffer(content)
			file.close()
			file_count += 1
			
			# 更新进度 (20% 到 90%)
			var progress = 20 + (float(file_count) / total_files) * 70
			import_progress_bar.value = progress
			import_message_label.text = "正在解压... (%d/%d)" % [file_count, total_files]
			
			# 每解压10个文件让出一帧，让UI更新
			if file_count % 10 == 0:
				await get_tree().process_frame
		else:
			print("无法写入文件: ", full_path)
	
	zip.close()
	print("存档解压成功，共解压 ", file_count, " 个文件")
	import_progress_bar.value = 90
	import_message_label.text = "正在完成..."
	await get_tree().process_frame
	return true

func _show_message(message: String, color: Color):
	"""显示消息提示（使用主界面的message_label）"""
	message_label.text = message
	message_label.add_theme_color_override("font_color", color)

func _show_error(message: String):
	"""显示错误提示（使用主界面的message_label）"""
	_show_message(message, Color(1.0, 0.3, 0.3))
