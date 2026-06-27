extends Node

## 通用 AI 请求组件 - 用于非流式请求
## 使用方式：
## - await easy_ai.request("chat_model", messages, true, extra_params)
## 返回：{ success: bool, content: String, error: String }

var config_loader: Node
var logger: Node

func _ready():
	pass

func initialize(cfg_loader: Node, log_node: Node = null):
	"""初始化组件"""
	config_loader = cfg_loader
	logger = log_node

func request(
	task_id: String, 
	messages: Array, 
	use_json: bool = false, 
	extra_params: Dictionary = {},
	timeout: float = 30.0
) -> Dictionary:
	"""
	执行非流式 AI 请求
	
	参数：
	- task_id: 任务类型（如 "chat_model", "summary_model" 等）
	- messages: 消息数组
	- use_json: 是否使用 JSON 模式（仅在模型支持时生效）
	- extra_params: 额外参数字典（优先级高于模型配置）
	- timeout: 请求超时时间（秒）
	
	返回：
	- { success: bool, content: String, error: String }
	"""
	var result = {
		"success": false,
		"content": "",
		"error": ""
	}
	
	if not config_loader:
		result.error = "配置加载器未初始化"
		return result
	
	# 获取模型配置
	var model_config = config_loader.get_model_config(task_id)
	if model_config.is_empty():
		result.error = "模型配置未找到：" + task_id
		return result
	
	var base_url = model_config.get("base_url", "")
	var api_key = model_config.get("api_key", "")
	var model_name = model_config.get("model", "")
	
	if base_url.is_empty() or api_key.is_empty() or model_name.is_empty():
		result.error = "模型配置不完整（缺少 base_url、api_key 或 model）"
		return result
	
	# 构建 URL
	var url_suffix = model_config.get("url_suffix", "/chat/completions")
	var url = base_url + url_suffix
	
	# 构建请求体
	var body = {
		"model": model_name,
		"messages": messages
	}
	
	# 先写入额外参数
	for key in extra_params.keys():
		body[key] = extra_params[key]

	# 再用 model_config 覆盖（优先级更高）
	var model_params = model_config.get("params", {})
	for key in model_params.keys():
		body[key] = model_params[key]
	
	# 序列化 JSON
	var json_body = JSON.stringify(body)
	
	if logger:
		logger.log_api_request("EASY_AI_REQUEST_" + task_id, body, json_body)
	
	# 创建 HTTP 请求
	var http_request = HTTPRequest.new()
	http_request.timeout = timeout
	add_child(http_request)
	
	# 发送请求
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	var error_code = http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if error_code != OK:
		result.error = "请求失败，错误码：" + str(error_code)
		http_request.queue_free()
		return result
	
	# 等待响应 - request_completed 信号返回一个数组
	# [result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray]
	var response = await http_request.request_completed
	http_request.queue_free()
	
	# 解包响应数据
	var response_result = response[0]      # HTTPRequest.RESULT_* 常量
	var response_code = response[1]        # HTTP 状态码（如 200, 404 等）
	var response_headers = response[2]     # 响应头（此处未使用）
	var response_body = response[3]        # 响应体（PackedByteArray）
	
	# 检查请求结果
	if response_result != HTTPRequest.RESULT_SUCCESS:
		result.error = "请求失败，结果码：" + str(response_result)
		return result
	
	# 检查 HTTP 状态码
	if response_code != 200:
		var error_text = response_body.get_string_from_utf8()
		result.error = "API 错误 " + str(response_code) + "：" + error_text
		if logger:
			logger.log_api_error(response_code, error_text, body)
		return result
	
	# 解析响应
	var response_text = response_body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(response_text) != OK:
		result.error = "响应解析失败：" + json.get_error_message()
		return result
	
	var response_data = json.data
	if not response_data.has("choices") or response_data.choices.is_empty():
		result.error = "响应格式错误：缺少 choices"
		return result
	
	var choice = response_data.choices[0]
	if not choice.has("message") or not choice.message.has("content"):
		result.error = "响应格式错误：缺少 message.content"
		return result
	
	result.success = true
	result.content = choice.message.content
	
	if logger:
		logger.log_api_call("EASY_AI_RESPONSE_" + task_id, messages, result.content)
	
	return result
