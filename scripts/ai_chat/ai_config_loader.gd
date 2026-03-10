extends Node

# AI 配置加载器
# 职责：加载和管理 AI 配置和 API 密钥
# 加载策略：
# - api_key, base_url, model: 只从用户配置(user://ai_keys.json)加载
# - 其他配置：只从项目配置(res://config/ai_config.json)加载
# - 不回退，不混合，配置缺失就留空

var config: Dictionary = {}  # 合并后的完整配置
var _user_api_key: String = ""  # 用户配置的 API 密钥
var builtin_key_manager: Node = null  # 内置密钥管理器

# API密钥属性（自动处理内置密钥）
var api_key: String:
	get:
		return _get_effective_api_key_global()

func load_all():
	"""加载所有配置"""
	_init_builtin_key_manager()  # 初始化内置密钥管理器
	_load_project_config()  # 先加载项目配置作为基础
	_load_user_config()     # 再加载用户配置覆盖特定字段

func _load_project_config():
	"""加载项目配置文件中的配置"""
	var config_path = "res://config/ai_config.json"
	if not FileAccess.file_exists(config_path):
		push_error("AI 项目配置文件不存在: " + config_path)
		return

	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		push_error("无法打开项目配置文件")
		return
	
	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) == OK:
		config = json.data
		print("AI 项目配置加载成功")
	else:
		push_error("AI 项目配置解析失败")

func _load_user_config():
	"""加载用户配置文件中的 API 密钥和模型配置"""
	var user_config_path = "user://ai_keys.json"
	if not FileAccess.file_exists(user_config_path):
		push_error("AI 用户配置文件不存在: " + user_config_path)
		return

	var file = FileAccess.open(user_config_path, FileAccess.READ)
	if not file:
		push_error("无法打开用户配置文件")
		return
	
	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		push_error("用户配置解析失败")
		return

	var user_config = json.data
	
	# 处理每个模型的配置：只更新 api_key, base_url, model
	_update_model_config("chat_model", user_config)
	_update_model_config("summary_model", user_config)
	_update_model_config("relationship_model", user_config)
	_update_model_config("tts_model", user_config)
	_update_model_config("embedding_model", user_config)
	_update_model_config("view_model", user_config)
	_update_model_config("stt_model", user_config)
	_update_model_config("rerank_model", user_config)
	
	# 兼容旧格式：直接读取 api_key 字段
	if user_config.has("api_key"):
		_user_api_key = user_config.api_key
	
	# 注入有效密钥到所有模型配置
	_inject_effective_keys()
	
	print("AI 用户配置加载成功")

func _update_model_config(model_name: String, user_config: Dictionary):
	"""更新指定模型的配置（仅更新 api_key, base_url, model, enable_json_mode）"""
	if not user_config.has(model_name):
		return
	
	var user_model_config = user_config[model_name]
	
	# 确保配置字典中有该模型
	if not config.has(model_name):
		config[model_name] = {}
	
	# 只更新特定字段
	if user_model_config.has("api_key"):
		config[model_name]["api_key"] = user_model_config.api_key
		# 如果是 chat_model，也设置主 api_key
		if model_name == "chat_model" and _user_api_key.is_empty():
			_user_api_key = user_model_config.api_key
	
	if user_model_config.has("base_url"):
		config[model_name]["base_url"] = user_model_config.base_url
	
	if user_model_config.has("model"):
		config[model_name]["model"] = user_model_config.model
	
	if user_model_config.has("enable_json_mode"):
		config[model_name]["enable_json_mode"] = user_model_config.enable_json_mode


func load_generation_options() -> bool:
	"""加载生成选项设置（从AIConfigManager单例读取）"""
	var config_mgr = get_node_or_null("/root/AIConfigManager")
	if config_mgr and config_mgr.has_method("load_generation_options"):
		return config_mgr.load_generation_options()
	return false  # 默认关闭


func _init_builtin_key_manager():
	"""初始化内置密钥管理器"""
	if builtin_key_manager == null:
		builtin_key_manager = Node.new()
		builtin_key_manager.script = load("res://scripts/ai_chat/builtin_key_manager.gd")
		add_child(builtin_key_manager)

func _get_effective_api_key_global() -> String:
	"""获取全局有效的API密钥（检查所有模型是否合法）"""
	# 检查是否启用内置密钥
	var config_mgr = get_node_or_null("/root/AIConfigManager")
	if config_mgr and config_mgr.has_method("load_use_builtin_key"):
		var use_builtin = config_mgr.load_use_builtin_key()
		if use_builtin:
			# 检查所有模型是否都允许使用内置密钥
			if builtin_key_manager:
				var model_names = ["chat_model", "summary_model", "relationship_model", "tts_model", 
								   "embedding_model", "view_model", "stt_model", "rerank_model"]
				
				for model_name in model_names:
					if config.has(model_name) and config[model_name].has("model"):
						var model = config[model_name]["model"]
						if not model.is_empty() and not builtin_key_manager.is_model_allowed(model):
							push_error("模型 " + model + " 不支持使用内置密钥")
							return "INVALID_MODEL_FOR_BUILTIN_KEY"
			
			# 所有模型都合法，返回内置密钥
			if builtin_key_manager:
				var builtin_key = builtin_key_manager.get_builtin_key()
				if not builtin_key.is_empty():
					return builtin_key
				else:
					push_error("无法获取内置密钥")
					return ""
	
	# 返回用户配置的密钥
	return _user_api_key

func _get_effective_api_key(model_name: String = "") -> String:
	"""获取有效的API密钥（考虑内置密钥）- 内部方法"""
	# 检查是否启用内置密钥
	var config_mgr = get_node_or_null("/root/AIConfigManager")
	if config_mgr and config_mgr.has_method("load_use_builtin_key"):
		var use_builtin = config_mgr.load_use_builtin_key()
		if use_builtin:
			# 检查模型是否允许使用内置密钥
			if not model_name.is_empty() and builtin_key_manager:
				if not builtin_key_manager.is_model_allowed(model_name):
					push_error("模型 " + model_name + " 不支持使用内置密钥")
					return "INVALID_MODEL_FOR_BUILTIN_KEY"
			
			# 返回内置密钥
			if builtin_key_manager:
				var builtin_key = builtin_key_manager.get_builtin_key()
				if not builtin_key.is_empty():
					return builtin_key
				else:
					push_error("无法获取内置密钥")
					return ""
	
	# 返回用户配置的密钥
	return _user_api_key

func get_model_config(model_name: String) -> Dictionary:
	"""获取模型配置（自动注入有效的API密钥）"""
	if not config.has(model_name):
		return {}
	
	var model_config = config[model_name].duplicate(true)
	# 获取模型名称用于验证
	var model = model_config.get("model", "")
	
	# 如果配置中有api_key，用有效密钥替换
	if model_config.has("api_key"):
		model_config["api_key"] = _get_effective_api_key(model)
	return model_config

func _inject_effective_keys():
	"""将有效的API密钥注入到所有模型配置中"""
	var model_names = ["chat_model", "summary_model", "relationship_model", "tts_model", 
					   "embedding_model", "view_model", "stt_model", "rerank_model"]

	for model_name in model_names:
		
		if config.has(model_name) and config[model_name].has("model"):
			var model = config[model_name]["model"]
			var effective_key = _get_effective_api_key(model)
			if not effective_key.is_empty():
				config[model_name]["api_key"] = effective_key
