extends Node

# 音频控制器
# 负责音频播放、音量控制、均衡和可视化
# 使用AudioServer峰值音量API实现实时音频可视化

signal volume_changed(value: float)
signal balance_changed(value: float)

# 音频节点引用
var audio_player: AudioStreamPlayer
var left_visualizer: ColorRect
var right_visualizer: ColorRect

# 音频总线
var bus_name: String = "SleepAudio"
var bus_idx: int = -1

# 音频参数
var master_volume: float = 0.0  # dB
var balance: float = 0.0  # -1.0 (左) 到 1.0 (右)

# 可视化参数
var smoothed_left: float = 0.0
var smoothed_right: float = 0.0
var smooth_factor: float = 0.15
var min_visible_height: float = 20.0

func _ready():
	set_process(false)

func initialize(player: AudioStreamPlayer, left_vis: ColorRect, right_vis: ColorRect):
	"""初始化音频控制器（仅用于背景音）"""
	audio_player = player
	left_visualizer = left_vis
	right_visualizer = right_vis
	
	# 设置音频总线（仅用于背景音）
	await _setup_audio_bus()
	
	# 显示可视化元素
	if left_visualizer:
		left_visualizer.visible = true
	if right_visualizer:
		right_visualizer.visible = true
	
	# 开始处理
	set_process(true)

func _setup_audio_bus():
	"""设置音频总线（仅用于背景音，不包含触发音）"""
	if audio_player and audio_player.playing:
		audio_player.stop()
	
	# 查找或创建专用音频总线
	bus_idx = AudioServer.get_bus_index(bus_name)
	
	if bus_idx == -1:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, bus_name)
		AudioServer.set_bus_send(bus_idx, "Master")
	else:
		# 清除现有效果
		for i in range(AudioServer.get_bus_effect_count(bus_idx) - 1, -1, -1):
			AudioServer.remove_bus_effect(bus_idx, i)
	
	# 设置总线
	AudioServer.set_bus_volume_db(bus_idx, 0.0)
	AudioServer.set_bus_mute(bus_idx, false)
	AudioServer.set_bus_solo(bus_idx, false)
	
	await get_tree().process_frame
	
	# 连接背景音AudioPlayer（不包含触发音）
	if audio_player:
		audio_player.bus = bus_name

func load_and_play_audio(audio_path: String):
	"""加载并播放音频文件（普通循环播放）"""
	if not audio_player:
		push_error("AudioPlayer未初始化")
		return
	
	var audio_stream = load(audio_path)
	
	if audio_stream:
		# 设置音频流
		audio_player.stream = audio_stream
		
		# 设置音量
		audio_player.volume_db = 0.0
		
		# 设置循环播放
		if audio_stream is AudioStreamMP3:
			audio_stream.loop = true
		elif audio_stream is AudioStreamOggVorbis:
			audio_stream.loop = true
		elif audio_stream is AudioStreamWAV:
			audio_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		
		await get_tree().process_frame
		
		# 开始播放
		audio_player.play()
		
		print("音频已加载并开始播放（普通循环模式）: ", audio_path)
	else:
		push_error("无法加载音频文件: " + audio_path)

func set_volume(volume_db: float):
	"""设置音量（dB）"""
	master_volume = volume_db
	
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, master_volume)
		volume_changed.emit(master_volume)

func set_balance(balance_value: float):
	"""设置左右均衡 (-1.0 到 1.0)"""
	balance = clamp(balance_value, -1.0, 1.0)
	_apply_balance()
	balance_changed.emit(balance)

func _apply_balance():
	"""应用均衡设置"""
	if bus_idx == -1:
		return
	
	# 移除旧的平移效果
	for i in range(AudioServer.get_bus_effect_count(bus_idx) - 1, -1, -1):
		var effect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectPanner:
			AudioServer.remove_bus_effect(bus_idx, i)
	
	# 添加新的平移效果（如果需要）
	if abs(balance) > 0.01:
		var panner = AudioEffectPanner.new()
		panner.pan = balance
		AudioServer.add_bus_effect(bus_idx, panner)

func _process(_delta):
	"""每帧更新音频可视化"""
	_update_visualization()

func _update_visualization():
	"""更新音频可视化 - 使用峰值音量"""
	if bus_idx == -1:
		return
	
	if not audio_player or not audio_player.playing:
		_reset_visualizers()
		return
	
	# 使用AudioServer.get_bus_peak_volume获取实时音量
	# 返回值是dB，范围通常是-80到0
	var left_db = AudioServer.get_bus_peak_volume_left_db(bus_idx, 0)
	var right_db = AudioServer.get_bus_peak_volume_right_db(bus_idx, 0)
	
	# 将dB转换为线性幅度 (0.0 到 1.0)
	var left_amplitude = db_to_linear(left_db)
	var right_amplitude = db_to_linear(right_db)
	
	# 限制范围
	left_amplitude = clamp(left_amplitude, 0.0, 1.0)
	right_amplitude = clamp(right_amplitude, 0.0, 1.0)
	
	# 平滑处理
	smoothed_left = lerp(smoothed_left, left_amplitude, smooth_factor)
	smoothed_right = lerp(smoothed_right, right_amplitude, smooth_factor)
	
	# 更新可视化
	_update_visualizer_bars(smoothed_left, smoothed_right)

func _update_visualizer_bars(left_mag: float, right_mag: float):
	"""更新可视化条的高度和颜色"""
	if not left_visualizer or not right_visualizer:
		return
	
	var screen_height = get_viewport().get_visible_rect().size.y
	var max_height = screen_height * 0.8
	
	# 计算高度
	var left_height = left_mag * max_height
	var right_height = right_mag * max_height
	
	# 设置最小可见高度
	if left_mag > 0.01:
		left_height = max(left_height, min_visible_height)
	if right_mag > 0.01:
		right_height = max(right_height, min_visible_height)
	
	# 更新左侧可视化
	left_visualizer.size.y = left_height
	left_visualizer.position.y = screen_height - left_height
	
	# 更新右侧可视化
	right_visualizer.size.y = right_height
	right_visualizer.position.y = screen_height - right_height
	
	# 根据音量调整透明度
	var left_alpha = 0.3 + left_mag * 0.7
	var right_alpha = 0.3 + right_mag * 0.7
	
	left_visualizer.color = Color(0.2, 0.6, 1.0, left_alpha)
	right_visualizer.color = Color(1.0, 0.4, 0.2, right_alpha)

func _reset_visualizers():
	"""重置可视化器到默认状态"""
	smoothed_left = 0.0
	smoothed_right = 0.0
	
	if left_visualizer:
		left_visualizer.size.y = 0
		left_visualizer.color = Color(0.2, 0.6, 1.0, 0.3)
	
	if right_visualizer:
		right_visualizer.size.y = 0
		right_visualizer.color = Color(1.0, 0.4, 0.2, 0.3)

func stop_audio():
	"""停止音频播放"""
	if audio_player:
		audio_player.stop()
	_reset_visualizers()

func cleanup():
	"""清理音频资源"""
	stop_audio()
	
	if bus_idx != -1:
		for i in range(AudioServer.get_bus_effect_count(bus_idx) - 1, -1, -1):
			AudioServer.remove_bus_effect(bus_idx, i)
		AudioServer.remove_bus(bus_idx)
		bus_idx = -1

func get_volume() -> float:
	return master_volume

func get_balance() -> float:
	return balance
