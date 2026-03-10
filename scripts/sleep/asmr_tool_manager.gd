extends Node
class_name ASMRToolManager

# ASMR工具管理器
# 负责工具执行、触发音播放

signal tool_started(tool_name: String, display_name: String)
signal tool_completed(tool_name: String, feedback: String)

# 音频播放器
var trigger_player: AudioStreamPlayer = null
var trigger_bus_name: String = "TriggerAudio"
var trigger_bus_idx: int = -1

# 工具配置
var tools_config: Dictionary = {}

# 工具执行状态
var is_executing: bool = false
var current_execution_id: int = 0
var current_tool_name: String = ""
var tool_results: Array = []

# 当前播放状态
var current_tool_start_time: float = 0.0
var current_tool_duration: float = 0.0

func initialize(t_player: AudioStreamPlayer):
	"""初始化"""
	trigger_player = t_player
	_setup_trigger_audio_bus()
	_load_tools_config()

func _setup_trigger_audio_bus():
	"""设置触发音独立总线"""
	if not trigger_player:
		push_error("触发音播放器未初始化")
		return
	
	trigger_bus_idx = AudioServer.get_bus_index(trigger_bus_name)
	
	if trigger_bus_idx == -1:
		AudioServer.add_bus()
		trigger_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(trigger_bus_idx, trigger_bus_name)
		AudioServer.set_bus_send(trigger_bus_idx, "Master")
	else:
		for i in range(AudioServer.get_bus_effect_count(trigger_bus_idx) - 1, -1, -1):
			AudioServer.remove_bus_effect(trigger_bus_idx, i)
	
	AudioServer.set_bus_volume_db(trigger_bus_idx, 0.0)
	AudioServer.set_bus_mute(trigger_bus_idx, false)
	AudioServer.set_bus_solo(trigger_bus_idx, false)
	
	trigger_player.bus = trigger_bus_name

func _load_tools_config():
	"""加载工具配置"""
	var config_path = "res://config/asmr_tools.json"
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_string) == OK:
			tools_config = json.data

func execute_tools(tool_calls: Array):
	"""执行工具列表"""
	tool_results.clear()
	current_execution_id += 1
	var execution_id = current_execution_id
	
	print("开始执行工具，ID:", execution_id)
	
	for i in range(tool_calls.size()):
		# 检查是否被打断
		if execution_id != current_execution_id:
			print("工具执行被打断")
			break
		
		await _execute_single_tool(tool_calls[i], execution_id)

func _execute_single_tool(tool_call: Dictionary, execution_id: int):
	"""执行单个工具"""
	var function_name = tool_call.function.name
	var arguments_str = tool_call.function.arguments
	var tool_call_id = tool_call.id
	
	is_executing = true
	current_tool_name = function_name
	current_tool_start_time = Time.get_ticks_msec() / 1000.0
	
	# 解析参数
	var arguments = _parse_arguments(arguments_str)
	
	# 获取显示名称
	var display_name = get_display_name(function_name)
	
	# 发送开始信号
	tool_started.emit(function_name, display_name)
	
	# 执行工具
	var feedback = await _dispatch_tool(function_name, arguments, execution_id)
	
	is_executing = false
	current_tool_name = ""
	
	# 保存结果
	tool_results.append({
		"tool_call_id": tool_call_id,
		"feedback": feedback
	})
	
	# 发送完成信号
	tool_completed.emit(function_name, feedback)

func _parse_arguments(arguments_str: String) -> Dictionary:
	"""解析工具参数"""
	if arguments_str.is_empty():
		return {}
	
	var json = JSON.new()
	if json.parse(arguments_str) == OK:
		return json.data
	
	return {}

func get_display_name(function_name: String) -> String:
	"""获取工具显示名称"""
	if tools_config.has("audio_mapping") and tools_config.audio_mapping.has(function_name):
		if tools_config.audio_mapping[function_name].has("displayed_name"):
			return tools_config.audio_mapping[function_name].displayed_name
	return function_name

func _dispatch_tool(function_name: String, arguments: Dictionary, execution_id: int) -> String:
	"""分发工具执行"""
	match function_name:
		"ear_cleaning", "aloe_vera_gel", "aromatherapy_massage","fabric_friction":
			return await _handle_tool(function_name, arguments, execution_id)
		_:
			return "未知工具: " + function_name

func _handle_tool(tool_name: String, arguments: Dictionary, execution_id: int) -> String:
	"""通用工具处理逻辑"""
	var save_mgr = get_node("/root/SaveManager")
	var user_name = save_mgr.get_user_name()
	
	var tool_config = tools_config.audio_mapping.get(tool_name, {})
	var audio_id = tool_config.get("audio_id", "")
	
	if audio_id.is_empty():
		return "工具配置错误: 缺少audio_id"
	
	var default_duration = tool_config.get("default_duration", 60)
	var default_prepare = tool_config.get("default_prepare", false)
	var default_intensity = tool_config.get("default_intensity", "")
	var displayed_name = tool_config.get("displayed_name", tool_name)
	
	# 解析参数
	var position = arguments.get("position", "")
	var duration = arguments.get("duration", 0)
	var intensity = arguments.get("intensity", default_intensity)
	var prepare = arguments.get("prepare", default_prepare)
	if position not in ["left", "right", "both"]:
		position = "both"
	
	if duration <= 0:
		duration = default_duration
	
	# 播放准备音频
	if prepare:
		await _play_prepare_audio(audio_id, position, execution_id)
		if execution_id != current_execution_id:
			return "操作被打断"
	
	# 播放主音频
	await _play_audio_for_duration(audio_id, position, duration, intensity, execution_id)
	
	var actual_duration = current_tool_duration if current_tool_duration > 0 else duration
	var minutes = int(round(actual_duration / 60.0))
	
	# 构造反馈消息
	var action_name = displayed_name.replace("正在", "").replace("...", "")
	var msg = "给%s%s了%d分钟" % [user_name, action_name, minutes]
	
	if position != "both" and position != "":
		msg += "（%s）" % _position_to_chinese(position)
	
	return msg

func _position_to_chinese(position: String) -> String:
	"""位置转中文"""
	match position:
		"left": return "左耳"
		"right": return "右耳"
		"both": return "双耳"
		_: return position

func _play_prepare_audio(audio_id: String, position: String, execution_id: int):
	"""播放准备音频"""
	var files = _get_prepare_audio_files(audio_id)
	if files.is_empty():
		return
		
	var audio_file = files[randi() % files.size()]
	await _play_single_file(audio_file, position, execution_id)

func _play_single_file(audio_file: String, position: String, execution_id: int):
	"""播放单个音频文件"""
	print("播放：" + audio_file + " 位置：" + position)
	var file = FileAccess.open(audio_file, FileAccess.READ)
	if file:
		var audio_data = file.get_buffer(file.get_length())
		file.close()
		
		var stream = AudioStreamMP3.new()
		stream.data = audio_data
		
		trigger_player.stream = stream
		_set_audio_balance(position)
		trigger_player.play()
		
		var audio_length = stream.get_length()
		var check_interval = 0.1
		var time_waited = 0.0
		
		while time_waited < audio_length:
			if execution_id != current_execution_id:
				return
			
			await get_tree().create_timer(check_interval).timeout
			time_waited += check_interval
	else:
		push_error("无法打开音频文件: " + audio_file)

func _play_audio_for_duration(audio_id: String, position: String, duration: float, intensity: String, execution_id: int):
	"""播放音频直到达到指定时长或被打断"""
	var available_files = _get_audio_files(audio_id, intensity)
	
	if available_files.is_empty():
		push_error("没有找到音频文件: " + audio_id + " intensity: " + intensity)
		return
	
	var elapsed_time = 0.0
	current_tool_duration = 0.0
	
	while elapsed_time < duration:
		# 检查是否被打断
		if execution_id != current_execution_id:
			print("音频播放被打断，实际时长: %.1f秒" % elapsed_time)
			current_tool_duration = elapsed_time
			return
		
		# 随机选择音频
		var audio_file = available_files[randi() % available_files.size()]
		
		# 复用 _play_single_file 的逻辑，但我们需要计算时间
		# 由于 _play_single_file 是 void 且不返回时长，这里手动内联或重构
		# 为了方便，这里内联并修改以支持时间计算
		print("播放：" + audio_file + " 位置：" + position)
		var file = FileAccess.open(audio_file, FileAccess.READ)
		if file:
			var audio_data = file.get_buffer(file.get_length())
			file.close()
			
			var stream = AudioStreamMP3.new()
			stream.data = audio_data
			
			trigger_player.stream = stream
			_set_audio_balance(position)
			trigger_player.play()
			
			var audio_length = stream.get_length()
			var check_interval = 0.1
			var time_waited = 0.0
			
			while time_waited < audio_length:
				if execution_id != current_execution_id:
					print("音频播放中被打断")
					current_tool_duration = elapsed_time + time_waited
					return
				
				await get_tree().create_timer(check_interval).timeout
				time_waited += check_interval
			
			elapsed_time += audio_length
			current_tool_duration = elapsed_time
		else:
			push_error("无法打开音频文件: " + audio_file)
			break

func _get_prepare_audio_files(audio_id: String) -> Array:
	"""获取准备音频文件列表"""
	var files = []
	var path = "user://sleep/" + audio_id + "/"
	var dir = DirAccess.open(path)
	
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".mp3"):
				if file_name.begins_with("prepare_"):
					files.append(path + file_name)
			file_name = dir.get_next()
		
		dir.list_dir_end()
	
	return files

func _get_audio_files(audio_id: String, intensity: String = "") -> Array:
	"""获取音频文件列表"""
	var files = []
	var path = "user://sleep/" + audio_id + "/"
	var dir = DirAccess.open(path)
	
	if not dir:
		return files
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	var normal_files = []
	var s_files = []
	var d_files = []
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".mp3"):
			# 跳过prepare文件
			if file_name.begins_with("prepare_"):
				file_name = dir.get_next()
				continue
			
			if file_name.begins_with("S_"):
				s_files.append(path + file_name)
			elif file_name.begins_with("D_"):
				d_files.append(path + file_name)
			else:
				normal_files.append(path + file_name)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	if intensity == "random":
		var combined = []
		combined.append_array(s_files)
		combined.append_array(d_files)
		if combined.is_empty():
			return normal_files
		return combined
	elif intensity == "deep":
		if d_files.is_empty(): return normal_files
		return d_files
	elif intensity == "shallow":
		if s_files.is_empty(): return normal_files
		return s_files
	else:
		return normal_files

func _set_audio_balance(position: String):
	"""设置触发音左右均衡"""
	if not trigger_player or trigger_bus_idx == -1:
		return
	
	# 清除旧的Panner效果
	for i in range(AudioServer.get_bus_effect_count(trigger_bus_idx) - 1, -1, -1):
		var effect = AudioServer.get_bus_effect(trigger_bus_idx, i)
		if effect is AudioEffectPanner:
			AudioServer.remove_bus_effect(trigger_bus_idx, i)
	
	var pan_value = 0.0
	match position:
		"left": pan_value = -1.0
		"right": pan_value = 1.0
		"both": pan_value = 0.0
		_: pan_value = 0.0
	
	if abs(pan_value) > 0.01:
		var panner_effect = AudioEffectPanner.new()
		panner_effect.pan = pan_value
		AudioServer.add_bus_effect(trigger_bus_idx, panner_effect)

func set_volume(volume_db: float):
	"""设置触发音音量"""
	if trigger_player:
		trigger_player.volume_db = volume_db

func get_tool_results() -> Array:
	"""获取工具结果"""
	return tool_results

func interrupt():
	"""中断工具执行"""
	print("中断工具执行")
	
	current_execution_id += 1
	
	if trigger_player and trigger_player.playing:
		trigger_player.stop()
	
	is_executing = false
	current_tool_name = ""

func clear_all():
	"""清空所有状态"""
	print("清空工具队列")
	
	interrupt()
	tool_results.clear()
	current_tool_duration = 0.0

func cleanup():
	"""清理资源"""
	clear_all()
	
	if trigger_bus_idx != -1 and trigger_bus_idx < AudioServer.bus_count:
		for i in range(AudioServer.get_bus_effect_count(trigger_bus_idx) - 1, -1, -1):
			AudioServer.remove_bus_effect(trigger_bus_idx, i)
		AudioServer.remove_bus(trigger_bus_idx)
		trigger_bus_idx = -1
