extends Node

# AI 响应解析器
# 负责解析流式响应和提取字段

signal content_received(content: String)
signal mood_extracted(mood_name_en: String)
signal parse_error(error_message: String)
signal warning(message: String)  # 新增：警告信号

var sse_buffer: String = ""
var json_response_buffer: String = ""
var msg_buffer: String = ""
var extracted_fields: Dictionary = {}
var pending_goto: int = -1  # 暂存的goto字段（-1表示无暂存）
var fallback_extraction_used: bool = false
var empty_msg_response_detected: bool = false
var last_error_message: String = ""

func reset():
	"""重置所有缓冲区"""
	sse_buffer = ""
	json_response_buffer = ""
	msg_buffer = ""
	extracted_fields = {}
	pending_goto = -1
	fallback_extraction_used = false
	empty_msg_response_detected = false
	last_error_message = ""

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
		var anonymous_content = _extract_likely_msg_from_anonymous_fields(buffer_to_parse)
		if anonymous_content.is_empty():
			return
		_emit_msg_delta_if_changed(anonymous_content)
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

	_emit_msg_delta_if_changed(extracted_content)

func _emit_msg_delta_if_changed(extracted_content: String):
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
	"""从缓冲中提取英文mood名称。"""
	if extracted_fields.has("mood"):
		return
	var mood_start = buffer.find('"mood"')
	if mood_start == -1:
		return
	var colon_pos = buffer.find(':', mood_start)
	if colon_pos == -1:
		return
	var value_start = _find_next_non_whitespace(buffer, colon_pos + 1)
	if value_start == -1:
		return
	var value_str = ""
	if buffer[value_start] == '"':
		var parsed = _extract_json_string_at(buffer, value_start)
		value_str = str(parsed.get("value", ""))
	else:
		for i in range(value_start, buffer.length()):
			if buffer[i] in [',', '\n', ' ', '\t', '}', '\r']:
				break
			value_str += buffer[i]
	var mood_name = _normalize_mood_name(value_str)
	if mood_name.is_empty():
		return
	extracted_fields["mood"] = mood_name
	print("实时提取到mood字段: ", mood_name)
	mood_extracted.emit(mood_name)

func finalize_response() -> Dictionary:
	"""完成流式响应处理，返回提取的所有字段
	返回: 成功时返回字段字典，失败时返回空字典（可以通过检查empty判断）
	"""
	print("流式响应完成，完整内容: ", json_response_buffer)
	last_error_message = ""
	fallback_extraction_used = false
	empty_msg_response_detected = false

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
		if typeof(full_response) != TYPE_DICTIONARY:
			last_error_message = "JSON解析错误：根节点不是对象"
			parse_error.emit(last_error_message)
			json_response_buffer = ""
			msg_buffer = ""
			return {}

		var recovered_any = _extract_fields_from_json(full_response)
		# 正常JSON也可能是重复空key/空key导致的信息丢失，例如 {"": 8, "": ""}。
		# 当没有拿到有效msg时，用原始文本再跑一遍容错扫描，避免被Godot解析后的Dictionary吞掉前面的重复key。
		if msg_buffer.is_empty():
			recovered_any = _attempt_fallback_extraction(clean_json) or recovered_any

		if recovered_any or empty_msg_response_detected:
			_fill_default_fields_for_missing()
			print("提取的字段: ", extracted_fields)
			return extracted_fields.duplicate()

		last_error_message = "JSON解析错误，无法从响应中提取任何有效字段"
		parse_error.emit(last_error_message)
		json_response_buffer = ""
		msg_buffer = ""
		return {}
	else:
		# JSON解析失败，尝试容错提取。注意：只有真实提取到字段/消息才算成功，
		# 不能先写入默认值，否则完全损坏的响应也会被当成成功。
		fallback_extraction_used = true
		warning.emit("JSON解析失败: " + json.get_error_message())
		print("尝试容错提取...")
		var recovered_any = _attempt_fallback_extraction(clean_json)
		
		if recovered_any or empty_msg_response_detected:
			_fill_default_fields_for_missing()
			print("容错提取的字段: ", extracted_fields)
			return extracted_fields.duplicate()
		else:
			# 完全失败，发送错误信号
			last_error_message = "JSON解析错误，无法从响应中提取任何有效字段"
			parse_error.emit(last_error_message)
			
			# 清空缓冲区，避免污染上下文
			json_response_buffer = ""
			msg_buffer = ""
			
			return {}

func _extract_fields_from_json(data) -> bool:
	"""从正常JSON中提取真实字段。返回是否拿到了非默认填充的信息。"""
	var recovered_any = false

	if data.has("msg"):
		var msg_text = "" if data.msg == null else str(data.msg)
		_accept_final_msg(msg_text)
		if not msg_text.is_empty():
			recovered_any = true
	elif data.has("") and typeof(data[""]) == TYPE_STRING:
		# 兼容字段名被吞成空字符串但JSON仍可解析的情况：{"": "回复文本", ...}
		fallback_extraction_used = true
		var anonymous_msg = _clean_damaged_msg_candidate(str(data[""]))
		if not anonymous_msg.is_empty() and _score_msg_candidate(anonymous_msg) >= 0:
			_accept_final_msg(anonymous_msg)
			recovered_any = true
		else:
			empty_msg_response_detected = true
			if not anonymous_msg.is_empty():
				warning.emit("空key消息候选信息量过低，按空消息处理: " + anonymous_msg)

	if data.has("mood") and data.mood != null:
		var mood_name = _normalize_mood_name(str(data.mood))
		if not mood_name.is_empty():
			extracted_fields["mood"] = mood_name
		else:
			extracted_fields["mood"] = "calm"  # 默认平静
			warning.emit("mood字段值无效: " + str(data.mood))
		recovered_any = true
	
	if data.has("will"):
		var will_val = _extract_and_validate_numeric_field(data.will, -30, 30, "will")
		extracted_fields["will"] = 0 if will_val == null else will_val
		recovered_any = true
	
	if data.has("like"):
		var like_val = _extract_and_validate_numeric_field(data.like, -10, 10, "like")
		extracted_fields["like"] = 0 if like_val == null else like_val
		recovered_any = true
	
	if data.has("goto"):
		if data.goto != null:
			var goto_val = int(data.goto) if typeof(data.goto) != TYPE_STRING or data.goto.is_valid_int() else -1
			if goto_val >= -1 and goto_val <= 7:
				extracted_fields["goto"] = goto_val
			else:
				extracted_fields["goto"] = -1  # 默认不移动
				warning.emit("goto字段值无效: " + str(data.goto))
		else:
			extracted_fields["goto"] = -1
		recovered_any = true
	
	if data.has("item") and data.item != null:
		extracted_fields["item"] = int(data.item) if typeof(data.item) != TYPE_STRING or data.item.is_valid_int() else -1
		recovered_any = true

	return recovered_any

func _attempt_fallback_extraction(clean_json: String) -> bool:
	"""当JSON解析失败时的容错提取。返回是否提取到真实有效信息。"""
	var recovered_any = _has_recovered_real_field()
	
	# 尝试提取msg（如果还没有）
	if msg_buffer.is_empty():
		var recovered_msg = _extract_msg_fallback(clean_json)
		if not recovered_msg.is_empty():
			msg_buffer = recovered_msg
			content_received.emit(msg_buffer)
			recovered_any = true
	
	# 尝试提取mood（如果还没有）
	if not extracted_fields.has("mood") or extracted_fields["mood"] == null:
		var mood_name = _extract_mood_fallback(clean_json)
		if not mood_name.is_empty():
			extracted_fields["mood"] = mood_name
			mood_extracted.emit(mood_name)
			recovered_any = true
	
	# 尝试提取will
	var will_val = _extract_numeric_field_fallback(clean_json, "will")
	if will_val != null:
		extracted_fields["will"] = clamp(will_val, -30, 30)
		recovered_any = true
	
	# 尝试提取like
	var like_val = _extract_numeric_field_fallback(clean_json, "like")
	if like_val != null:
		extracted_fields["like"] = clamp(like_val, -10, 10)
		recovered_any = true
	
	# 尝试提取goto
	var goto_val = _extract_numeric_field_fallback(clean_json, "goto")
	if goto_val != null:
		extracted_fields["goto"] = clamp(goto_val, -1, 7)
		recovered_any = true

	# 尝试提取item；未提取到时不填默认值，让物品逻辑按“未返回item”处理。
	var item_val = _extract_numeric_field_fallback(clean_json, "item")
	if item_val != null:
		extracted_fields["item"] = item_val
		recovered_any = true

	return recovered_any

func _has_recovered_real_field() -> bool:
	"""检查是否已通过流式过程拿到真实字段（不含稍后补的默认值）。"""
	if not msg_buffer.is_empty():
		return true
	for key in extracted_fields.keys():
		if extracted_fields[key] != null:
			return true
	return false

func _fill_default_fields_for_missing():
	"""容错提取成功后，为缺失的非文本字段补安全默认值。"""
	if not extracted_fields.has("mood") or extracted_fields["mood"] == null:
		extracted_fields["mood"] = "calm"  # 默认平静
	if not extracted_fields.has("will") or extracted_fields["will"] == null:
		extracted_fields["will"] = 0
	if not extracted_fields.has("like") or extracted_fields["like"] == null:
		extracted_fields["like"] = 0
	if not extracted_fields.has("goto") or extracted_fields["goto"] == null:
		extracted_fields["goto"] = -1

func _accept_final_msg(msg_text: String):
	"""在最终JSON可解析时兜底同步msg，避免流式提取漏掉最后内容。"""
	if msg_text.is_empty():
		warning.emit("msg字段为空字符串")
		empty_msg_response_detected = true
		msg_buffer = ""
		return

	if msg_buffer.is_empty():
		msg_buffer = msg_text
		content_received.emit(msg_text)
	elif msg_text != msg_buffer:
		if msg_text.begins_with(msg_buffer) and msg_text.length() > msg_buffer.length():
			var delta = msg_text.substr(msg_buffer.length())
			msg_buffer = msg_text
			if not delta.is_empty():
				content_received.emit(delta)
		else:
			# 已经显示过的内容无法撤回，只更新内部缓冲用于历史修复。
			msg_buffer = msg_text

func _extract_msg_fallback(text: String) -> String:
	"""容错提取msg字段"""
	# 标准形式："msg": "..."
	var named_msg = _extract_string_value_after_field(text, "msg")
	if not named_msg.is_empty():
		var cleaned_named_msg = _clean_damaged_msg_candidate(named_msg)
		if _score_msg_candidate(cleaned_named_msg) >= 0:
			return cleaned_named_msg
		warning.emit("容错msg候选信息量过低，放弃提取: " + cleaned_named_msg)
		empty_msg_response_detected = true
		return ""
	elif text.find('"msg"') != -1:
		empty_msg_response_detected = true
		warning.emit("容错msg字段为空或不是字符串，按空消息处理")
		return ""
	
	# 常见损坏形式：字段名被模型吞掉，变成 {": 7, ": "回复文本", "will": ...}
	# 这时第二个匿名字段的字符串值通常就是 msg。
	return _extract_likely_msg_from_anonymous_fields(text)

func _extract_string_value_after_field(text: String, field_name: String) -> String:
	var field_start = text.find('"' + field_name + '"')
	if field_start == -1:
		return ""
	
	var colon_pos = text.find(':', field_start)
	if colon_pos == -1:
		return ""
	
	var quote_start = -1
	for i in range(colon_pos + 1, text.length()):
		if text[i] == '"':
			quote_start = i
			break
		elif text[i] not in [' ', '\t', '\n', '\r']:
			break
	
	if quote_start == -1:
		return ""
	
	var parsed = _extract_json_string_at(text, quote_start)
	return str(parsed.get("value", ""))

func _extract_likely_msg_from_anonymous_fields(text: String) -> String:
	"""从字段名缺失/字段和值错位的损坏响应中提取最像msg的正文。"""
	var best_candidate = ""
	var best_score = -1
	var i = 0
	while i < text.length():
		if text[i] == '"' and _is_anonymous_key_quote(text, i):
			var colon_pos = _find_anonymous_key_colon(text, i)
			var value_start = _find_next_non_whitespace(text, colon_pos + 1) if colon_pos != -1 else -1
			if value_start != -1 and text[value_start] == '"':
				var parsed = _extract_json_string_at(text, value_start)
				var value = _clean_damaged_msg_candidate(str(parsed.get("value", "")))
				var score = _score_msg_candidate(value)
				if score > best_score:
					best_score = score
					best_candidate = value
				var end_pos = int(parsed.get("end_pos", value_start))
				if end_pos > i:
					i = end_pos
		i += 1

	# 更严重的错位形式里，正文可能被放到了“key”位置，例如：
	# {": 8{,": "msg{", "真正正文{,": "will{", ...}
	# 所以还要扫描所有被引号包住的片段，过滤schema标记后选最高分候选。
	var quoted_candidate = _extract_best_msg_from_all_quoted_strings(text)
	var quoted_score = _score_msg_candidate(quoted_candidate)
	if quoted_score > best_score:
		best_candidate = quoted_candidate

	return best_candidate

func _looks_like_msg_candidate(value: String) -> bool:
	return _score_msg_candidate(value) >= 0

func _extract_best_msg_from_all_quoted_strings(text: String) -> String:
	var best_candidate = ""
	var best_score = -1
	var i = 0
	while i < text.length():
		if text[i] == '"':
			var parsed = _extract_json_string_at(text, i)
			var value = _clean_damaged_msg_candidate(str(parsed.get("value", "")))
			var score = _score_msg_candidate(value)
			if score > best_score:
				best_score = score
				best_candidate = value
			var end_pos = int(parsed.get("end_pos", i))
			if end_pos > i:
				i = end_pos
		i += 1
	return best_candidate

func _score_msg_candidate(value: String) -> int:
	var stripped = _clean_damaged_msg_candidate(value)
	if stripped.is_empty():
		return -1
	if _is_low_information_msg_candidate(stripped):
		return -1

	var normalized = _normalize_schema_token(stripped)
	if normalized.is_empty():
		return -1
	if normalized in ["msg", "mood", "will", "like", "goto", "item"]:
		return -1
	if normalized.is_valid_int():
		return -1

	var score = stripped.length()
	if _contains_message_punctuation(stripped):
		score += 30
	return score

func _is_low_information_msg_candidate(value: String) -> bool:
	var stripped = _clean_damaged_msg_candidate(value)
	if stripped.is_empty():
		return true

	var english_word_count = 0
	var chinese_char_count = 0
	var has_meaningful_letter = false
	var in_english_word = false

	for i in range(stripped.length()):
		var code = stripped.unicode_at(i)
		if _is_ascii_letter_code(code):
			has_meaningful_letter = true
			if not in_english_word:
				english_word_count += 1
			in_english_word = true
		elif _is_cjk_code(code):
			has_meaningful_letter = true
			chinese_char_count += 1
			in_english_word = false
		else:
			in_english_word = false

	# 只有符号/数字/空白：没有英文字母或中文字符。
	if not has_meaningful_letter:
		return true

	# 只有 <=1 个英文单词。
	if english_word_count > 0 and chinese_char_count == 0 and english_word_count <= 1:
		return true

	# 只有 <=2 个中文字符。
	if chinese_char_count > 0 and english_word_count == 0 and chinese_char_count <= 2:
		return true

	# 中英混合但两边都只有极少内容，也视为低信息候选。
	if english_word_count > 0 and chinese_char_count > 0 and english_word_count <= 1 and chinese_char_count <= 2:
		return true

	return false

func _is_ascii_letter_code(code: int) -> bool:
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122)

func _is_cjk_code(code: int) -> bool:
	return (code >= 0x3400 and code <= 0x4DBF) or (code >= 0x4E00 and code <= 0x9FFF) or (code >= 0xF900 and code <= 0xFAFF)

func _clean_damaged_msg_candidate(value: String) -> String:
	var result = value.strip_edges()
	while result.length() > 0 and result[0] in [',', ':', '"', '{', '}', ' ']:
		result = result.substr(1).strip_edges()
	while result.length() > 0 and result[result.length() - 1] in ['{', '}', ',', ':', '"', ' ']:
		result = result.substr(0, result.length() - 1).strip_edges()
	return result

func _normalize_schema_token(value: String) -> String:
	var normalized = ""
	for i in range(value.length()):
		var ch = value[i]
		if ch in ['{', '}', ',', ':', '"', ' ', '\t', '\n', '\r']:
			continue
		normalized += ch
	return normalized.strip_edges()

func _contains_message_punctuation(value: String) -> bool:
	for marker in ["。", "，", "！", "？", "…", "（", "）", "「", "」", "“", "”", "、", "；", "："]:
		if value.contains(marker):
			return true
	return false

func _extract_json_string_at(text: String, quote_start: int) -> Dictionary:
	"""从指定双引号处读取JSON字符串，返回 {value, end_pos}。end_pos为结束引号位置。"""
	var current_pos = quote_start + 1
	var extracted_content = ""
	var escape_next = false
	
	while current_pos < text.length():
		var ch = text[current_pos]
		
		if escape_next:
			if ch == 'n':
				extracted_content += '\n'
			elif ch == 't':
				extracted_content += '\t'
			elif ch == 'r':
				extracted_content += '\r'
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
			return {"value": extracted_content, "end_pos": current_pos}
		else:
			extracted_content += ch
			current_pos += 1
	
	# 未闭合字符串也尽量返回已读到的内容，适配截断/缺右引号响应。
	return {"value": extracted_content, "end_pos": current_pos}

func _is_anonymous_key_quote(text: String, quote_pos: int) -> bool:
	"""判断这个双引号是否像 {\": value、{\"\": value 或 , \"\": value 这种缺字段名/空字段名key起点。"""
	return _find_anonymous_key_colon(text, quote_pos) != -1

func _find_anonymous_key_colon(text: String, quote_pos: int) -> int:
	var prev_pos = _find_previous_non_whitespace(text, quote_pos - 1)
	if prev_pos == -1:
		return -1
	if text[prev_pos] not in ['{', ',']:
		return -1
	
	var next_pos = _find_next_non_whitespace(text, quote_pos + 1)
	if next_pos == -1:
		return -1
	
	# 损坏形式：": value，只有一个起始引号，字段名和结束引号都丢了。
	if text[next_pos] == ':':
		return next_pos
	
	# 可解析但无字段名形式："": value。
	if text[next_pos] == '"':
		var colon_pos = _find_next_non_whitespace(text, next_pos + 1)
		if colon_pos != -1 and text[colon_pos] == ':':
			return colon_pos
	
	return -1

func _find_next_non_whitespace(text: String, start_pos: int) -> int:
	for i in range(max(0, start_pos), text.length()):
		if text[i] not in [' ', '\t', '\n', '\r']:
			return i
	return -1

func _find_previous_non_whitespace(text: String, start_pos: int) -> int:
	for i in range(min(start_pos, text.length() - 1), -1, -1):
		if text[i] not in [' ', '\t', '\n', '\r']:
			return i
	return -1

func _normalize_mood_name(value: String) -> String:
	var mood_name = value.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if mood_name.is_empty():
		return ""
	var prompt_builder = get_node_or_null("/root/PromptBuilder")
	if prompt_builder and prompt_builder.has_method("get_mood_name_en_by_display_name"):
		# 中文是提示词要求的格式，英文保留用于兼容旧回复。
		return prompt_builder.get_mood_name_en_by_display_name(mood_name)
	return mood_name if mood_name in ["calm", "happy", "sad", "angry", "surprised", "scared", "disgusted", "doubtful", "shy", "speechless", "worried"] else ""

func _extract_mood_fallback(text: String) -> String:
	"""容错提取英文mood名称。"""
	var mood_start = text.find('"mood"')
	if mood_start == -1:
		return ""
	var colon_pos = text.find(':', mood_start)
	if colon_pos == -1:
		return ""
	var value_start = _find_next_non_whitespace(text, colon_pos + 1)
	if value_start == -1:
		return ""
	if text[value_start] == '"':
		return _normalize_mood_name(str(_extract_json_string_at(text, value_start).get("value", "")))
	var value = ""
	for i in range(value_start, text.length()):
		if text[i] in [',', '\n', ' ', '\t', '}', '\r']:
			break
		value += text[i]
	return _normalize_mood_name(value)

func _extract_mood_from_anonymous_fields(text: String) -> int:
	"""从 {\": 7, \": "msg"} 这种字段名缺失格式中推断mood。"""
	var i = 0
	while i < text.length():
		if text[i] == '"' and _is_anonymous_key_quote(text, i):
			var colon_pos = _find_anonymous_key_colon(text, i)
			var value_start = _find_next_non_whitespace(text, colon_pos + 1) if colon_pos != -1 else -1
			if value_start != -1:
				var value_str = ""
				for j in range(value_start, min(value_start + 10, text.length())):
					var ch = text[j]
					if ch in [',', '\n', ' ', '\t', '}', '\r']:
						break
					if ch.is_valid_int() or ch == '-':
						value_str += ch
					else:
						break
				if not value_str.is_empty() and value_str.is_valid_int():
					var mood_val = int(value_str)
					if mood_val >= 0 and mood_val <= 10:
						return mood_val
		i += 1
	return -1

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

func get_history_response_content() -> String:
	"""获取应写入对话历史的内容。
	容错解析成功时写入修复后的合法JSON；msg缺失时写入占位文本，避免损坏JSON污染上下文。
	"""
	if msg_buffer.strip_edges().is_empty():
		return "{\"mood\": \"calm\", \"msg\": \"……\", \"will\": 0, \"like\": 0, \"goto\": -1}"

	if fallback_extraction_used:
		return _build_repaired_response_json()

	return json_response_buffer

func _build_repaired_response_json() -> String:
	# 不使用 JSON.stringify(Dictionary)，因为Godot会按key排序；这里需要固定输出顺序，
	# 避免修复后的历史与提示词要求的字段顺序不一致。
	var parts = []
	parts.append("\"mood\":\"" + str(extracted_fields.get("mood", "calm")) + "\"")
	parts.append("\"msg\":\"" + _escape_json_string(msg_buffer) + "\"")
	parts.append("\"will\":" + str(_get_int_field_for_repaired_json("will", 0)))
	parts.append("\"like\":" + str(_get_int_field_for_repaired_json("like", 0)))
	parts.append("\"goto\":" + str(_get_int_field_for_repaired_json("goto", -1)))
	if extracted_fields.has("item") and extracted_fields["item"] != null:
		parts.append("\"item\":" + str(int(extracted_fields["item"])))
	return "{" + ", ".join(parts) + "}"

func _get_int_field_for_repaired_json(field_name: String, default_value: int) -> int:
	var value = extracted_fields.get(field_name, null)
	if value == null:
		return default_value
	return int(value)

func _escape_json_string(value: String) -> String:
	var escaped = ""
	for i in range(value.length()):
		var ch = value[i]
		if ch == "\\":
			escaped += "\\\\"
		elif ch == "\"":
			escaped += "\\\""
		elif ch == "\n":
			escaped += "\\n"
		elif ch == "\t":
			escaped += "\\t"
		elif ch == "\r":
			escaped += "\\r"
		else:
			escaped += ch
	return escaped

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
