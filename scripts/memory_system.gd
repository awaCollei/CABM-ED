extends Node
## 记忆系统 - 向量存储和检索
## 使用C++插件进行高性能余弦相似度计算

# 记忆项结构
class MemoryItem:
	var text: String = ""
	var vector: Array = []
	var timestamp: String = ""
	var type: String = "" # "conversation" 或 "diary"
	var metadata: Dictionary = {}
	
	func _init(p_text: String = "", p_vector: Array = [], p_type: String = "conversation"):
		text = p_text
		vector = p_vector.duplicate()  # 强制复制，防止引用问题
		timestamp = _get_local_datetime_string()
		type = p_type
	
	static func _get_local_datetime_string() -> String:
		"""获取本地时间字符串（带时区转换）"""
		var unix_time = Time.get_unix_time_from_system()
		var timezone_offset = TimeUtil.get_timezone_offset()
		var local_dict = Time.get_datetime_dict_from_unix_time(int(unix_time + timezone_offset))
		return "%04d-%02d-%02dT%02d:%02d:%02d" % [
			local_dict.year, local_dict.month, local_dict.day,
			local_dict.hour, local_dict.minute, local_dict.second
		]
	
	func to_dict() -> Dictionary:
		return {
			"text": text,
			"vector": vector,
			"timestamp": timestamp,
			"type": type,
			"metadata": metadata
		}
	
	static func from_dict(data: Dictionary) -> MemoryItem:
		var item = MemoryItem.new()
		var raw_text: String = data.get("text", "")
		# 兼容旧版：历史数据可能在文本开头带有类似 "[02-02 20:26] " 的绝对时间前缀
		if raw_text.begins_with("["):
			var close_idx := raw_text.find("] ")
			if close_idx != -1:
				raw_text = raw_text.substr(close_idx + 2)
		item.text = raw_text
		item.vector = data.get("vector", [])
		item.timestamp = data.get("timestamp", "")
		item.type = data.get("type", "conversation")
		item.metadata = data.get("metadata", {})
		return item

var memory_items: Array[MemoryItem] = []
var config: Dictionary = {}
var db_name: String = "default"
var cosine_calculator = null
var http_request: HTTPRequest = null
var retrieval_optimizer = null
var keyword_extractor = null
# 查询关键词提取缓存：被动检索与知识图谱可复用同一玩家输入的提取结果。
var query_keyword_cache: Dictionary = {}

# 记忆系统配置检查函数（依赖关系在此集中校验）
func _should_save_memory_vectors() -> bool:
	"""检查是否应该保存记忆向量"""
	return _check_memory_config("save_memory_vectors", true)

func _should_save_memory_keywords() -> bool:
	"""检查是否应该保存记忆关键词"""
	return _check_memory_config("save_memory_keywords", true)

func _keyword_count() -> int:
	"""保存/检索时提取的关键词数量"""
	return max(1, int(_memory_number("keyword_count", 8)))

# ── 主动检索（工具调用）──
func _should_active_semantic_search() -> bool:
	return _should_save_memory_vectors() and _check_memory_config("enable_active_semantic_search", true)

func _should_active_keyword_search() -> bool:
	return _should_save_memory_keywords() and _check_memory_config("enable_active_keyword_search", true)

func _should_active_time_search() -> bool:
	return (_should_save_memory_vectors() or _should_save_memory_keywords()) and _check_memory_config("enable_active_time_search", true)

func _should_active_detail_search() -> bool:
	# 详细检索读取记忆的原始对话；若无任何存储方式，则记忆条目根本不会产生。
	return (_should_save_memory_vectors() or _should_save_memory_keywords()) and _check_memory_config("enable_active_detail_search", true)

func _should_active_reranking() -> bool:
	return _should_active_semantic_search() and _check_memory_config("active_reranking", true)

func _should_active_time_aware() -> bool:
	return _should_active_reranking() and _check_memory_config("active_time_aware", true)

# ── 被动检索 ──
func _should_passive_semantic_search() -> bool:
	return _should_save_memory_vectors() and _check_memory_config("enable_passive_semantic_search", false)

func _should_passive_keyword_search() -> bool:
	return _should_save_memory_keywords() and _check_memory_config("enable_passive_keyword_search", false)

func _should_passive_reranking() -> bool:
	return _should_passive_semantic_search() and _check_memory_config("passive_reranking", true)

func _should_passive_time_aware() -> bool:
	return _should_passive_reranking() and _check_memory_config("passive_time_aware", false)

func _should_passive_pre_recall_reasoning() -> bool:
	return _should_passive_semantic_search() and _check_memory_config("passive_pre_recall_reasoning", false)

func _should_save_knowledge_graph() -> bool:
	"""检查是否应该保存知识图谱"""
	return _check_memory_config("save_knowledge_graph", true)

func _should_perform_kg_search() -> bool:
	"""检查是否应该进行知识图谱检索"""
	return _check_memory_config("enable_kg_search", true)

## 主动检索是否启用（任一工具可用），供提示词/请求构建判断
func is_active_retrieval_enabled() -> bool:
	return _should_active_semantic_search() or _should_active_keyword_search() \
		or _should_active_time_search() or _should_active_detail_search()

# 供 ai_service 组装工具定义时逐项判断
func is_active_semantic_enabled() -> bool:
	return _should_active_semantic_search()

func is_active_keyword_enabled() -> bool:
	return _should_active_keyword_search()

func is_active_time_enabled() -> bool:
	return _should_active_time_search()

func is_active_detail_enabled() -> bool:
	return _should_active_detail_search()

func _check_memory_config(key: String, default_value: bool) -> bool:
	"""通用配置检查函数"""
	var ai_config_mgr = get_node_or_null("/root/AIConfigManager")
	if ai_config_mgr:
		var memory_config = ai_config_mgr.load_memory_config()
		return memory_config.get(key, default_value)
	return default_value

func _memory_number(key: String, default_value):
	var ai_config_mgr = get_node_or_null("/root/AIConfigManager")
	if ai_config_mgr:
		return ai_config_mgr.load_memory_config().get(key, default_value)
	return default_value

# 嵌入API配置
var embedding_model: String = ""
var embedding_base_url: String = ""
var embedding_timeout: float = 5.0
var vector_dim: int = 1024

# 重排序API配置
var rerank_model: String = ""
var rerank_base_url: String = ""
var rerank_timeout: float = 10.0
var rerank_top_n: int = 5
var rerank_instruction: String = ""

# 召回前推理API配置
var retrieval_optimization_model: String = ""
var retrieval_optimization_base_url: String = ""
var retrieval_optimization_timeout: float = 30.0
var retrieval_optimization_max_tokens: int = 512
var retrieval_optimization_temperature: float = 0.3
var retrieval_optimization_top_p: float = 0.7
var retrieval_optimization_system_prompt: String = ""

# 请求队列系统
class EmbeddingRequest:
	var text: String = ""
	var completed: bool = false
	var result: Array = []
	
	func _init(p_text: String):
		text = p_text

var request_queue: Array = []
var is_processing_request: bool = false

func _ready():
	# 创建HTTP请求节点
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_embedding_request_completed)

	# 关键词分词器只在启用 Jieba 时参与召回；结果按文本缓存，避免重复分词。
	keyword_extractor = preload("res://scripts/keyword_extractor.gd").new()
	add_child(keyword_extractor)

	# 创建检索优化器
	retrieval_optimizer = Node.new()
	retrieval_optimizer.script = load("res://scripts/retrieval_optimizer.gd")
	add_child(retrieval_optimizer)

	# 加载C++余弦计算插件
	_load_cosine_calculator()

func _load_cosine_calculator():
	"""加载C++余弦相似度计算插件"""
	if ClassDB.class_exists("CosineCalculator"):
		cosine_calculator = ClassDB.instantiate("CosineCalculator")
		print("✓ 余弦计算插件加载成功（C++高性能模式）")
	else:
		print("ℹ 余弦计算插件未编译，使用GDScript实现（性能较低但功能完整）")
		print("  提示：如需高性能，请编译C++插件：cd addons/cosine_calculator && scons")

func initialize(p_config: Dictionary, p_db_name: String = "default"):
	"""初始化记忆系统"""
	config = p_config
	db_name = p_db_name
	_apply_config()
	
	# 加载已保存的向量数据
	load_from_file()
	
	print("记忆系统初始化完成")

func update_config(p_config: Dictionary):
	"""更新配置（不重新加载数据）"""
	config = p_config
	_apply_config()
	print("记忆系统配置已更新")

func _apply_config():
	"""应用配置到成员变量"""
	# 从配置读取嵌入模型参数
	var embed_config = config.get("embedding_model", {})
	embedding_model = embed_config.get("model", "")
	embedding_base_url = embed_config.get("base_url", "")
	embedding_timeout = embed_config.get("timeout", 30.0)
	vector_dim = embed_config.get("vector_dim", 1024)

	# 从配置读取重排序模型参数
	var rerank_config = config.get("rerank_model", {})
	rerank_model = rerank_config.get("model", "")
	rerank_base_url = rerank_config.get("base_url", "")
	rerank_timeout = rerank_config.get("timeout", 10.0)
	rerank_top_n = rerank_config.get("top_n", 5)
	rerank_instruction = rerank_config.get("instruction", "")

	print("重排序配置: model='%s', base_url='%s'" % [rerank_model, rerank_base_url])

	# 从配置读取召回前推理模型参数
	var summary_config = config.get("summary_model", {})
	retrieval_optimization_model = summary_config.get("model", "")
	retrieval_optimization_base_url = summary_config.get("base_url", "")
	retrieval_optimization_timeout = summary_config.get("timeout", 30.0)

	var retrieval_config = summary_config.get("retrieval_optimization", {})
	retrieval_optimization_max_tokens = retrieval_config.get("max_tokens", 512)
	retrieval_optimization_temperature = retrieval_config.get("temperature", 0.3)
	retrieval_optimization_top_p = retrieval_config.get("top_p", 0.7)
	retrieval_optimization_system_prompt = retrieval_config.get("system_prompt", "")

	print("召回前推理配置: model='%s', base_url='%s'" % [retrieval_optimization_model, retrieval_optimization_base_url])

	# 初始化检索优化器
	retrieval_optimizer.initialize(
		"summary_model",
		retrieval_optimization_timeout,
		retrieval_optimization_max_tokens,
		retrieval_optimization_temperature,
		retrieval_optimization_top_p,
		retrieval_optimization_system_prompt
	)

func add_text(text: String, item_type: String = "conversation", metadata: Dictionary = {}, custom_timestamp: String = "") -> void:
	"""添加文本到记忆系统（异步，支持队列）

	Args:
		text: 原始文本内容
		item_type: 类型（conversation 或 diary）
		metadata: 元数据（可选），如 {"mood": "happy", "affection": 75}
		custom_timestamp: 自定义时间戳（可选），格式为 "YYYY-MM-DDTHH:MM:SS"
	"""
	if text.strip_edges().is_empty():
		print("警告: 尝试添加空文本")
		return

	# 检查配置：向量与关键词任一开启即可保存（二者皆关才跳过）
	var save_vectors := _should_save_memory_vectors()
	var save_keywords := _should_save_memory_keywords()
	if not save_vectors and not save_keywords:
		print("配置已禁用保存记忆向量和关键词，跳过添加")
		return

	# 使用自定义时间戳或当前时间
	var timestamp: String
	if not custom_timestamp.is_empty():
		timestamp = custom_timestamp
		print("使用自定义时间戳: %s" % timestamp)
	else:
		timestamp = MemoryItem._get_local_datetime_string()

	# 保存记忆时不再把绝对时间前缀拼进文本
	var formatted_text = text

	# 获取文本的向量表示（使用队列系统，可能有延迟）；仅保存向量时才需要
	var vector: Array = []
	if save_vectors:
		vector = await get_embedding(formatted_text)
		if vector.is_empty():
			if not save_keywords:
				print("警告: 获取向量失败，且未启用关键词保存，跳过添加")
				return
			print("警告: 获取向量失败，仅保存关键词")

	# 创建记忆项（使用确定的时间戳）
	var item = MemoryItem.new(formatted_text, vector, item_type)
	# 先复制业务元数据，再补充 mag / keywords，避免 raw_conversation 等字段被覆盖。
	item.metadata = metadata.duplicate()

	# 预计算向量模长并存入 metadata，便于后续快速相似度计算。
	if not vector.is_empty():
		var mag = 0.0
		for i in range(vector.size()):
			mag += vector[i] * vector[i]
		mag = sqrt(mag)
		if not item.metadata.has("mag") or float(item.metadata.get("mag", 0.0)) == 0.0:
			item.metadata["mag"] = mag

	# 关键词：保存记忆时用 jieba 提取，来源优先原始对话（与向量一同保存）
	if save_keywords:
		var kw_source := str(item.metadata.get("raw_conversation", ""))
		if kw_source.strip_edges().is_empty():
			kw_source = formatted_text
		item.metadata["keywords"] = _extract_keywords(kw_source)

	item.timestamp = timestamp  # 覆盖构造函数中的时间戳

	memory_items.append(item)

	print("添加记忆: [%s] %s..." % [item_type, formatted_text.substr(0, 50)])

	# 立即保存到文件
	save_to_file()
	print("记忆已保存到文件: %d 条" % memory_items.size())

func add_diary_entry(diary_text: String, metadata: Dictionary = {}) -> void:
	"""添加日记条目
	
	Args:
		diary_text: 日记文本（可以已包含时间戳，也可以不包含）
		metadata: 元数据，如 {"event_type": "offline", "mood": "happy"}
	"""
	await add_text(diary_text, "diary", metadata)

func _format_timestamp_for_display(timestamp: String) -> String:
	"""格式化时间戳为显示格式 MM-DD HH:MM"""
	# timestamp 格式: "2025-10-25T10:16:45"
	var parts = timestamp.split("T")
	if parts.size() != 2:
		return timestamp
	
	var date_parts = parts[0].split("-")
	var time_parts = parts[1].split(":")
	
	if date_parts.size() >= 3 and time_parts.size() >= 2:
		return "%s-%s %s:%s" % [date_parts[1], date_parts[2], time_parts[0], time_parts[1]]
	
	return timestamp

func get_embedding(text: String) -> Array:
	"""获取文本的向量表示（调用嵌入API，使用队列系统）"""
	if embedding_base_url.is_empty() or embedding_model.is_empty():
		print("警告: 嵌入模型未配置")
		return []
	
	# 从配置读取API密钥
	var api_key = ""
	if config.has("embedding_model") and config.embedding_model.has("api_key"):
		api_key = config.embedding_model.get("api_key", "")
	
	if api_key.is_empty():
		print("警告: 嵌入模型API密钥未配置")
		return []
	
	# 创建独立的请求对象
	var request = EmbeddingRequest.new(text)
	request_queue.append({"request": request, "api_key": api_key})
	
	# 如果没有正在处理的请求，开始处理队列
	if not is_processing_request:
		_process_request_queue()
	
	# 等待这个特定请求完成
	while not request.completed:
		await get_tree().process_frame
	
	return request.result

var current_request: Dictionary = {}

func _process_request_queue():
	"""处理请求队列"""
	if request_queue.is_empty():
		is_processing_request = false
		return
	
	is_processing_request = true
	current_request = request_queue.pop_front()
	var request = current_request.request
	var api_key = current_request.api_key
	
	var url = embedding_base_url.trim_suffix("/") + "/embeddings"
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	
	var body = JSON.stringify({
		"model": embedding_model,
		"input": request.text
	})
	
	print("调用嵌入API (队列中还有 %d 个请求): %s" % [request_queue.size(), request.text.substr(0, 30)])
	
	http_request.timeout = embedding_timeout
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		print("嵌入请求失败: ", error)
		request.completed = true
		request.result = []
		# 继续处理下一个请求
		_process_request_queue()

func _on_embedding_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	"""嵌入请求完成回调"""
	var request = current_request.request if current_request.has("request") else null
	
	if not request:
		print("警告: 没有当前请求")
		_process_request_queue()
		return
	
	if result != HTTPRequest.RESULT_SUCCESS:
		print("嵌入请求失败: ", result)
		request.completed = true
		request.result = []
		_process_request_queue()
		return
	
	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		print("嵌入API返回错误 %d: %s" % [response_code, error_text])
		
		# 特殊处理401错误
		if response_code == 401:
			print("  ⚠️ 认证失败！请检查：")
			print("    1. API密钥是否正确")
			print("    2. API密钥是否有权限访问嵌入模型")
			print("    3. Base URL是否正确")
		
		request.completed = true
		request.result = []
		_process_request_queue()
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		print("解析嵌入响应失败")
		request.completed = true
		request.result = []
		_process_request_queue()
		return
	
	var response = json.data
	
	# 提取向量
	if response.has("data") and response.data.size() > 0:
		var embedding = response.data[0].get("embedding", [])
		request.completed = true
		request.result = embedding.duplicate()
	else:
		print("嵌入响应格式错误")
		request.completed = true
		request.result = []
	
	# 继续处理下一个请求
	_process_request_queue()

func search(query: String, top_k: int, min_similarity: float, exclude_timestamps: Array = []) -> Array:
	"""被动检索：语义 + 关键词双路召回并合并（均由配置控制）

		query: 查询文本
		top_k: 返回结果数量
		min_similarity: 语义检索的最小相似度阈值
		exclude_timestamps: 要排除的时间戳列表（通过时间戳精确匹配）
	"""
	var semantic_enabled := _should_passive_semantic_search()
	var keyword_enabled := _should_passive_keyword_search()
	if not semantic_enabled and not keyword_enabled:
		return []
	if memory_items.is_empty():
		return []

	# 召回前推理（仅语义检索支持）：生成额外的查询以提高召回率
	var queries_to_search: Array = [query]
	if semantic_enabled and _should_passive_pre_recall_reasoning():
		print("启用召回前推理，生成优化查询")
		var context := _flatten_context_for_optimization()
		var optimized_queries = await retrieval_optimizer.optimize_query(query, context)
		if not optimized_queries.is_empty():
			var reasoning_count = max(1, int(_memory_number("passive_reasoning_count", 3)))
			queries_to_search.append_array(optimized_queries.slice(0, reasoning_count))
			print("召回前推理成功，添加 %d 个优化查询" % min(reasoning_count, optimized_queries.size()))
		else:
			print("召回前推理失败，使用原始查询")

	# 收集候选（按文本去重）
	var candidates: Dictionary = {}

	if semantic_enabled:
		for search_query in queries_to_search:
			var query_vector = await get_embedding(search_query)
			if query_vector.is_empty():
				print("警告: 获取查询向量失败，跳过该查询: %s" % str(search_query).substr(0, 30))
				continue
			_collect_semantic_candidates(candidates, search_query, query_vector, min_similarity, exclude_timestamps)

	if keyword_enabled:
		_collect_keyword_candidates(candidates, query, exclude_timestamps)

	var similarities := _sorted_candidates(candidates)

	# 未启用重排序：直接返回按分数排序的结果
	if not _should_passive_reranking():
		print("配置已禁用重排序，使用原始检索结果")
		return _candidates_to_results(similarities, top_k, false)

	# 重排序：准备更多候选，必要时加入时间感知前缀
	var use_time_aware := _should_passive_time_aware()
	var candidate_multiplier = max(1, int(_memory_number("passive_rerank_multiplier", 5)))
	var num_candidates = min(top_k * candidate_multiplier, similarities.size())
	var initial_results := _candidates_to_results(similarities.slice(0, num_candidates), num_candidates, use_time_aware)

	var reranked_results = await rerank_documents(query, initial_results)
	if not reranked_results.is_empty():
		return reranked_results.slice(0, top_k)
	print("重排序失败，使用原始检索结果")
	return _candidates_to_results(similarities, top_k, use_time_aware)

# ── 候选收集与合并 ──

func _collect_semantic_candidates(candidates: Dictionary, search_query: String, query_vector: Array, min_similarity: float, exclude_timestamps: Array) -> void:
	"""收集语义检索候选（跳过无向量的记忆项）"""
	for i in range(memory_items.size()):
		var item = memory_items[i]
		if exclude_timestamps.has(item.timestamp):
			continue
		if item.vector.is_empty():
			continue
		var semantic_similarity := _calculate_similarity(query_vector, item.vector, item.metadata)
		if semantic_similarity < min_similarity:
			continue
		_merge_candidate(candidates, {
			"item": item,
			"semantic_similarity": semantic_similarity,
			"keyword_score": 0.0,
			"similarity": _score_candidates(semantic_similarity, 0.0),
			"query": search_query
		})

func _collect_keyword_candidates(candidates: Dictionary, query: String, exclude_timestamps: Array) -> void:
	"""收集关键词检索候选：用 jieba 提取查询关键词，与记忆保存的关键词匹配"""
	var query_terms := _extract_keywords(query)
	if query_terms.is_empty():
		return
	for item in memory_items:
		if exclude_timestamps.has(item.timestamp):
			continue
		var item_keywords: Array = item.metadata.get("keywords", [])
		if item_keywords.is_empty():
			continue
		var keyword_score := _keyword_match_score(query_terms, item_keywords)
		if keyword_score <= 0.0:
			continue
		_merge_candidate(candidates, {
			"item": item,
			"semantic_similarity": 0.0,
			"keyword_score": keyword_score,
			"similarity": _score_candidates(0.0, keyword_score),
			"query": query
		})

func _merge_candidate(candidates: Dictionary, candidate: Dictionary) -> void:
	"""按文本合并同一记忆：取各来源最高分，合并命中时间戳"""
	var key: String = candidate.item.text
	if not candidates.has(key):
		candidate["merged_timestamps"] = [candidate.item.timestamp]
		candidates[key] = candidate
		return
	var existing: Dictionary = candidates[key]
	existing.semantic_similarity = maxf(existing.semantic_similarity, candidate.semantic_similarity)
	existing.keyword_score = maxf(existing.keyword_score, candidate.keyword_score)
	existing.similarity = _score_candidates(existing.semantic_similarity, existing.keyword_score)
	if not existing.merged_timestamps.has(candidate.item.timestamp):
		existing.merged_timestamps.append(candidate.item.timestamp)

func _score_candidates(semantic_score: float, keyword_score: float) -> float:
	"""融合语义与关键词分数：两者同时命中会得到小幅加成"""
	if semantic_score > 0.0 and keyword_score > 0.0:
		return semantic_score * 0.6 + keyword_score * 0.4
	return maxf(semantic_score, keyword_score)

func _sorted_candidates(candidates: Dictionary) -> Array:
	var list := []
	for candidate in candidates.values():
		list.append(candidate)
	list.sort_custom(func(a, b): return a.similarity > b.similarity)
	return list

func _candidate_to_result(candidate: Dictionary, time_aware: bool) -> Dictionary:
	var base_text: String = candidate.item.text
	if time_aware and not candidate.merged_timestamps.is_empty():
		base_text = "%s %s" % [TimeUtil.to_merged_relative_time_prefix(candidate.merged_timestamps), base_text]
	return {
		"text": base_text,
		"similarity": candidate.similarity,
		"timestamp": candidate.item.timestamp,
		"merged_timestamps": candidate.merged_timestamps,
		"type": candidate.item.type,
		"metadata": candidate.item.metadata
	}

func _candidates_to_results(list: Array, count: int, time_aware: bool) -> Array:
	var results := []
	for i in range(min(count, list.size())):
		results.append(_candidate_to_result(list[i], time_aware))
	return results

func _ensure_time_prefix(result: Dictionary) -> Dictionary:
	"""确保结果文本带相对时间前缀（幂等，供主动检索返回给模型）"""
	var text := str(result.get("text", ""))
	if text.begins_with("["):
		return result
	var out := result.duplicate()
	out["text"] = _prepend_time_prefix(result, text)
	return out

func _prepend_time_prefix(result: Dictionary, text: String) -> String:
	var merged_ts: Array = result.get("merged_timestamps", [])
	if not merged_ts.is_empty():
		return "%s %s" % [TimeUtil.to_merged_relative_time_prefix(merged_ts), text]
	var ts := str(result.get("timestamp", ""))
	if not ts.is_empty():
		return "%s %s" % [TimeUtil.to_relative_time_prefix(ts), text]
	return text

# ── 关键词提取与匹配 ──

func _extract_keywords(text: String) -> Array:
	"""使用 jieba 提取关键词（带查询缓存与降级）"""
	if text.strip_edges().is_empty() or keyword_extractor == null:
		return []
	if query_keyword_cache.has(text):
		return query_keyword_cache[text].duplicate()
	var terms := []
	for term in keyword_extractor.extract_keywords(text, _keyword_count()):
		var cleaned := str(term).strip_edges().to_lower()
		if not cleaned.is_empty():
			terms.append(cleaned)
	if query_keyword_cache.size() > 64:
		query_keyword_cache.clear()
	query_keyword_cache[text] = terms.duplicate()
	return terms

func _keyword_match_score(query_terms: Array, item_keywords: Array) -> float:
	"""查询关键词与记忆关键词的匹配比例"""
	if query_terms.is_empty() or item_keywords.is_empty():
		return 0.0
	var item_set := {}
	for kw in item_keywords:
		item_set[str(kw).to_lower()] = true
	var unique := {}
	var matched := 0
	for term in query_terms:
		var cleaned := str(term).to_lower()
		if unique.has(cleaned):
			continue
		unique[cleaned] = true
		if item_set.has(cleaned):
			matched += 1
	if unique.is_empty():
		return 0.0
	return float(matched) / float(unique.size())

func format_results(results: Array, include_time_prefix: bool = true) -> String:
	"""把检索结果格式化为文本（用于工具调用返回给模型）"""
	if results.is_empty():
		return "记不太清了..."
	var lines := []
	for i in range(results.size()):
		var text := str(results[i].get("text", ""))
		if include_time_prefix and not text.begins_with("["):
			text = _prepend_time_prefix(results[i], text)
		lines.append("%d. %s" % [i + 1, text])
	return "\n".join(lines)

func _calculate_similarity(vec1: Array, vec2: Array, item_metadata: Dictionary = {}) -> float:
	"""计算余弦相似度"""
	if cosine_calculator != null:
		# 转换为 PackedFloat64Array 后调用 C++ 实现
		var p1 = _to_packed_float64_array(vec1)
		var p2 = _to_packed_float64_array(vec2)
		return float(cosine_calculator.calculate(p1, p2))
	else:
		return _calculate_similarity_gdscript(vec1, vec2, item_metadata)

func _to_packed_float64_array(vec: Array) -> PackedFloat64Array:
	var p = PackedFloat64Array()
	if vec == null:
		return p
	p.resize(vec.size())
	for i in range(vec.size()):
		p.set(i, float(vec[i]))
	return p

func _calculate_similarity_gdscript(vec1: Array, vec2: Array, item_metadata: Dictionary = {}) -> float:
	"""GDScript实现的余弦相似度（降级方案）"""
	if vec1.size() != vec2.size() or vec1.size() == 0:
		return 0.0
	
	var dot = 0.0
	var mag1 = 0.0
	var mag2 = 0.0
	
	for i in range(vec1.size()):
		dot += vec1[i] * vec2[i]
		mag1 += vec1[i] * vec1[i]
		# 如果item_metadata中预存了模长（平方和或模长），优先使用
		# 支持 metadata.mag 为模长（不是平方和）
		if item_metadata.has("mag"):
			mag2 = item_metadata.get("mag", 0.0)
		else:
			mag2 += vec2[i] * vec2[i]
	
	mag1 = sqrt(mag1)
	if mag2 != 0.0 and item_metadata.has("mag"):
		# 已经是模长值
		mag2 = mag2
	else:
		mag2 = sqrt(mag2)
	
	if mag1 == 0.0 or mag2 == 0.0:
		return 0.0
	
	return dot / (mag1 * mag2)

func get_relevant_memory(query: String, top_k: int, _timeout: float, min_similarity: float, exclude_timestamps: Array = []) -> String:
	"""获取相关记忆并格式化为提示词（被动检索，不携带对话细节）

	Args:
		query: 查询文本
		top_k: 返回结果数量
		_timeout: 超时时间（保留参数，暂未使用）
		min_similarity: 最小相似度阈值
		exclude_timestamps: 要排除的时间戳列表
	"""
	var results = await search(query, top_k, min_similarity, exclude_timestamps)

	if results.is_empty():
		return ""

	# 从配置读取提示词模板
	var memory_config = config.get("memory", {})
	var prompts = memory_config.get("prompts", {})
	var prefix = prompts.get("memory_prefix", "这是唤醒的记忆，可以作为参考：\n```\n")
	var suffix = prompts.get("memory_suffix", "\n```\n以上是记忆而不是最近的对话，可以不使用。")

	# 时间前缀：
	# - 启用“时间感知增强”时已在检索/重排序阶段加入，此处不再重复
	# - 否则在此处添加，保证提示词中始终能看到相对时间
	var use_time_aware := _should_passive_reranking() and _should_passive_time_aware()
	var memory_texts = []
	for result in results:
		var memory_text := str(result.text)
		# 被动检索不再展开原始对话细节（细节改由主动"详细检索"提供）
		if use_time_aware or memory_text.begins_with("["):
			memory_texts.append(memory_text)
		else:
			memory_texts.append(_prepend_time_prefix(result, memory_text))

	var memory_prompt = prefix + "\n".join(memory_texts) + suffix

	print("检索到 %d 条相关记忆" % results.size())
	return memory_prompt

# ── 主动检索（工具调用）──

## 语义检索：一个或多个问题
func active_semantic_search(queries: Array, top_k: int = 5) -> Array:
	if not _should_active_semantic_search() or memory_items.is_empty():
		return []
	var query_list: Array = []
	for q in queries:
		var cleaned := str(q).strip_edges()
		if not cleaned.is_empty():
			query_list.append(cleaned)
	if query_list.is_empty():
		return []

	# 主动检索的查询由模型通过工具直接给出，无需召回前推理扩展
	var candidates: Dictionary = {}
	for search_query in query_list:
		var query_vector = await get_embedding(search_query)
		if query_vector.is_empty():
			continue
		_collect_semantic_candidates(candidates, search_query, query_vector, 0.0, [])

	var sorted_list := _sorted_candidates(candidates)
	return await _finalize_active_results(sorted_list, query_list[0], top_k)

## 关键词检索：一个或多个关键词
func active_keyword_search(keywords: Array, top_k: int = 5) -> Array:
	if not _should_active_keyword_search() or memory_items.is_empty():
		return []
	var query_terms: Array = []
	for kw in keywords:
		var cleaned := str(kw).strip_edges().to_lower()
		if not cleaned.is_empty():
			query_terms.append(cleaned)
	if query_terms.is_empty():
		return []

	var candidates: Dictionary = {}
	for item in memory_items:
		var item_keywords: Array = item.metadata.get("keywords", [])
		var keyword_score := _keyword_match_score(query_terms, item_keywords)
		if keyword_score <= 0.0:
			continue
		_merge_candidate(candidates, {
			"item": item,
			"semantic_similarity": 0.0,
			"keyword_score": keyword_score,
			"similarity": keyword_score,
			"query": ""
		})

	var sorted_list := _sorted_candidates(candidates)
	return await _finalize_active_results(sorted_list, " ".join(query_terms), top_k)

## 时间检索：按时间点与方向（更早/更晚/附近）查找
func active_time_search(time_str: String, direction: String = "附近", top_k: int = 5) -> Array:
	if not _should_active_time_search() or memory_items.is_empty():
		return []
	var target := _parse_time_point(time_str)
	if target <= 0.0:
		return []

	var scored := []
	for item in memory_items:
		var ts := TimeUtil.get_unix_time(item.timestamp)
		if ts <= 0.0:
			continue
		var delta := ts - target
		if direction == "更早" and delta > 0.0:
			continue
		if direction == "更晚" and delta < 0.0:
			continue
		# 距离越近分数越高（按小时衰减）
		scored.append({"item": item, "score": 1.0 / (1.0 + abs(delta) / 3600.0)})

	scored.sort_custom(func(a, b): return a.score > b.score)
	var results := []
	for i in range(min(top_k, scored.size())):
		var item: MemoryItem = scored[i].item
		results.append(_ensure_time_prefix({
			"text": item.text,
			"similarity": scored[i].score,
			"timestamp": item.timestamp,
			"merged_timestamps": [item.timestamp],
			"type": item.type,
			"metadata": item.metadata
		}))
	return results

## 详细检索：按记忆开头几个字确认，返回完整对话
func active_detail_search(prefix: String) -> String:
	if not _should_active_detail_search():
		return "详细检索未启用。"
	var needle := prefix.strip_edges()
	if needle.is_empty():
		return "请提供记忆开头的文字。"

	var prefix_matches: Array = []
	var contains_matches: Array = []
	for item in memory_items:
		if item.text.begins_with(needle):
			prefix_matches.append(item)
		elif item.text.find(needle) >= 0:
			contains_matches.append(item)

	var candidates := prefix_matches if not prefix_matches.is_empty() else contains_matches
	if candidates.is_empty():
		return "没有找到与“%s”匹配的记忆。" % needle

	# 文本最短者通常是最精确的匹配
	candidates.sort_custom(func(a, b): return a.text.length() < b.text.length())
	var item: MemoryItem = candidates[0]
	var header := "%s %s" % [TimeUtil.to_relative_time_prefix(item.timestamp), item.text]
	var detail := str(item.metadata.get("raw_conversation", ""))
	if detail.strip_edges().is_empty():
		return header + "\n（这条记忆没有保存更详细的对话内容）"
	return header + "\n\n完整对话：\n" + detail

func _finalize_active_results(sorted_list: Array, rerank_query: String, top_k: int) -> Array:
	"""主动检索结果收尾：可选重排序，并统一附带相对时间前缀"""
	if sorted_list.is_empty():
		return []
	var results: Array
	if _should_active_reranking():
		var time_aware := _should_active_time_aware()
		var multiplier = max(1, int(_memory_number("active_rerank_multiplier", 5)))
		var num_candidates = min(top_k * multiplier, sorted_list.size())
		var initial := _candidates_to_results(sorted_list.slice(0, num_candidates), num_candidates, time_aware)
		var reranked = await rerank_documents(rerank_query, initial)
		if not reranked.is_empty():
			results = reranked.slice(0, top_k)
		else:
			results = _candidates_to_results(sorted_list, top_k, time_aware)
	else:
		results = _candidates_to_results(sorted_list, top_k, true)

	var out := []
	for result in results:
		out.append(_ensure_time_prefix(result))
	return out

func _parse_time_point(time_str: String) -> float:
	"""解析 "YYYY-MM-DD HH:MM"（或 "YYYY-MM-DD"）为本地时间 UNIX 时间戳"""
	var s := time_str.strip_edges()
	if s.is_empty():
		return 0.0
	# 允许空格或 T 分隔
	s = s.replace(" ", "T")
	var parts := s.split("T")
	if parts.size() == 1:
		s += "T00:00:00"
	elif parts[1].split(":").size() == 2:
		s += ":00"
	return TimeUtil.iso_to_unix(s)

func save_to_file(file_path: String = "") -> void:
	"""保存记忆数据到文件（文本和向量分开存储）"""
	if file_path.is_empty():
		file_path = "user://memory_%s.json" % db_name
	
	# 分离文本和向量
	var texts = []
	var vectors = []
	var metadata_list = []
	
	for item in memory_items:
		texts.append({
			"text": item.text,
			"timestamp": item.timestamp,
			"type": item.type,
			"metadata": item.metadata
		})
		vectors.append(item.vector.duplicate())  # 强制复制
		metadata_list.append({
			"timestamp": item.timestamp,
			"type": item.type
		})
	
	var data = {
		"db_name": db_name,
		"vector_dim": vector_dim,
		"last_updated": MemoryItem._get_local_datetime_string(),
		"count": memory_items.size(),
		"texts": texts,
		"vectors": vectors
	}
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		print("保存记忆失败: ", FileAccess.get_open_error())
		return
	
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	
	print("记忆已保存: %s (%d 条)" % [file_path, memory_items.size()])

func load_from_file(file_path: String = "") -> void:
	"""从文件加载记忆数据（支持新旧格式）"""
	if file_path.is_empty():
		file_path = "user://memory_%s.json" % db_name
	
	if not FileAccess.file_exists(file_path):
		print("记忆文件不存在，将创建新数据库")
		return
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		print("加载记忆失败: ", FileAccess.get_open_error())
		return
	
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	
	if parse_result != OK:
		print("解析记忆文件失败")
		return
	
	var data = json.data
	
	db_name = data.get("db_name", db_name)
	vector_dim = data.get("vector_dim", vector_dim)
	
	memory_items.clear()
	
	# 检测格式：新格式有 texts 和 vectors 字段
	if data.has("texts") and data.has("vectors"):
		# 新格式：文本和向量分开
		var texts = data.get("texts", [])
		var vectors = data.get("vectors", [])
		
		for i in range(min(texts.size(), vectors.size())):
			var text_data = texts[i]
			var item = MemoryItem.new()
			var raw_text: String = text_data.get("text", "")
			# 兼容旧版：历史数据可能在文本开头带有类似 "[02-02 20:26] " 的绝对时间前缀
			if raw_text.begins_with("["):
				var close_idx := raw_text.find("] ")
				if close_idx != -1:
					raw_text = raw_text.substr(close_idx + 2)
			item.text = raw_text
			item.vector = vectors[i].duplicate()  # 强制复制
			item.timestamp = text_data.get("timestamp", "")
			item.type = text_data.get("type", "conversation")
			item.metadata = text_data.get("metadata", {})
			memory_items.append(item)
		
		print("记忆已加载（新格式）: %d 条" % memory_items.size())
	else:
		# 旧格式：兼容处理
		for item_data in data.get("items", []):
			memory_items.append(MemoryItem.from_dict(item_data))
		
		print("记忆已加载（旧格式）: %d 条" % memory_items.size())

func clear() -> void:
	"""清空所有记忆"""
	memory_items.clear()
	print("记忆已清空")

func rerank_documents(query: String, documents: Array) -> Array:
	"""对文档进行重排序

	Args:
		query: 查询文本
		documents: 文档列表，每个文档包含text, similarity, timestamp, type等字段

	Returns:
		重排序后的文档列表
	"""
	if rerank_base_url.is_empty() or rerank_model.is_empty():
		print("重排序模型未配置，使用原始检索结果")
		return documents

	if documents.is_empty():
		return documents

	# 从配置读取API密钥
	var api_key = ""
	if config.has("rerank_model") and config.rerank_model.has("api_key"):
		api_key = config.rerank_model.get("api_key", "")

	if api_key.is_empty():
		print("重排序模型API密钥未配置，使用原始检索结果")
		return documents

	# 准备重排序请求数据
	var document_texts = []
	for doc in documents:
		document_texts.append(doc.text)

	var url = rerank_base_url.trim_suffix("/") + config.rerank_model.get("url_suffix","")
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]

	var body = {
		"model": rerank_model,
		"query": query,
		"documents": document_texts,
		"instruction": rerank_instruction,
		"top_n": min(rerank_top_n, documents.size()),
		"return_documents": true
	}

	var json_body = JSON.stringify(body)

	print("调用重排序API，文档数量: %d" % documents.size())

	# 创建新的HTTP请求节点用于重排序
	var rerank_request = HTTPRequest.new()
	add_child(rerank_request)
	rerank_request.timeout = rerank_timeout

	# 发送请求
	var error = rerank_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		print("重排序请求失败: ", error)
		rerank_request.queue_free()
		return documents

	# 等待响应
	var response_data = await _wait_for_rerank_response(rerank_request)

	rerank_request.queue_free()

	if response_data.is_empty():
		print("重排序响应为空，使用原始检索结果")
		return documents

	# 解析重排序结果
	var reranked_results = []
	var results = response_data.get("results", [])

	for result in results:
		var document = result.get("document", {})
		var text = document.get("text", "")
		var relevance_score = result.get("relevance_score", 0.0)
		var index = result.get("index", 0)

		# 从原始文档中获取额外信息
		if index < documents.size():
			var original_doc = documents[index]
			reranked_results.append({
				"text": text,
				"similarity": relevance_score,
				"timestamp": original_doc.get("timestamp", ""),
				"merged_timestamps": original_doc.get("merged_timestamps", []),
				"type": original_doc.get("type", ""),
				"metadata": original_doc.get("metadata", {})
			})

	print("重排序完成，返回 %d 个结果" % reranked_results.size())
	return reranked_results if not reranked_results.is_empty() else documents

func _flatten_context_for_optimization(max_items: int = 10) -> String:
	"""为检索优化创建扁平化的上下文
	Args:
		max_items: 最大记忆项数量
	Returns:
		扁平化的上下文字符串
	"""
	if memory_items.is_empty():
		return "暂无记忆内容"

	# 获取最近的记忆项（按时间戳倒序）
	var recent_items = memory_items.duplicate()
	recent_items.sort_custom(func(a, b): return a.timestamp > b.timestamp)

	var context_parts = []
	var count = 0
	for item in recent_items:
		if count >= max_items:
			break
		context_parts.append(item.text)
		count += 1

	return "\n".join(context_parts)

func _wait_for_rerank_response(rerank_request: HTTPRequest) -> Dictionary:
	"""等待重排序响应完成"""
	var result_data = []
	var response_code = 0
	var _headers = []
	var body = []

	# 使用信号的await语法，避免竞态条件
	var signal_result = await rerank_request.request_completed
	result_data = signal_result

	var http_result = result_data[0]
	response_code = result_data[1]
	_headers = result_data[2]
	body = result_data[3]

	if http_result != HTTPRequest.RESULT_SUCCESS:
		print("重排序请求失败: ", http_result)
		return {}

	if response_code != 200:
		var error_text = body.get_string_from_utf8()
		print("重排序API返回错误 %d: %s" % [response_code, error_text])
		return {}

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())

	if parse_result != OK:
		print("解析重排序响应失败")
		return {}

	return json.data
