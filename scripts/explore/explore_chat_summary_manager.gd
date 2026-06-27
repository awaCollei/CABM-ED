extends Node

# 探索场景专用聊天总结管理器
# 用于生成探索场景的聊天归档总结

var easy_ai: Node = EasyAi  # easy_ai 组件引用

func _init():
	pass

func setup():
	"""初始化管理器"""
	pass

func call_explore_summary_api(conversation_history: Array, user_name: String, explore_scene_name: String, character_name: String) -> String:
	"""调用探索场景总结API

	Args:
		conversation_history: 对话历史数组
		user_name: 用户名
		explore_scene_name: 探索场景名称
		character_name: 角色名称

	Returns:
		总结文本，如果失败则返回空字符串
	"""
	if not easy_ai:
		push_error("探索总结管理器: easy_ai 未初始化")
		return ""

	# 扁平化对话历史
	var flattened_conversation = _flatten_conversation_history(conversation_history)

	# 构建系统提示词
	var system_prompt = "你是一个总结专家。请以%s的第一人称视角，用简洁的语言总结这段探索场景中的对话内容。总结应该反映探索、战斗和互动的主要内容，不要超过150字。直接给出总结内容，不要包含多余的提示。" % [character_name]

	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": flattened_conversation}
	]

	# 使用 easy_ai 发送请求
	var result = await easy_ai.request(
		"summary_model",
		messages,
		false,  # 不使用 JSON 模式
		{
			"max_tokens": 1024,
			"temperature": 0.3,
			"top_p": 0.7
		}
	)

	if not result.success:
		push_error("探索总结请求失败: " + result.error)
		return ""

	return result.content.strip_edges()

func _flatten_conversation_history(conversation_history: Array) -> String:
	"""将对话历史扁平化为文本格式

	Args:
		conversation_history: 对话历史数组，每个元素包含role和content

	Returns:
		扁平化的对话文本
	"""
	var flattened = []

	for msg in conversation_history:
		var role = msg.get("role", "")
		var content = msg.get("content", "")

		if role == "user":
			flattened.append("用户: " + content)
		elif role == "assistant":
			flattened.append("AI: " + content)

	return "\n".join(flattened)


