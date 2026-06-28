class_name CurlParser

# curl 命令解析器
# 支持解析 curl 命令为结构化数据

static func parse(curl_command: String) -> Dictionary:
	"""解析 curl 命令，返回结构化数据
	返回: {url, method, headers, body, form_fields}
	"""
	var result = {
		"url": "",
		"method": "GET",
		"headers": [],
		"body": "",
		"form_fields": [],
		"has_binary_file": false,
	}

	if curl_command.strip_edges().is_empty():
		return result

	var tokens = _tokenize(curl_command)
	var i = 0
	var has_explicit_method = false

	while i < tokens.size():
		var token = tokens[i].strip_edges()
		if token.is_empty():
			i += 1
			continue

		if token == "curl":
			i += 1
			continue

		if token.begins_with("-"):
			# 处理选项
			match token:
				"-X", "--request":
					i += 1
					if i < tokens.size():
						result.method = tokens[i].strip_edges().to_upper()
						has_explicit_method = true
				"-H", "--header":
					i += 1
					if i < tokens.size():
						var header = tokens[i].strip_edges()
						# 去除引号
						header = _strip_quotes(header)
						if not header.is_empty():
							result.headers.append(header)
				"-d", "--data", "--data-raw", "--data-binary", "--data-urlencode":
					i += 1
					if i < tokens.size():
						var data = _strip_quotes(tokens[i].strip_edges())
						if not data.is_empty():
							if result.body.is_empty():
								result.body = data
							else:
								result.body += "&" + data
						if not has_explicit_method:
							result.method = "POST"
				"-F", "--form":
					i += 1
					if i < tokens.size():
						var form_data = _strip_quotes(tokens[i].strip_edges())
						if not form_data.is_empty():
							var parsed_form = _parse_form_field(form_data)
							result.form_fields.append(parsed_form)
							if parsed_form.get("is_file", false):
								result.has_binary_file = true
						if not has_explicit_method:
							result.method = "POST"
				"-u", "--user":
					i += 1
					if i < tokens.size():
						var auth = _strip_quotes(tokens[i].strip_edges())
						var encoded = Marshalls.utf8_to_base64(auth)
						result.headers.append("Authorization: Basic %s" % encoded)
				"--url":
					i += 1
					if i < tokens.size():
						result.url = _strip_quotes(tokens[i].strip_edges())
				_:
					# 跳过其他选项（如 -s, -S, -v, --compressed 等）
					if not token.begins_with("-") or token.length() == 2:
						# 单字母选项不带参数（如 -s, -S, -v），跳过
						pass
					elif token.contains("="):
						# 如 --connect-timeout=30
						pass
		else:
			# 位置参数，视为 URL
			if result.url.is_empty():
				result.url = _strip_quotes(token)

		i += 1

	# 如果有 form_fields 且没有设置 body，标记为 multipart
	if not result.form_fields.is_empty() and result.body.is_empty():
		result.method = "POST"

	# 如果没有显式方法且有 body，设为 POST
	if not has_explicit_method and not result.body.is_empty():
		result.method = "POST"

	return result

static func _tokenize(curl_command: String) -> Array:
	"""将 curl 命令分词，正确处理引号"""
	var tokens = []
	var current = ""
	var in_single_quote = false
	var in_double_quote = false
	var i = 0

	while i < curl_command.length():
		var c = curl_command[i]

		if c == '\\' and i + 1 < curl_command.length():
			# 处理反斜杠转义
			if not in_single_quote:
				i += 1
				current += curl_command[i]
			else:
				current += c
			i += 1
			continue

		if c == "'" and not in_double_quote:
			in_single_quote = not in_single_quote
			current += c
			i += 1
			continue

		if c == '"' and not in_single_quote:
			in_double_quote = not in_double_quote
			current += c
			i += 1
			continue

		if (c == ' ' or c == '\t' or c == '\n' or c == '\r') and not in_single_quote and not in_double_quote:
			if not current.is_empty():
				tokens.append(current)
				current = ""
			i += 1
			continue

		current += c
		i += 1

	if not current.is_empty():
		tokens.append(current)

	return tokens

static func _strip_quotes(s: String) -> String:
	"""去除首尾引号"""
	if s.length() >= 2:
		if (s.begins_with("'") and s.ends_with("'")) or (s.begins_with('"') and s.ends_with('"')):
			return s.substr(1, s.length() - 2)
		# 处理 $'...' 语法
		if s.begins_with("$'") and s.ends_with("'"):
			return s.substr(2, s.length() - 3)
	return s

static func _parse_form_field(field_str: String) -> Dictionary:
	"""解析 -F 表单字段
	格式: name=value 或 name=@filename
	"""
	var eq_pos = field_str.find("=")
	if eq_pos == -1:
		return {"name": field_str, "value": "", "is_file": false}

	var name = field_str.substr(0, eq_pos)
	var value = field_str.substr(eq_pos + 1)

	if value.begins_with("@"):
		# 文件上传
		return {
			"name": name,
			"value": value.substr(1),
			"is_file": true,
		}
	else:
		return {
			"name": name,
			"value": value,
			"is_file": false,
		}

static func replace_placeholders(text: String, variables: Dictionary) -> String:
	"""替换 {{key}} 占位符"""
	var result = text
	for key in variables:
		result = result.replace("{{%s}}" % key, str(variables[key]))
	return result

static func is_curl_command(text: String) -> bool:
	"""判断文本是否为 curl 命令"""
	return text.strip_edges().begins_with("curl ")
