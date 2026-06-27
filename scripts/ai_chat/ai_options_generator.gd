extends Node

# AI 选项生成器
# 负责在对话结束时生成三个对话选项

signal options_generated(options: Array)
signal options_error(error_message: String)

var owner_service: Node  # AIService
var logger: Node

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
	
	# 构建对话历史文本
	var conversation_text = _build_conversation_text(conversation_history)
	
	# 构建系统提示词
	var system_prompt = _build_system_prompt()
	
	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": conversation_text}
	]
	
	# 使用 easy_ai 发送请求
	var result = await owner_service.easy_ai.request(
		"summary_model",  # 使用 summary_model 任务
		messages, 
		false,  # 不使用 JSON 模式
		{
			"max_tokens": 300,
			"temperature": 0.8,
			"top_p": 0.9
		}
	)

	if not result.success:
		MessageDisplay.show_failure_message("选项生成失败: " + result.error)
		push_error("选项生成请求失败: " + result.error)
		options_error.emit("请求失败")
		return
	
	# 处理响应
	_process_options_response(result.content, messages)

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

func _process_options_response(content: String, messages: Array):
	"""处理选项生成响应"""
	var cleaned_content = content.strip_edges()
	
	# 解析选项（按行分割）
	var lines = cleaned_content.split("\n")
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
