extends Node
## 检索优化器 - 召回前推理
## 根据用户问题和上下文生成优化后的检索查询

# 请求队列系统
class RetrievalOptimizationRequest:
	var query: String = ""
	var context: String = ""
	var completed: bool = false
	var result: Array = []

	func _init(p_query: String, p_context: String):
		query = p_query
		context = p_context

var request_queue: Array = []
var is_processing_request: bool = false
var current_request: Dictionary = {}

# easy_ai 组件引用
var easy_ai: Node = EasyAi

# 配置变量
var task_id: String = "summary_model"  # 默认使用 summary_model 任务
var timeout: float = 30.0
var max_tokens: int = 512
var temperature: float = 0.3
var top_p: float = 0.7
var system_prompt: String = ""

func _ready():
	pass

func initialize(p_task_id: String, p_timeout: float, p_max_tokens: int, p_temperature: float, p_top_p: float, p_system_prompt: String):
	"""初始化检索优化器"""
	task_id = p_task_id
	timeout = p_timeout
	max_tokens = p_max_tokens
	temperature = p_temperature
	top_p = p_top_p
	system_prompt = p_system_prompt

func optimize_query(query: String, context: String) -> Array:
	"""优化检索查询
	Args:
		query: 用户原始查询
		context: 扁平化上下文信息
	Returns:
		优化后的查询列表，失败时返回空数组
	"""
	if not easy_ai:
		print("检索优化器: easy_ai 未配置")
		return []

	if system_prompt.is_empty():
		print("检索优化系统提示词未配置")
		return []

	# 创建请求对象
	var request = RetrievalOptimizationRequest.new(query, context)
	request_queue.append({"request": request})

	# 如果没有正在处理的请求，开始处理队列
	if not is_processing_request:
		_process_request_queue()

	# 等待这个特定请求完成
	while not request.completed:
		await get_tree().process_frame

	return request.result

func _process_request_queue():
	"""处理请求队列"""
	if request_queue.is_empty():
		is_processing_request = false
		current_request = {}
		return

	is_processing_request = true
	current_request = request_queue.pop_front()
	var request = current_request.request

	# 构建用户提示词
	var user_prompt = "用户问题: " + request.query + "\n\n上下文信息:\n" + request.context

	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt}
	]

	print("调用检索优化API: %s" % request.query.substr(0, 30))

	# 使用 easy_ai 发送请求
	var result = await easy_ai.request(
		task_id,
		messages,
		false,  # 不使用 JSON 模式
		{
			"max_tokens": max_tokens,
			"temperature": temperature,
			"top_p": top_p
		},
		timeout
	)

	if not result.success:
		print("检索优化请求失败: ", result.error)
		request.completed = true
		request.result = []
		# 继续处理下一个请求
		_process_request_queue()
		return

	# 提取优化后的查询
	var optimized_queries = []
	var content = result.content

	# 解析换行分隔的查询文本
	var lines = content.split("\n", false)
	for line in lines:
		var trimmed_line = line.strip_edges()
		# 跳过空行
		if not trimmed_line.is_empty():
			optimized_queries.append(trimmed_line)

	print("检索优化成功，生成 %d 个查询" % optimized_queries.size())
	if optimized_queries.size() == 0:
		print("警告: 解析响应后没有有效的查询")

	request.completed = true
	request.result = optimized_queries

	# 继续处理下一个请求
	_process_request_queue()
