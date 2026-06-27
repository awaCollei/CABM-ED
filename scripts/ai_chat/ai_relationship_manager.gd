extends Node

# Relationship manager: handles relationship model calls and saving

var owner_service: Node = null
var logger: Node = null

func call_relationship_api():
	if not owner_service:
		push_error("RelationshipManager: owner_service not set")
		return

	var prompt_builder = owner_service.get_node("/root/PromptBuilder")
	var current_relationship = prompt_builder.get_relationship_context()
	var memory_context = prompt_builder.get_memory_context()

	# Debug logging to ensure we actually call the relationship model
	print("RelationshipManager: calling relationship model. current_relationship length=%d, memory_context length=%d" % [str(current_relationship.length()).to_int(), str(memory_context.length()).to_int()])
	var save_mgr = owner_service.get_node("/root/SaveManager")
	var character_name = save_mgr.get_character_name()
	var user_name = save_mgr.get_user_name()

	var summary_config = owner_service.config_loader.get_model_config("summary_model")
	var relationship_params = summary_config.get("relationship", {})
	var system_prompt = relationship_params.get("system_prompt", "").replace("{character_name}", character_name).replace("{user_name}", user_name)

	var user_content = "{character_name}的日记：\n{memory_context}".replace("{character_name}", character_name).replace("{memory_context}", memory_context)

	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_content}
	]

	# 使用 easy_ai 发送请求
	var result = await owner_service.easy_ai.request(
		"summary_model",  # 使用 summary_model 任务（关系模型复用）
		messages, 
		false,  # 不使用 JSON 模式
		{
			"max_tokens": int(relationship_params.get("max_tokens", 500)),
			"temperature": float(relationship_params.get("temperature", 0.5)),
			"top_p": float(relationship_params.get("top_p", 0.95))
		}
	)

	if not result.success:
		push_error("关系模型请求失败: " + result.error)
		return

	# 处理响应
	_process_relationship_response(result.content, messages)

func _process_relationship_response(relationship_summary: String, messages: Array):
	# If model returned the same as current relationship, warn — maybe the model was not properly invoked
	var prompt_builder = owner_service.get_node("/root/PromptBuilder")
	var current_relationship = prompt_builder.get_relationship_context()
	if relationship_summary.strip_edges() == current_relationship.strip_edges():
		push_warning("关系模型返回与当前关系相同，可能未更新: %s" % relationship_summary)

	_save_relationship(relationship_summary)
	print("关系模型已更新: ", relationship_summary)

func _save_relationship(relationship_summary: String):
	var save_mgr = owner_service.get_node("/root/SaveManager")
	if not save_mgr.save_data.ai_data.has("relationship_history"):
		save_mgr.save_data.ai_data.relationship_history = []

	var timestamp = owner_service._get_local_datetime_string()
	var cleaned_summary = relationship_summary.strip_edges()

	var relationship_item = {"timestamp": timestamp, "content": cleaned_summary}
	save_mgr.save_data.ai_data.relationship_history.append(relationship_item)

	var max_relationship_history = owner_service.config_loader.config.memory.get("max_relationship_history", 2)
	if save_mgr.save_data.ai_data.relationship_history.size() > max_relationship_history:
		save_mgr.save_data.ai_data.relationship_history = save_mgr.save_data.ai_data.relationship_history.slice(-max_relationship_history)

	save_mgr.save_game(save_mgr.current_slot)

	print("关系信息已保存: ", relationship_summary)
