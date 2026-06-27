extends Node

# 助眠模式专用聊天总结管理器
# 用于生成助眠模式的聊天归档总结

var easy_ai: Node = EasyAi  # easy_ai 组件引用

func _init():
	pass

func setup():
	"""初始化管理器"""
	pass

func call_sleep_summary_api(display_history: String, character_name: String) -> String:
	"""调用助眠场景总结API
	
	Args:
		display_history: 已格式化的对话历史文本
		character_name: 角色名称
		
	Returns:
		总结文本，如果失败则返回空字符串
	"""
	if not easy_ai:
		push_error("助眠总结管理器: easy_ai 未初始化")
		return ""

	# 构建系统提示词（专门针对助眠场景）
	var system_prompt = "你是一个总结专家。请以%s的第一人称视角，用温柔简洁的语言总结这段助眠陪伴中的对话内容。总结应该反映陪伴、安抚和互动的主要内容，不要超过150字。直接给出总结内容，不要包含多余的提示。" % [character_name]

	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": display_history}
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
		push_error("助眠总结请求失败: " + result.error)
		return ""

	return result.content.strip_edges()
