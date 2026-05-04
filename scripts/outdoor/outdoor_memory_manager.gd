extends Node

## 户外场景记忆管理器
## 职责：
## - 维护当前场景的"短期记忆"列表（仅在内存中，离开场景时清除）
## - 通过 UnifiedMemorySaver 将记忆持久化保存（存档 + 日记 + 向量库）
## - 对外提供 get_scene_memory_context() 供 prompt_builder 使用

# 当前场景的内存记忆条目，格式：[{timestamp, content}, ...]
# 离开场景时调用 clear_scene_memory() 清除
var _scene_memories: Array = []

## 添加一条记忆到当前场景的内存中（不持久化，仅供本次场景使用）
func add_scene_memory(content: String, timestamp: String) -> void:
	if content.strip_edges().is_empty():
		return
	_scene_memories.append({
		"timestamp": timestamp,
		"content": content
	})
	print("户外记忆已加入内存：%s..." % content.substr(0, 40))

## 获取当前场景的记忆上下文字符串，供 prompt_builder 注入提示词
func get_scene_memory_context() -> String:
	if _scene_memories.is_empty():
		return ""
	var lines: Array[String] = []
	for mem in _scene_memories:
		var ts = str(mem.get("timestamp", ""))
		var content = str(mem.get("content", ""))
		if ts.is_empty():
			lines.append(content)
		else:
			lines.append("%s %s" % [TimeUtil.to_relative_time_prefix(ts), content])
	return "\n".join(lines)

## 离开场景时调用，清除内存中的场景记忆（持久化数据不受影响）
func clear_scene_memory() -> void:
	print("户外场景记忆已清除（共 %d 条）" % _scene_memories.size())
	_scene_memories.clear()

## 通过 UnifiedMemorySaver 持久化保存记忆
## @param summary: 总结文本
## @param conversation_text: 原始对话文本（用于日记）
## @param custom_timestamp: Unix 时间戳（可选）
func save_memory_persistent(summary: String, conversation_text: String, custom_timestamp = null) -> void:
	var unified_saver = get_node_or_null("/root/UnifiedMemorySaver")
	if not unified_saver:
		push_error("OutdoorMemoryManager: UnifiedMemorySaver 未找到，无法持久化保存")
		return
	# 使用 CHAT 类型，支持查看完整对话记录和语音播放
	await unified_saver.save_memory(
		summary,
		unified_saver.MemoryType.CHAT,
		custom_timestamp,
		conversation_text,
		{}
	)
