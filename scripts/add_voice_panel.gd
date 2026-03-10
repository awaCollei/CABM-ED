extends Panel

# 添加声线面板

signal voice_added

@onready var close_button = $MarginContainer/VBoxContainer/TitleContainer/CloseButton
@onready var name_input = $MarginContainer/VBoxContainer/ScrollContainer/FormContainer/NameInput
@onready var language_option = $MarginContainer/VBoxContainer/ScrollContainer/FormContainer/LanguageOption
@onready var audio_path_label = $MarginContainer/VBoxContainer/ScrollContainer/FormContainer/AudioContainer/AudioPathLabel
@onready var select_audio_button = $MarginContainer/VBoxContainer/ScrollContainer/FormContainer/AudioContainer/SelectAudioButton
@onready var text_input = $MarginContainer/VBoxContainer/ScrollContainer/FormContainer/TextInput
@onready var status_label = $MarginContainer/VBoxContainer/StatusLabel
@onready var cancel_button = $MarginContainer/VBoxContainer/ButtonsContainer/CancelButton
@onready var confirm_button = $MarginContainer/VBoxContainer/ButtonsContainer/ConfirmButton

var selected_audio_path: String = ""
var _lang_index_map = {0: "zh", 1: "en", 2: "ja"}
var _audio_file_dialog: FileDialog = null

func _ready():
	close_button.pressed.connect(_on_close_pressed)
	select_audio_button.pressed.connect(_on_select_audio_pressed)
	cancel_button.pressed.connect(_on_close_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	
	# 初始化语言选项
	language_option.clear()
	language_option.add_item("汉语")
	language_option.add_item("英语")
	language_option.add_item("日语")
	language_option.select(0)

func _on_close_pressed():
	"""关闭面板"""
	queue_free()

func _on_select_audio_pressed():
	"""打开文件选择器选择音频文件（Android 下先请求存储权限）"""
	_show_audio_file_dialog()

func _show_audio_file_dialog():
	"""先请求权限（仅 Android），再弹出文件选择器"""
	if OS.has_feature("android"):
		var ap = get_node_or_null("/root/AndroidPermissions")
		if ap:
			await ap.request_storage_permission()
	
	if _audio_file_dialog != null:
		_audio_file_dialog.queue_free()
	
	_audio_file_dialog = FileDialog.new()
	_audio_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_audio_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_audio_file_dialog.add_filter("*.mp3,*.wav;音频文件")
	_audio_file_dialog.file_selected.connect(_on_file_selected)
	_audio_file_dialog.canceled.connect(_on_audio_file_dialog_canceled)
	_audio_file_dialog.use_native_dialog = true
	
	# 设置默认目录（Android 下尝试常用音频目录）
	if OS.has_feature("android"):
		var audio_paths = [
			"/storage/emulated/0/Music",
			"/storage/emulated/0/Download",
			"/storage/emulated/0/Ringtones",
			"/storage/emulated/0/Recordings",
			OS.get_system_dir(OS.SYSTEM_DIR_MUSIC),
			OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		]
		for p in audio_paths:
			if p and not p.is_empty() and DirAccess.dir_exists_absolute(p):
				_audio_file_dialog.current_dir = p
				break
	else:
		var music_dir = OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
		if not music_dir.is_empty():
			_audio_file_dialog.current_dir = music_dir
		else:
			var downloads_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
			if not downloads_dir.is_empty():
				_audio_file_dialog.current_dir = downloads_dir
	
	get_tree().root.add_child(_audio_file_dialog)
	_audio_file_dialog.popup_centered()

func _on_file_selected(path: String):
	"""文件选择完成"""
	selected_audio_path = path
	audio_path_label.text = path.get_file()

func _on_audio_file_dialog_canceled():
	"""文件选择取消"""
	# 可选的取消处理
	pass

func _on_confirm_pressed():
	"""确认添加声线"""
	var voice_name = name_input.text.strip_edges()
	var ref_text = text_input.text.strip_edges()
	var lang_idx = language_option.get_selected_id()
	var lang = _lang_index_map.get(lang_idx, "zh")
	
	# 验证输入
	if voice_name.is_empty():
		status_label.text = "⚠ 请输入声线名称"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		return
	
	if selected_audio_path.is_empty():
		status_label.text = "⚠ 请选择参考音频文件"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		return
	
	if ref_text.is_empty():
		status_label.text = "⚠ 请输入参考文本"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		return
	
	if not has_node("/root/TTSService"):
		status_label.text = "⚠ TTS服务未加载"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		return
	
	var tts = get_node("/root/TTSService")
	
	# 检查名称冲突
	if tts.voice_name_exists(voice_name, lang):
		status_label.text = "⚠ 该声线名称已存在"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		return
	
	# 禁用按钮
	confirm_button.disabled = true
	cancel_button.disabled = true
	
	status_label.text = "正在上传参考音频..."
	status_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	
	# 添加声线
	var success = await tts.add_custom_voice(voice_name, lang, selected_audio_path, ref_text)
	
	if success:
		status_label.text = "✓ 声线添加成功"
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		voice_added.emit()
		await get_tree().create_timer(1.0).timeout
		queue_free()
	else:
		status_label.text = "✗ 声线添加失败，请查看日志"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		confirm_button.disabled = false
		cancel_button.disabled = false
