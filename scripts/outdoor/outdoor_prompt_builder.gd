extends Node

# 户外场景提示词构建器
# 目标：复用主系统已有的记忆/配置能力，但按户外规则生成纯文本提示词。

func build_outdoor_prompt(user_input: String, outdoor_scene_name: String, costume_data: Dictionary) -> String:
	var save_mgr = get_node_or_null("/root/SaveManager")
	var prompt_builder = get_node_or_null("/root/PromptBuilder")
	if save_mgr == null or prompt_builder == null:
		push_error("OutdoorPromptBuilder: 缺少 SaveManager 或 PromptBuilder")
		return ""

	_ensure_prompt_builder_ready(prompt_builder)

	var character_name = save_mgr.get_character_name()
	var user_name = save_mgr.get_user_name()
	var user_address = save_mgr.get_user_address()

	var character_prompt = _build_outdoor_costume_prompt(costume_data)
	var identity = _build_identity(character_name, user_name, user_address, character_prompt)

	# 复用主系统已有上下文能力：关系、知识、最近发生（中期记忆）。
	var relationship_context = prompt_builder.get_relationship_context()
	var knowledge_memory = prompt_builder._retrieve_knowledge_memory(user_input)
	var recent_memory = prompt_builder.get_memory_context()

	var affection_level = prompt_builder._convert_affection_to_text(save_mgr.get_affection())
	var interaction_level = prompt_builder._convert_willingness_to_text(save_mgr.get_reply_willingness())
	var current_time = prompt_builder._format_current_time()

	# 户外场景统一按 ongoing 触发上下文。
	var trigger_context = _build_ongoing_trigger_context(outdoor_scene_name, user_name)

	var sections: Array[String] = []
	sections.append("## 身份\n%s" % identity)
	sections.append("## 当前状态\n时间：%s\n你和%s位于：%s\n对%s的好感度：%s\n互动意愿：%s" % [
		current_time,
		user_name,
		outdoor_scene_name,
		user_name,
		affection_level,
		interaction_level
	])

	if not String(relationship_context).strip_edges().is_empty():
		sections.append("## 你们之间的关系\n%s" % relationship_context)
	if not String(knowledge_memory).strip_edges().is_empty():
		sections.append("## 相关的知识记忆\n%s" % knowledge_memory)
	# if not String(recent_memory).strip_edges().is_empty():
	# 	sections.append("## 最近发生的事情\n```\n%s\n```" % recent_memory)

	sections.append(trigger_context)
	return "\n\n".join(sections)

func _ensure_prompt_builder_ready(prompt_builder: Node) -> void:
	if not prompt_builder.has_method("_load_config"):
		return
	if prompt_builder.config.is_empty():
		prompt_builder._load_config()

func _build_identity(character_name: String, user_name: String, user_address: String, character_prompt: String) -> String:
	var identity_loader = get_node_or_null("/root/CharacterIdentityLoader")
	if identity_loader == null:
		return "你是%s，正在和%s交流。%s" % [character_name, user_name, character_prompt]

	var identity = identity_loader.get_full_identity(user_address, character_prompt)
	identity = identity.replace("{character_name}", character_name)
	identity = identity.replace("{user_name}", user_name)
	return identity

func _build_ongoing_trigger_context(outdoor_scene_name: String, user_name: String) -> String:
	return "你现在和%s来到了%s。" % [user_name,outdoor_scene_name]

func _build_outdoor_costume_prompt(costume_data: Dictionary) -> String:
	var prompt_text = str(costume_data.get("prompt", "")).strip_edges()
	if not prompt_text.is_empty():
		return prompt_text

	var costume_name = str(costume_data.get("name", "当前户外服装")).strip_edges()
	var costume_desc = str(costume_data.get("description", "")).strip_edges()
	if costume_desc.is_empty():
		return "你现在穿着%s。" % costume_name
	return "你现在穿着%s。服装特点：%s" % [costume_name, costume_desc]
