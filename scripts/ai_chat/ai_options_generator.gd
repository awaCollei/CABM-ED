extends Node

# AI 选项生成器
# 负责在对话结束时生成三个对话选项

signal options_generated(options: Array)
signal options_error(error_message: String)

var owner_service: Node  # AIService
var logger: Node
var http_request: HTTPRequest

func _ready():
	# 创建 HTTP 请求节点
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func generate_options(conversation_history: Array):
	"""根据对话历史生成三个选项"""
	if not owner_service or not owner_service.config_loader:
		push_error("配置加载器未初始化")
		options_error.emit("配置加载器未初始化")
		return
	
	# 检查是否启用生成选项
	if not owner_service.config_loader.load_generation_options():
		print("生成选项功能未启用")
		return
	
	var summary_config = owner_service.config_loader.get_model_config("summary_model")
	var model = summary_config.get("model", "")
	var base_url = summary_config.get("base_url", "")
	var api_key = summary_config.get("api_key", "")
	
	if model.is_empty() or base_url.is_empty():
		push_error("总结模型配置不完整")
		options_error.emit("总结模型配置不完整")
		return
	
	if api_key.is_empty():
		push_error("总结模型 API 密钥未配置")
		options_error.emit("总结模型 API 密钥未配置")
		return
	
	var url = base_url + "/chat/completions"
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	# 构建对话历史文本
	var conversation_text = _build_conversation_text(conversation_history)
	
	# 构建系统提示词
	var system_prompt = _build_system_prompt()
	
	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": conversation_text}
	]
	
	var body = {
		"model": model,
		"messages": messages,
		"max_tokens": 300,
		"temperature": 0.8,
		"top_p": 0.9
	}
	
	var json_body = JSON.stringify(body)
	
	if logger:
		logger.log_api_request("OPTIONS_GENERATION", body, json_body)
	
	http_request.set_meta("request_body", body)
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		MessageDisplay.show_failure_message("选项生成失败: " + str(error))
		push_error("选项生成请求失败: " + str(error))
		options_error.emit("请求失败")

func _build_conversation_text(conversation_history: Array) -> String:
	"""构建对话历史文本"""
	var lines = []
	
	var save_mgr = get_node_or_null("/root/SaveManager")
	var char_name = save_mgr.get_character_name() if save_mgr else "角色"
	var user_name = save_mgr.get_user_name() if save_mgr else "用户"
	# 只取最近的几条对话（避免太长）
	var start_index = max(0, conversation_history.size() - 6)
	var recent_history = conversation_history.slice(start_index)
	
	for msg in recent_history:
		if msg.role == "user":
			var user_content = msg.content.strip_edges()
			if user_content.is_empty():
				continue
			lines.append("%s：%s" % [user_name, user_content])
		elif msg.role == "assistant":
			var content = msg.content
			var clean_content = content
			
			# 解析JSON格式的回复
			if clean_content.contains("```json"):
				var json_start = clean_content.find("```json") + 7
				clean_content = clean_content.substr(json_start)
			elif clean_content.contains("```"):
				var json_start = clean_content.find("```") + 3
				clean_content = clean_content.substr(json_start)
			
			if clean_content.contains("```"):
				var json_end = clean_content.find("```")
				clean_content = clean_content.substr(0, json_end)
			
			clean_content = clean_content.strip_edges()
			
			var json = JSON.new()
			if json.parse(clean_content) == OK:
				var data = json.data
				if data.has("msg") and data.msg is String:
					content = data.msg
			
			lines.append("%s：%s" % [char_name, content])
	
	return "\n".join(lines)

func _build_system_prompt() -> String:
	"""构建系统提示词"""
	var save_mgr = get_node_or_null("/root/SaveManager")
	var user_name = save_mgr.get_user_name() if save_mgr else "用户"
	var char_name = save_mgr.get_character_name() if save_mgr else "角色"
	
	return """你是**%s**，正在与**%s**对话。请根据对话历史，思考接下来你要说的话。

任务：生成三个你可能会说的对话选项，这些选项是你对**%s**说的话。

要求：
1. 生成3个自然、符合情境的对话选项
2. 必须以你（即**%s**）的第一人称视角
3. 每个选项是真实发言，而不是内心想法
4. 每个选项控制在15字以内
5. 直接输出三个选项，每行一个，不要编号，不要引号，不要其他说明

示例格式：
今天天气真不错呢
你最近在忙什么？
我们去散散步吧""" % [user_name, char_name, char_name, user_name]

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	"""HTTP 请求完成回调"""
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = "请求失败: " + str(result)
		print(error_msg)
		options_error.emit(error_msg)
		return
	
	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		var error_msg = "API 错误 (%d): %s" % [response_code, error_text]
		print(error_msg)
		
		if logger:
			var request_body = http_request.get_meta("request_body", {})
			logger.log_api_error(response_code, error_text, request_body)
		
		options_error.emit(error_msg)
		return
	
	var response_text = body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(response_text) != OK:
		var error_msg = "响应解析失败"
		push_error(error_msg)
		options_error.emit(error_msg)
		return
	
	_handle_options_response(json.data)

func _handle_options_response(response: Dictionary):
	"""处理选项生成响应"""
	if not response.has("choices") or response.choices.is_empty():
		push_error("响应中没有choices字段")
		options_error.emit("响应格式错误")
		return
	
	var choice = response.choices[0]
	if not choice.has("message") or not choice.message.has("content"):
		push_error("响应格式错误")
		options_error.emit("响应格式错误")
		return
	
	var content = choice.message.content.strip_edges()
	
	# 解析选项（按行分割）
	var lines = content.split("\n")
	var options = []
	
	for line in lines:
		var option = line.strip_edges()
		# 移除可能的编号（1. 2. 3. 或 1、2、3、）
		var regex = RegEx.new()
		regex.compile("^[0-9]+[.、]\\s*")
		var cleaned = regex.sub(option, "", true)
		if not cleaned.is_empty():
			options.append(cleaned)
	
	# 确保有3个选项
	if options.size() < 3:
		push_error("生成的选项少于3个: " + str(options.size()))
		options_error.emit("生成的选项不足")
		return
	
	# 只取前3个
	options = options.slice(0, 3)
	
	print("生成的选项: ", options)
	options_generated.emit(options)
