extends Node
class_name ASMRMainFlow

# ASMR主流程控制器
# 负责管理整个对话流程：发送请求 -> 处理响应 -> TTS播放 -> 工具执行

signal status_updated(status: String)
signal error_occurred(error: String)
signal user_message_display(message: String)
signal input_state_changed(enabled: bool, placeholder: String)
signal cleanup_completed()  # 新增：清理完成信号
signal ai_reply_started()  # 新增：AI开始新回复的信号

# 子组件
var tts_manager: Node = null
var tool_manager: Node = null

# AI相关
var ai_http_client: Node
var logger: Node

# 对话历史
var conversation_history: Array = []
var max_history_count: int = 14

# 流式响应
var streaming_buffer: String = ""
var streaming_full_reply: String = ""
var is_streaming: bool = false
var pending_tool_calls: Array = []

# 流程控制
var is_running: bool = false  # 是否有asmr_chat()在运行
var is_cleaning_up: bool = false  # 是否正在清理中
var status_display_updated: bool = false  # 状态栏是否已更新
var is_continuous_mode: bool = false  # 连续模式开关
var continuous_request_count: int = 0  # 连续模式请求计数
const MAX_CONTINUOUS_REQUESTS: int = 100  # 最大连续请求次数

func _ready():
	# 初始化日志
	logger = preload("res://scripts/ai_chat/ai_logger.gd").new()
	add_child(logger)
	
	# 初始化AI HTTP客户端
	ai_http_client = preload("res://scripts/ai_chat/ai_http_client.gd").new()
	add_child(ai_http_client)
	ai_http_client.stream_chunk_received.connect(_on_stream_chunk_received)
	ai_http_client.stream_completed.connect(_on_stream_completed)
	ai_http_client.stream_error.connect(_on_stream_error)

func initialize(tts: Node, tool: Node):
	"""初始化子组件"""
	tts_manager = tts
	tool_manager = tool

func send_message(user_message: String):
	"""用户发送消息的入口"""
	var ai_service = get_node_or_null("/root/AIService")
	if not ai_service or not ai_service.config_loader:
		error_occurred.emit("AIService 未初始化")
		return
		
	var chat_config = ai_service.config_loader.get_model_config("chat_model")
	if chat_config.get("api_key", "").is_empty():
		error_occurred.emit("API密钥未配置")
		return
	
	# 用户发送消息时，关闭连续模式并清空计数
	_disable_continuous_mode()
	
	# 如果有流程在运行，等待清理完成
	if is_running:
		print("等待当前流程清理完成...")
		await _cleanup_current_flow()
		print("清理完成，开始处理新消息")
	
	# 等待一帧，确保所有信号回调都已执行
	await get_tree().process_frame
	
	# 显示用户消息
	_display_user_message(user_message)
	
	# 启动新流程
	asmr_chat(user_message)

func asmr_chat(user_message: String):
	"""ASMR对话主流程
	
	工作流程：
	1. 清理：清空TTS队列、工具队列，中断音频等
	2. 发送请求
	3. 处理响应：同时发送给TTS组件
	4. 等待TTS播放完毕
	5. 如果没有工具，直接结束
	6. 如果有工具，执行工具，回到2
	"""
	# 保证没有另一个流程在运行
	if is_running:
		print("已有流程在运行，跳过")
		return
	
	is_running = true
	print("=== 开始ASMR对话流程 ===")
	
	# 连续模式计数
	if is_continuous_mode:
		continuous_request_count += 1
		print("连续模式请求计数: %d/%d" % [continuous_request_count, MAX_CONTINUOUS_REQUESTS])
		
		# 检查是否达到最大次数
		if continuous_request_count >= MAX_CONTINUOUS_REQUESTS:
			print("达到最大连续请求次数，关闭连续模式")
			_disable_continuous_mode()
	
	# 1. 清理前，禁用输入框，显示"正在说话"
	var save_mgr = get_node("/root/SaveManager")
	var character_name = save_mgr.get_character_name()
	input_state_changed.emit(false, character_name + "正在说话")
	
	_cleanup_all()
	
	# 2. 发送请求
	_send_ai_request(user_message)
	
	# 3. 等待流式响应完成（在_on_stream_completed中处理）
	await _wait_for_stream_complete()
	
	# 4. 等待TTS播放完毕
	if tts_manager:
		await tts_manager.wait_for_all_finished()
	
	# 检查是否被打断
	if not is_running:
		print("流程被打断（TTS播放后）")
		# 恢复输入框
		input_state_changed.emit(true, "输入消息")
		return
	
	# 5. 检查是否有工具调用
	if pending_tool_calls.is_empty():
		# 没有工具，结束流程
		is_running = false
		print("=== ASMR对话流程结束（无工具）===")
		
		# 检查响应内容是否为空或无意义
		var is_empty_response = _is_empty_or_meaningless_response(streaming_full_reply)
		
		# 检查是否开启连续模式
		if is_continuous_mode:
			if is_empty_response:
				print("检测到空响应，自动添加'继续'消息")
				# 恢复输入框（短暂显示）
				input_state_changed.emit(true, "输入消息")
				# 等待一小段时间让UI更新
				await get_tree().create_timer(0.1).timeout
				# 添加用户消息"继续"
				conversation_history.append({"role": "user", "content": "继续"})
				_display_user_message("继续")
				# 发送信号通知UI：新的AI回复即将开始
				ai_reply_started.emit()
				# 继续请求
				asmr_chat("")
			else:
				print("连续模式已开启，立即再次调用")
				# 恢复输入框（短暂显示）
				input_state_changed.emit(true, "输入消息")
				# 等待一小段时间让UI更新
				await get_tree().create_timer(0.1).timeout
				# 立即再次调用（空消息）
				asmr_chat("")
		else:
			# 恢复输入框
			input_state_changed.emit(true, "输入消息")
		return
	
	# 6. 执行工具
	var tool_calls = pending_tool_calls.duplicate(true)
	pending_tool_calls.clear()
	
	# 添加助手消息到历史
	var assistant_message = {
		"role": "assistant",
		"tool_calls": tool_calls
	}
	if not streaming_full_reply.is_empty():
		assistant_message["content"] = streaming_full_reply
	else:
		assistant_message["content"] = null
	conversation_history.append(assistant_message)
	
	# 连接工具开始信号来更新输入框
	if not tool_manager.tool_started.is_connected(_on_tool_started_for_input):
		tool_manager.tool_started.connect(_on_tool_started_for_input)
	
	# 执行工具
	await tool_manager.execute_tools(tool_calls)
	
	# 获取工具结果
	var tool_results = tool_manager.get_tool_results()
	
	# 检查是否被打断
	if not is_running:
		print("流程被打断（工具执行后）")
		# 即使被打断，也要添加工具结果到历史
		for result in tool_results:
			conversation_history.append({
				"role": "tool",
				"tool_call_id": result.tool_call_id,
				"content": result.feedback
			})
		# 恢复输入框
		input_state_changed.emit(true, "输入消息")
		return
	
	# 将工具结果添加到历史
	for result in tool_results:
		conversation_history.append({
			"role": "tool",
			"tool_call_id": result.tool_call_id,
			"content": result.feedback
		})
	
	# 继续对话（让AI根据工具结果回复）
	print("=== 工具执行完成，请求AI回复 ===")
	is_running = false
	asmr_chat("")

func _on_tool_started_for_input(_tool_name: String, display_name: String):
	"""工具开始时更新输入框"""
	input_state_changed.emit(true, display_name)

func _cleanup_all():
	"""清理所有状态（除了对话历史）"""
	print("清理所有状态")
	
	# 清空TTS队列
	if tts_manager:
		tts_manager.clear_all()
	
	# 清空工具队列
	if tool_manager:
		tool_manager.clear_all()
	
	# 重置流式状态
	streaming_buffer = ""
	streaming_full_reply = ""
	is_streaming = false
	pending_tool_calls.clear()

func _cleanup_current_flow():
	"""清理当前流程（被打断时调用）- 等待清理完成"""
	if is_cleaning_up:
		print("已经在清理中，等待...")
		await cleanup_completed
		return
	
	is_cleaning_up = true
	print("开始清理当前流程")
	is_running = false
	
	# 停止流式请求
	if ai_http_client:
		ai_http_client.stop_streaming()
	
	# 清理TTS
	if tts_manager:
		tts_manager.interrupt()
	
	# 清理工具（会触发 tool_completed 信号）
	var was_executing = false
	if tool_manager:
		was_executing = tool_manager.is_executing
		tool_manager.interrupt()
	
	# 如果工具正在执行，等待状态栏更新完成
	if was_executing:
		print("等待工具完成信号和状态栏更新...")
		status_display_updated = false
		
		# 等待状态栏更新完成（通过 _on_status_display_updated 设置）
		var max_wait_frames = 30  # 最多等待30帧（约0.5秒）
		var waited_frames = 0
		while not status_display_updated and waited_frames < max_wait_frames:
			await get_tree().process_frame
			waited_frames += 1
		
		if status_display_updated:
			print("状态栏更新已完成")
		else:
			print("等待超时，继续处理")
	
	is_cleaning_up = false
	cleanup_completed.emit()
	print("清理流程完成")

func _on_status_display_updated():
	"""状态栏更新完成的回调"""
	status_display_updated = true

func _send_ai_request(user_message: String):
	"""发送AI请求"""
	# 构建系统提示词
	var system_prompt = _build_system_prompt()
	
	# 构建消息列表
	var messages = [{"role": "system", "content": system_prompt}]
	
	# 添加历史
	var history_to_send = _get_limited_history()
	for msg in history_to_send:
		messages.append(msg)
	
	# 添加用户消息（如果有）
	if not user_message.is_empty():
		messages.append({"role": "user", "content": user_message})
		conversation_history.append({"role": "user", "content": user_message})
	
	# 加载工具配置
	var tools_config = _load_tools_config()
	
	# 调用AI API
	var ai_service = get_node_or_null("/root/AIService")
	if not ai_service or not ai_service.config_loader:
		push_error("AIService 未初始化")
		return

	var chat_config = ai_service.config_loader.get_model_config("chat_model")
	var base_url = chat_config.get("base_url", "")
	var url = base_url + "/chat/completions"
	var api_key = chat_config.get("api_key", "")
	
	if api_key.is_empty():
		push_error("对话模型 API 密钥未配置")
		return
	
	var body = {
		"model": chat_config.get("model", ""),
		"messages": messages,
		"max_tokens": int(chat_config.get("max_tokens", 1024)),
		"temperature": 0.8,
		"top_p": float(chat_config.get("top_p", 0.9)),
		"stream": true,
		"tools": tools_config.tools
	}
	
	var json_body = JSON.stringify(body)
	logger.log_api_request("ASMR_AI_REQUEST", body, json_body)
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	# 重置流式状态
	is_streaming = true
	streaming_full_reply = ""
	streaming_buffer = ""
	
	# 启动流式请求
	ai_http_client.start_stream_request(url, headers, json_body, 30.0)

func _on_stream_chunk_received(chunk_text: String):
	"""处理流式数据块"""
	if not is_streaming:
		return
	
	streaming_buffer += chunk_text
	
	var lines = streaming_buffer.split("\n", false)
	var lines_array = Array(lines)
	
	if lines_array.size() > 0:
		var last_line = lines_array.back()
		if not streaming_buffer.ends_with("\n"):
			streaming_buffer = last_line
			lines_array.pop_back()
		else:
			streaming_buffer = ""
	else:
		streaming_buffer = ""
	
	for line in lines_array:
		line = line.strip_edges()
		if line.is_empty():
			continue
		
		if line.begins_with("data: "):
			var data = line.substr(6)
			
			if data == "[DONE]":
				_finalize_stream()
				return
			
			var json = JSON.new()
			if json.parse(data) == OK:
				var chunk_data = json.data
				
				if chunk_data.has("choices") and chunk_data.choices.size() > 0:
					var choice = chunk_data.choices[0]
					
					if choice.has("finish_reason"):
						if choice.finish_reason in ["tool_calls", "stop"]:
							_finalize_stream()
							return
					
					if choice.has("delta"):
						var delta = choice.delta
						
						# 处理文本内容
						if delta.has("content") and delta.content != null:
							var content = delta.content
							if not content.strip_edges().is_empty():
								streaming_full_reply += content
								status_updated.emit(content)
								
								# 发送给TTS
								if tts_manager:
									tts_manager.process_text_chunk(content)
						
						# 处理工具调用
						if delta.has("tool_calls") and delta.tool_calls != null:
							for tool_call_delta in delta.tool_calls:
								_process_tool_call_delta(tool_call_delta)

func _process_tool_call_delta(tool_call_delta: Dictionary):
	"""处理工具调用增量"""
	var index = tool_call_delta.get("index", 0)
	
	while pending_tool_calls.size() <= index:
		pending_tool_calls.append({
			"id": "",
			"type": "function",
			"function": {"name": "", "arguments": ""}
		})
	
	var tool_call = pending_tool_calls[index]
	
	if tool_call_delta.has("id") and tool_call_delta.id != null:
		tool_call.id = tool_call_delta.id
	
	if tool_call_delta.has("function"):
		var func_delta = tool_call_delta.function
		if func_delta.has("name"):
			tool_call.function.name += func_delta.name
		if func_delta.has("arguments"):
			tool_call.function.arguments += func_delta.arguments

func _finalize_stream():
	"""完成流式响应"""
	if not is_streaming:
		return
	
	is_streaming = false
	ai_http_client.stop_streaming()
	
	# 通知TTS流式完成
	if tts_manager:
		tts_manager.on_stream_finished()
	
	# 验证工具调用ID
	for i in range(pending_tool_calls.size()):
		var tool_call = pending_tool_calls[i]
		if tool_call.id.is_empty():
			tool_call.id = "call_" + str(Time.get_ticks_msec()) + "_" + str(i)
	
	# 添加助手消息到历史（如果没有工具调用）
	if pending_tool_calls.is_empty() and not streaming_full_reply.is_empty():
		conversation_history.append({"role": "assistant", "content": streaming_full_reply})
	
	# 记录完整响应（包括工具调用）
	var log_data = {
		"content": streaming_full_reply,
		"tool_calls": pending_tool_calls if not pending_tool_calls.is_empty() else null
	}
	logger.log_api_call("ASMR_AI_RESPONSE", [], JSON.stringify(log_data))

func _on_stream_completed():
	"""流式响应完成"""
	_finalize_stream()

func _on_stream_error(error_message: String):
	"""流式响应错误"""
	is_streaming = false
	is_running = false
	error_occurred.emit("AI请求失败: " + error_message)
	# 恢复输入框
	input_state_changed.emit(true, "输入消息")

func _wait_for_stream_complete():
	"""等待流式响应完成"""
	while is_streaming:
		await get_tree().process_frame

func _build_system_prompt() -> String:
	"""构建系统提示词"""
	var save_mgr = get_node("/root/SaveManager")
	var character_name = save_mgr.get_character_name()
	var user_name = save_mgr.get_user_name()
	var user_address = save_mgr.get_user_address()
	
	var prompt = """## 身份设定
你的名字是{character_name}，被{user_name}收养的失忆少女，现在和他生活在一起，你称呼他为{user_address}。你现在和他在床上。

## 行为准则
- 使用可用的工具为{user_name}提供ASMR服务
- 可以连续调用多个工具，提供完整的助眠体验
- 在执行工具前，可以先说你要做什么
- 工具执行完成后，你可以继续说话或执行下一个工具
- 禁止使用markdown

## 可用工具
你可以使用以下工具为{user_name}提供服务：
- ear_cleaning: 采耳
- aloe_vera_gel: 用芦荟胶按摩
- aromatherapy_massage: 用精油按摩耳朵
- fabric_friction: 用布料摩擦耳朵
"""
	
	return prompt.format({
		"character_name": character_name,
		"user_name": user_name,
		"user_address": user_address
	})

func _get_limited_history() -> Array:
	"""获取限制数量的历史"""
	var history_to_send = []
	var start_index = max(0, conversation_history.size() - max_history_count)
	
	for i in range(start_index, conversation_history.size()):
		history_to_send.append(conversation_history[i])
	
	# 确保不以 role=tool 开头（OpenAI 协议要求 tool 消息必须跟在 assistant 的 tool_calls 之后）
	while history_to_send.size() > 0 and history_to_send[0].role == "tool":
		history_to_send.pop_front()
	
	return history_to_send

func _load_tools_config() -> Dictionary:
	"""加载工具配置"""
	var config_path = "res://config/asmr_tools.json"
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_string) == OK:
			return json.data
	
	return {}

func _display_user_message(message: String):
	"""显示用户消息"""
	var save_mgr = get_node("/root/SaveManager")
	var user_name = save_mgr.get_user_name()
	user_message_display.emit("\n" + user_name + ": " + message)

func set_continuous_mode(enabled: bool):
	"""设置连续模式"""
	is_continuous_mode = enabled
	if enabled:
		continuous_request_count = 0
		print("连续模式: 开启")
	else:
		_disable_continuous_mode()

func _disable_continuous_mode():
	"""关闭连续模式并清空计数"""
	if is_continuous_mode or continuous_request_count > 0:
		is_continuous_mode = false
		continuous_request_count = 0
		print("连续模式: 关闭（计数已清空）")

func _is_empty_or_meaningless_response(response: String) -> bool:
	"""检查响应是否为空或无意义
	
	无意义的响应包括：
	- 空字符串
	- 仅包含空白字符（空格、换行、制表符等）
	- 仅包含标点符号
	"""
	if response.is_empty():
		return true
	
	# 去除空白字符后检查
	var trimmed = response.strip_edges()
	if trimmed.is_empty():
		return true
	
	# 检查是否仅包含标点符号和空白字符
	var has_meaningful_char = false
	for i in range(trimmed.length()):
		var c = trimmed[i]
		# 检查是否为字母、数字或中文字符
		var code = c.unicode_at(0)
		# 字母数字: 0-9, A-Z, a-z
		# 中文: 0x4E00-0x9FFF
		if (code >= 48 and code <= 57) or \
		   (code >= 65 and code <= 90) or \
		   (code >= 97 and code <= 122) or \
		   (code >= 0x4E00 and code <= 0x9FFF):
			has_meaningful_char = true
			break
	
	return not has_meaningful_char

func cleanup():
	"""清理资源"""
	is_running = false
	
	if ai_http_client:
		ai_http_client.stop_streaming()
	
	if tts_manager:
		tts_manager.clear_all()
	
	if tool_manager:
		tool_manager.clear_all()
