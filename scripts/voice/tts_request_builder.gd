class_name TTSRequestBuilder

# TTS 请求构建器
# 解析用户自定义的 curl/JSON 模板，替换占位符，生成 HTTP 请求参数

# 占位符说明：
# {{url}}       - 模型服务商的完整URL
# {{base_url}}       - 模型服务商的基础URL
# {{model}}     - 模型标识符
# {{input}}     - 合成文本
# {{voice}}     - 声线标识 (voice_uri)
# {{speed}}     - 语速
# {{api_key}}   - API 密钥
# {{ref_file}}  - 参考音频文件路径
# {{ref_base64}} - 参考音频的 base64 编码
# {{ref_text}}  - 参考文本
# {{uri}}       - 响应中的 URI 字段名（仅在响应解析中使用）

static func build_tts_request(template: String, params: Dictionary) -> Dictionary:
	"""构建 TTS 请求
	params 需包含: url, model, input, voice, speed, api_key
	返回: {method, url, headers, body, body_raw}
	"""
	var is_curl = CurlParser.is_curl_command(template)

	if is_curl:
		return _build_from_curl(template, params)
	else:
		return _build_from_json_template(template, params)

static func build_upload_request(template: String, params: Dictionary) -> Dictionary:
	"""构建上传音色请求
	params 需包含: url, model, api_key, ref_file 或 ref_base64, ref_text
	返回: {method, url, headers, body, body_raw}
	"""
	var is_curl = CurlParser.is_curl_command(template)

	if is_curl:
		return _build_from_curl(template, params)
	else:
		return _build_from_json_template(template, params)

static func _build_from_curl(template: String, params: Dictionary) -> Dictionary:
	"""从 curl 命令构建请求"""
	# 先替换占位符
	var expanded = CurlParser.replace_placeholders(template, params)
	var parsed = CurlParser.parse(expanded)

	var result = {
		"method": parsed.method,
		"url": parsed.url,
		"headers": parsed.headers,
		"body": "",
		"body_raw": PackedByteArray(),
		"is_multipart": false,
		"form_fields": parsed.form_fields,
	}

	# 如果有表单字段（multipart），构建 multipart body
	if not parsed.form_fields.is_empty():
		result.is_multipart = true
		# form_fields 中的文件路径需要在调用处处理
	elif not parsed.body.is_empty():
		result.body = parsed.body

	return result

static func _build_from_json_template(template: String, params: Dictionary) -> Dictionary:
	"""从 JSON 模板构建请求"""
	var expanded = CurlParser.replace_placeholders(template, params)

	# 解析 JSON
	var json = JSON.new()
	if json.parse(expanded) != OK:
		push_error("TTS请求模板 JSON 解析失败: %s" % json.get_error_message())
		return {"method": "", "url": "", "headers": [], "body": "", "body_raw": PackedByteArray(), "is_multipart": false, "form_fields": []}

	var data = json.data
	var url = data.get("url", "")
	var method = data.get("method", "POST").to_upper()
	var headers_dict = data.get("headers", {})

	# 构建 headers 数组
	var headers = []
	for key in headers_dict:
		headers.append("%s: %s" % [key, headers_dict[key]])

	# 构建 body（去掉 url, method, headers）
	var body_data = {}
	for key in data:
		if key != "url" and key != "method" and key != "headers":
			body_data[key] = data[key]

	var body = JSON.stringify(body_data) if not body_data.is_empty() else ""

	return {
		"method": method,
		"url": url,
		"headers": headers,
		"body": body,
		"body_raw": PackedByteArray(),
		"is_multipart": false,
		"form_fields": [],
	}

static func parse_upload_response(response_text: String, uri_field: String) -> String:
	"""解析上传音色响应，提取 URI
	uri_field: 响应中 URI 的字段名，支持嵌套如 "data.uri"
	"""
	if uri_field.is_empty():
		uri_field = "uri"

	var json = JSON.new()
	if json.parse(response_text) != OK:
		push_error("上传响应解析失败: %s" % json.get_error_message())
		return ""

	var data = json.data
	var fields = uri_field.split(".")
	var current = data
	for field in fields:
		if current is Dictionary and current.has(field):
			current = current[field]
		else:
			push_error("上传响应中找不到字段: %s" % uri_field)
			return ""

	return str(current)
