extends Node
class_name ASMRTTSManager

# ASMR TTS管理器
# 负责TTS队列管理、播放控制

signal sentence_playback_started(sentence_hash: String)
signal sentence_playback_finished(sentence_hash: String)
signal tts_error(error_message: String)

# TTS服务
var tts_service: Node = null

# 播放队列
var playback_queue: Array = []
var sentence_data: Dictionary = {}

# 状态
var is_playing: bool = false
var is_waiting_for_audio: bool = false
var current_playing_hash: String = ""
var voice_enabled: bool = true

# 句子缓冲区 - 使用SentenceSplitter的流式状态
var stream_state: SentenceSplitter.StreamState = null
const END_MARKER = "END_MARKER"

# 处理循环
var processing_active: bool = false

func _ready():
	tts_service = get_node_or_null("/root/TTSService")
	if not tts_service:
		push_error("无法获取TTSService")
		return
	
	tts_service.tts_error.connect(_on_tts_error)
	_load_voice_settings()
	
	# 初始化流式分句状态
	stream_state = SentenceSplitter.StreamState.new()
	
	_start_processing_loop()

func _load_voice_settings():
	"""加载语音开关"""
	var settings_path = "user://tts_settings.json"
	if FileAccess.file_exists(settings_path):
		var file = FileAccess.open(settings_path, FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_string) == OK:
			var settings = json.data
			voice_enabled = settings.get("enabled", false)

func set_voice_enabled(enabled: bool):
	"""设置语音开关"""
	voice_enabled = enabled
	if not enabled:
		clear_all()

func process_text_chunk(text: String):
	"""处理文本块"""
	if not voice_enabled or text.strip_edges().is_empty():
		return
	
	# 使用SentenceSplitter进行流式分句
	var sentences = SentenceSplitter.split_stream(stream_state, text, false)
	
	# 将提取出的句子入队
	for sentence_dict in sentences:
		_enqueue_sentence(sentence_dict.text)

func _enqueue_sentence(sentence: String):
	"""句子入队并请求TTS"""
	var sentence_hash = tts_service._compute_sentence_hash(sentence)
	
	if sentence_hash in playback_queue:
		return
	
	sentence_data[sentence_hash] = sentence
	playback_queue.append(sentence_hash)
	
	print("TTS入队: %s, 队列长度:%d" % [sentence.substr(0, 20), playback_queue.size()])
	
	tts_service.synthesize_speech(sentence)

func _start_processing_loop():
	"""启动处理循环"""
	if processing_active:
		return
	
	processing_active = true
	_processing_loop()

func _processing_loop():
	"""处理循环：从队列取出并播放"""
	while processing_active:
		if playback_queue.is_empty():
			await get_tree().process_frame
			continue
		
		var sentence_hash = playback_queue[0]
		
		# 检查结束标记
		if sentence_hash == END_MARKER:
			playback_queue.pop_front()
			sentence_playback_finished.emit(END_MARKER)
			continue
		
		# 先通知 TTS Service 这是当前要播放的句子（避免竞态条件）
		tts_service.on_new_sentence_displayed(sentence_hash)
		
		# 等待音频准备
		is_waiting_for_audio = true
		await _wait_for_audio_ready(sentence_hash)
		is_waiting_for_audio = false
		
		# 播放
		is_playing = true
		current_playing_hash = sentence_hash
		
		sentence_playback_started.emit(sentence_hash)
		
		# 等待播放完成
		await _wait_for_playback_finished()
		
		# 出队
		playback_queue.pop_front()
		is_playing = false
		current_playing_hash = ""
		
		sentence_playback_finished.emit(sentence_hash)

func _wait_for_audio_ready(sentence_hash: String):
	"""等待音频准备完毕"""
	var timeout = 30.0
	var elapsed = 0.0
	var check_interval = 0.1
	
	while elapsed < timeout:
		var state = tts_service.sentence_state.get(sentence_hash, "")
		if state == "ready":
			return
		
		await get_tree().create_timer(check_interval).timeout
		elapsed += check_interval
	
	push_error("TTS等待音频超时")
	tts_error.emit("等待音频超时")

func _wait_for_playback_finished():
	"""等待播放完成"""
	if tts_service.current_player.playing:
		await tts_service.current_player.finished
	
	await get_tree().create_timer(0.4).timeout

func set_voice_volume(volume_db: float):
	"""设置语音音量"""
	if not tts_service:
		return
	
	var linear_volume = db_to_linear(volume_db)
	tts_service.volume = clamp(linear_volume, 0.0, 1.0)
	
	if tts_service.current_player and tts_service.current_player.playing:
		tts_service.current_player.volume_db = volume_db

func _on_tts_error(error_message: String):
	"""TTS错误"""
	tts_error.emit(error_message)

func on_stream_finished():
	"""流式响应完成"""
	# 使用SentenceSplitter处理缓冲区剩余内容
	var remaining_sentences = SentenceSplitter.split_stream(stream_state, "", true)
	
	for sentence_dict in remaining_sentences:
		_enqueue_sentence(sentence_dict.text)
	
	playback_queue.append(END_MARKER)
	print("TTS添加结束标记，队列长度:", playback_queue.size())

func wait_for_all_finished():
	"""等待所有播放完成"""
	if not voice_enabled:
		return
	
	print("等待TTS播放完成...")
	
	while true:
		if playback_queue.is_empty() and not is_playing and not is_waiting_for_audio:
			print("TTS播放完成")
			break
		
		await get_tree().process_frame

func interrupt():
	"""中断播放"""
	print("中断TTS播放")
	
	if is_playing and tts_service and tts_service.current_player:
		tts_service.current_player.stop()
	
	is_playing = false
	is_waiting_for_audio = false

func clear_all():
	"""清空所有队列和状态"""
	print("清空TTS队列")
	
	interrupt()
	
	playback_queue.clear()
	sentence_data.clear()
	current_playing_hash = ""
	
	# 重置流式分句状态
	if stream_state:
		stream_state.buffer = ""
		stream_state.in_paren = false
	
	if tts_service:
		tts_service.clear_queue()
