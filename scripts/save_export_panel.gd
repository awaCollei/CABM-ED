extends MarginContainer
# 存档导出面板

@onready var api_key_input: LineEdit = $MainHBox/LeftPanel/APIKeyInput
@onready var export_button: Button = $MainHBox/LeftPanel/ExportButton
@onready var status_label: Label = $StatusBar/StatusLabel
@onready var chk_speech: CheckBox = $MainHBox/LeftPanel/IncludeSpeech
@onready var chk_logs: CheckBox = $MainHBox/LeftPanel/IncludeLogs
@onready var chk_music: CheckBox = $MainHBox/LeftPanel/IncludeMusic
@onready var chk_resources: CheckBox = $MainHBox/LeftPanel/IncludeResources
@onready var cloud_backup_button: Button = $MainHBox/RightPanel/CloudBackupButton
@onready var uuid_label: Label = $MainHBox/RightPanel/UUIDLabel  # 新增UUID标签

var current_uuid: String = ""

func _ready():
	# 居中显示
	position = (get_viewport_rect().size - size) / 2

	# 连接信号
	export_button.pressed.connect(_on_export_pressed)
	cloud_backup_button.pressed.connect(_on_cloud_backup_pressed)
	uuid_label.gui_input.connect(_on_uuid_label_gui_input)  # 连接UUID标签的输入事件

	# 初始化UUID
	_init_uuid()

func _init_uuid():
	"""初始化UUID：从文件读取或生成新的"""
	var uuid_file_path = "user://uuid.txt"
	
	if FileAccess.file_exists(uuid_file_path):
		# 读取现有UUID
		var file = FileAccess.open(uuid_file_path, FileAccess.READ)
		if file:
			current_uuid = file.get_as_text().strip_edges()
			file.close()
	
	# 如果UUID无效，生成新的
	if current_uuid.is_empty():
		current_uuid = _generate_uuid()
		# 保存到文件
		var file = FileAccess.open(uuid_file_path, FileAccess.WRITE)
		if file:
			file.store_string(current_uuid)
			file.close()
	
	# 更新显示
	uuid_label.text = "UUID(点击复制): " + _truncate_uuid(current_uuid)
	uuid_label.tooltip_text = current_uuid  # 设置工具提示显示完整UUID

func _generate_uuid() -> String:
	"""生成简单的UUID（格式：xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx）"""
	var hex_chars = "0123456789abcdef"
	var uuid = ""
	
	for i in range(36):
		match i:
			8, 13, 18, 23:  # 添加连字符的位置
				uuid += "-"
			_:
				uuid += hex_chars[randi() % hex_chars.length()]
	
	# 设置版本位（第14个字符应为4）
	uuid = uuid.substr(0, 14) + "4" + uuid.substr(15)
	# 设置变体位（第19个字符应为8、9、A或B）
	var variant = ["8", "9", "a", "b"][randi() % 4]
	uuid = uuid.substr(0, 19) + variant + uuid.substr(20)
	
	return uuid

func _truncate_uuid(uuid: String, max_length: int = 16) -> String:
	"""截断UUID显示（只显示前8个字符）"""
	if uuid.length() > max_length:
		return uuid.substr(0, max_length) + "..."
	return uuid

func _on_uuid_label_gui_input(event: InputEvent):
	"""处理UUID标签的输入事件"""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# 复制UUID到剪贴板
		DisplayServer.clipboard_set(current_uuid)
		_show_status("✓ UUID已复制到剪贴板", Color(0.3, 1.0, 0.3))
		
		# 3秒后恢复状态显示
		await get_tree().create_timer(3.0).timeout
		status_label.text = ""

func _on_export_pressed():
	var input_key = api_key_input.text.strip_edges()
	if input_key.is_empty():
		_show_status("请输入“确认”", Color(1.0, 0.3, 0.3))
		return

	# 验证API密钥
	if not _verify_api_key(input_key):
		_show_status("确认指令验证失败，请输入“确认”或“Confirm”", Color(1.0, 0.3, 0.3))
		return

	# 执行导出
	_export_save(input_key)

func _verify_api_key(input_key: String) -> bool:
	"""验证输入的是否为确认指令（不区分大小写）"""
	return input_key.to_lower() == "确认" or input_key.to_lower() == "confirm"

# func _verify_api_key(input_key: String) -> bool:
# 	"""验证输入的API密钥是否匹配"""
# 	# 使用统一的AI配置加载器
# 	var ai_service = get_node_or_null("/root/AIService")
# 	if ai_service and ai_service.config_loader:
# 		var chat_config = ai_service.config_loader.get_model_config("chat_model")
# 		if not chat_config.is_empty():
# 			var api_key = chat_config.get("api_key", "")
# 			if api_key == input_key:
# 				return true
# 	return false

func _export_save(_api_key: String):
	"""导出存档为zip文件"""
	_show_status("正在整理存档...", Color(0.3, 0.8, 1.0))
	# 获取user://目录的实际路径
	var user_path = OS.get_user_data_dir()

	# 生成导出文件名（带时间戳）
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var export_filename = "CABM-ED_Save_%s.zip" % timestamp

	# 使用文件对话框让用户选择保存位置
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.current_file = export_filename
	file_dialog.add_filter("*.zip", "存档文件")
	file_dialog.file_selected.connect(_on_export_path_selected.bind(user_path, file_dialog))
	get_tree().root.add_child(file_dialog)
	file_dialog.popup_centered(Vector2i(800, 600))

func _on_export_path_selected(export_path: String, user_path: String, dialog: FileDialog):
	"""用户选择了导出路径"""
	dialog.queue_free()
	# 等待对话框完全关闭
	await get_tree().process_frame
	await get_tree().process_frame

	export_button.disabled = true
	_show_status("正在整理存档...", Color(0.3, 0.8, 1.0))

	# 再等待一帧确保UI更新
	await get_tree().process_frame

	# 构建排除列表
	var exclusions = ["shader_cache"]
	if not chk_speech.button_pressed:
		exclusions.append_array(["speech", "recordings","voices"])
	if not chk_logs.button_pressed:
		exclusions.append_array(["ai_logs", "logs"])
	if not chk_music.button_pressed:
		exclusions.append_array(["custom_bgm"])
	if not chk_resources.button_pressed:
		exclusions.append_array(["*.utf8", "sleep", "ResourceList.json", "clothes"])

	var zip = ZIPPacker.new()
	var err = zip.open(export_path)
	if err != OK:
		_show_status("✗ 导出失败：无法创建压缩文件", Color(1.0, 0.3, 0.3))
		export_button.disabled = false
		return

	var success = await _zip_directory(user_path, zip, exclusions)
	zip.close()
	if success:
		_show_status("✓ 导出成功: " + export_path, Color(0.3, 1.0, 0.3))
		print("存档导出成功: ", export_path)
	else:
		_show_status("✗ 导出失败", Color(1.0, 0.3, 0.3))

	export_button.disabled = false

func _zip_directory(root_path: String, zip: ZIPPacker, exclusions: Array) -> bool:
	return await _zip_walk(root_path, "", zip, exclusions, 0)

func _zip_walk(abs_path: String, rel_path: String, zip: ZIPPacker, exclusions: Array, file_count: int) -> bool:
	var dir = DirAccess.open(abs_path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var child_abs = abs_path + "/" + file_name
		var child_rel = file_name if rel_path == "" else rel_path + "/" + file_name
		
		if dir.current_is_dir():
			if not _should_exclude(child_rel, exclusions):
				var result = await _zip_walk(child_abs, child_rel, zip, exclusions, file_count)
				if not result:
					dir.list_dir_end()
					return false
		else:
			if not _should_exclude(child_rel, exclusions):
				var bytes = FileAccess.get_file_as_bytes(child_abs)
				var err = zip.start_file(child_rel)
				if err != OK:
					dir.list_dir_end()
					return false
				err = zip.write_file(bytes)
				if err != OK:
					dir.list_dir_end()
					return false
				err = zip.close_file()
				if err != OK:
					dir.list_dir_end()
					return false
				
				file_count += 1
				# 每处理10个文件让出一帧，让UI更新
				if file_count % 10 == 0:
					_show_status("正在导出存档... (%d 个文件)" % file_count, Color(0.3, 0.8, 1.0))
					await get_tree().process_frame
		
		file_name = dir.get_next()
	dir.list_dir_end()
	return true

func _should_exclude(rel_path: String, exclusions: Array) -> bool:
	var base = rel_path.get_file()
	for ex in exclusions:
		if typeof(ex) == TYPE_STRING:
			var s: String = ex
			if s.find("*") != -1 or s.find("?") != -1:
				if base.match(s) or rel_path.match(s):
					return true
			else:
				if rel_path.contains("/" + s + "/") or base == s or rel_path.begins_with(s + "/"):
					return true
	return false

func _show_status(message: String, color: Color):
	"""显示状态信息"""
	status_label.add_theme_color_override("font_color", color)
	status_label.text = message

func _on_cloud_backup_pressed():
	"""处理云备份按钮点击"""
	# 确保UUID已初始化
	if current_uuid.is_empty():
		_init_uuid()
	
	# 禁用按钮
	export_button.disabled = true
	cloud_backup_button.disabled = true
	
	_show_status("正在准备云备份...", Color(0.3, 0.8, 1.0))
	
	# 执行云备份
	await _perform_cloud_backup()
	
	# 恢复按钮
	export_button.disabled = false
	cloud_backup_button.disabled = false

func _perform_cloud_backup():
	"""执行云备份操作"""
	var user_path = OS.get_user_data_dir()
	
	# 创建临时zip文件
	var temp_zip_path = user_path + "/cloud_backup_temp.zip"
	
	# 要打包的文件列表
	var files_to_backup = [
		"memory_main_memory.json",
		"memory_graph.json",
		"uuid.txt"  # 也备份UUID文件
	]
	
	# 要打包的目录
	var dirs_to_backup = [
		"saves",
		"companion",
		"story",
		"diary"
	]
	
	_show_status("正在打包存档...", Color(0.3, 0.8, 1.0))
	await get_tree().process_frame
	
	# 创建zip文件
	var zip = ZIPPacker.new()
	var err = zip.open(temp_zip_path)
	if err != OK:
		_show_status("✗ 云备份失败：无法创建临时文件", Color(1.0, 0.3, 0.3))
		return
	
	# 添加文件到zip
	for file_name in files_to_backup:
		var file_path = user_path + "/" + file_name
		if FileAccess.file_exists(file_path):
			var bytes = FileAccess.get_file_as_bytes(file_path)
			zip.start_file(file_name)
			zip.write_file(bytes)
			zip.close_file()
	
	# 添加目录到zip
	for dir_name in dirs_to_backup:
		var dir_path = user_path + "/" + dir_name
		if DirAccess.dir_exists_absolute(dir_path):
			await _zip_directory_for_cloud(dir_path, dir_name, zip)
	
	zip.close()

	_show_status("正在上传到云端...", Color(0.3, 0.8, 1.0))
	await get_tree().process_frame
	
	# 读取zip文件内容
	var zip_bytes = FileAccess.get_file_as_bytes(temp_zip_path)
	if zip_bytes == null or zip_bytes.size() == 0:
		_show_status("✗ 云备份失败：无法读取打包文件", Color(1.0, 0.3, 0.3))
		DirAccess.remove_absolute(temp_zip_path)
		return
	
	# 上传到服务器（使用新的URL格式）
	var http = HTTPRequest.new()
	add_child(http)
	
	# 构建新的URL格式：api/upload/<uuid>
	var url = "https://cabm.shasnow.top/api/upload/%s" % current_uuid
	var headers = ["Content-Type: application/zip","Content-Length: " + str(zip_bytes.size())]
	
	http.request_completed.connect(_on_upload_completed.bind(http, temp_zip_path))
	err = http.request_raw(url, headers, HTTPClient.METHOD_POST, zip_bytes)
	
	if err != OK:
		_show_status("✗ 云备份失败：无法发送请求", Color(1.0, 0.3, 0.3))
		http.queue_free()
		DirAccess.remove_absolute(temp_zip_path)

func _zip_directory_for_cloud(abs_path: String, base_name: String, zip: ZIPPacker):
	"""为云备份打包目录（支持排除特定目录和文件类型）"""
	var dir = DirAccess.open(abs_path)
	if dir == null:
		return
	
	# 定义要排除的目录名（黑名单）
	var excluded_dirs = ["backgrounds"]
	# 定义要排除的文件后缀（黑名单）
	var excluded_extensions = [".jpeg",".png",".jpg",".wav",".mp3",".mp4",".tmp", ".log", ".cache", ".import"]
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name != "." and file_name != "..":
			var child_abs = abs_path + "/" + file_name
			var child_rel = base_name + "/" + file_name
			
			if dir.current_is_dir():
				# 检查是否是要排除的目录
				if file_name not in excluded_dirs:
					await _zip_directory_for_cloud(child_abs, child_rel, zip)
			else:
				# 检查文件后缀是否在排除列表中
				var should_exclude = false
				for ext in excluded_extensions:
					if file_name.ends_with(ext):
						should_exclude = true
						break
				
				if not should_exclude:
					var bytes = FileAccess.get_file_as_bytes(child_abs)
					if bytes != null:
						zip.start_file(child_rel)
						zip.write_file(bytes)
						zip.close_file()
		
		file_name = dir.get_next()
	
	dir.list_dir_end()

func _on_upload_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest, temp_zip_path: String):
	"""上传完成回调"""
	http.queue_free()
	
	# 删除临时文件
	DirAccess.remove_absolute(temp_zip_path)
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		_show_status("✓ 云备份成功", Color(0.3, 1.0, 0.3))
		print("云备份上传成功，UUID: ", current_uuid)
	else:
		_show_status("✗ 云备份失败：服务器响应错误 (代码: %d)" % response_code, Color(1.0, 0.3, 0.3))
		print("云备份失败: result=", result, " response_code=", response_code, " UUID=", current_uuid)
