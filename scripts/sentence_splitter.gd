# sentence_splitter.gd
# 统一管理文本分句逻辑的模块
# 实现了对普通句子和括号内句子的智能切分
class_name SentenceSplitter

# 定义中文标点符号，用于切分句子
const CHINESE_PUNCTUATION = ["。", "！", "？", "；", "…"]

# 定义中文括号
const LEFT_PAREN_CN = "（"
const RIGHT_PAREN_CN = "）"

# 定义英文括号
const LEFT_PAREN_EN = "("
const RIGHT_PAREN_EN = ")"

# 定义所有左括号和右括号集合，方便查找
const ALL_LEFT_PARENS = [LEFT_PAREN_CN, LEFT_PAREN_EN]
const ALL_RIGHT_PARENS = [RIGHT_PAREN_CN, RIGHT_PAREN_EN]

# 专门用于流式分句的状态对象
class StreamState:
	var buffer: String = ""
	var in_paren: bool = false

	func _init():
		buffer = ""
		in_paren = false

# 内部方法：切分一个文本块（普通文本或括号内的文本）
# chunk_text: 要切分的文本字符串
# is_in_paren: 一个布尔值，指示这个文本块是否来自括号内部
# 返回一个数组，每个元素是一个包含 "text" 和 "no_tts" 标志的字典
static func _split_chunk(chunk_text: String, is_in_paren: bool) -> Array:
	var sentences = []
	var buffer = chunk_text.strip_edges()
	if buffer.is_empty():
		return []

	while not buffer.is_empty():
		var earliest_pos = -1
		
		# 查找最早出现的标点符号的位置
		for punct in CHINESE_PUNCTUATION:
			var pos = buffer.find(punct)
			if pos != -1:
				if earliest_pos == -1 or pos < earliest_pos:
					earliest_pos = pos
		
		var sentence_text = ""
		if earliest_pos == -1:
			# 如果没有找到标点，整个剩余部分就是一句话
			sentence_text = buffer
			buffer = "" # 清空 buffer
		else:
			# 找到了标点，切分句子
			var end_pos = earliest_pos + 1
			# 检查并包含连续的标点符号
			while end_pos < buffer.length() and buffer[end_pos] in CHINESE_PUNCTUATION:
				end_pos += 1
			
			sentence_text = buffer.substr(0, end_pos)
			buffer = buffer.substr(end_pos)

		sentence_text = sentence_text.strip_edges()
		if not sentence_text.is_empty():
			var result_text = sentence_text
			# 如果是在括号内，根据规则用括号包裹句子
			if is_in_paren:
				# 输出时统一使用中文括号
				result_text = LEFT_PAREN_CN + sentence_text + RIGHT_PAREN_CN
			
			sentences.append({"text": result_text, "no_tts": is_in_paren})

	return sentences

# 公开方法：将包含括号的完整文本切分为句子数组
# text: 完整的输入文本
# 返回一个句子数组，格式同上
static func split_text(text: String) -> Array:
	var results = []
	var regex = RegEx.new()
	regex.compile("([（\\(][^）\\)]*?[）\\)])")
	var last_index = 0
	var matches = regex.search_all(text)

	for match in matches:
		# 1. 处理括号块之前的部分
		var pretext = text.substr(last_index, match.get_start() - last_index)
		if not pretext.strip_edges().is_empty():
			results.append_array(_split_chunk(pretext, false))
			
		# 2. 处理括号块本身
		var block_text = match.get_string()
		# 尝试按中文右括号和英文右括号分割，取较长的那一段作为内容
		var content_cn = block_text.substr(1, block_text.rfind(RIGHT_PAREN_CN) - 1)
		var content_en = block_text.substr(1, block_text.rfind(RIGHT_PAREN_EN) - 1)
		var content = content_cn if content_cn.length() > content_en.length() else content_en

		if not content.strip_edges().is_empty():
			# 注意：这里传入 true，因为内容是括号内的
			results.append_array(_split_chunk(content, true)) # 传递 true 表示括号内，_split_chunk 会处理成中文括号
			
		last_index = match.get_end()
		
	# 3. 处理最后一个括号块之后剩余的部分
	var posttext = text.substr(last_index)
	if not posttext.strip_edges().is_empty():
		results.append_array(_split_chunk(posttext, false))
		
	return results

# 公开方法：流式切分文本
# state: StreamState 状态对象，由调用方维护
# new_text: 新到来的文本内容
# is_end: 是否是流的最后一部分
# 返回一个新提取出来的句子数组，格式同上
static func split_stream(state: StreamState, new_text: String, is_end: bool = false) -> Array:
	state.buffer += new_text
	var results = []
	
	while not state.buffer.is_empty():
		var earliest_pos = -1
		var found_punct = ""
		var found_left_paren = false
		var found_right_paren = false
		var matched_left_type = null # 记录匹配到的左括号类型
		var matched_right_type = null # 记录匹配到的右括号类型
		
		# 1. 查找最早出现的特殊字符
		# 检查标点
		for punct in CHINESE_PUNCTUATION:
			var pos = state.buffer.find(punct)
			if pos != -1 and (earliest_pos == -1 or pos < earliest_pos):
				# 特殊处理括号内：如果标点后面紧跟右括号，则不在此处切分
				var end_pos = pos + 1
				while end_pos < state.buffer.length() and state.buffer[end_pos] in CHINESE_PUNCTUATION:
					end_pos += 1
				
				# 检查紧跟的是不是右括号
				var is_followed_by_right_paren = end_pos < state.buffer.length() and state.buffer[end_pos] in ALL_RIGHT_PARENS
				
				if state.in_paren and is_followed_by_right_paren:
					continue # 忽略这个标点，留给右括号处理
				
				earliest_pos = pos
				found_punct = punct
		
		# 根据当前状态，检查括号
		if not state.in_paren:
			# 寻找任何类型的左括号
			for paren_char in ALL_LEFT_PARENS:
				var l_pos = state.buffer.find(paren_char)
				if l_pos != -1 and (earliest_pos == -1 or l_pos < earliest_pos):
					earliest_pos = l_pos
					found_left_paren = true
					matched_left_type = paren_char
					found_punct = ""
		else:
			# 寻找任何类型的右括号
			for paren_char in ALL_RIGHT_PARENS:
				var r_pos = state.buffer.find(paren_char)
				if r_pos != -1 and (earliest_pos == -1 or r_pos < earliest_pos):
					earliest_pos = r_pos
					found_right_paren = true
					matched_right_type = paren_char
					found_punct = ""

		# 2. 如果没找到任何切分点，根据 is_end 决定是否结束
		if earliest_pos == -1:
			if is_end:
				var final_text = state.buffer.strip_edges()
				if not final_text.is_empty():
					var result_text = final_text
					if state.in_paren:
						# 如果在括号内结束，说明缺少右括号，按规则输出
						# 但这里我们无法知道对应的左括号类型，只能用默认中文括号
						result_text = LEFT_PAREN_CN + final_text + RIGHT_PAREN_CN
					results.append({ "text": result_text, "no_tts": state.in_paren})
				state.buffer = ""
			break # 跳出 while，等待更多内容
			
		# 3. 处理切分点
		if found_left_paren:
			# 遇到左括号：切分括号之前的内容，并进入括号模式
			var pretext = state.buffer.substr(0, earliest_pos).strip_edges()
			if not pretext.is_empty():
				results.append({ "text": pretext, "no_tts": false})
			state.in_paren = true
			state.buffer = state.buffer.substr(earliest_pos + 1) # 移除已处理的左括号
			continue # 继续处理 buffer
			
		if found_right_paren:

			var content = state.buffer.substr(0, earliest_pos).strip_edges()
			if not content.is_empty():
				# 输出时统一使用中文括号
				results.append({ "text": LEFT_PAREN_CN + content + RIGHT_PAREN_CN, "no_tts": true})
			state.in_paren = false
			state.buffer = state.buffer.substr(earliest_pos + 1) # 移除已处理的右括号
			continue
			
		if not found_punct.is_empty():
			# 遇到标点：处理连续标点
			var end_pos = earliest_pos + 1
			while end_pos < state.buffer.length() and state.buffer[end_pos] in CHINESE_PUNCTUATION:
				end_pos += 1
				
			var sentence = state.buffer.substr(0, end_pos).strip_edges()
			if not sentence.is_empty():
				var result_text = sentence
				if state.in_paren:
					result_text = LEFT_PAREN_CN + sentence + RIGHT_PAREN_CN
				results.append({ "text": result_text, "no_tts": state.in_paren})
			state.buffer = state.buffer.substr(end_pos) # 移除已处理的部分


	return results
