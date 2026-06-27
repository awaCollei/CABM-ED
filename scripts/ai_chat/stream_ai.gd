extends Node

## 通用流式 AI 请求组件
## 负责根据模型配置发送流式请求，并转发响应信号

signal stream_chunk_received(data: String)
signal stream_completed()
signal stream_error(error_message: String)

var config_loader: Node
var logger: Node
var ai_http_client: Node

func initialize(cfg_loader: Node, log_node: Node = null):
	config_loader = cfg_loader
	logger = log_node
	_setup_http_client()

func _setup_http_client():
	ai_http_client = preload("res://scripts/ai_chat/ai_http_client.gd").new()
	add_child(ai_http_client)
	ai_http_client.stream_chunk_received.connect(_on_stream_chunk_received)
	ai_http_client.stream_completed.connect(_on_stream_completed)
	ai_http_client.stream_error.connect(_on_stream_error)

func start_stream_chat(
	task_id: String,
	messages: Array,
	extra_params: Dictionary = {},
	timeout: float = 30.0
):
	"""启动流式 AI 请求
	
	Args:
		task_id: 任务类型（如 "chat_model", "summary_model"）
		messages: 消息数组
		extra_params: 额外参数（优先级高于配置）
		timeout: 超时时间（秒）
	"""
	if not config_loader:
		stream_error.emit("配置加载器未初始化")
		return

	var model_config = config_loader.get_model_config(task_id)
	if model_config.is_empty():
		stream_error.emit("模型配置未找到：" + task_id)
		return

	var api_key = str(model_config.get("api_key", ""))
	var base_url = str(model_config.get("base_url", ""))
	var model = str(model_config.get("model", ""))

	if api_key.is_empty():
		stream_error.emit("API 密钥未配置")
		return
	if base_url.is_empty() or model.is_empty():
		stream_error.emit("模型配置不完整")
		return

	var url_suffix = model_config.get("url_suffix", "/chat/completions")
	var url = base_url + url_suffix

	var body = {
		"model": model,
		"messages": messages,
		"max_tokens": int(model_config.get("max_tokens", 1024)),
		"temperature": float(model_config.get("temperature", 0.8)),
		"top_p": float(model_config.get("top_p", 0.9)),
		"stream": true
	}

	for key in extra_params.keys():
		body[key] = extra_params[key]

	var json_body = JSON.stringify(body)

	if logger:
		logger.log_api_request("STREAM_AI_REQUEST_" + task_id, body, json_body)

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]

	ai_http_client.start_stream_request(url, headers, json_body, timeout)

func stop_streaming():
	if ai_http_client:
		ai_http_client.stop_streaming()

func _on_stream_chunk_received(data: String):
	stream_chunk_received.emit(data)

func _on_stream_completed():
	stream_completed.emit()

func _on_stream_error(error_message: String):
	stream_error.emit(error_message)
