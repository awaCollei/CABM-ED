# test.gd
# 测试 SentenceSplitter 的分句功能

extends Node

func _ready():
	print("========== SentenceSplitter 测试开始 ==========\n")
	
	# 测试用例1: 基础分句
	test_basic_split()
	
	# 测试用例2: 括号内分句
	test_parenthesis_split()
	
	# 测试用例3: 混合括号和普通文本
	test_mixed_split()
	
	# 测试用例4: 省略号处理
	test_ellipsis_split()
	
	# 测试用例5: 流式分句
	test_stream_split()
	test_edge_cases()
	print("\n========== 所有测试完成 ==========")

# 测试用例1: 基础分句
func test_basic_split():
	print("--- 测试1: 基础分句 ---")
	var text = "今天天气真好。阳光明媚，微风拂面。我们去公园散步吧！你愿意一起来吗？"
	var results = SentenceSplitter.split_text(text)
	print("输入文本: ", text)
	print("分句结果:")
	for i in range(results.size()):
		var item = results[i]
		print("  第%d句: \"%s\" (no_tts=%s)" % [i+1, item["text"], item["no_tts"]])
	print("")

# 测试用例2: 括号内分句
func test_parenthesis_split():
	print("--- 测试2: 括号内分句 ---")
	var text = "今天天气真好（阳光明媚，微风拂面）。我们去公园散步吧！"
	var results = SentenceSplitter.split_text(text)
	print("输入文本: ", text)
	print("分句结果:")
	for i in range(results.size()):
		var item = results[i]
		print("  第%d句: \"%s\" (no_tts=%s)" % [i+1, item["text"], item["no_tts"]])
	print("")

# 测试用例3: 混合括号和普通文本
func test_mixed_split():
	print("--- 测试3: 混合括号和普通文本 ---")
	var text = "请注意（这个很重要）。同时（另一个要点）也需要关注。最后总结一下。"
	var results = SentenceSplitter.split_text(text)
	print("输入文本: ", text)
	print("分句结果:")
	for i in range(results.size()):
		var item = results[i]
		print("  第%d句: \"%s\" (no_tts=%s)" % [i+1, item["text"], item["no_tts"]])
	print("")

# 测试用例4: 省略号处理
func test_ellipsis_split():
	print("--- 测试4: 省略号处理 ---")
	
	# 4.1: 正常省略号
	var text1 = "他沉默了很久……然后轻轻地说了一句话。"
	var results1 = SentenceSplitter.split_text(text1)
	print("输入文本1: ", text1)
	print("分句结果:")
	for i in range(results1.size()):
		var item = results1[i]
		print("  第%d句: \"%s\" (no_tts=%s)" % [i+1, item["text"], item["no_tts"]])
	
	# 4.2: 多个省略号
	var text2 = "他想了想……还是决定不说……毕竟已经过去了。"
	var results2 = SentenceSplitter.split_text(text2)
	print("\n输入文本2: ", text2)
	print("分句结果:")
	for i in range(results2.size()):
		var item = results2[i]
		print("  第%d句: \"%s\" (no_tts=%s)" % [i+1, item["text"], item["no_tts"]])
	print("")

# 测试用例5: 流式分句
func test_stream_split():
	print("--- 测试5: 流式分句 ---")
	
	var state = SentenceSplitter.StreamState.new()
	
	# 模拟流式输入
	var chunks = [
		"今天天气真好，",
		"阳光明媚。",
		"我们去公园（",
		"那里有花有草",
		"），散步吧！",
		"啊……真舒服。"
	]
	
	print("流式输入:")
	for chunk in chunks:
		print("  收到: \"", chunk, "\"")
	
	print("\n流式分句结果:")
	var all_results = []
	
	for i in range(chunks.size()):
		var is_end = (i == chunks.size() - 1)
		var results = SentenceSplitter.split_stream(state, chunks[i], is_end)
		if results.size() > 0:
			print("  第%d次处理输出:" % (i+1))
			for item in results:
				print("    \"%s\" (no_tts=%s)" % [item["text"], item["no_tts"]])
				all_results.append(item)
	
	# 验证最终结果
	print("\n流式分句完整结果:")
	for i in range(all_results.size()):
		var item = all_results[i]
		print("  第%d句: \"%s\" (no_tts=%s)" % [i+1, item["text"], item["no_tts"]])
	print("")

# 测试用例6: 边界情况
func test_edge_cases():
	print("--- 测试6: 边界情况 ---")
	
	# 空文本
	var empty = ""
	var results = SentenceSplitter.split_text(empty)
	print("空文本分句结果: ", results)
	
	# 只有括号
	var only_paren = "（括号内容）"
	results = SentenceSplitter.split_text(only_paren)
	print("只有括号: \"", only_paren, "\" -> ", results)
	
	# 多重括号
	var nested = "（外层（内层）内容）"
	results = SentenceSplitter.split_text(nested)
	print("多重括号: \"", nested, "\" -> ", results)

	var ellipsis_text = "……"
	results = SentenceSplitter.split_text(ellipsis_text)
	print("省略号: \"", ellipsis_text, "\" -> ", results)
	
	print("")
