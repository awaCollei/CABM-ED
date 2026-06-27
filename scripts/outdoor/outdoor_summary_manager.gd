extends Node

## 户外场景总结管理器
## 职责：调用总结 API，解析响应，并通过 outdoor_memory_manager 保存记忆。

signal summary_completed(summary: String)
signal summary_failed(error: String)

var config_loader: Node = null
var easy_ai: Node = EasyAi  # easy_ai 组件引用
var memory_manager: Node = null  # outdoor_memory_manager 引用
var logger: Node = null

var _pending_conversation_text: String = ""
var _pending_conversation_data: Array = []
var _pending_timestamp = null
var _is_auto_save: bool = false

## 发起总结 API 请求
## @param conversation_text: 扁平化的对话文本
## @param conversation_data: 原始对话数组（用于提取时间戳）
## @param is_auto_save: 是否为自动保存模式（不清除上下文）
func call_summary_api(conversation_text: String, conversation_data: Array, is_auto_save: bool = false) -> void:
	if not config_loader:
		push_error("OutdoorSummaryManager: config_loader 未设置")
		summary_failed.emit("config_loader 未设置")
		return

	if not easy_ai:
		push_error("OutdoorSummaryManager: easy_ai 未设置")
		summary_failed.emit("easy_ai 未设置")
		return

	# 保存待处理数据
	_pending_conversation_text = conversation_text
	_pending_conversation_data = conversation_data
	_is_auto_save = is_auto_save

	# 提取最后一条消息的时间戳
	_pending_timestamp = null
	for i in range(conversation_data.size() - 1, -1, -1):
		if conversation_data[i].has("timestamp"):
			_pending_timestamp = conversation_data[i].timestamp
			break

	# 构建总结提示词
	var save_mgr = get_node_or_null("/root/SaveManager")
	var helpers = get_node_or_null("/root/EventHelpers")
	var char_name = helpers.get_character_name() if helpers else ""
	var user_name = save_mgr.get_user_name() if save_mgr else ""
	var user_address = save_mgr.get_user_address() if save_mgr else ""

	var conversation_count = conversation_data.size()
	var word_limit = _calculate_word_limit(conversation_count)

	var summary_config = config_loader.get_model_config("summary_model")
	var summary_params = summary_config.get("summary", {})
	var system_prompt = summary_params.get("system_prompt", "请总结以下对话。")
	system_prompt = system_prompt.replace("{character_name}", char_name)
	system_prompt = system_prompt.replace("{user_name}", user_name)
	system_prompt = system_prompt.replace("{user_address}", user_address)
	system_prompt = system_prompt.replace("{word_limit}", str(word_limit))

	var messages = [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": conversation_text}
	]

	# 使用 easy_ai 发送请求
	var result = await easy_ai.request(
		"summary_model",
		messages,
		true,  # 使用 JSON 模式
		{
			"max_tokens": int(summary_params.get("max_tokens", 500)),
			"temperature": float(summary_params.get("temperature", 0.5)),
			"top_p": float(summary_params.get("top_p", 0.95))
		}
	)

	if not result.success:
		push_error("OutdoorSummaryManager: 请求失败 " + result.error)
		summary_failed.emit(result.error)
		return

	# 处理响应
	_handle_summary_response_text(result.content)

func _handle_summary_response_text(content: String) -> void:
	# 清理 markdown 代码块标记
	var cleaned = content.strip_edges()
	if cleaned.begins_with("```json"):
		cleaned = cleaned.substr(7)
	elif cleaned.begins_with("```"):
		cleaned = cleaned.substr(3)
	if cleaned.ends_with("```"):
		cleaned = cleaned.substr(0, cleaned.length() - 3)
	cleaned = cleaned.strip_edges()

	var json = JSON.new()
	if json.parse(cleaned) != OK:
		push_error("OutdoorSummaryManager: 总结 JSON 解析失败: " + cleaned)
		summary_failed.emit("总结 JSON 解析失败")
		return

	var data = json.data
	if not data.has("summary"):
		push_error("OutdoorSummaryManager: 响应缺少 summary 字段")
		summary_failed.emit("响应缺少 summary 字段")
		return

	var summary: String = data.summary

	# 持久化保存记忆（存档 + 日记 + 向量库）
	if memory_manager:
		await memory_manager.save_memory_persistent(summary, _pending_conversation_text, _pending_timestamp)
		# 同时将总结加入当前场景的内存记忆，供后续对话使用
		var ts_str = _get_timestamp_string(_pending_timestamp)
		memory_manager.add_scene_memory(summary, ts_str)
	else:
		push_error("OutdoorSummaryManager: memory_manager 未设置，无法保存记忆")

	summary_completed.emit(summary)
	print("户外场景总结完成：%s..." % summary.substr(0, 50))

func _calculate_word_limit(conversation_count: int) -> int:
	if conversation_count <= 2:
		return 30
	elif conversation_count <= 4:
		return 50
	elif conversation_count <= 6:
		return 70
	elif conversation_count <= 9:
		return 90
	elif conversation_count <= 12:
		return 110
	else:
		return 130

func _get_timestamp_string(unix_ts) -> String:
	var timezone_offset = TimeUtil.get_timezone_offset()
	var unix_time: float
	if unix_ts == null:
		unix_time = Time.get_unix_time_from_system()
	else:
		unix_time = float(unix_ts)
	var local_dict = Time.get_datetime_dict_from_unix_time(int(unix_time + timezone_offset))
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [
		local_dict.year, local_dict.month, local_dict.day,
		local_dict.hour, local_dict.minute, local_dict.second
	]
