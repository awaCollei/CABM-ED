extends Node

# TTS 服务 - 处理语音合成
# 自动加载单例

signal voice_ready(voice_uri: String) # 声音URI准备完成
signal audio_chunk_ready(audio_data: PackedByteArray) # 音频块准备完成
signal tts_error(error_message: String)

var config: Dictionary = {}
var voice_uri: String = "" # 当前使用的声音URI
var is_enabled: bool = false # 是否启用TTS
var volume: float = 0.8 # 音量 (0.0 - 1.0)
var speed: float = 1.0 # 语速 (0.25 - 4.0)
var language: String = "zh" # 当前选择语言: zh / en / ja
var current_voice_id: String = "" # 当前选择的声线ID

# 声线数据结构
# voice_cache.json 格式:
# {
#   "voices": [
#     {
#       "id": "builtin-zh",
#       "name": "默认-汉语",
#       "language": "zh",
#       "is_builtin": true,
#       "voice_uri": "...",
#       "audio_hash": "...",
#       "audio_path": "res://assets/audio/ref_zh.wav",
#       "reference_text": "..."
#     },
#     {
#       "id": "custom-xxx",
#       "name": "我的声线",
#       "language": "zh",
#       "is_builtin": false,
#       "voice_uri": "...",
#       "audio_hash": "...",
#       "audio_path": "user://voices/xxx.wav",
#       "reference_text": "..."
#     }
#   ],
#   "current_voice": {"zh": "builtin-zh", "en": "builtin-en", "ja": "builtin-ja"}
# }
var voices_data: Dictionary = {"voices": [], "current_voice": {}}

# 动态获取TTS配置的辅助函数
func _get_tts_config() -> Dictionary:
	"""每次调用时从配置加载器获取最新的TTS配置（包含api_key, model, base_url）"""
	var ai_service = get_node_or_null("/root/AIService")
	if ai_service and ai_service.config_loader:
		return ai_service.config_loader.get_model_config("tts_model")
	return {}

# TTS请求管理（句子为单位）
var tts_requests: Dictionary = {} # {sentence_hash: HTTPRequest}
var translate_requests: Dictionary = {}
var translate_callbacks: Dictionary = {}
var next_translate_id: int = 0

# 声线上传管理器
var voice_upload_manager: Node

# 句子跟踪系统（使用哈希作为句子唯一ID）
var sentence_audio: Dictionary = {} # {sentence_hash: audio_data 或 null}
var sentence_state: Dictionary = {} # {sentence_hash: "pending"|"ready"|"playing"}
var current_sentence_hash: String = "" # 当前正在显示/应播放的句子哈希
var playing_sentence_hash: String = "" # 正在播放的句子哈希

# 重试管理
var retry_count: Dictionary = {} # {sentence_hash: retry_count}
const MAX_RETRY_COUNT: int = 3

var current_player: AudioStreamPlayer
var is_playing: bool = false

# 中文标点符号
const CHINESE_PUNCTUATION = ["。", "！", "？", "；"]

func _ready():
	var sm = get_node_or_null("/root/SaveManager")
	if sm and not sm.is_resources_ready():
		return
	_load_config()
	_load_voice_cache()
	
	# 创建声线上传管理器
	var VoiceUploadManager = load("res://scripts/voice_upload_manager.gd")
	voice_upload_manager = VoiceUploadManager.new()
	add_child(voice_upload_manager)
	voice_upload_manager.upload_completed.connect(_on_upload_completed)
	voice_upload_manager.upload_failed.connect(_on_upload_failed)
	
	# 创建音频播放器
	current_player = AudioStreamPlayer.new()
	add_child(current_player)
	current_player.finished.connect(_on_audio_finished)
	
	# 初始化内置声线
	_init_builtin_voices()
	
	# 加载TTS设置（在声线初始化之后）
	_load_tts_settings()
	
	# 如果启用TTS且当前声线需要上传（voice_uri为空或audio_hash不匹配），上传参考音频
	if is_enabled:
		_check_and_upload_current_voice()

func _load_config():
	"""加载AI配置（包含TTS配置）"""
	var config_path = "res://config/ai_config.json"
	if not FileAccess.file_exists(config_path):
		push_error("AI配置文件不存在")
		return
	
	var file = FileAccess.open(config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) == OK:
		config = json.data
		print("TTS配置加载成功")
	else:
		push_error("AI配置解析失败")

func _load_tts_settings():
	"""加载TTS设置（启用状态、音量）"""
	var settings_path = "user://tts_settings.json"
	
	if FileAccess.file_exists(settings_path):
		var file = FileAccess.open(settings_path, FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		if json.parse(json_string) == OK:
			var settings = json.data
			is_enabled = settings.get("enabled", false)
			volume = settings.get("volume", 0.8)
			speed = settings.get("speed", 1.0)
			language = settings.get("language", "zh")
			current_voice_id = settings.get("current_voice_id", "")
			print("TTS设置加载成功: enabled=%s, volume=%.2f, speed=%.2f, language=%s, voice_id=%s" % [is_enabled, volume, speed, language, current_voice_id])
	
	# 同步 voice_uri（从当前声线数据中获取）
	var voice = _get_current_voice()
	if not voice.is_empty():
		voice_uri = voice.get("voice_uri", "")
		print("同步 voice_uri: %s" % voice_uri)
	
	# 验证配置是否可用（不缓存）
	var tts_config = _get_tts_config()
	var api_key = tts_config.get("api_key", "")
	var tts_model = tts_config.get("model", "")
	var tts_base_url = tts_config.get("base_url", "")
	
	# 最终状态总结
	print("=== TTS设置加载完成 ===")
	print("API密钥: %s" % ("已配置" if not api_key.is_empty() else "未配置"))
	print("模型: %s" % (tts_model if not tts_model.is_empty() else "未配置"))
	print("地址: %s" % (tts_base_url if not tts_base_url.is_empty() else "未配置"))
	print("启用状态: %s" % is_enabled)
	print("音量: %.2f" % volume)
	print("当前 voice_uri: %s" % voice_uri)

func reload_settings():
	"""重新加载TTS设置（公共接口）"""
	_load_tts_settings()
	print("TTS设置已重新加载")

func save_tts_settings():
	"""保存TTS设置（不保存API密钥）"""
	var settings = {
		"enabled": is_enabled,
		"volume": volume,
		"speed": speed,
		"language": language,
		"current_voice_id": current_voice_id
	}
	
	var settings_path = "user://tts_settings.json"
	var file = FileAccess.open(settings_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()
		print("TTS设置已保存（不包含API密钥）")

func set_speed(value: float):
	"""设置语速 (0.25 - 4.0)"""
	speed = clamp(value, 0.25, 4.0)
	save_tts_settings()
	print("TTS语速设置为: %.2f" % speed)

func _load_voice_cache():
	"""加载声线缓存"""
	var cache_path = "user://voice_cache.json"
	if FileAccess.file_exists(cache_path):
		var file = FileAccess.open(cache_path, FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_string) == OK:
			var cache = json.data
			
			# 检查是否为有效的新格式
			if cache.has("voices") && cache.has("current_voice"):
				voices_data = cache
				print("声线缓存加载成功")
			else:
				# 格式不正确，删除缓存文件
				DirAccess.remove_absolute(cache_path)
				print("旧格式缓存文件已删除，将重新生成")
				# 重新初始化 voices_data
				voices_data = {"voices": [], "current_voice": {}}
	
	# 确保current_voice有默认值
	for lang in ["zh", "en", "ja"]:
		if not voices_data.current_voice.has(lang):
			voices_data.current_voice[lang] = "builtin-%s" % lang

func _save_voice_cache():
	"""保存声线缓存"""
	var cache_path = "user://voice_cache.json"
	var file = FileAccess.open(cache_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(voices_data, "\t"))
		file.close()
		print("声线缓存已保存")

func _init_builtin_voices():
	"""初始化内置声线"""
	for lang in ["zh", "en", "ja"]:
		var voice_id = "builtin-%s" % lang
		var lang_name = {"zh":"汉语","en":"英语","ja":"日语"}[lang]
		
		# 检查是否已存在
		var exists = false
		for voice in voices_data.voices:
			if voice.id == voice_id:
				exists = true
				break
		
		if not exists:
			# 从配置文件读取参考文本
			var ref_text = ""
			if config.has("tts_model") && config.tts_model.has("reference_text"):
				var rt = config.tts_model.reference_text
				if typeof(rt) == TYPE_DICTIONARY:
					ref_text = rt.get(lang, "")
				elif typeof(rt) == TYPE_STRING && lang == "zh":
					ref_text = rt
			
			# 计算参考音频的哈希值
			var audio_path = "res://assets/audio/ref_%s.wav" % lang
			var audio_hash = ""
			if FileAccess.file_exists(audio_path):
				audio_hash = _calculate_file_hash(audio_path)
			
			voices_data.voices.append({
				"id": voice_id,
				"name": "默认-%s" % lang_name,
				"language": lang,
				"is_builtin": true,
				"voice_uri": "",
				"audio_hash": audio_hash,  # 使用计算出的哈希值
				"audio_path": audio_path,
				"reference_text": ref_text
			})
			print("初始化内置声线: %s (audio_hash: %s)" % [voice_id, audio_hash])
	
	# 设置当前声线
	if current_voice_id.is_empty():
		current_voice_id = voices_data.current_voice.get(language, "builtin-%s" % language)
	
	_save_voice_cache()

func _calculate_audio_hash() -> String:
	"""计算参考音频文件的SHA256哈希值
	可选参数: language ("zh","en","ja") 指定哪种参考音频文件
	如果文件不存在或无法读取返回空字符串
	"""
	return _calculate_audio_hash_for_lang("zh")

func _calculate_audio_hash_for_lang(lang: String) -> String:
	var ref_audio_path = "res://assets/audio/ref_%s.wav" % lang

	if not FileAccess.file_exists(ref_audio_path):
		push_error("参考音频文件不存在: " + ref_audio_path)
		return ""

	var audio_file = FileAccess.open(ref_audio_path, FileAccess.READ)
	if audio_file == null:
		push_error("无法打开参考音频文件: " + ref_audio_path)
		return ""

	var audio_data = audio_file.get_buffer(audio_file.get_length())
	audio_file.close()
	
	# 使用SHA256计算哈希值
	var hashing_context = HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA256)
	hashing_context.update(audio_data)
	var hash_bytes = hashing_context.finish()

	# 转换为十六进制字符串
	var hash_string = hash_bytes.hex_encode()

	return hash_string

func _calculate_file_hash(file_path: String) -> String:
	"""计算任意文件的SHA256哈希值"""
	if not FileAccess.file_exists(file_path):
		return ""
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ""
	
	var data = file.get_buffer(file.get_length())
	file.close()
	
	var hashing_context = HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA256)
	hashing_context.update(data)
	var hash_bytes = hashing_context.finish()
	
	return hash_bytes.hex_encode()

# === 声线管理函数 ===

func get_voices_for_language(lang: String) -> Array:
	"""获取指定语言的所有声线"""
	var result = []
	for voice in voices_data.voices:
		if voice.language == lang:
			result.append(voice)
	return result

func get_current_voice_id() -> String:
	"""获取当前声线ID"""
	return current_voice_id

func _get_current_voice() -> Dictionary:
	"""获取当前声线数据"""
	for voice in voices_data.voices:
		if voice.id == current_voice_id:
			return voice
	return {}

func set_current_voice(voice_id: String):
	"""设置当前声线"""
	# 验证声线是否存在
	var voice_exists = false
	var voice_lang = ""
	for voice in voices_data.voices:
		if voice.id == voice_id:
			voice_exists = true
			voice_lang = voice.language
			break
	
	if not voice_exists:
		push_error("声线不存在: %s" % voice_id)
		return
	
	current_voice_id = voice_id
	voices_data.current_voice[voice_lang] = voice_id
	
	# 更新voice_uri
	var voice = _get_current_voice()
	voice_uri = voice.get("voice_uri", "")
	
	_save_voice_cache()
	save_tts_settings()
	
	# 如果voice_uri为空，需要上传
	print("切换声线ID: %s, voice_uri: %s" % [voice_id, voice_uri])
	if voice_uri.is_empty() and is_enabled:
		_check_and_upload_current_voice()

func is_builtin_voice(voice_id: String) -> bool:
	"""检查是否为内置声线"""
	for voice in voices_data.voices:
		if voice.id == voice_id:
			return voice.get("is_builtin", false)
	return false

func voice_name_exists(voice_name: String, lang: String) -> bool:
	"""检查声线名称是否已存在"""
	for voice in voices_data.voices:
		if voice.name == voice_name and voice.language == lang:
			return true
	return false

func reload_builtin_voice(voice_id: String):
	"""重新加载内置声线"""
	if not is_builtin_voice(voice_id):
		push_error("只能重新加载内置声线")
		return
	
	# 清空voice_uri，强制重新上传
	for voice in voices_data.voices:
		if voice.id == voice_id:
			voice.voice_uri = ""
			voice.audio_hash = ""
			break
	
	_save_voice_cache()
	_check_and_upload_voice(voice_id)

func delete_voice(voice_id: String):
	"""删除自定义声线"""
	if is_builtin_voice(voice_id):
		MessageDisplay.show_failure_message("无法删除内置声线")
		return
	
	# 删除声线数据
	var voice_to_delete = null
	for i in range(voices_data.voices.size()):
		if voices_data.voices[i].id == voice_id:
			voice_to_delete = voices_data.voices[i]
			voices_data.voices.remove_at(i)
			break
	
	if voice_to_delete == null:
		return
	
	# 删除音频文件
	var audio_path = voice_to_delete.get("audio_path", "")
	if not audio_path.is_empty() and audio_path.begins_with("user://"):
		if FileAccess.file_exists(audio_path):
			DirAccess.remove_absolute(audio_path)
	
	# 如果删除的是当前声线，切换到默认声线
	if current_voice_id == voice_id:
		var lang = voice_to_delete.language
		current_voice_id = "builtin-%s" % lang
		voices_data.current_voice[lang] = current_voice_id
		var voice = _get_current_voice()
		voice_uri = voice.get("voice_uri", "")
	
	_save_voice_cache()
	save_tts_settings()

func add_custom_voice(voice_name: String, lang: String, audio_path: String, ref_text: String) -> bool:
	"""添加自定义声线
	
	返回: 是否成功
	"""
	# 生成唯一ID
	var voice_id = "custom-%s-%d" % [lang, Time.get_ticks_msec()]
	
	# 复制音频文件到user://voices/
	var voices_dir = "user://voices/"
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(voices_dir):
		dir.make_dir_recursive(voices_dir)
	
	var dest_path = voices_dir + voice_id + ".wav"
	var error = DirAccess.copy_absolute(audio_path, dest_path)
	if error != OK:
		push_error("复制音频文件失败: %d" % error)
		return false
	
	# 计算音频哈希
	var audio_hash = _calculate_file_hash(dest_path)
	
	# 添加到声线列表
	var voice_data = {
		"id": voice_id,
		"name": voice_name,
		"language": lang,
		"is_builtin": false,
		"voice_uri": "",
		"audio_hash": audio_hash,
		"audio_path": dest_path,
		"reference_text": ref_text
	}
	
	voices_data.voices.append(voice_data)
	_save_voice_cache()
	
	# 上传参考音频
	await _check_and_upload_voice(voice_id)
	
	return true

func _check_and_upload_current_voice():
	"""检查并上传当前声线（如果需要）"""
	var current_voice = _get_current_voice()
	if current_voice.is_empty():
		return
	
	var audio_path = current_voice.get("audio_path", "")
	var current_hash = ""
	if !audio_path.is_empty() && FileAccess.file_exists(audio_path):
		current_hash = _calculate_file_hash(audio_path)
	var cached_hash = current_voice.get("audio_hash", "")
	
	# 检查是否需要上传：voice_uri为空或哈希值不匹配
	if current_voice.get("voice_uri", "").is_empty() || current_hash != cached_hash:
		print("参考音频需要上传：voice_uri为空或audio_hash不匹配")
		print("当前哈希: %s, 缓存哈希: %s" % [current_hash, cached_hash])
		_check_and_upload_voice(current_voice_id)

func _check_and_upload_voice(voice_id: String):
	"""检查并上传指定声线"""
	var voice = null
	for v in voices_data.voices:
		if v.id == voice_id:
			voice = v
			break
	
	if voice == null:
		push_error("声线不存在: %s" % voice_id)
		return
	
	if voice_upload_manager:
		voice_upload_manager.upload_voice(voice_id, voice)

func _on_upload_completed(voice_id: String, voice_uri_result: String):
	"""上传完成回调"""
	# 更新声线的voice_uri
	for voice in voices_data.voices:
		if voice.id == voice_id:
			voice.voice_uri = voice_uri_result
			
			# 更新audio_hash为当前文件的哈希值
			var audio_path = voice.get("audio_path", "")
			if !audio_path.is_empty() && FileAccess.file_exists(audio_path):
				voice.audio_hash = _calculate_file_hash(audio_path)
			
			print("✓ 声线URI获取成功: %s -> %s (audio_hash: %s)" % [voice.name, voice_uri_result, voice.audio_hash])
			
			# 如果是当前声线，更新voice_uri并通知
			if voice_id == current_voice_id:
				voice_uri = voice_uri_result
				voice_ready.emit(voice_uri)
			break
	
	_save_voice_cache()

func _on_upload_failed(voice_id: String, error_message: String):
	"""上传失败回调"""
	push_error("声线 %s 上传失败: %s" % [voice_id, error_message])
	tts_error.emit(error_message)

func _remove_parentheses(text: String) -> String:
	"""移除括号"""
	var result = text
	
	# 移除所有成对括号及内容
	var paired_regex = RegEx.new()
	paired_regex.compile("(\\([^)]*\\)|（[^）]*）|\\[[^]]*\\]|【[^】]*】|\\{[^}]*\\}|<[^>]*>)")
	result = paired_regex.sub(result, "", true)
	
	# 移除所有单边括号情况
	# 匹配 "(xxx" 或 "xxx)" 的模式
	var single_regex = RegEx.new()
	# 这个正则匹配：左括号开头的内容 或 右括号结尾的内容
	single_regex.compile("(^\\([^)]*|^（[^）]*|^\\[[^]]*|^【[^】]*|^\\{[^}]*|^<[^>]*|[^)]*\\)$|[^）]*）$|[^]]*\\]$|[^】]*】$|[^}]*\\}$|[^>]*>$)")
	result = single_regex.sub(result, "", true)
	
	# 清理空格
	result = result.strip_edges()
	var spaces = RegEx.new()
	spaces.compile("\\s+")
	result = spaces.sub(result, " ")
	
	return result

func compute_sentence_hash(original_text: String, lang: String = "", voice_tag: String = "", speed_value: float = -1.0) -> String:
	if original_text == null:
		original_text = ""
	original_text = str(original_text)
	var chosen_lang = lang if not lang.is_empty() else language
	var chosen_voice = voice_tag
	if chosen_voice.is_empty():
		chosen_voice = current_voice_id
	if chosen_voice.is_empty():
		chosen_voice = voice_uri
	var chosen_speed = speed_value if speed_value >= 0.0 else speed
	var cache_key = "%s|%s|%s|%.4f" % [original_text, chosen_lang, chosen_voice, chosen_speed]
	var hashing_context = HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA256)
	hashing_context.update(cache_key.to_utf8_buffer())
	var hash_bytes = hashing_context.finish()
	return hash_bytes.hex_encode()

func _compute_sentence_hash(original_text: String) -> String:
	return compute_sentence_hash(original_text)

func _short_hash(h: String) -> String:
	if h == null:
		return "(null)"
	if h == "":
		return "(empty)"
	var s = str(h)
	if s.length() <= 8:
		return s
	return s.substr(0, 8)

func synthesize_speech(text: String, lang: String = ""):
	"""合成语音（入口）
	- 如果 lang 为空，使用当前self.language
	- 如果语言不是中文（zh），先调用翻译（summary_model.translation）再合成
	"""
	if not is_enabled:
		return

	if text.strip_edges().is_empty():
		return

	var chosen_lang = lang if not lang.is_empty() else language

	# 保留原始文本用于哈希（未翻译，未去除括号）
	var original_text = text
	var sentence_hash = compute_sentence_hash(original_text, chosen_lang)

	# 对用于合成的文本继续进行后处理（移除括号）
	text = _remove_parentheses(original_text)
	if text.is_empty():
		return

	# 仅在第一次见到该哈希时初始化状态
	if not sentence_state.has(sentence_hash):
		sentence_state[sentence_hash] = "pending"
		sentence_audio[sentence_hash] = null
		print("初始化句子 hash:%s 的状态为 pending" % _short_hash(sentence_hash))

	print("=== 新句子 hash:%s (%s) ===" % [_short_hash(sentence_hash), chosen_lang])
	print("原文: ", original_text)
	print("用于合成的文本: ", text)

	# 如果已经有音频数据（内存或磁盘缓存），跳过TTS请求
	var cached_audio = sentence_audio.get(sentence_hash, null)
	if cached_audio != null and cached_audio.size() > 0:
		print("【缓存命中】句子 hash:%s 已有缓存，跳过TTS请求" % _short_hash(sentence_hash))
		return

	# 如果目标语言不是中文，先进行翻译（翻译结果仍与该哈希绑定）
	if chosen_lang != "zh":
		translate_text(chosen_lang, text, func(translated_text: String) -> void:
			_on_translation_ready(sentence_hash, translated_text, chosen_lang)
		)
	else:
		_on_translation_ready(sentence_hash, text, chosen_lang)

func _on_translation_ready(sentence_hash: String, text: String, lang: String):
	"""翻译完成或无需翻译时触发"""
	if text.strip_edges().is_empty():
		print("句子 hash:%s 翻译后为空，跳过" % _short_hash(sentence_hash))
		return

	print("句子 hash:%s 已准备翻译，开始合成语音" % _short_hash(sentence_hash))
	_synthesize_with_voice(sentence_hash, text, lang)

func translate_text(target_lang: String, text: String, callback: Callable) -> void:
	"""使用 summary_model.translation 配置将 text 翻译到 target_lang，回调呼回传入翻译后的文本"""
	var ai_service = get_node_or_null("/root/AIService")
	var summary_conf = {}
	if ai_service and ai_service.config.has("summary_model"):
		summary_conf = ai_service.config.summary_model
	else:
		push_error("未配置 summary_model，无法进行翻译")
		callback.call("")
		return

	var model = summary_conf.get("model", "")
	var base_url = summary_conf.get("base_url", "")
	var trans_params = summary_conf.get("translation", {})

	var system_prompt = trans_params.get("system_prompt", "")
	system_prompt = system_prompt.replace("{language}", target_lang)

	var messages = [
		{"role":"system","content": system_prompt},
		{"role":"user","content": text}
	]

	var body = {
		"model": model,
		"messages": messages,
		"max_tokens": int(trans_params.get("max_tokens", 256)),
		"temperature": float(trans_params.get("temperature", 0.2)),
		"top_p": float(trans_params.get("top_p", 0.7))
	}

	var tid = next_translate_id
	next_translate_id += 1

	var http_request = HTTPRequest.new()
	add_child(http_request)
	translate_requests[tid] = http_request
	translate_callbacks[tid] = callback
	http_request.request_completed.connect(_on_translate_completed.bind(tid, http_request))

	var url = base_url + "/chat/completions"
	var translate_config = ai_service.config_loader.get_model_config("summary_model")
	var auth_key = translate_config.api_key
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + auth_key]
	var json_body = JSON.stringify(body)
	var err = http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		push_error("翻译请求发送失败: %s" % str(err))
		translate_requests.erase(tid)
		var cb = translate_callbacks.get(tid, null)
		translate_callbacks.erase(tid)
		if cb:
			cb.call("")

func _on_translate_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, tid: int, http_request: HTTPRequest):
	print("翻译请求完成: tid=%d, result=%d, code=%d" % [tid, result, response_code])
	var cb = translate_callbacks.get(tid, null)
	translate_requests.erase(tid)
	translate_callbacks.erase(tid)
	if http_request:
		http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if cb:
			cb.call("")
		return

	var response_text = body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(response_text) != OK:
		if cb:
			cb.call("")
		return

	var response = json.data
	# 修复这里：将 empty() 改为 is_empty()
	if not response.has("choices") or response.choices.is_empty():
		if cb:
			cb.call("")
		return

	var message = response.choices[0].get("message", null)
	var translated = ""
	if message and message.has("content"):
		translated = message.content

	if cb:
		cb.call(translated)

func _synthesize_with_voice(sentence_hash: String, text: String, lang: String):
	"""发送TTS请求

	参数:
	- sentence_id: 句子ID（用于追踪句子）
	- text: 要合成的文本
	- lang: 目标语言
	"""
	# 获取TTS配置
	var tts_config = _get_tts_config()
	var api_key = tts_config.get("api_key", "")
	var tts_model = tts_config.get("model", "")
	var tts_base_url = tts_config.get("base_url", "")
	
	if api_key.is_empty():
		push_error("TTS API密钥未配置")
		return

	# 使用当前声线的voice_uri
	if voice_uri.is_empty():
		push_error("声音URI未准备好，跳过 hash:%s" % _short_hash(sentence_hash))
		return

	print("=== 开始TTS请求 hash:%s (%s) ===" % [_short_hash(sentence_hash), lang])
	print("文本: ", text)

	var http_request = HTTPRequest.new()
	add_child(http_request)

	http_request.set_meta("sentence_hash", sentence_hash)
	http_request.set_meta("text", text)
	http_request.set_meta("lang", lang)

	http_request.request_completed.connect(_on_tts_completed.bind(sentence_hash, http_request))
	tts_requests[sentence_hash] = http_request

	if tts_base_url.is_empty() or tts_model.is_empty():
		push_error("TTS配置不完整（model或base_url未配置）")
		tts_requests.erase(sentence_hash)
		http_request.queue_free()
		return

	var url = tts_base_url + "/audio/speech"
	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	]

	var request_body = {
		"model": tts_model,
		"input": text,
		"voice": voice_uri,
		"speed": speed
	}

	var json_body = JSON.stringify(request_body)
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		push_error("TTS请求 hash:%s 发送失败: %s" % [_short_hash(sentence_hash), str(error)])
		tts_requests.erase(sentence_hash)
		http_request.queue_free()
	else:
		print("TTS请求 hash:%s 已发送" % _short_hash(sentence_hash))

func _on_tts_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, sentence_hash: String, http_request: HTTPRequest):
	"""TTS请求完成回调"""
	var text = http_request.get_meta("text", "")
	var lang = http_request.get_meta("lang", "")
	print("=== TTS请求 hash:%s 完成 ===" % _short_hash(sentence_hash))
	print("文本: ", text)
	print("result: %d, response_code: %d, body_size: %d" % [result, response_code, body.size()])

	# 清理请求节点
	tts_requests.erase(sentence_hash)
	http_request.queue_free()

	# 初始化重试计数器
	if not retry_count.has(sentence_hash):
		retry_count[sentence_hash] = 0

	# 检查是否应该重试
	var should_retry = false
	var error_msg = ""

	# 超时不重试，只有响应错误才重试
	if result != HTTPRequest.RESULT_SUCCESS:
		error_msg = "TTS请求 hash:%s 超时失败: %s" % [_short_hash(sentence_hash), str(result)]
		print(error_msg)
		tts_error.emit(error_msg)
		# 超时不重试
	elif response_code >= 400 and response_code < 600:  # 4xx, 5xx 错误
		var current_retry = retry_count.get(sentence_hash, 0)
		if current_retry < MAX_RETRY_COUNT:
			should_retry = true
			error_msg = "TTS请求 hash:%s 服务器错误 (%d)，准备重试 (%d/%d)" % [_short_hash(sentence_hash), response_code, current_retry + 1, MAX_RETRY_COUNT]
			print(error_msg)
			tts_error.emit(error_msg)
		else:
			error_msg = "TTS请求 hash:%s 服务器错误 (%d)，已达到最大重试次数 (%d)" % [_short_hash(sentence_hash), response_code, MAX_RETRY_COUNT]
			print(error_msg)
			tts_error.emit(error_msg)
	elif body.size() == 0:
		error_msg = "TTS请求 hash:%s 接收到的音频数据为空" % _short_hash(sentence_hash)
		print(error_msg)
		tts_error.emit(error_msg)

	# 如果需要重试
	if should_retry:
		var current_retry = retry_count.get(sentence_hash, 0) + 1
		retry_count[sentence_hash] = current_retry
		print("开始第 %d 次重试句子 hash:%s" % [current_retry, _short_hash(sentence_hash)])
		_synthesize_with_voice(sentence_hash, text, lang)
		return

	# 如果有有效的音频数据，保存并标记为ready
	if body.size() > 0 and result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		print("句子 hash:%s 接收到音频数据: %d 字节" % [_short_hash(sentence_hash), body.size()])

		# 保存音频文件到永久存储
		_save_audio_to_file(sentence_hash, body)

		# 存储音频数据
		sentence_audio[sentence_hash] = body
		sentence_state[sentence_hash] = "ready"

		audio_chunk_ready.emit(body)
		var cur_disp = "(none)"
		if current_sentence_hash != "":
			cur_disp = _short_hash(current_sentence_hash)
		print("句子 hash:%s 状态更新为 ready，当前应播放 hash:%s" % [_short_hash(sentence_hash), cur_disp])

		# 只有当这个句子是当前应该播放的句子时，才尝试播放
		if sentence_hash == current_sentence_hash:
			_try_play_sentence()
		else:
			print("句子 hash:%s 不是当前应播放的句子（当前 hash:%s），暂不播放" % [_short_hash(sentence_hash), _short_hash(current_sentence_hash)])
	else:
		# 没有有效音频数据，但仍然保存空的音频数据以避免重复请求
		sentence_audio[sentence_hash] = PackedByteArray()
		print("句子 hash:%s 没有有效的音频数据，标记为空" % _short_hash(sentence_hash))
		
		# 如果是当前应播放的句子，通知对话框继续（当作语音播完了）
		if sentence_hash == current_sentence_hash:
			print("句子 hash:%s 是当前应播放的句子，但 TTS 失败，1秒后通知对话框继续" % _short_hash(sentence_hash))
			get_tree().create_timer(1.0).timeout.connect(_notify_voice_finished)

func _save_audio_to_file(sentence_hash: String, audio_data: PackedByteArray) -> bool:
	"""保存音频数据到 user://speech/ 目录，使用哈希作为文件名
	
	返回: 是否保存成功
	"""
	# 确保目录存在
	var dir_path = "user://speech/"
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(dir_path):
		var error = dir.make_dir_recursive(dir_path)
		if error != OK:
			push_error("创建目录失败: user://speech/")
			return false
	
	# 构建文件路径（使用哈希作为文件名，保存为MP3格式）
	var file_path = dir_path + sentence_hash + ".mp3"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		var error = FileAccess.get_open_error()
		push_error("无法创建音频文件 %s (错误: %d)" % [file_path, error])
		return false
	
	# 写入音频数据
	file.store_buffer(audio_data)
	file.close()
	
	print("音频文件已保存: %s (%d 字节)" % [file_path, audio_data.size()])
	return true

func _load_audio_from_file(sentence_hash: String) -> bool:
	"""从磁盘加载缓存的音频文件
	
	返回: 是否加载成功
	"""
	var file_path = "user://speech/" + sentence_hash + ".mp3"
	
	# 检查文件是否存在
	if not FileAccess.file_exists(file_path):
		return false
	
	# 读取音频文件
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		var error = FileAccess.get_open_error()
		push_error("无法打开音频文件 %s (错误: %d)" % [file_path, error])
		return false
	
	var audio_data = file.get_buffer(file.get_length())
	file.close()
	
	if audio_data.size() == 0:
		print("音频文件为空: %s" % file_path)
		return false
	
	# 存储到内存缓存
	sentence_audio[sentence_hash] = audio_data
	sentence_state[sentence_hash] = "ready"
	
	print("【缓存命中】从磁盘加载音频缓存: %s (%d 字节)" % [file_path, audio_data.size()])
	return true
		
func on_new_sentence_displayed(sentence_hash: String):
	"""用户通知：某个句子（通过其哈希ID）已被显示。

	参数：
	- sentence_hash: 由句子原始文本计算的SHA256十六进制字符串（唯一ID）

	此函数会：
	1. 中断并停止正在播放的不同句子的音频
	2. 取消并放弃与当前显示句子无关的未完成TTS请求（节省资源）
	3. 尝试播放当前句子的语音（如果已准备好）
	"""

	print("=== 用户显示新句子 hash:%s ===" % _short_hash(sentence_hash))

	# 如果正在播放的是旧句子，立即中断
	if is_playing and playing_sentence_hash != sentence_hash:
		print("中断旧句子 hash:%s 的语音播放" % _short_hash(playing_sentence_hash))
		current_player.stop()
		is_playing = false
		# 将被中断的句子状态重置为ready，以便可以重新播放
		if sentence_state.has(playing_sentence_hash):
			sentence_state[playing_sentence_hash] = "ready"
			print("将被中断的句子 hash:%s 状态重置为 ready" % _short_hash(playing_sentence_hash))
		playing_sentence_hash = ""

	# 将当前期望播放的句子设置为该哈希
	current_sentence_hash = sentence_hash

	# 确保当前哈希有初始化的状态条目
	if not sentence_state.has(sentence_hash):
		sentence_state[sentence_hash] = "pending"
		sentence_audio[sentence_hash] = null
		print("初始化句子 hash:%s 的状态为 pending" % _short_hash(sentence_hash))
		
		# 尝试从磁盘加载缓存的音频
		_load_audio_from_file(sentence_hash)
	else:
		# 如果状态是playing，说明之前被中断了，重置为ready
		if sentence_state[sentence_hash] == "playing":
			sentence_state[sentence_hash] = "ready"
			print("句子 hash:%s 状态从 playing 重置为 ready" % _short_hash(sentence_hash))

	print("当前句子 hash:%s 的状态: %s" % [_short_hash(sentence_hash), sentence_state.get(sentence_hash, "unknown")])

	# 尝试播放
	_try_play_sentence()

func _try_play_sentence():
	"""尝试播放当前句子的语音（基于哈希ID）"""
	# 如果正在播放，先等播放完成
	if is_playing:
		print("正在播放句子 hash:%s，等待完成" % _short_hash(playing_sentence_hash))
		return

	# 如果没有当前句子哈希，等待
	if current_sentence_hash == "" or current_sentence_hash == null:
		print("当前没有要播放的句子，等待...")
		return

	var cur_hash = current_sentence_hash

	# 检查当前句子的状态
	var current_state = sentence_state.get(cur_hash, "")

	if current_state != "ready":
		print("句子 hash:%s 状态为 %s，等待..." % [_short_hash(cur_hash), current_state])
		return

	# 开始播放
	var audio_data = sentence_audio.get(cur_hash)
	if audio_data == null or audio_data.size() == 0:
		if sentence_state.get(cur_hash, "") == "ready" or audio_data != null:
			print("句子 hash:%s 音频为空，1秒后通知播完" % _short_hash(cur_hash))
			get_tree().create_timer(1.0).timeout.connect(_notify_voice_finished)
		else:
			print("错误：句子 hash:%s 的音频数据为 null 且状态不是 ready，等待..." % _short_hash(cur_hash))
		return

	print("=== 开始播放句子 hash:%s ===" % _short_hash(cur_hash))
	print("音频数据大小: %d 字节" % audio_data.size())

	is_playing = true
	playing_sentence_hash = cur_hash
	sentence_state[cur_hash] = "playing"

	# 将音频数据转换为AudioStream
	var stream = _create_audio_stream(audio_data)
	if stream:
		current_player.stream = stream
		current_player.volume_db = linear_to_db(volume)
		print("设置音量: %.2f (%.2f dB)" % [volume, linear_to_db(volume)])

		# 所有音频都跳过开头的静音
		var skip_time = _detect_silence_duration(stream)
		if skip_time > 0:
			print("检测到开头静音 %.2f 秒，跳过" % skip_time)
			current_player.play(skip_time)
		else:
			current_player.play()

		print("开始播放语音 hash:%s，音频流长度: %.2f 秒" % [_short_hash(current_sentence_hash), stream.get_length()])
	else:
		print("音频流创建失败，跳过")
		is_playing = false
		playing_sentence_hash = ""

func _create_audio_stream(audio_data: PackedByteArray) -> AudioStream:
	"""将音频数据转换为AudioStream"""
	# 检查数据是否有效
	if audio_data.size() == 0:
		push_error("音频数据为空")
		return null
	
	# 检查音频格式（前几个字节）
	var header = ""
	for i in range(min(4, audio_data.size())):
		header += "%02X " % audio_data[i]
	print("音频数据头: ", header)
	
	# API返回的是MP3格式
	var stream = AudioStreamMP3.new()
	stream.data = audio_data
	
	# 尝试获取音频长度来验证是否有效
	var length = stream.get_length()
	if length <= 0:
		push_error("音频流无效，长度: %.2f" % length)
		return null
	
	print("音频流创建成功，长度: %.2f 秒" % length)
	return stream

func _detect_silence_duration(_stream: AudioStream) -> float:
	"""检测音频开头的静音时长"""
	#由于Godot对于音频处理的支持有限，这里不进行处理
	return 0.0

func _on_audio_finished():
	"""音频播放完成"""
	print("句子 hash:%s 的语音播放完成" % _short_hash(playing_sentence_hash))
	
	# 将播放完成的句子状态重置为ready，以便可以再次播放
	if playing_sentence_hash != "" and sentence_state.has(playing_sentence_hash):
		sentence_state[playing_sentence_hash] = "ready"
	
	is_playing = false
	playing_sentence_hash = ""
	# 清空当前句子哈希，为下一句做准备
	# 这样可以避免竞态条件：下一句的音频可能在 on_new_sentence_displayed() 被调用之前就准备好了
	current_sentence_hash = ""

	# 通知聊天对话框语音播放完毕（用于重置计时器）
	_notify_voice_finished()

func _notify_voice_finished():
	"""通知聊天对话框语音播放完毕"""
	# 获取主场景中的聊天对话框
	var main_scene = get_tree().root.get_node_or_null("Main")
	if main_scene == null:
		return
	
	var chat_dialog = main_scene.get_node_or_null("ChatDialog")
	if chat_dialog == null:
		return
	
	# 如果聊天框可见且在等待继续状态，重置空闲计时器
	if chat_dialog.visible and chat_dialog.waiting_for_continue:
		if has_node("/root/EventManager"):
			var event_mgr = get_node("/root/EventManager")
			event_mgr.reset_idle_timer()
			print("语音播放完毕，重置空闲计时器")
		
		# 通知聊天框语音播放完毕，用于自动继续
		if chat_dialog.has_method("on_voice_finished"):
			chat_dialog.on_voice_finished()

func process_text_chunk(text: String):
	"""处理文本块，检测中文标点并合成语音"""
	if not is_enabled:
		return
	
	# 检查是否包含中文标点
	for punct in CHINESE_PUNCTUATION:
		if punct in text:
			# 按标点分割
			var sentences = text.split(punct, false)
			for i in range(sentences.size()):
				var sentence = sentences[i].strip_edges()
				if not sentence.is_empty():
					# 添加标点符号
					if i < sentences.size() - 1 or text.ends_with(punct):
						sentence += punct
					synthesize_speech(sentence)
			return
	
	# 如果没有标点，暂时不合成（等待更多文本）

func stop_playback():
	"""停止当前播放（不清空缓存）"""
	if current_player.playing:
		print("停止当前语音播放 hash:%s" % _short_hash(playing_sentence_hash))
		current_player.stop()
	
	# 将正在播放的句子状态重置为ready
	if is_playing and sentence_state.has(playing_sentence_hash):
		sentence_state[playing_sentence_hash] = "ready"
		print("将句子 hash:%s 状态重置为 ready" % _short_hash(playing_sentence_hash))
	
	is_playing = false
	playing_sentence_hash = ""
	current_sentence_hash = ""

func clear_queue():
	"""清空所有队列和缓冲"""
	# 取消所有进行中的TTS请求（keys 为句子哈希）
	for hash_key in tts_requests.keys():
		var http_request = tts_requests[hash_key]
		if http_request:
			http_request.cancel_request()
			http_request.queue_free()
	tts_requests.clear()

	# 清空句子相关数据
	sentence_audio.clear()
	sentence_state.clear()
	retry_count.clear()

	# 停止播放
	if current_player.playing:
		current_player.stop()
	is_playing = false
	playing_sentence_hash = ""

	# 重置当前句子哈希
	current_sentence_hash = ""

	print("所有队列和缓冲已清空（TTS请求 + 句子数据 + 重试计数器）")

func set_enabled(enabled: bool):
	"""设置是否启用TTS"""
	is_enabled = enabled
	save_tts_settings()
	print("设置TTS启用状态为: %s" % enabled)
	print("当前声线ID: %s, voice_uri: %s" % [current_voice_id, voice_uri])
	if enabled and voice_uri.is_empty():
		var voice = _get_current_voice()
		if not voice.is_empty():
			_check_and_upload_voice(current_voice_id)

func set_volume(vol: float):
	"""设置音量"""
	volume = clamp(vol, 0.0, 1.0)
	save_tts_settings()
	
	if current_player.playing:
		current_player.volume_db = linear_to_db(volume)
