extends Node

signal stream_text_received(text: String)
signal stream_completed(full_text: String)
signal stream_error(error_message: String)

var config_loader: Node = null
var http_client_module: Node = null
var logger: Node
var conversation_history: Array = []
var is_chatting: bool = false

var _sse_buffer: String = ""
var _assistant_buffer: String = ""
var _has_received_token: bool = false

func _ready() -> void:
	_setup_config_loader()
	_setup_http_client()
	logger = preload("res://scripts/ai_chat/ai_logger.gd").new()
	add_child(logger)

func _setup_config_loader() -> void:
	# 优先复用主系统配置加载器，确保 API 配置和上下文限制一致。
	var ai_service = get_node_or_null("/root/AIService")
	if ai_service and ai_service.config_loader:
		config_loader = ai_service.config_loader
		return

	config_loader = preload("res://scripts/ai_chat/ai_config_loader.gd").new()
	add_child(config_loader)
	config_loader.load_all()

func _setup_http_client() -> void:
	http_client_module = preload("res://scripts/ai_chat/ai_http_client.gd").new()
	add_child(http_client_module)
	http_client_module.stream_chunk_received.connect(_on_stream_chunk_received)
	http_client_module.stream_error.connect(_on_stream_error)

func start_stream_chat(system_prompt: String, user_message: String) -> bool:
	if is_chatting:
		stream_error.emit("正在回复中，请稍后再试")
		return false
	if config_loader == null:
		stream_error.emit("AI 配置加载器不可用")
		return false

	var chat_config = config_loader.get_model_config("chat_model")
	var api_key = str(chat_config.get("api_key", ""))
	var base_url = str(chat_config.get("base_url", ""))
	var model = str(chat_config.get("model", ""))
	if api_key.is_empty():
		stream_error.emit("API 密钥未配置")
		return false
	if base_url.is_empty() or model.is_empty():
		stream_error.emit("聊天模型配置不完整")
		return false

	var messages = _build_request_messages(system_prompt, user_message)
	var body = {
		"model": model,
		"messages": messages,
		"max_tokens": int(chat_config.get("max_tokens", 1024)),
		"temperature": float(chat_config.get("temperature", 0.7)),
		"top_p": float(chat_config.get("top_p", 0.9)),
		"stream": true
	}
	var json_body = JSON.stringify(body)
	logger.log_api_request("CHAT_REQUEST", body, json_body)
	_reset_stream_state()
	is_chatting = true

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	if base_url.ends_with("/"):
		base_url = base_url.substr(0, base_url.length() - 1)
	var url = base_url + "/chat/completions"
	var timeout = float(chat_config.get("timeout", 30.0))
	http_client_module.start_stream_request(url, headers, JSON.stringify(body), timeout)
	return true

func stop_stream() -> void:
	if http_client_module:
		http_client_module.stop_streaming()
	is_chatting = false

func clear_history() -> void:
	conversation_history.clear()

func _build_request_messages(system_prompt: String, user_message: String) -> Array:
	var messages: Array = [{"role": "system", "content": system_prompt}]
	var memory_cfg = config_loader.config.get("memory", {})
	var max_history = int(memory_cfg.get("max_conversation_history", 10))
	var start_index = max(0, conversation_history.size() - max_history)
	var history_to_send = conversation_history.slice(start_index)

	for msg in history_to_send:
		messages.append({"role": msg.role, "content": msg.content})

	var ts = Time.get_unix_time_from_system()
	conversation_history.append({"role": "user", "content": user_message, "timestamp": ts})
	messages.append({"role": "user", "content": user_message})
	return messages

func _on_stream_chunk_received(data: String) -> void:
	_sse_buffer += data
	var lines = _sse_buffer.split("\n")

	if not _sse_buffer.ends_with("\n"):
		_sse_buffer = lines[-1]
		lines = lines.slice(0, -1)
	else:
		_sse_buffer = ""

	for raw_line in lines:
		var line = raw_line.strip_edges()
		if line.is_empty():
			continue
		if line == "data: [DONE]":
			_finalize_stream_success()
			return
		if line.begins_with("data: "):
			_parse_sse_json_line(line.substr(6))

func _parse_sse_json_line(json_str: String) -> void:
	var json = JSON.new()
	if json.parse(json_str) != OK:
		return

	var chunk = json.data
	if not chunk.has("choices") or chunk.choices.is_empty():
		return

	var delta = chunk.choices[0].get("delta", {})
	var token = str(delta.get("content", ""))
	if token.is_empty():
		return

	_has_received_token = true
	_assistant_buffer += token
	stream_text_received.emit(token)

func _on_stream_error(error_message: String) -> void:
	if _has_received_token and not _assistant_buffer.is_empty():
		# 流中途断开但已有可用文本时，按“部分成功”结束，避免白屏。
		_finalize_stream_success()
		return

	is_chatting = false
	stream_error.emit(error_message)

func _finalize_stream_success() -> void:
	if not is_chatting:
		return

	is_chatting = false
	if http_client_module:
		http_client_module.stop_streaming()

	if not _assistant_buffer.strip_edges().is_empty():
		var ts = Time.get_unix_time_from_system()
		conversation_history.append({"role": "assistant", "content": _assistant_buffer, "timestamp": ts})

	stream_completed.emit(_assistant_buffer)

func _reset_stream_state() -> void:
	_sse_buffer = ""
	_assistant_buffer = ""
	_has_received_token = false
