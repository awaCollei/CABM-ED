# AI 配置管理模块
# 负责：配置的加载、保存、迁移等

extends Node

const CONFIG_PATH = "user://ai_keys.json"

# 新的数据结构：厂商、模型、模型任务
# 厂商数据结构: { "厂商名": { "base_url": "...", "api_key": "..." } }
# 模型数据结构: { "模型名": { "provider": "厂商名", "identifier": "模型标识符", "params": {...} } }
# 模型任务数据结构: { "任务名": { "description": "描述", "model": "模型名" } }

# 预设厂商
const PRESET_PROVIDERS = {
	"硅基流动": {
		"base_url": "https://api.siliconflow.cn/v1",
		"api_key": ""
	}
}

# 预设模型
const PRESET_MODELS = {
	"Qwen3-8B": {
		"provider": "硅基流动",
		"identifier": "Qwen/Qwen3-8B",
		"params": {},
		"url_suffix": "/chat/completions"
	},
	"DeepSeek-V3.2": {
		"provider": "硅基流动",
		"identifier": "deepseek-ai/DeepSeek-V3.2",
		"params": {},
		"url_suffix": "/chat/completions"
	},
	"DeepSeek-V3": {
		"provider": "硅基流动",
		"identifier": "deepseek-ai/DeepSeek-V3",
		"params": {},
		"url_suffix": "/chat/completions"
	},
	"Qwen3-30B-A3B": {
		"provider": "硅基流动",
		"identifier": "Qwen/Qwen3-30B-A3B-Instruct-2507",
		"params": {},
		"url_suffix": "/chat/completions"
	},
	"CosyVoice2": {
		"provider": "硅基流动",
		"identifier": "FunAudioLLM/CosyVoice2-0.5B",
		"params": {},
		"url_suffix": "/audio/speech"
	},
	"bge-m3": {
		"provider": "硅基流动",
		"identifier": "BAAI/bge-m3",
		"params": {},
		"url_suffix": "/embeddings"
	},
	"GLM-4.1V": {
		"provider": "硅基流动",
		"identifier": "THUDM/GLM-4.1V-9B-Thinking",
		"params": {},
		"url_suffix": "/chat/completions"
	},
	"Qwen3-Omni": {
		"provider": "硅基流动",
		"identifier": "Qwen/Qwen3-Omni-30B-A3B-Captioner",
		"params": {},
		"url_suffix": "/chat/completions"
	},
	"SenseVoice": {
		"provider": "硅基流动",
		"identifier": "FunAudioLLM/SenseVoiceSmall",
		"params": {},
		"url_suffix": "/audio/transcriptions"
	},
	"bge-reranker": {
		"provider": "硅基流动",
		"identifier": "BAAI/bge-reranker-v2-m3",
		"params": {},
		"url_suffix": "/embeddings"
	}
}

# 模型任务定义
const MODEL_TASKS = {
	"chat_model": {
		"name": "对话模型",
		"description": "用于角色的对话和行为"
	},
	"summary_model": {
		"name": "总结模型",
		"description": "用于信息的整合和提取"
	},
	"tts_model": {
		"name": "语音模型",
		"description": "用于语音合成"
	},
	"embedding_model": {
		"name": "嵌入模型",
		"description": "用于文本向量化"
	},
	"view_model": {
		"name": "视觉模型",
		"description": "用于图像识别"
	},
	"stt_model": {
		"name": "语音输入",
		"description": "用于语音识别"
	},
	"rerank_model": {
		"name": "重排模型",
		"description": "用于搜索结果重排"
	}
}

# 配置模板定义（快速配置用，引用预设模型名）
const CONFIG_TEMPLATES = {
	"free": {
		"name": "免费",
		"description": "没有语音，而且不太聪明，但是免费",
		"models": {
			"chat_model": "Qwen3-8B",
			"summary_model": "Qwen3-8B",
			"tts_model": "",
			"embedding_model": "bge-m3",
			"view_model": "GLM-4.1V",
			"stt_model": "SenseVoice",
			"rerank_model": "bge-reranker"
		}
	},
	"standard": {
		"name": "标准",
		"description": "以高性价比获得更佳的体验",
		"models": {
			"chat_model": "DeepSeek-V3.2",
			"summary_model": "Qwen3-30B-A3B",
			"tts_model": "CosyVoice2",
			"embedding_model": "bge-m3",
			"view_model": "Qwen3-Omni",
			"stt_model": "SenseVoice",
			"rerank_model": "bge-reranker"
		}
	},
	"alternate": {
		"name": "备用",
		"description": "比标准稍微差点，可以作为备选",
		"models": {
			"chat_model": "DeepSeek-V3",
			"summary_model": "Qwen3-30B-A3B",
			"tts_model": "CosyVoice2",
			"embedding_model": "bge-m3",
			"view_model": "Qwen3-Omni",
			"stt_model": "SenseVoice",
			"rerank_model": "bge-reranker"
		}
	}
}

## 加载现有配置
func load_config() -> Dictionary:
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return {}
	
	return json.data as Dictionary

## 保存配置到文件
func save_config(config: Dictionary) -> bool:
	# 先加载现有配置，避免覆盖其他设置
	var existing_config = load_config()
	
	# 合并新配置到现有配置中
	for key in config.keys():
		existing_config[key] = config[key]
	
	var file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return false
	
	file.store_string(JSON.stringify(existing_config, "\t"))
	file.close()
	
	print("AI配置已保存")
	return true

## 获取模板配置
func get_template(template_name: String) -> Dictionary:
	if CONFIG_TEMPLATES.has(template_name):
		return CONFIG_TEMPLATES[template_name]
	return {}

## 获取所有模板
func get_all_templates() -> Dictionary:
	return CONFIG_TEMPLATES

## 验证API密钥
func verify_api_key(input_key: String) -> bool:
	if not FileAccess.file_exists(CONFIG_PATH):
		return false
	
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return false
	
	var config = json.data
	
	# 检查 chat_model 的 api_key
	if config.has("chat_model") and config.chat_model.has("api_key"):
		if config.chat_model.api_key == input_key:
			return true
	
	# 检查快速配置的 api_key
	if config.has("api_key"):
		if config.api_key == input_key:
			return true
	
	return false

## 加载特定模型的配置
func load_model_config(model_type: String) -> Dictionary:
	var config = load_config()
	
	if config.has(model_type):
		return config[model_type] as Dictionary
	
	return {}

## 保存响应模式
func save_response_mode(mode: String) -> bool:
	var config = load_config()
	config["response_mode"] = mode
	return save_config(config)

## 加载响应模式
func load_response_mode() -> String:
	var config = load_config()
	return config.get("response_mode", "narrative")

## 保存记忆系统配置
func save_memory_config(memory_config: Dictionary) -> bool:
	var config = load_config()
	config["memory_system"] = memory_config
	return save_config(config)

## 加载记忆系统配置
func load_memory_config() -> Dictionary:
	var config = load_config()
	var default_config = {
		"save_memory_vectors": true,
		"enable_semantic_search": true,
		"enable_reranking": true,
		"enable_time_aware_reranking": false,
		"enable_pre_recall_reasoning": false,
		"save_knowledge_graph": true,
		"enable_kg_search": true
	}

	if config.has("memory_system"):
		var memory_config = config.memory_system
		# 合并默认配置，确保所有字段都存在
		for key in default_config.keys():
			if not memory_config.has(key):
				memory_config[key] = default_config[key]
		return memory_config

	return default_config

## 保存表情差分设置
func save_expression_diff(enabled: bool) -> bool:
	var config = load_config()
	config["expression_diff"] = enabled
	return save_config(config)

## 加载表情差分设置
func load_expression_diff() -> bool:
	var config = load_config()
	return config.get("expression_diff", true) # 默认开启

## 保存生成选项设置
func save_generation_options(enabled: bool) -> bool:
	var config = load_config()
	config["generation_options"] = enabled
	return save_config(config)

## 加载生成选项设置
func load_generation_options() -> bool:
	var config = load_config()
	return config.get("generation_options", true) # 默认开启

## 保存上方输入框设置
func save_top_input_box(enabled: bool) -> bool:
	var config = load_config()
	config["top_input_box"] = enabled
	var result = save_config(config)
	print("ConfigManager: 保存顶部输入框设置 = %s, 结果 = %s" % [enabled, result])
	return result

## 加载上方输入框设置
func load_top_input_box() -> bool:
	var config = load_config()
	var value = config.get("top_input_box", false) # 默认关闭
	print("ConfigManager: 加载顶部输入框设置 = %s (配置文件: %s)" % [value, CONFIG_PATH])
	return value

## 保存显示请求状态设置
func save_status_check(enabled: bool) -> bool:
	var config = load_config()
	config["status_check"] = enabled
	return save_config(config)

## 加载显示请求状态设置
func load_status_check() -> bool:
	var config = load_config()
	return config.get("status_check", true) # 默认开启

## 保存使用内置密钥设置
func save_use_builtin_key(enabled: bool) -> bool:
	var config = load_config()
	config["use_builtin_key"] = enabled
	return save_config(config)

## 加载使用内置密钥设置
func load_use_builtin_key() -> bool:
	var config = load_config()
	return config.get("use_builtin_key", false) # 默认关闭

## 保存呼唤触发对话设置
func save_call_trigger_dialog(enabled: bool) -> bool:
	var config = load_config()
	config["call_trigger_dialog"] = enabled
	return save_config(config)

## 加载呼唤触发对话设置
func load_call_trigger_dialog() -> bool:
	var config = load_config()
	return config.get("call_trigger_dialog", true) # 默认开启

## 保存启用主动对话设置
func save_active_chat(enabled: bool) -> bool:
	var config = load_config()
	config["active_chat"] = enabled
	return save_config(config)

## 加载启用主动对话设置
func load_active_chat() -> bool:
	var config = load_config()
	return config.get("active_chat", true) # 默认开启

## 保存离线模式设置（0=自动, 1=视为玩家离开, 2=视为玩家在家）
func save_offline_mode(mode: int) -> bool:
	var config = load_config()
	config["offline_mode"] = mode
	return save_config(config)

## 加载离线模式设置
func load_offline_mode() -> int:
	var config = load_config()
	return int(config.get("offline_mode", 0)) # 默认自动

## 保存启用离线日记设置
func save_offline_diary(enabled: bool) -> bool:
	var config = load_config()
	config["offline_diary"] = enabled
	return save_config(config)

## 加载启用离线日记设置
func load_offline_diary() -> bool:
	var config = load_config()
	return config.get("offline_diary", true) # 默认开启

## 保存文本输出速度（秒/字）
func save_typing_speed(speed: float) -> bool:
	var config = load_config()
	# 防止异常值写入配置
	var clamped_speed = clampf(speed, 0.01, 0.09)
	config["typing_speed"] =clamped_speed
	return save_config(config)

## 加载文本输出速度（秒/字）
func load_typing_speed() -> float:
	var config = load_config()
	var speed = float(config.get("typing_speed", 0.05))
	return clampf(speed, 0.01, 0.09)

## 保存自动播放设置
func save_auto_continue(enabled: bool) -> bool:
	var config = load_config()
	config["auto_continue"] = enabled
	var result = save_config(config)
	print("ConfigManager: 保存自动播放设置 = %s, 结果 = %s" % [enabled, result])
	return result

## 加载自动播放设置
func load_auto_continue() -> bool:
	var config = load_config()
	var value = config.get("auto_continue", false) # 默认关闭
	return value

## 遮蔽密钥显示
func mask_key(key: String) -> String:
	if key.length() <= 10:
		return "***"
	return key.substr(0, 7) + "..." + key.substr(key.length() - 4)

# ========== 新的数据结构管理方法 ==========

## 获取所有厂商（合并预设和用户自定义）
func get_all_providers() -> Dictionary:
	var config = load_config()
	var providers = PRESET_PROVIDERS.duplicate(true)
	
	# 合并用户自定义厂商
	if config.has("providers"):
		for provider_name in config.providers.keys():
			providers[provider_name] = config.providers[provider_name]
	
	return providers

## 保存厂商
func save_provider(provider_name: String, provider_data: Dictionary) -> bool:
	var config = load_config()
	if not config.has("providers"):
		config["providers"] = {}
	config["providers"][provider_name] = provider_data
	return save_config(config)

## 删除厂商
func delete_provider(provider_name: String) -> bool:
	var config = load_config()
	if config.has("providers") and config.providers.has(provider_name):
		config.providers.erase(provider_name)
		return save_config(config)
	return false

## 获取所有模型（合并预设和用户自定义）
func get_all_models() -> Dictionary:
	var config = load_config()
	var models = PRESET_MODELS.duplicate(true)
	
	# 合并用户自定义模型
	if config.has("models"):
		for model_name in config.models.keys():
			models[model_name] = config.models[model_name]
	
	return models

## 保存模型
func save_model(model_name: String, model_data: Dictionary) -> bool:
	var config = load_config()
	if not config.has("models"):
		config["models"] = {}
	config["models"][model_name] = model_data
	return save_config(config)

## 删除模型
func delete_model(model_name: String) -> bool:
	var config = load_config()
	if config.has("models") and config.models.has(model_name):
		config.models.erase(model_name)
		return save_config(config)
	return false

## 获取所有模型任务配置
func get_model_tasks() -> Dictionary:
	var config = load_config()
	var tasks = {}
	
	# 初始化默认任务
	for task_id in MODEL_TASKS.keys():
		tasks[task_id] = {
			"name": MODEL_TASKS[task_id].name,
			"description": MODEL_TASKS[task_id].description,
			"model": ""
		}
	
	# 合并用户配置
	if config.has("model_tasks"):
		for task_id in config.model_tasks.keys():
			if tasks.has(task_id):
				tasks[task_id]["model"] = config.model_tasks[task_id].get("model", "")
	
	return tasks

## 保存模型任务配置
func save_model_tasks(tasks: Dictionary) -> bool:
	var config = load_config()
	config["model_tasks"] = tasks
	return save_config(config)

## 根据模型名获取完整配置（包含厂商信息）
func get_model_full_config(model_name: String) -> Dictionary:
	var models = get_all_models()
	var providers = get_all_providers()
	
	if not models.has(model_name):
		return {}
	
	var model = models[model_name]
	var provider_name = model.get("provider", "")
	var provider = providers.get(provider_name, {})
	
	return {
		"model": model.get("identifier", ""),
		"base_url": provider.get("base_url", ""),
		"api_key": provider.get("api_key", ""),
		"params": model.get("params", {}),
		"url_suffix": model.get("url_suffix", "")
	}

## 根据任务ID获取模型配置
func get_task_model_config(task_id: String) -> Dictionary:
	var tasks = get_model_tasks()
	if not tasks.has(task_id):
		return {}
	
	var model_name = tasks[task_id].get("model", "")
	if model_name.is_empty():
		return {}
	
	return get_model_full_config(model_name)
