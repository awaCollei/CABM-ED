extends Node

# 声线上传管理器 - 处理参考音频上传

signal upload_completed(voice_id: String, voice_uri: String)
signal upload_failed(voice_id: String, error_message: String)

var upload_request: HTTPRequest

func _ready():
	# 创建HTTP请求节点
	upload_request = HTTPRequest.new()
	add_child(upload_request)
	upload_request.request_completed.connect(_on_upload_completed)

func upload_voice(voice_id: String, voice_data: Dictionary) -> void:
	"""上传声线的参考音频
	
	参数:
	- voice_id: 声线ID
	- voice_data: 声线数据字典，包含audio_path, reference_text等
	"""
	print("=== 开始上传声线: %s ===" % voice_id)
	
	# 获取TTS配置
	var tts_config = _get_tts_config()
	var api_key = tts_config.get("api_key", "")
	var tts_model = tts_config.get("model", "")
	var tts_base_url = tts_config.get("base_url", "")
	
	if api_key.is_empty():
		var error_msg = "TTS API密钥未配置"
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)
		return
	
	if tts_model.is_empty() or tts_base_url.is_empty():
		var error_msg = "TTS配置不完整"
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)
		return
	
	var audio_path = voice_data.get("audio_path", "")
	var ref_text = voice_data.get("reference_text", "")
	
	# 检查音频文件
	if not FileAccess.file_exists(audio_path):
		var error_msg = "参考音频文件不存在: " + audio_path
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)
		return
	
	# 读取音频文件
	var audio_file = FileAccess.open(audio_path, FileAccess.READ)
	if audio_file == null:
		var error_msg = "无法打开参考音频文件: " + audio_path
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)
		return
	var audio_data = audio_file.get_buffer(audio_file.get_length())
	audio_file.close()
	
	# 构建multipart/form-data请求
	var boundary = "----GodotFormBoundary" + str(Time.get_ticks_msec())
	var body = PackedByteArray()
	
	# 添加model字段
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"model\"\r\n\r\n".to_utf8_buffer())
	body.append_array((tts_model + "\r\n").to_utf8_buffer())
	
	# 添加text字段
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"text\"\r\n\r\n".to_utf8_buffer())
	body.append_array((ref_text + "\r\n").to_utf8_buffer())
	
	# 添加file字段
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	var filename = audio_path.get_file()
	body.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n" % filename).to_utf8_buffer())
	body.append_array("Content-Type: audio/wav\r\n\r\n".to_utf8_buffer())
	body.append_array(audio_data)
	body.append_array("\r\n".to_utf8_buffer())
	
	# 结束boundary
	body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())
	
	var url = tts_base_url + "/uploads/audio/voice"
	var headers = [
		"Authorization: Bearer " + api_key,
		"Content-Type: multipart/form-data; boundary=" + boundary
	]
	
	# 记录上传的声线ID
	upload_request.set_meta("voice_id", voice_id)
	
	print("上传声线: %s (%s)" % [voice_data.get("name", ""), voice_data.get("language", "")])
	print("请求URL: ", url)
	print("音频数据大小: ", audio_data.size(), " 字节")
	print("参考文本: ", ref_text)
	upload_request.request_raw(url, headers, HTTPClient.METHOD_POST, body)

func _on_upload_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	"""上传完成回调"""
	print("=== 参考音频上传完成 ===")
	print("result: %d, response_code: %d, body_size: %d" % [result, response_code, body.size()])
	
	var voice_id = upload_request.get_meta("voice_id", "")
	
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = "上传失败: " + str(result)
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)
		return
	
	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		var error_msg = "上传错误 (%d): %s" % [response_code, error_text]
		push_error(error_msg)
		print("错误详情: ", error_text)
		upload_failed.emit(voice_id, error_msg)
		return
	
	var response_text = body.get_string_from_utf8()
	print("上传响应: ", response_text)
	
	var json = JSON.new()
	if json.parse(response_text) != OK:
		var error_msg = "解析上传响应失败: " + json.get_error_message()
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)
		return
	
	var response = json.data
	if response.has("uri"):
		var returned_uri = response.uri
		print("✓ 声线URI获取成功: %s" % returned_uri)
		upload_completed.emit(voice_id, returned_uri)
	else:
		var error_msg = "响应中没有URI字段，响应内容: " + response_text
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)

func _get_tts_config() -> Dictionary:
	"""获取TTS配置"""
	var ai_service = get_node_or_null("/root/AIService")
	if ai_service and ai_service.config_loader:
		return ai_service.config_loader.get_model_config("tts_model")
	return {}
