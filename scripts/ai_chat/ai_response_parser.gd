extends Node

# AI 响应解析器
# 负责解析流式响应和提取字段

signal content_received(content: String)
signal mood_extracted(mood_id: int)
signal parse_error(error_message: String)
signal warning(message: String)  # 新增：警告信号

var sse_buffer: String = ""
var json_response_buffer: String = ""
var msg_buffer: String = ""
var extracted_fields: Dictionary = {}
var pending_goto: int = -1  # 暂存的goto字段（-1表示无暂存）

func reset():
	"""重置所有缓冲区"""
	sse_buffer = ""
	json_response_buffer = ""
	msg_buffer = ""
	extracted_fields = {}
	pending_goto = -1

func process_stream_data(data: String):
	"""处理流式响应数据（SSE格式）"""
	sse_buffer += data

	var lines = sse_buffer.split("\n")

	if not sse_buffer.ends_with("\n"):
		sse_buffer = lines[-1]
		lines = lines.slice(0, -1)
	else:
		sse_buffer = ""

	for line in lines:
		line = line.strip_edges()
		if line.is_empty():
			continue

		if line == "data: [DONE]":
			return true  # 流式结束

		if line.begins_with("data: "):
			var json_str = line.substr(6)
			_parse_stream_chunk(json_str)

	return false  # 继续接收

func _parse_stream_chunk(json_str: String):
	"""解析单个流式数据块"""
	var json = JSON.new()
	if json.parse(json_str) != OK:
		print("流式块解析失败: ", json_str.substr(0, 100))
		return

	var chunk = json.data
	if not chunk.has("choices") or chunk.choices.is_empty():
		return

	var delta = chunk.choices[0].get("delta", {})
	if delta.has("content") and delta.content != null:
		var content = delta.content
		json_response_buffer += content
		# print("接收到内容块: ", content)
		_extract_msg_from_buffer()

func _extract_msg_from_buffer():
	"""从流式缓冲中实时提取msg字段内容"""
	var buffer_to_parse = json_response_buffer

	if buffer_to_parse.contains("```json"):
		var json_start = buffer_to_parse.find("```json") + 7
		buffer_to_parse = buffer_to_parse.substr(json_start)
	elif buffer_to_parse.contains("```"):
		var json_start = buffer_to_parse.find("```") + 3
		buffer_to_parse = buffer_to_parse.substr(json_start)

	if buffer_to_parse.contains("```"):
		var json_end = buffer_to_parse.find("```")
		buffer_to_parse = buffer_to_parse.substr(0, json_end)

	buffer_to_parse = buffer_to_parse.strip_edges()

	_extract_mood_from_buffer(buffer_to_parse)

	var msg_start = buffer_to_parse.find('"msg"')
	if msg_start == -1:
		return

	var colon_pos = buffer_to_parse.find(':', msg_start)
	if colon_pos == -1:
		return

	var quote_start = -1
	for i in range(colon_pos + 1, buffer_to_parse.length()):
		if buffer_to_parse[i] == '"':
			quote_start = i
			break
		elif buffer_to_parse[i] != ' ' and buffer_to_parse[i] != '\t':
			break

	if quote_start == -1:
		return

	var content_start = quote_start + 1
	var current_pos = content_start
	var extracted_content = ""

	while current_pos < buffer_to_parse.length():
		var ch = buffer_to_parse[current_pos]

		if ch == '\\' and current_pos + 1 < buffer_to_parse.length():
			var next_ch = buffer_to_parse[current_pos + 1]
			if next_ch == '"':
				extracted_content += '"'
				current_pos += 2
				continue
			elif next_ch == 'n':
				extracted_content += '\n'
				current_pos += 2
				continue
			elif next_ch == 't':
				extracted_content += '\t'
				current_pos += 2
				continue
			elif next_ch == '\\':
				extracted_content += '\\'
				current_pos += 2
				continue
			else:
				extracted_content += ch
				current_pos += 1
		elif ch == '"':
			break
		else:
			extracted_content += ch
			current_pos += 1

	# 检查是否有新内容（包括从空到空的情况）
	if extracted_content != msg_buffer:
		var new_content = extracted_content.substr(msg_buffer.length())
		var old_length = msg_buffer.length()
		msg_buffer = extracted_content

		# 只有当真的有新内容时才发送信号
		if extracted_content.length() > old_length:
			if not new_content.is_empty():
				# print("发送新内容: ", new_content)
				content_received.emit(new_content)
		# 如果msg字段是空字符串，也记录一下
		elif extracted_content.is_empty() and old_length == 0:
			warning.emit("msg字段为空字符串")

func _extract_mood_from_buffer(buffer: String):
	"""从缓冲中提取mood字段"""
	if extracted_fields.has("mood"):
		return

	var mood_start = buffer.find('"mood"')
	if mood_start == -1:
		return

	var colon_pos = buffer.find(':', mood_start)
	if colon_pos == -1:
		return

	var value_start = -1
	for i in range(colon_pos + 1, buffer.length()):
		var ch = buffer[i]
		if ch == ' ' or ch == '\t' or ch == '\n':
			continue
		value_start = i
		break

	if value_start == -1:
		return

	var value_str = ""
	for i in range(value_start, buffer.length()):
		var ch = buffer[i]
		if ch in [',', '\n', ' ', '\t', '}', '\r']:
			break
		value_str += ch

	if value_str.is_empty():
		return

	if value_str.begins_with("null"):
		print("mood字段为null，跳过")
		extracted_fields["mood"] = null
		return

	if not value_str.is_valid_int():
		return

	var mood_id = int(value_str)
	extracted_fields["mood"] = mood_id

	print("实时提取到mood字段: ", mood_id)
	mood_extracted.emit(mood_id)

func finalize_response() -> Dictionary:
	"""完成流式响应处理，返回提取的所有字段
	返回: 成功时返回字段字典，失败时返回空字典（可以通过检查empty判断）
	"""
	print("流式响应完成，完整内容: ", json_response_buffer)

	var clean_json = json_response_buffer
	if clean_json.contains("```json"):
		var json_start = clean_json.find("```json") + 7
		clean_json = clean_json.substr(json_start)
	elif clean_json.contains("```"):
		var json_start = clean_json.find("```") + 3
		clean_json = clean_json.substr(json_start)

	if clean_json.contains("```"):
		var json_end = clean_json.find("```")
		clean_json = clean_json.substr(0, json_end)

	clean_json = clean_json.strip_edges()

	# 先尝试正常解析JSON
	var json = JSON.new()
	if json.parse(clean_json) == OK:
		var full_response = json.data
		_extract_fields_from_json(full_response)
		print("提取的字段: ", extracted_fields)
		return extracted_fields.duplicate()
	else:
		# JSON解析失败，尝试容错提取
		warning.emit("JSON解析失败: " + json.get_error_message())
		print("尝试容错提取...")
		_attempt_fallback_extraction(clean_json)
		
		# 如果有任何字段被提取出来，也返回成功（部分成功）
		if not extracted_fields.is_empty():
			print("容错提取的字段: ", extracted_fields)
			return extracted_fields.duplicate()
		else:
			# 完全失败，发送错误信号
			var error_msg = "JSON解析错误，无法从响应中提取任何有效字段"
			parse_error.emit(error_msg)
			
			# 清空缓冲区，避免污染上下文
			json_response_buffer = ""
			msg_buffer = ""
			
			return {}

func _extract_fields_from_json(data):
	"""从正常JSON中提取字段"""
	if data.has("mood") and data.mood != null:
		var mood_val = int(data.mood) if typeof(data.mood) != TYPE_STRING or data.mood.is_valid_int() else -1
		if mood_val >= 0 and mood_val <= 10:
			extracted_fields["mood"] = mood_val
		else:
			extracted_fields["mood"] = 0  # 默认平静
			warning.emit("mood字段值无效: " + str(data.mood))
	
	if data.has("will"):
		extracted_fields["will"] = _extract_and_validate_numeric_field(data.will, -30, 30, "will")
	else:
		extracted_fields["will"] = 0  # 默认will增量
	
	if data.has("like"):
		extracted_fields["like"] = _extract_and_validate_numeric_field(data.like, -10, 10, "like")
	else:
		extracted_fields["like"] = 0  # 默认like增量
	
	if data.has("goto") and data.goto != null:
		var goto_val = int(data.goto) if typeof(data.goto) != TYPE_STRING or data.goto.is_valid_int() else -1
		if goto_val >= -1 and goto_val <= 7:
			extracted_fields["goto"] = goto_val
		else:
			extracted_fields["goto"] = -1  # 默认不移动
			warning.emit("goto字段值无效: " + str(data.goto))
	else:
		extracted_fields["goto"] = -1  # 默认不移动
	
	if data.has("item") and data.item != null:
		extracted_fields["item"] = int(data.item) if typeof(data.item) != TYPE_STRING or data.item.is_valid_int() else -1

func _attempt_fallback_extraction(clean_json: String):
	"""当JSON解析失败时的容错提取"""
	# 重置字段（保留已有的mood和msg）
	if not extracted_fields.has("mood"):
		extracted_fields["mood"] = 0  # 默认平静
	if not extracted_fields.has("will"):
		extracted_fields["will"] = 0
	if not extracted_fields.has("like"):
		extracted_fields["like"] = 0
	if not extracted_fields.has("goto"):
		extracted_fields["goto"] = -1
	if not extracted_fields.has("item"):
		extracted_fields["item"] = 1
	
	# 尝试提取msg（如果还没有）
	if msg_buffer.is_empty():
		msg_buffer = _extract_msg_fallback(clean_json)
		if not msg_buffer.is_empty():
			content_received.emit(msg_buffer)
	
	# 尝试提取mood（如果还没有）
	if not extracted_fields.has("mood") or extracted_fields["mood"] == 0:
		var mood_val = _extract_mood_fallback(clean_json)
		if mood_val >= 0 and mood_val <= 10:
			extracted_fields["mood"] = mood_val
			mood_extracted.emit(mood_val)
	
	# 尝试提取will
	var will_val = _extract_numeric_field_fallback(clean_json, "will")
	if will_val != null:
		extracted_fields["will"] = clamp(will_val, -30, 30)
	
	# 尝试提取like
	var like_val = _extract_numeric_field_fallback(clean_json, "like")
	if like_val != null:
		extracted_fields["like"] = clamp(like_val, -10, 10)
	
	# 尝试提取goto
	var goto_val = _extract_numeric_field_fallback(clean_json, "goto")
	if goto_val != null:
		extracted_fields["goto"] = clamp(goto_val, -1, 7)

	# 尝试提取item
	var item_val = _extract_numeric_field_fallback(clean_json, "item")
	if item_val != null:
		extracted_fields["item"] = item_val

func _extract_msg_fallback(text: String) -> String:
	"""容错提取msg字段"""
	var msg_start = text.find('"msg"')
	if msg_start == -1:
		return ""
	
	var colon_pos = text.find(':', msg_start)
	if colon_pos == -1:
		return ""
	
	var quote_start = -1
	for i in range(colon_pos + 1, text.length()):
		if text[i] == '"':
			quote_start = i
			break
		elif text[i] not in [' ', '\t', '\n']:
			break
	
	if quote_start == -1:
		return ""
	
	var content_start = quote_start + 1
	var current_pos = content_start
	var extracted_content = ""
	var escape_next = false
	
	while current_pos < text.length():
		var ch = text[current_pos]
		
		if escape_next:
			if ch == 'n':
				extracted_content += '\n'
			elif ch == 't':
				extracted_content += '\t'
			elif ch == '"':
				extracted_content += '"'
			elif ch == '\\':
				extracted_content += '\\'
			else:
				extracted_content += ch
			escape_next = false
			current_pos += 1
		elif ch == '\\':
			escape_next = true
			current_pos += 1
		elif ch == '"':
			break
		else:
			extracted_content += ch
			current_pos += 1
	
	return extracted_content

func _extract_mood_fallback(text: String) -> int:
	"""容错提取mood字段"""
	var mood_start = text.find('"mood"')
	if mood_start == -1:
		return -1
	
	var colon_pos = text.find(':', mood_start)
	if colon_pos == -1:
		return -1
	
	var value_start = -1
	for i in range(colon_pos + 1, text.length()):
		if text[i] not in [' ', '\t', '\n']:
			value_start = i
			break
	
	if value_start == -1:
		return -1
	
	var value_str = ""
	for i in range(value_start, min(value_start + 10, text.length())):
		var ch = text[i]
		if ch in [',', '\n', ' ', '\t', '}', '\r']:
			break
		if ch.is_valid_int() or ch == '-':
			value_str += ch
		else:
			break
	
	if value_str.is_empty() or not value_str.is_valid_int():
		return -1
	
	return int(value_str)

func _extract_numeric_field_fallback(text: String, field_name: String):
	"""容错提取数值字段"""
	var field_start = text.find('"' + field_name + '"')
	if field_start == -1:
		return null
	
	var colon_pos = text.find(':', field_start)
	if colon_pos == -1:
		return null
	
	var value_start = -1
	for i in range(colon_pos + 1, text.length()):
		if text[i] not in [' ', '\t', '\n']:
			value_start = i
			break
	
	if value_start == -1:
		return null
	
	var value_str = ""
	for i in range(value_start, min(value_start + 10, text.length())):
		var ch = text[i]
		if ch in [',', '\n', ' ', '\t', '}', '\r']:
			break
		if ch.is_valid_int() or ch == '-':
			value_str += ch
		else:
			break
	
	if value_str.is_empty() or not value_str.is_valid_int():
		return null
	
	return int(value_str)

func _extract_and_validate_numeric_field(value, min_val: int, max_val: int, field_name: String):
	"""提取并验证数值字段，支持从复杂文本中提取数字"""
	if value == null:
		return null

	# 如果已经是整数且在范围内，直接返回
	if typeof(value) == TYPE_INT:
		return clamp(value, min_val, max_val)
	elif typeof(value) == TYPE_FLOAT:
		var int_val = int(value)
		return clamp(int_val, min_val, max_val)
	elif typeof(value) == TYPE_STRING:
		var str_val = str(value).strip_edges()

		# 如果是纯数字字符串，直接转换
		if str_val.is_valid_int():
			var int_val = int(str_val)
			return clamp(int_val, min_val, max_val)

		# 从末尾开始查找数字
		var extracted_num = _extract_number_from_string(str_val)
		if extracted_num != null:
			return clamp(extracted_num, min_val, max_val)

		# 如果都失败了，返回边界值（取0或最小值）
		warning.emit("无法从%s字段提取有效数字，使用默认值0" % field_name)
		return 0

	# 其他类型，返回边界值
	warning.emit("%s字段类型异常，使用默认值0" % field_name)
	return 0

func _extract_number_from_string(text: String) -> int:
	# 从字符串中反向查找最后一段整数（支持负数），允许末尾有非数字
	if text.is_empty():
		return 0

	var num_str := ""
	var found_digit := false

	for i in range(text.length() - 1, -1, -1):
		var ch := text[i]

		if ch.is_valid_int():
			num_str = ch + num_str
			found_digit = true
		elif ch == "-" and found_digit:
			# 负号必须紧邻数字，且负号前不能再是数字
			if i > 0 and text[i - 1].is_valid_int():
				break
			num_str = ch + num_str
			break
		elif found_digit:
			# 已经开始收集数字，遇到非数字则结束
			break
		else:
			# 还没找到数字，继续向前跳过
			continue

	if num_str.is_valid_int():
		return int(num_str)

	return 0

func get_full_response() -> String:
	"""获取完整的响应内容"""
	return json_response_buffer

func get_msg_content() -> String:
	"""获取提取的msg内容"""
	return msg_buffer

func has_field(field_name: String) -> bool:
	"""检查是否提取到了指定字段"""
	return extracted_fields.has(field_name)

func get_field(field_name: String, default_value = null):
	"""获取指定字段的值"""
	return extracted_fields.get(field_name, default_value)
