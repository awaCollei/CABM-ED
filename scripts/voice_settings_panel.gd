extends MarginContainer

# 语音设置面板

@onready var enable_checkbox = $ScrollContainer/VBoxContainer/EnableContainer/EnableCheckBox
@onready var volume_slider = $ScrollContainer/VBoxContainer/SliderContainer/VolumeContainer/VolumeSlider
@onready var volume_value_label = $ScrollContainer/VBoxContainer/SliderContainer/VolumeContainer/VolumeValueLabel
@onready var status_label = $ScrollContainer/VBoxContainer/StatusLabel
@onready var language_option = $ScrollContainer/VBoxContainer/VBoxContainer/LanguageContainer/LanguageOption
@onready var voice_option = $ScrollContainer/VBoxContainer/VBoxContainer/VoiceContainer/VoiceOption
@onready var delete_voice_button = $ScrollContainer/VBoxContainer/VoiceButtonsContainer/DeleteVoiceButton
@onready var add_voice_button = $ScrollContainer/VBoxContainer/VoiceButtonsContainer/AddVoiceButton
@onready var speed_slider = $ScrollContainer/VBoxContainer/SliderContainer/SpeedContainer/SpeedSlider
@onready var speed_value_label = $ScrollContainer/VBoxContainer/SliderContainer/SpeedContainer/SpeedValueLabel
@onready var cache_cleanup_option = $ScrollContainer/VBoxContainer/EnableContainer/OptionButton

var _lang_index_map = {0: "zh", 1: "en", 2: "ja"}
var _lang_name_map = {"zh": "汉语", "en": "英语", "ja": "日语"}
var blue_theme = preload("res://theme/blue_button.tres")
var red_theme = preload("res://theme/red_button.tres")
const AddVoicePanelScene = preload("res://scenes/add_voice_panel.tscn")

# 确认对话框相关
var confirmation_dialog: AcceptDialog
var pending_voice_id: String  # 待删除的声线ID
var pending_voice_name: String  # 待删除的声线名称

func _ready():
	enable_checkbox.toggled.connect(_on_enable_toggled)
	volume_slider.value_changed.connect(_on_volume_changed)
	speed_slider.value_changed.connect(_on_speed_changed)
	language_option.item_selected.connect(_on_language_selected)
	voice_option.item_selected.connect(_on_voice_selected)
	delete_voice_button.pressed.connect(_on_delete_voice_pressed)
	add_voice_button.pressed.connect(_on_add_voice_pressed)
	cache_cleanup_option.item_selected.connect(_on_cache_cleanup_selected)
	
	# 初始化语言选项
	language_option.clear()
	language_option.add_item("汉语")
	language_option.add_item("英语")
	language_option.add_item("日语")
	
	# 创建确认对话框
	_create_confirmation_dialog()
	
	# 加载当前设置
	_load_settings()

func _create_confirmation_dialog():
	"""创建确认对话框"""
	confirmation_dialog = AcceptDialog.new()
	confirmation_dialog.title = "确认删除"
	confirmation_dialog.dialog_text = "确定要删除这个声线吗？此操作不可撤销。"
	confirmation_dialog.get_ok_button().text = "删除"
	confirmation_dialog.add_cancel_button("取消")
	confirmation_dialog.confirmed.connect(_on_confirmation_confirmed)
	confirmation_dialog.canceled.connect(_on_confirmation_canceled)
	confirmation_dialog.close_requested.connect(_on_confirmation_canceled)
	add_child(confirmation_dialog)

func _load_settings():
	"""加载当前TTS设置"""
	if not has_node("/root/TTSService"):
		status_label.text = "TTS服务未加载"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		return
	
	var tts = get_node("/root/TTSService")
	
	enable_checkbox.button_pressed = tts.is_enabled
	volume_slider.value = tts.volume
	_update_volume_label(tts.volume)
	
	speed_slider.value = tts.speed
	_update_speed_label(tts.speed)
	
	# 缓存清理设置
	cache_cleanup_option.select(tts.cache_cleanup_days)

	# 语言设置
	var current_lang = tts.language
	var idx = 0
	for k in _lang_index_map.keys():
		if _lang_index_map[k] == current_lang:
			idx = k
			break
	language_option.select(idx)
	
	# 刷新声线列表
	_refresh_voice_list()
	
	# 检查配置状态
	var tts_config = tts._get_tts_config()
	var api_key = tts_config.get("api_key", "")
	if api_key.is_empty():
		status_label.text = "⚠ 请在AI配置中设置TTS密钥"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	elif tts.voice_uri.is_empty():
		status_label.text = "⏳ 正在加载TTS..."
		status_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		# 连接voice_ready信号
		if not tts.voice_ready.is_connected(_on_voice_ready):
			tts.voice_ready.connect(_on_voice_ready)
	else:
		status_label.text = "✓ TTS已就绪"
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))

func _refresh_voice_list():
	"""刷新声线列表"""
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	var current_lang = tts.language
	
	voice_option.clear()
	
	# 加载voice_cache.json
	var voices = tts.get_voices_for_language(current_lang)
	
	var current_voice_id = tts.get_current_voice_id()
	var selected_idx = 0
	
	for i in range(voices.size()):
		var voice = voices[i]
		voice_option.add_item(voice.name)
		voice_option.set_item_metadata(i, voice.id)
		if voice.id == current_voice_id:
			selected_idx = i
	
	if voices.size() > 0:
		voice_option.select(selected_idx)
		_update_delete_button()

func _update_delete_button():
	"""更新删除/重新加载按钮"""
	if voice_option.get_selected_id() == -1:
		return
	
	var selected_idx = voice_option.get_selected_id()
	var voice_id = voice_option.get_item_metadata(selected_idx)
	
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	var is_builtin = tts.is_builtin_voice(voice_id)
	
	if is_builtin:
		delete_voice_button.theme = blue_theme
		delete_voice_button.text = "重新加载"
	else:
		delete_voice_button.theme = red_theme
		delete_voice_button.text = "删除声线"

func _on_enable_toggled(enabled: bool):
	"""启用/禁用TTS"""
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	tts.set_enabled(enabled)
	
	if enabled:
		status_label.text = "✓ TTS已启用"
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		status_label.text = "TTS已禁用"
		status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

func _on_language_selected(index: int) -> void:
	"""语言选择改变"""
	var lang = _lang_index_map.get(index, "zh")
	if not has_node("/root/TTSService"):
		return
	var tts = get_node("/root/TTSService")
	tts.language = lang
	
	# 切换到该语言的默认声线
	var new_voice_id = tts.voices_data.current_voice.get(lang, "builtin-%s" % lang)
	tts.set_current_voice(new_voice_id)
	
	# 刷新声线列表
	_refresh_voice_list()
	
	# 更新状态提示
	status_label.text = "语言已切换为 %s" % _lang_name_map.get(lang, lang)
	status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))

func _on_voice_selected(index: int) -> void:
	"""声线选择改变"""
	if index == -1:
		return
	
	var voice_id = voice_option.get_item_metadata(index)
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	tts.set_current_voice(voice_id)
	
	_update_delete_button()
	
	status_label.text = "声线已切换"
	status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))

func _on_delete_voice_pressed():
	"""删除或重新加载声线"""
	var selected_idx = voice_option.get_selected_id()
	if selected_idx == -1:
		return
	
	var voice_id = voice_option.get_item_metadata(selected_idx)
	var voice_name = voice_option.get_item_text(selected_idx)
	
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	var is_builtin = tts.is_builtin_voice(voice_id)
	
	if is_builtin:
		# 重新加载内置声线，不需要确认
		status_label.text = "正在重新上传参考音频..."
		status_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		tts.reload_builtin_voice(voice_id)
		await get_tree().create_timer(1.0).timeout
		status_label.text = "✓ 重新上传完成"
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		# 删除自定义声线，显示确认对话框
		pending_voice_id = voice_id
		pending_voice_name = voice_name
		confirmation_dialog.dialog_text = "确定要删除声线 \"%s\" 吗？此操作不可撤销。" % voice_name
		confirmation_dialog.popup_centered()

func _on_confirmation_confirmed():
	"""确认对话框确认"""
	if pending_voice_id.is_empty():
		return
	
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	tts.delete_voice(pending_voice_id)
	_refresh_voice_list()
	status_label.text = "✓ 声线已删除"
	status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	
	# 清空待删除记录
	pending_voice_id = ""
	pending_voice_name = ""

func _on_confirmation_canceled():
	"""确认对话框取消"""
	pending_voice_id = ""
	pending_voice_name = ""

func _on_add_voice_pressed():
	"""添加新声线"""
	var add_panel = AddVoicePanelScene.instantiate()
	get_tree().root.add_child(add_panel)
	add_panel.voice_added.connect(_on_voice_added)

func _on_voice_added():
	"""新声线添加完成"""
	_refresh_voice_list()
	status_label.text = "✓ 声线已添加"
	status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))

func _on_volume_changed(value: float):
	"""音量改变"""
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	tts.set_volume(value)
	_update_volume_label(value)

func _update_volume_label(value: float):
	"""更新音量显示"""
	volume_value_label.text = "%d%%" % int(value * 100)

func _on_speed_changed(value: float):
	"""语速改变"""
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	tts.set_speed(value)
	_update_speed_label(value)

func _update_speed_label(value: float):
	"""更新语速显示"""
	speed_value_label.text = "%.2fx" % value

func _on_voice_ready(_voice_uri: String):
	"""声音准备完成"""
	status_label.text = "✓ TTS已就绪"
	status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))

func _on_cache_cleanup_selected(index: int):
	"""缓存清理选项改变"""
	if not has_node("/root/TTSService"):
		return
	
	var tts = get_node("/root/TTSService")
	tts.set_cache_cleanup_days(index)
	
	var cleanup_text = ["不清理", "1个月", "7天", "1天"][index]
	status_label.text = "缓存清理设置为: %s，下次启动游戏时生效" % cleanup_text
	status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
