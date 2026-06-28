extends Node

# 声线上传管理器 - 处理参考音频上传

signal upload_completed(voice_id: String, voice_uri: String)
signal upload_failed(voice_id: String, error_message: String)

var upload_request: HTTPRequest
var advanced_config: Dictionary = {}  # TTS高级配置

func _ready():
	# 创建HTTP请求节点
	upload_request = HTTPRequest.new()
	add_child(upload_request)
	upload_request.request_completed.connect(_on_upload_completed)
	_load_advanced_config()

func _load_advanced_config():
	"""加载TTS高级配置"""
	var config_path = "user://tts_advanced_config.json"
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(json_string) == OK:
				advanced_config = json.data
				print("TTS高级配置加载成功")

func reload_advanced_config():
	"""重新加载高级配置（供外部调用）"""
	advanced_config = {}
	_load_advanced_config()

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
	
	# 记录上传的声线ID
	upload_request.set_meta("voice_id", voice_id)
	
	# 检查是否有自定义上传模板
	var upload_template = advanced_config.get("upload_voice_request", "")
	if not upload_template.is_empty():
		_upload_with_custom_template(voice_id, voice_data, tts_config)
		return
	
	# 使用默认的multipart上传方式
	_upload_with_default(voice_id, voice_data, tts_config)

func _upload_with_custom_template(voice_id: String, voice_data: Dictionary, tts_config: Dictionary):
	"""使用自定义模板上传"""
	var audio_path = voice_data.get("audio_path", "")
	var ref_text = voice_data.get("reference_text", "")
	var tts_model = tts_config.get("model", "")
	var tts_base_url = tts_config.get("base_url", "")
	var api_key = tts_config.get("api_key", "")
	var tts_url_suffix = tts_config.get("url_suffix","")
	
	# 读取音频文件并计算base64
	var audio_file = FileAccess.open(audio_path, FileAccess.READ)
	if audio_file == null:
		var error_msg = "无法打开参考音频文件: " + audio_path
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)
		return
	var audio_data = audio_file.get_buffer(audio_file.get_length())
	audio_file.close()
	var audio_base64 = Marshalls.raw_to_base64(audio_data)
	
	# 构建占位符变量（ref_base64 不注入模板，避免巨量数据导致解析卡死）
	var variables = {
		"base_url": tts_base_url,
		"url": tts_base_url + tts_url_suffix,
		"model": tts_model,
		"api_key": api_key,
		"ref_file": audio_path,
		"ref_text": ref_text,
	}

	var template = advanced_config.get("upload_voice_request", "")
	var request_data = TTSRequestBuilder.build_upload_request(template, variables)
	# ref_base64 单独替换到 body 中
	if not audio_base64.is_empty():
		request_data.body = request_data.body.replace("{{ref_base64}}", audio_base64)
	
	if request_data.url.is_empty():
		var error_msg = "自定义上传模板解析失败：URL为空"
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)
		return
	
	# 处理multipart表单
	if request_data.is_multipart and not request_data.form_fields.is_empty():
		_upload_multipart_custom(voice_id, request_data, audio_data, audio_path)
		return
	
	# 处理普通请求
	var headers = request_data.headers
	var method = _http_method_from_string(request_data.method)
	
	print("自定义上传声线: %s (%s)" % [voice_data.get("name", ""), voice_data.get("language", "")])
	print("请求URL: ", request_data.url)
	if not request_data.body.is_empty():
		upload_request.request(request_data.url, headers, method, request_data.body)
	else:
		upload_request.request(request_data.url, headers, method)

func _upload_multipart_custom(voice_id: String, request_data: Dictionary, audio_data: PackedByteArray, audio_path: String):
	"""使用自定义模板的multipart上传"""
	var boundary = "----GodotFormBoundary" + str(Time.get_ticks_msec())
	var body = PackedByteArray()
	
	var audio_base64 = Marshalls.raw_to_base64(audio_data)
	for field in request_data.form_fields:
		body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
		if field.get("is_file", false):
			var filename = audio_path.get_file()
			body.append_array(("Content-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n" % [field.name, filename]).to_utf8_buffer())
			body.append_array("Content-Type: audio/wav\r\n\r\n".to_utf8_buffer())
			body.append_array(audio_data)
			body.append_array("\r\n".to_utf8_buffer())
		else:
			var field_value = str(field.value).replace("{{ref_base64}}", audio_base64)
			body.append_array(("Content-Disposition: form-data; name=\"%s\"\r\n\r\n" % field.name).to_utf8_buffer())
			body.append_array((field_value + "\r\n").to_utf8_buffer())
	
	body.append_array(("--" + boundary + "--\r\n").to_utf8_buffer())
	
	var headers = request_data.headers
	# 更新或添加Content-Type
	var has_content_type = false
	var final_headers = []
	for header in headers:
		if header.begins_with("Content-Type:"):
			final_headers.append("Content-Type: multipart/form-data; boundary=" + boundary)
			has_content_type = true
		else:
			final_headers.append(header)
	if not has_content_type:
		final_headers.append("Content-Type: multipart/form-data; boundary=" + boundary)
	
	print("自定义multipart上传URL: ", request_data.url)
	print(body)
	upload_request.request_raw(request_data.url, final_headers, HTTPClient.METHOD_POST, body)

func _upload_with_default(voice_id: String, voice_data: Dictionary, tts_config: Dictionary):
	"""使用默认multipart方式上传"""
	var tts_model = tts_config.get("model", "")
	var tts_base_url = tts_config.get("base_url", "")
	var api_key = tts_config.get("api_key", "")
	var audio_path = voice_data.get("audio_path", "")
	var ref_text = voice_data.get("reference_text", "")
	
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
	
	# 使用自定义响应字段或默认的 uri
	var uri_field = advanced_config.get("upload_voice_response", "uri")
	if uri_field.is_empty():
		uri_field = "uri"
	
	var returned_uri = TTSRequestBuilder.parse_upload_response(response_text, uri_field)
	if not returned_uri.is_empty():
		print("✓ 声线URI获取成功: %s" % returned_uri)
		upload_completed.emit(voice_id, returned_uri)
	else:
		var error_msg = "响应中没有找到字段 '%s'，响应内容: %s" % [uri_field, response_text]
		push_error(error_msg)
		upload_failed.emit(voice_id, error_msg)

func _http_method_from_string(method: String) -> HTTPClient.Method:
	"""将HTTP方法字符串转换为HTTPClient.Method"""
	match method.to_upper():
		"GET":
			return HTTPClient.METHOD_GET
		"POST":
			return HTTPClient.METHOD_POST
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
		"PATCH":
			return HTTPClient.METHOD_PATCH
		_:
			return HTTPClient.METHOD_POST

func _get_tts_config() -> Dictionary:
	"""获取TTS配置"""
	var ai_service = get_node_or_null("/root/AIService")
	if ai_service and ai_service.config_loader:
		return ai_service.config_loader.get_model_config("tts_model")
	return {}
