extends Node

# AI故事生成器
# 负责根据关键词生成故事标题和简介

# 信号
signal generation_started()
signal generation_completed(title: String, summary: String)
signal generation_error(error_message: String)

# 依赖节点引用
var story_creation_panel: Control = null
var ai_http_client: Node = null

# AI配置相关
var config_loader: Node

# 生成状态
var is_generating: bool = false
var current_title: String = ""
var current_summary: String = ""
var full_response_content: String = ""  # 累积的完整响应内容

# 确认机制
var confirm_timer: Timer = null
var is_confirm_mode: bool = false

func _ready():
	"""初始化AI生成器"""
	_initialize_ai_config()
	_initialize_http_client()
	_initialize_confirm_timer()

func _initialize_ai_config():
	"""初始化AI配置"""
	# 使用全局AIService获取配置加载器
	var ai_service = get_node_or_null("/root/AIService")
	if ai_service and ai_service.config_loader:
		config_loader = ai_service.config_loader
	else:
		push_error("AIService 未初始化，无法获取 config_loader")

func _initialize_http_client():
	"""初始化HTTP客户端"""
	ai_http_client = preload("res://scripts/ai_chat/ai_http_client.gd").new()
	add_child(ai_http_client)

	# 连接流式响应信号
	ai_http_client.stream_chunk_received.connect(_on_stream_chunk_received)
	ai_http_client.stream_completed.connect(_on_stream_completed)
	ai_http_client.stream_error.connect(_on_stream_error)

func _initialize_confirm_timer():
	"""初始化确认计时器"""
	confirm_timer = Timer.new()
	add_child(confirm_timer)
	confirm_timer.wait_time = 3.0
	confirm_timer.one_shot = true
	confirm_timer.timeout.connect(_on_confirm_timeout)

func set_story_creation_panel(panel: Control):
	"""设置故事创建面板引用"""
	story_creation_panel = panel

func generate_story_from_keywords(keywords: String):
	"""根据关键词生成故事"""
	if is_generating:
		push_warning("AI生成正在进行中，请等待完成")
		return

	# 检查输入框是否有内容
	var has_content = _has_input_content()

	if has_content and not is_confirm_mode:
		# 进入确认模式
		is_confirm_mode = true
		_update_generate_button_state(false, "清空并生成")
		confirm_timer.start()
		return

	# 退出确认模式（如果在确认模式中）
	if is_confirm_mode:
		is_confirm_mode = false
		confirm_timer.stop()

	var story_config = config_loader.get_model_config("summary_model")
	if story_config.is_empty() or story_config.get("api_key", "").is_empty():
		var error_msg = "AI配置不完整，请检查配置"
		_handle_generation_error(error_msg)
		return

	# 清空当前内容
	_clear_input_fields()

	# 设置生成状态
	is_generating = true
	current_title = ""
	current_summary = ""
	full_response_content = ""

	# 更新按钮状态
	_update_generate_button_state(true, "生成中...")

	# 发送生成信号
	generation_started.emit()

	# 调用AI生成API
	_call_story_generation_api(keywords)

func _clear_input_fields():
	"""清空输入框"""
	if story_creation_panel:
		story_creation_panel.title_input.text = ""
		story_creation_panel.summary_input.text = ""
		story_creation_panel.user_role_input.text = ""
		story_creation_panel.character_role_input.text = ""

func _has_input_content() -> bool:
	"""检查输入框是否有内容"""
	if not story_creation_panel:
		return false

	var title_text = story_creation_panel.title_input.text.strip_edges() if story_creation_panel.title_input else ""
	var summary_text = story_creation_panel.summary_input.text.strip_edges() if story_creation_panel.summary_input else ""
	var user_role_text = story_creation_panel.user_role_input.text.strip_edges() if story_creation_panel.user_role_input else ""
	var character_role_text = story_creation_panel.character_role_input.text.strip_edges() if story_creation_panel.character_role_input else ""

	return not title_text.is_empty() or not summary_text.is_empty() or not user_role_text.is_empty() or not character_role_text.is_empty()

func _update_generate_button_state(disabled: bool, text: String = ""):
	"""更新生成按钮状态"""
	print("_update_generate_button_state 被调用: disabled=", disabled, ", text='", text, "'")
	if story_creation_panel and story_creation_panel.generate_button:
		print("更新按钮状态: disabled=", disabled, ", text='", text, "'")
		story_creation_panel.generate_button.disabled = disabled
		if not text.is_empty():
			story_creation_panel.generate_button.text = text
	else:
		print("警告：story_creation_panel 或 generate_button 为 null")

func _call_story_generation_api(keywords: String):
	"""调用故事生成API"""
	var story_config = config_loader.get_model_config("summary_model")
	var model = story_config.get("model", "")
	var base_url = story_config.get("base_url", "")

	if model.is_empty() or base_url.is_empty():
		var error_msg = "故事生成模型配置不完整"
		_handle_generation_error(error_msg)
		return
	var api_key = story_config.get("api_key", "")
	if api_key.is_empty():
		var error_msg = "故事生成模型 API 密钥未配置"
		_handle_generation_error(error_msg)
		return
	# 构建系统提示词
	var system_prompt = _build_story_generation_system_prompt()

	# 构建用户提示词
	var user_prompt = _build_story_generation_user_prompt(keywords)

	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt}
	]

	var url = base_url + "/chat/completions"
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + api_key]

	var body = {
		"model": model,
		"messages": messages,
		"max_tokens": 512,
		"temperature": 0.8,
		"top_p": 0.9,
		"enable_thinking": false,
		"stream": true  # 启用流式响应
	}

	var json_body = JSON.stringify(body)

	# 启动流式请求
	ai_http_client.start_stream_request(url, headers, json_body)

func _build_story_generation_system_prompt() -> String:
	"""构建故事生成系统提示词"""
	var prompt = """你是一个故事生成助手。请根据用户提供的关键词，创作一个引人入胜的角色扮演故事设定。"""

	prompt += """
输出要求：
```
标题：故事的标题
主角A：主角A的身份设定，约20字
主角B：主角B的身份设定，约20字
简介：故事的简介与开头，约50字
```
禁止使用markdown。
"""
	return prompt

func _build_story_generation_user_prompt(keywords: String) -> String:
	"""构建故事生成用户提示词"""
	var prompt = "请根据以下关键词创作故事："

	if not keywords.strip_edges().is_empty():
		prompt += "\n关键词：" + keywords
	else:
		prompt += "\n（无特定关键词，请自由创作）"

	return prompt

func _on_stream_chunk_received(data: String):
	"""处理流式数据块"""
	if not is_generating:
		print("收到数据块但is_generating为false，忽略: " + data.substr(0, 100) + "...")
		return

	# 解析流式数据
	var parsed_data = _parse_stream_data(data)
	if parsed_data.is_empty():
		return

	# 累积完整响应内容
	full_response_content += parsed_data
	# print("累积响应内容长度: ", full_response_content.length())

	# 解析标题和简介
	_parse_and_display_content(full_response_content)

func _parse_stream_data(data: String) -> String:
	"""解析流式响应数据"""
	var result = ""
	
	# 按行分割数据，处理可能连在一起的多个data块
	var lines = data.split("\n")
	
	for line in lines:
		var trimmed_line = line.strip_edges()
		
		# 跳过空行
		if trimmed_line.is_empty():
			continue
		
		# 处理SSE格式的数据
		if trimmed_line.begins_with("data: "):
			var json_str = trimmed_line.substr(6).strip_edges()
			
			if json_str == "[DONE]":
				print("收到[DONE]标记，流式响应结束")
				# 直接标记生成完成，不等待_http_client的信号
				_finalize_generation()
				continue
			
			var json = JSON.new()
			if json.parse(json_str) == OK:
				var response_data = json.data
				if response_data.has("choices") and response_data.choices.size() > 0:
					var choice = response_data.choices[0]
					
					# 检查是否是结束chunk（包含finish_reason）
					if choice.has("finish_reason") and choice.finish_reason == "stop":
						print("收到finish_reason=stop，流式响应结束")
						_finalize_generation()
						continue
					
					# 处理正常的内容delta
					if choice.has("delta") and choice.delta.has("content"):
						var content = choice.delta.content
						# 只累积非空内容
						if not content.is_empty():
							result += content
			else:
				print("JSON解析失败: " + json_str)
		else:
			# 不是data:开头的行，可能是其他SSE事件或空行
			if not trimmed_line.is_empty():
				print("跳过非data行: " + trimmed_line)
	
	return result

func _parse_and_display_content(content: String):
	"""解析并显示内容"""
	var all_lines = content.split("\n")
	
	# 初始化变量
	var title = ""
	var user_role = ""
	var character_role = ""
	var summary_lines = []
	var in_summary = false
	
	# 逐行解析
	for line in all_lines:
		var stripped_line = line.strip_edges()
		
		# 跳过空行
		if stripped_line.is_empty():
			continue
		
		# 解析标题行
		if stripped_line.begins_with("标题：") or stripped_line.begins_with("标题:"):
			var separator = "标题：" if "标题：" in stripped_line else "标题:"
			title = stripped_line.substr(separator.length()).strip_edges()
			continue
		
		# 解析主角A
		if stripped_line.begins_with("主角A：") or stripped_line.begins_with("主角A:"):
			var separator = "主角A：" if "主角A：" in stripped_line else "主角A:"
			user_role = stripped_line.substr(separator.length()).strip_edges()
			continue
		
		# 解析主角B
		if stripped_line.begins_with("主角B：") or stripped_line.begins_with("主角B:"):
			var separator = "主角B：" if "主角B：" in stripped_line else "主角B:"
			character_role = stripped_line.substr(separator.length()).strip_edges()
			continue
		
		# 解析简介
		if stripped_line.begins_with("简介：") or stripped_line.begins_with("简介:"):
			var separator = "简介：" if "简介：" in stripped_line else "简介:"
			var intro_text = stripped_line.substr(separator.length()).strip_edges()
			if not intro_text.is_empty():
				summary_lines.append(intro_text)
			in_summary = true
			continue
		
		# 如果已经进入简介部分，收集后续内容
		if in_summary:
			summary_lines.append(stripped_line)
	
	# 处理标题（去除可能的markdown标记和书名号）
	var processed_title = _process_title(title)
	
	# 处理简介
	var processed_summary = "\n".join(summary_lines)
	
	# 更新当前内容
	current_title = processed_title
	current_summary = processed_summary
	
	# 显示到UI
	_display_content(processed_title, processed_summary, user_role, character_role)

func _process_title(raw_title: String) -> String:
	"""处理标题格式"""
	var title = raw_title.strip_edges()

	# 去除markdown标题标记
	if title.begins_with("#"):
		title = title.substr(1).strip_edges()
		# 处理多级标题
		while title.begins_with("#"):
			title = title.substr(1).strip_edges()

	# 去除书名号
	title = title.replace("《", "").replace("》", "")

	return title

func _display_content(title: String, summary: String, user_role: String = "", character_role: String = ""):
	"""显示内容到UI"""
	if not story_creation_panel:
		return

	if story_creation_panel.title_input:
		story_creation_panel.title_input.text = title

	if story_creation_panel.summary_input:
		story_creation_panel.summary_input.text = summary
	
	# 更新身份设定输入框
	if story_creation_panel.user_role_input:
		story_creation_panel.user_role_input.text = user_role
	
	if story_creation_panel.character_role_input:
		story_creation_panel.character_role_input.text = character_role

func _finalize_generation():
	"""最终化生成过程（统一处理完成逻辑）"""
	print("进入_finalize_generation函数，is_generating = ", is_generating)

	# 如果已经完成，防止重复调用
	if not is_generating:
		print("is_generating为false，跳过重复的完成处理")
		return

	# 标记为已完成，防止重复调用
	is_generating = false
	print("设置is_generating = false")

	# 停止流式传输（如果还在进行中）
	if ai_http_client:
		ai_http_client.stop_streaming()

	# 调试：打印完整响应
	print("=== AI生成完成 ===")
	print("完整响应内容:")
	print("---")
	print(full_response_content)
	print("---")
	print("解析结果:")
	print("标题: '" + current_title + "'")
	print("简介: '" + current_summary + "'")
	print("==================")

	# 恢复按钮状态
	_update_generate_button_state(false, "生成故事")

	# 发送完成信号
	generation_completed.emit(current_title, current_summary)

func _on_stream_completed():
	"""流式响应完成（由HTTP客户端调用）"""
	print("HTTP客户端报告流式响应完成，调用_finalize_generation")
	_finalize_generation()

func _on_stream_error(error_message: String):
	"""流式响应错误"""
	_handle_generation_error(error_message)

func _handle_generation_error(error_message: String):
	"""处理生成错误"""
	is_generating = false
	full_response_content = ""  # 清空响应内容

	# 恢复按钮状态
	_update_generate_button_state(false, "生成故事")

	# 将错误信息显示到简介框
	if story_creation_panel and story_creation_panel.summary_input:
		story_creation_panel.summary_input.text = "生成失败：\n" + error_message

	# 发送错误信号
	generation_error.emit(error_message)

func stop_generation():
	"""停止生成过程"""
	if is_generating:
		is_generating = false
		full_response_content = ""  # 清空响应内容
		ai_http_client.stop_streaming()
		_update_generate_button_state(false, "生成故事")

func _on_confirm_timeout():
	"""确认计时器超时"""
	is_confirm_mode = false
	_update_generate_button_state(false, "生成故事")
