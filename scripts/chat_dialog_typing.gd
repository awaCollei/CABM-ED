extends Node

# 打字机效果和流式输出模块
# 负责文本的逐字显示和句子分段
signal sentence_completed
signal all_sentences_completed
signal sentence_ready_for_tts(text: String) # 句子准备好进行TTS处理

const TYPING_SPEED = 0.05
var parent_dialog: Panel
var message_label: Label
var typing_timer: Timer


# 流式输出相关
var display_buffer: String = ""
var displayed_text: String = ""
var is_receiving_stream: bool = false

# 分段输出相关
var splitter_state: SentenceSplitter.StreamState = SentenceSplitter.StreamState.new()
var sentence_queue: Array = [] # 数组，元素为 {text: String, sentence_hash: String, no_tts: bool}
var current_sentence_index: int = 0
var is_showing_sentence: bool = false

const COLOR_NORMAL = Color.WHITE 
const COLOR_GRAY = Color.GRAY

func _ready():
	typing_timer = Timer.new()
	typing_timer.one_shot = false
	typing_timer.timeout.connect(_on_typing_timer_timeout)
	add_child(typing_timer)

func setup(dialog: Panel, msg_label: Label):
	parent_dialog = dialog
	message_label = msg_label

func start_stream():
	is_receiving_stream = true
	splitter_state = SentenceSplitter.StreamState.new()
	sentence_queue = []
	current_sentence_index = 0
	is_showing_sentence = false
	if message_label:
		message_label.add_theme_color_override("font_color", COLOR_NORMAL)

	message_label.text = ""

func add_stream_content(content: String):
	_extract_sentences(content, false)

func end_stream():
	is_receiving_stream = false
	_extract_sentences("", true)
	# 如果还没有开始显示，则开始显示第一句
	if not is_showing_sentence and sentence_queue.size() > 0:
		_show_next_sentence()

func has_content() -> bool:
	return sentence_queue.size() > 0 or not splitter_state.buffer.strip_edges().is_empty()

func show_next_sentence() -> String:
	"""显示下一个句子，并返回其哈希值"""
	# 确保当前句子已完全显示
	if not typing_timer.is_stopped():
		print("警告: 上一个句子仍在显示中，请等待完成")
		typing_timer.stop()
		displayed_text = display_buffer
		if message_label:
			message_label.add_theme_color_override("font_color", COLOR_NORMAL)

		message_label.text = displayed_text

	# 获取下一个句子的哈希值（在显示之前）
	var next_hash = ""
	if current_sentence_index < sentence_queue.size():
		next_hash = sentence_queue[current_sentence_index].sentence_hash

	_show_next_sentence()

	# 返回下一个句子的哈希值
	return next_hash

func has_more_sentences() -> bool:
	return current_sentence_index < sentence_queue.size()

func _extract_sentences(new_content: String, is_end: bool):
	# 使用 SentenceSplitter 的流式分句功能
	var sentences_data = SentenceSplitter.split_stream(splitter_state, new_content, is_end)
	for sentence_data in sentences_data:
		var text = sentence_data.text
		var no_tts = sentence_data.no_tts
		var sentence_entry = {
			"text": text,
			"sentence_hash": _compute_sentence_hash(text),
			"no_tts": no_tts
		}
		sentence_queue.append(sentence_entry)
		print("提取句子 hash:%s: %s (TTS: %s)" % [sentence_entry.sentence_hash.substr(0,8), text, not no_tts])

		# 仅在 no_tts 为 false 时发送 TTS 信号
		if not no_tts:
			sentence_ready_for_tts.emit(text)

	# 如果打字机未运行且有句子在队列中，则开始显示
	if not is_showing_sentence and sentence_queue.size() > 0 and typing_timer.is_stopped():
		if current_sentence_index < sentence_queue.size():
			print("检测到新句子，继续显示")
			_show_next_sentence()

func _show_next_sentence():
	# 防止重复调用
	if is_showing_sentence and not typing_timer.is_stopped():
		print("警告: 句子正在显示中，忽略重复调用")
		return

	if current_sentence_index >= sentence_queue.size():
		# 没有更多句子了
		if not is_receiving_stream:
			# 流已结束，确实没有更多句子了
			is_showing_sentence = false
			all_sentences_completed.emit()
			if message_label:
				message_label.add_theme_color_override("font_color", COLOR_NORMAL)
			print("所有句子显示完成")
		else:
			# 流仍在继续，但暂时没有新句子
			is_showing_sentence = false
			if message_label:
				message_label.add_theme_color_override("font_color", COLOR_NORMAL)
			print("等待流式传输更多句子...")
		return

	is_showing_sentence = true
	var sentence_entry = sentence_queue[current_sentence_index]

	# 在开始显示之前，通知 TTS 系统当前要显示的句子
	if has_node("/root/TTSService") and not sentence_entry.no_tts:
		var tts = get_node("/root/TTSService")
		tts.on_new_sentence_displayed(sentence_entry.sentence_hash)
		print("已通知 TTS句子 hash:%s" % sentence_entry.sentence_hash.substr(0,8))

	current_sentence_index += 1

	print("开始显示句子 hash:%s: %s (括号内: %s)" % [sentence_entry.sentence_hash.substr(0,8), sentence_entry.text, sentence_entry.no_tts])

	if sentence_entry.no_tts:
		# 如果是括号内内容，设置为灰色
		if message_label:
			message_label.add_theme_color_override("font_color", COLOR_GRAY)
	else:
		# 如果不是括号内内容，恢复原始颜色
		if message_label:
			message_label.add_theme_color_override("font_color", COLOR_NORMAL)
	# 重置显示缓冲区
	message_label.text = ""
	displayed_text = ""
	display_buffer = sentence_entry.text

	typing_timer.start(TYPING_SPEED)

func _on_typing_timer_timeout():
	if displayed_text.length() < display_buffer.length():
		var next_char = display_buffer[displayed_text.length()]
		displayed_text += next_char
		message_label.text = displayed_text
	else:
		typing_timer.stop()
		sentence_completed.emit()

func stop():
	if typing_timer:
		typing_timer.stop()
		if message_label:
			message_label.add_theme_color_override("font_color", COLOR_NORMAL)
	is_receiving_stream = false
	is_showing_sentence = false

func _compute_sentence_hash(original_text: String) -> String:
	if has_node("/root/TTSService"):
		var tts = get_node("/root/TTSService")
		if tts:
			if tts.has_method("compute_sentence_hash"):
				return tts.compute_sentence_hash(original_text)
			if tts.has_method("_compute_sentence_hash"):
				return tts._compute_sentence_hash(original_text)
	if original_text == null:
		original_text = ""
	var hashing_context = HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA256)
	hashing_context.update(str(original_text).to_utf8_buffer())
	var hash_bytes = hashing_context.finish()
	return hash_bytes.hex_encode()

func get_current_sentence_data() -> Dictionary:
	"""获取当前正在显示（或刚刚显示完）的句子数据"""
	if current_sentence_index > 0 and current_sentence_index <= sentence_queue.size():
		return sentence_queue[current_sentence_index - 1]
	return {}

func get_sentence_data_by_hash(sentence_hash: String) -> Dictionary:
	"""通过哈希值查找句子数据"""
	for entry in sentence_queue:
		if entry.sentence_hash == sentence_hash:
			return entry
	return {}
