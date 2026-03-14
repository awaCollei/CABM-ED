extends Node
## 记忆管理器 - 统一管理对话和日记的向量存储
## 加载策略：
## - 嵌入和重排序模型：从用户配置加载 api_key, base_url, model
## - 其他所有配置：从项目配置加载

signal memory_system_ready

var memory_system: Node = null
var config: Dictionary = {}
var is_initialized: bool = false

# 自动保存
var auto_save_timer: Timer = null

func _ready():
	# 延迟初始化，等待 AIService 准备好
	call_deferred("_deferred_init")

func _deferred_init():
	# 等待保存管理器就绪
	var sm = get_node_or_null("/root/SaveManager")
	if sm and not sm.is_resources_ready():
		print("记忆管理器等待资源加载")
		return

	#这一坨……能跑就别动了
	# 等待 AIService 准备好
	var ai_service = get_node_or_null("/root/AIService")
	if not ai_service:
		print("错误: AIService 节点不存在，等待下一帧")
		await get_tree().process_frame
		_deferred_init()
		return
	
	if not ai_service.config_loader:
		print("等待 AIService.config_loader 初始化...")
		await get_tree().process_frame
		_deferred_init()
		return
	
	# 加载配置
	_load_config()

	# 如果配置加载失败，不继续初始化
	if config.is_empty() or not config.has("embedding_model"):
		print("记忆管理器初始化失败：配置不完整")
		return

	# 创建记忆系统实例
	var memory_script = load("res://scripts/memory_system.gd")
	memory_system = memory_script.new()
	add_child(memory_system)

	# 初始化记忆系统
	memory_system.initialize(config, "main_memory")
	is_initialized = true

	# 设置自动保存
	if config.get("storage", {}).get("auto_save", true):
		_setup_auto_save()

	memory_system_ready.emit()
	print("记忆管理器已就绪")

func _load_config():
	"""加载记忆配置"""
	# 使用统一的AI配置加载器
	var ai_service = get_node_or_null("/root/AIService")
	if not ai_service:
		print("错误: AIService 节点不存在")
		return
	
	if not ai_service.config_loader:
		print("错误: AI配置加载器不可用")
		return
	
	var config_loader = ai_service.config_loader
	
	# 1. 先加载项目配置中的记忆相关配置
	var project_config = _load_project_config()
	print("项目配置加载结果: ", "空" if project_config.is_empty() else str(project_config.keys()))
	# 2. 从配置加载器获取模型配置
	var embedding_config = config_loader.get_model_config("embedding_model")
	var rerank_config = config_loader.get_model_config("rerank_model")
	var summary_config = config_loader.get_model_config("summary_model")
	
	print("嵌入模型配置: ", embedding_config.keys() if not embedding_config.is_empty() else "空")
	print("重排序模型配置: ", rerank_config.keys() if not rerank_config.is_empty() else "空")
	print("总结模型配置: ", summary_config.keys() if not summary_config.is_empty() else "空")
	
	# 3. 合并配置
	config = project_config.duplicate(true)
	if not embedding_config.is_empty():
		config["embedding_model"] = embedding_config
	if not rerank_config.is_empty():
		config["rerank_model"] = rerank_config
	if not summary_config.is_empty():
		config["summary_model"] = summary_config
	
	print("最终配置包含的键: ", config.keys())
	print("是否包含 embedding_model: ", config.has("embedding_model"))
	
	if config.is_empty():
		print("错误: 配置为空")
		return
	
	if not config.has("embedding_model"):
		print("错误: 缺少 embedding_model 配置")
		return
	
	print("记忆配置加载完成")
	_log_memory_config()

func reload_config():
	"""重新加载配置并更新memory_system"""
	print("重新加载记忆配置...")
	_load_config()
	
	# 如果memory_system已初始化，更新其配置
	if memory_system and is_initialized:
		# 重新初始化memory_system（保留现有数据）
		memory_system.update_config(config)
		print("记忆系统配置已更新")
	else:
		print("记忆系统尚未初始化，配置将在初始化时应用")

func _load_project_config() -> Dictionary:
	"""从项目配置文件加载记忆相关配置"""
	var config_path = "res://config/ai_config.json"
	var result = {}
	
	if not FileAccess.file_exists(config_path):
		print("警告: AI 项目配置文件不存在")
		return result
	
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		print("警告: 无法打开项目配置文件")
		return result
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		print("警告: 项目配置解析失败")
		return result
	
	var project_config = json.data
	
	# 提取记忆相关配置
	if project_config.has("memory"):
		result["memory"] = project_config.memory

	# 复制summary_model配置
	if project_config.has("summary_model"):
		result["summary_model"] = project_config.summary_model
		
		# 从 memory 配置中提取子配置
		var memory_config = project_config.memory
		
		# 存储配置
		result["storage"] = {
			"store_summaries": memory_config.get("store_summaries", true),
			"store_diaries": memory_config.get("store_diaries", true),
			"auto_save": memory_config.get("auto_save", true),
			"save_interval": memory_config.get("save_interval", 300)
		}
		
		# 检索配置
		if memory_config.has("vector_db"):
			var vector_db = memory_config.vector_db
			result["retrieval"] = {
				"top_k": vector_db.get("top_k", 5),
				"min_similarity": vector_db.get("min_similarity", 0.3),
				"timeout": vector_db.get("timeout", 10.0)
			}
	
	# 嵌入模型的其他配置（非 api_key/base_url/model）
	if project_config.has("embedding_model"):
		var embed_config = project_config.embedding_model
		result["embedding_model_config"] = {}
		
		# 复制除了 api_key/base_url/model 之外的所有字段
		for key in embed_config:
			if key not in ["api_key", "base_url", "model"]:
				result["embedding_model_config"][key] = embed_config[key]
	
	# 重排序模型的其他配置
	if project_config.has("rerank_model"):
		var rerank_config = project_config.rerank_model
		result["rerank_model_config"] = {}

		for key in rerank_config:
			if key not in ["api_key", "base_url", "model"]:
				result["rerank_model_config"][key] = rerank_config[key]

	# 总结模型的其他配置
	if project_config.has("summary_model"):
		var summary_config = project_config.summary_model
		result["summary_model_config"] = {}

		for key in summary_config:
			if key not in ["api_key", "base_url", "model"]:
				result["summary_model_config"][key] = summary_config[key]

	print("项目配置加载成功")
	return result
func _log_memory_config():
	"""打印记忆配置摘要"""
	if config.has("embedding_model"):
		var embed = config.embedding_model
		print("嵌入模型: " + str(embed.get("model", "未设置")))
		if embed.has("base_url"):
			print("  Base URL: " + str(embed.base_url))
	
	if config.has("rerank_model"):
		print("重排序模型: 已配置")
	else:
		print("重排序模型: 未配置")

	if config.has("summary_model"):
		var summary = config.summary_model
		print("总结模型: " + str(summary.get("model", "未设置")))
		if summary.has("base_url"):
			print("  Base URL: " + str(summary.base_url))
	else:
		print("总结模型: 未配置")
	
	if config.has("storage"):
		var storage = config.storage
		print("存储配置:")
		print("  保存总结: " + str(storage.get("store_summaries", true)))
		print("  保存日记: " + str(storage.get("store_diaries", true)))
		print("  自动保存: " + str(storage.get("auto_save", true)))

func _setup_auto_save():
	"""设置自动保存定时器"""
	auto_save_timer = Timer.new()
	add_child(auto_save_timer)
	
	var interval = config.get("storage", {}).get("save_interval", 300)
	auto_save_timer.wait_time = interval
	auto_save_timer.timeout.connect(_on_auto_save)
	auto_save_timer.start()
	
	print("自动保存已启用，间隔: %d 秒" % interval)

func _on_auto_save():
	"""自动保存回调"""
	if memory_system:
		memory_system.save_to_file()
		print("记忆数据已自动保存")

func add_conversation_summary(summary: String, metadata: Dictionary = {}, custom_timestamp: String = ""):
	"""添加对话总结到记忆系统"""
	if not is_initialized:
		await memory_system_ready
	
	if summary.strip_edges().is_empty():
		return
	
	var storage_config = config.get("storage", {})
	if storage_config.get("store_summaries", true):
		await memory_system.add_text(summary, "conversation", metadata, custom_timestamp)
		print("对话总结已添加到向量库")

func add_diary_entry(entry: Dictionary):
	"""添加日记条目到记忆系统"""
	if not is_initialized:
		await memory_system_ready
	
	var storage_config = config.get("storage", {})
	if storage_config.get("store_diaries", true):
		var diary_text = entry.event
		await memory_system.add_diary_entry(diary_text)
		print("日记条目已添加到向量库")

func get_relevant_memory_for_chat(context: String, exclude_timestamps: Array = []) -> String:
	"""获取与当前对话相关的记忆"""
	if not is_initialized:
		print("记忆系统未初始化，等待就绪...")
		await memory_system_ready
	
	var retrieval_config = config.get("retrieval", {})
	var top_k = retrieval_config.get("top_k")
	var min_similarity = retrieval_config.get("min_similarity")
	var timeout = retrieval_config.get("timeout")
	
	print("开始检索记忆：top_k=%d, min_similarity=%.2f, 排除=%d条" % [top_k, min_similarity, exclude_timestamps.size()])
	var result = await memory_system.get_relevant_memory(context, top_k, timeout, min_similarity, exclude_timestamps)
	print("记忆检索完成，结果长度: %d" % result.length())
	
	return result

func save():
	"""手动保存记忆数据"""
	if memory_system:
		memory_system.save_to_file()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# 退出前保存
		if memory_system:
			memory_system.save_to_file()
			print("退出前保存记忆数据")
