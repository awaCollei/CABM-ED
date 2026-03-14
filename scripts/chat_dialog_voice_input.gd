
extends Node

signal recording_started()
signal recording_stopped()
signal transcription_received(text: String)
signal transcription_error(error: String)

var parent_dialog: Panel
var mic_button: Button
var input_field: LineEdit

# 录音相关变量
var is_recording: bool = false
var recording_bus_index: int = -1
var mic_player: AudioStreamPlayer = null
var mic_stream: AudioStreamMicrophone = null
var record_effect: AudioEffectRecord = null
var recording: AudioStreamWAV = null
var record_start_ms: int = 0
var is_transcribing: bool = false
var is_shutting_down: bool = false

# 可视化
var mic_base_icon: Texture2D
var stop_icon: Texture2D
var load_icon: Texture2D
var is_voice_available: bool = false

func setup(dialog: Panel, mic_btn: Button, input_fld: LineEdit):
	parent_dialog = dialog
	mic_button = mic_btn
	input_field = input_fld
	
	# 预加载所有图标
	_load_icons()
	
	# 检查音频系统
	check_audio_system()
	
	# 连接 AI 服务信号
	if has_node("/root/AIService"):
		var ai = get_node("/root/AIService")
		if ai.has_signal("stt_result"):
			ai.stt_result.connect(_on_stt_result)
		if ai.has_signal("stt_error"):
			ai.stt_error.connect(_on_stt_error)

func _load_icons():
	# 预加载所有图标以确保导出后可用
	mic_base_icon = preload("res://assets/images/chat/microphone.png")
	stop_icon = preload("res://assets/images/chat/stop.png")
	load_icon = preload("res://assets/images/chat/load.png")
	# 设置默认图标
	if mic_base_icon and mic_button:
		mic_button.icon = mic_base_icon
		mic_button.tooltip_text = "点击开始录音"
	
	# 检查图标是否成功加载
	if not mic_base_icon:
		print("❌ 微信图标未找到，请检查路径: res://assets/images/chat/microphone.png")
	if not stop_icon:
		print("⚠️ 停止图标未找到: res://assets/images/chat/stop.png")
	if not load_icon:
		print("⚠️ 加载图标未找到: res://assets/images/chat/load.png")

func check_audio_system():
	print("🎧 音频系统检查...")
	
	var input_devices = AudioServer.get_input_device_list()
	if input_devices.size() > 0:
		print("✅ 找到输入设备: ", input_devices)
		AudioServer.input_device = input_devices[0]
		is_voice_available = true
	else:
		print("⚠️ 未列出音频输入设备，尝试使用系统默认输入")
		is_voice_available = true
		if mic_button:
			mic_button.disabled = false
			mic_button.tooltip_text = "点击开始录音"

func _on_mic_button_pressed():
	if not is_voice_available:
		print("⚠️ 音频输入不可用")
		return
	
	if is_recording:
		stop_recording()
	else:
		start_recording()

func start_recording():
	if is_recording:
		return
	if not is_voice_available:
		print("⚠️ 音频输入不可用")
		return
	
	print("🎤 开始录音...")

	record_start_ms = Time.get_ticks_msec()
	
	if recording_bus_index == -1:
		var idx = AudioServer.get_bus_index("Record")
		if idx == -1:
			var count = AudioServer.get_bus_count()
			AudioServer.add_bus(count)
			recording_bus_index = count
			AudioServer.set_bus_name(recording_bus_index, "Record")
		else:
			recording_bus_index = idx
		AudioServer.set_bus_mute(recording_bus_index, true)
		if AudioServer.get_bus_effect_count(recording_bus_index) > 0:
			record_effect = AudioServer.get_bus_effect(recording_bus_index, 0) as AudioEffectRecord
		else:
			record_effect = AudioEffectRecord.new()
			AudioServer.add_bus_effect(recording_bus_index, record_effect, 0)
		print("✅ 录音总线与录音效果已就绪")
	
	if record_effect:
		record_effect.set_recording_active(true)
	
	if not mic_player:
		mic_player = AudioStreamPlayer.new()
		add_child(mic_player)
		mic_player.bus = AudioServer.get_bus_name(recording_bus_index)
		print("✅ 麦克风播放器已创建")
	
	mic_stream = AudioStreamMicrophone.new()
	mic_player.stream = mic_stream
	mic_player.play()
	
	# 确保麦克风输入已连接
	if mic_stream:
		pass
	
	is_recording = true
	
	# 等待一帧确保音频系统已准备好
	await get_tree().process_frame
	
	# 更新按钮状态
	if mic_button:
		# 使用预加载的图标
		if stop_icon:
			mic_button.icon = stop_icon
			print("✅ 使用停止图标")
		else:
			print("⚠️ 停止图标未找到，使用默认图标")
			mic_button.icon = mic_base_icon
		mic_button.modulate = Color(1.0, 0.3, 0.3, 1.0)
		mic_button.tooltip_text = "点击停止录音"
		_start_mic_animation()
	
	recording_started.emit()
	print("🎙️ 录音进行中...")

func _process(_delta: float):
	pass

func stop_recording():
	if not is_recording:
		return
	
	print("🛑 停止录音...")
	is_recording = false
	
	# 停止麦克风播放器
	if mic_player and mic_player.playing:
		mic_player.stop()
		print("✅ 麦克风已停止")
	
	if record_effect and record_effect.is_recording_active():
		record_effect.set_recording_active(false)
	
	recording = null
	if record_effect:
		recording = record_effect.get_recording()
	
	if recording == null:
		print("❌ 未获取到录音数据")
		_update_mic_button_state(false)
		recording_stopped.emit()
		return
	
	# 规范化录音流为16位
	recording.set_format(AudioStreamWAV.FORMAT_16_BITS)

	# 计算时长并检测几乎无声音
	var duration_sec = _calculate_duration_seconds(recording)
	if duration_sec < 0.5:
		print("⚠️ 录音过短(%.2fs)，忽略" % duration_sec)
		_update_mic_button_state(false)
		recording_stopped.emit()
		return

	if _is_audio_silent(recording, 0.02):
		print("⚠️ 录音几乎无声音，忽略")
		_update_mic_button_state(false)
		recording_stopped.emit()
		return
		
	var wav_bytes = _recording_to_wav_bytes(recording)
	print("💾 生成的WAV文件大小: ", wav_bytes.size(), " 字节")
	
	# 进入转写等待状态：禁用按钮并显示加载图标
	is_transcribing = true
	_set_mic_loading_state(true)
	
	# 保存录音到文件
	if not is_shutting_down:
		_save_recording_to_file(wav_bytes)
	# 发送到STT
	if has_node("/root/AIService"):
		var ai_service = get_node("/root/AIService")
		print("🤖 发送录音给语音识别...")
		if not is_shutting_down:
			ai_service.transcribe_audio(wav_bytes, "recording.wav")
	else:
		print("⚠️ 未找到 AIService")
		# 无法转写，恢复按钮
		is_transcribing = false
		_set_mic_loading_state(false)
		_update_mic_button_state(false)
	
	recording_stopped.emit()

func _recording_to_wav_bytes(rec: AudioStreamWAV) -> PackedByteArray:
	var channels = 2 if rec.stereo else 1
	var sample_rate = rec.mix_rate
	var bits_per_sample = 16
	@warning_ignore("integer_division")
	var byte_rate = sample_rate * channels * (bits_per_sample / 8)
	@warning_ignore("integer_division")
	var block_align = channels * (bits_per_sample / 8)
	var data_bytes = rec.get_data()
	var header = PackedByteArray()
	header.append_array("RIFF".to_utf8_buffer())
	var total_size = 36 + data_bytes.size()
	header.append_array(_u32le(total_size))
	header.append_array("WAVE".to_utf8_buffer())
	header.append_array("fmt ".to_utf8_buffer())
	header.append_array(_u32le(16))
	header.append_array(_u16le(1))
	header.append_array(_u16le(channels))
	header.append_array(_u32le(sample_rate))
	header.append_array(_u32le(byte_rate))
	header.append_array(_u16le(block_align))
	header.append_array(_u16le(bits_per_sample))
	header.append_array("data".to_utf8_buffer())
	header.append_array(_u32le(data_bytes.size()))
	var wav = PackedByteArray()
	wav.append_array(header)
	wav.append_array(data_bytes)
	return wav

func _u16le(n: int) -> PackedByteArray:
	var a = PackedByteArray()
	a.resize(2)
	a[0] = n & 0xFF
	a[1] = (n >> 8) & 0xFF
	return a

func _u32le(n: int) -> PackedByteArray:
	var a = PackedByteArray()
	a.resize(4)
	a[0] = n & 0xFF
	a[1] = (n >> 8) & 0xFF
	a[2] = (n >> 16) & 0xFF
	a[3] = (n >> 24) & 0xFF
	return a

func _start_mic_animation():
	if mic_button:
		var tween = create_tween()
		tween.set_loops()
		# 颜色脉动 + 轻微透明度变化
		tween.tween_property(mic_button, "self_modulate", 
			Color(1.0, 0.6, 0.6, 1.0), 0.5)
		tween.set_trans(Tween.TRANS_SINE)
		tween.tween_property(mic_button, "self_modulate", 
			Color.WHITE, 0.5)
		tween.set_trans(Tween.TRANS_SINE)
		mic_button.set_meta("mic_tween", tween)

func _stop_mic_animation():
	if mic_button and mic_button.has_meta("mic_tween"):
		var tween = mic_button.get_meta("mic_tween")
		tween.kill()
		mic_button.self_modulate = Color.WHITE

func _update_mic_button_state(is_now_recording: bool):
	if mic_button:
		if is_now_recording:
			if stop_icon:
				mic_button.icon = stop_icon
			else:
				mic_button.icon = mic_base_icon
			mic_button.modulate = Color(1.0, 0.3, 0.3, 1.0)
			mic_button.tooltip_text = "点击停止录音"
		else:
			mic_button.icon = mic_base_icon
			mic_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
			mic_button.tooltip_text = "点击开始录音"
			_stop_mic_animation()

func _set_mic_loading_state(loading: bool):
	if not mic_button:
		return
	if loading:
		mic_button.disabled = true
		mic_button.tooltip_text = "正在转写..."
		if load_icon:
			mic_button.icon = load_icon
		else:
			mic_button.icon = mic_base_icon
		_stop_mic_animation()
	else:
		mic_button.disabled = false
		mic_button.tooltip_text = "点击开始录音"
		mic_button.icon = mic_base_icon

func _on_stt_result(text: String):
	print("🗣️ 语音识别结果: ", text)
	# 结束加载状态
	is_transcribing = false
	_set_mic_loading_state(false)
	_update_mic_button_state(false)
	
	if is_shutting_down:
		print("⏹️ 正在退出，忽略STT结果")
		return
	
	# 解析可能的JSON字符串
	var content: String = text
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		if parsed.has("text"):
			content = str(parsed["text"])
		elif parsed.has("message"):
			content = str(parsed["message"])
	
	content = content.strip_edges()
	if content.is_empty():
		print("⚠️ STT返回空文本，忽略")
		transcription_received.emit("")
		return
	
	if input_field:
		var current_text = input_field.text
		if current_text.strip_edges().is_empty():
			input_field.text = content
		else:
			input_field.text = current_text + " " + content
		input_field.grab_focus()
		input_field.caret_column = input_field.text.length()
		# 刷新发送/结束按钮状态
		if parent_dialog and parent_dialog.has_method("_update_action_button_state"):
			parent_dialog._update_action_button_state()
	
	transcription_received.emit(content)

func _on_stt_error(err: String):
	print("❌ 语音识别错误: ", err)
	is_transcribing = false
	_set_mic_loading_state(false)
	transcription_error.emit(err)
	
	# 恢复按钮状态
	_update_mic_button_state(false)

func _exit_tree():
	is_shutting_down = true
	if is_recording:
		stop_recording()
	# 清理资源
	if recording_bus_index != -1:
		if record_effect:
			AudioServer.remove_bus_effect(recording_bus_index, 0)
		AudioServer.remove_bus(recording_bus_index)
		print("✅ 清理录音总线")
	if mic_player:
		mic_player.queue_free()
	# 恢复按钮UI
	_set_mic_loading_state(false)
	_update_mic_button_state(false)
		
func _save_recording_to_file(wav_data: PackedByteArray) -> void:
	var file_path = "user://recordings/"
	var dir = DirAccess.open("user://")
	
	# 创建 recordings 目录（如果不存在）
	if not dir.dir_exists("recordings"):
		dir.make_dir("recordings")
	
	# 生成带时间戳的文件名
	var time = Time.get_datetime_dict_from_system()
	var filename = "recording_%s%s%s_%s%s%s.wav" % [
		str(time.year), str(time.month).pad_zeros(2), str(time.day).pad_zeros(2),
		str(time.hour).pad_zeros(2), str(time.minute).pad_zeros(2), str(time.second).pad_zeros(2)
	]
	
	var full_path = file_path + filename
	
	var file = FileAccess.open(full_path, FileAccess.WRITE)
	if file:
		file.store_buffer(wav_data)
		file.close()
		print("💾 录音已保存到: ", full_path)
	else:
		print("❌ 无法保存录音文件")

func _calculate_duration_seconds(rec: AudioStreamWAV) -> float:
	var channels = 2 if rec.stereo else 1
	var sample_rate = rec.mix_rate
	var bytes_per_sample = 2
	var data_bytes = rec.get_data()
	if sample_rate <= 0 or channels <= 0 or data_bytes.size() == 0:
		return 0.0
	return float(data_bytes.size()) / float(channels * bytes_per_sample * sample_rate)

func _is_audio_silent(rec: AudioStreamWAV, threshold_rms: float = 0.02) -> bool:
	var data = rec.get_data()
	var n = data.size()
	if n < 2:
		return true
	var sum_sq: float = 0.0
	var count: int = 0
	for i in range(0, n - 1, 2):
		var lo: int = data[i]
		var hi: int = data[i + 1]
		var sample: int = (hi << 8) | lo
		if sample > 32767:
			sample -= 65536
		var norm: float = abs(sample) / 32768.0
		sum_sq += norm * norm
		count += 1
	if count == 0:
		return true
	var rms: float = sqrt(sum_sq / count)
	return rms < threshold_rms
