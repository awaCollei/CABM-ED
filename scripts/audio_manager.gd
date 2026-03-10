extends Node

# 音频播放器
var bgm_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer

# 音频配置
var audio_config: Dictionary = {}

# 当前播放状态
var current_scene: String = ""
var current_time: String = ""
var current_weather: String = ""
var user_locked_bgm: bool = false  # 用户是否手动锁定了BGM（在音乐面板点击音乐时设置）
var current_bgm_path: String = "" # 当前播放的BGM路径

# BGM播放模式
enum PlayMode {
	SINGLE_LOOP,    # 单曲循环
	SEQUENTIAL,     # 顺序播放
	RANDOM          # 随机播放
}

var current_play_mode: PlayMode = PlayMode.SEQUENTIAL
var current_playlist: Array = [] # 当前播放列表
var current_track_index: int = 0 # 当前播放的曲目索引
var played_tracks: Array = [] # 已播放的曲目（用于随机模式）

func _ready():
	# 创建背景音乐播放器
	bgm_player = AudioStreamPlayer.new()
	add_child(bgm_player)
	
	# 创建环境音播放器
	ambient_player = AudioStreamPlayer.new()
	add_child(ambient_player)
	
	# 加载音频配置
	_load_audio_config()

func _load_audio_config():
	"""加载音频配置文件（混合策略：默认配置从res://，用户配置从user://）"""
	# 1. 先加载默认配置（res://，只读，包含场景音乐和氛围音配置）
	var default_config_path = "res://config/audio_config.json"
	if FileAccess.file_exists(default_config_path):
		var file = FileAccess.open(default_config_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			if json.parse(json_string) == OK:
				audio_config = json.data
				print("[OK] 默认音频配置已加载")
			else:
				print("[ERROR] 解析默认音频配置失败")
				audio_config = _get_default_config()
		else:
			print("[ERROR] 无法打开默认音频配置")
			audio_config = _get_default_config()
	else:
		print("[WARN] 默认音频配置文件不存在，使用内置默认值")
		audio_config = _get_default_config()
	
	# 2. 加载用户配置（user://，可写，包含音量设置）
	var user_config_path = "user://audio_settings.json"
	if FileAccess.file_exists(user_config_path):
		var file = FileAccess.open(user_config_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			if json.parse(json_string) == OK:
				var user_config = json.data
				print("✅ 用户音频设置已加载")
				
				# 合并用户配置（覆盖默认配置）
				if user_config.has("volume"):
					audio_config["volume"] = user_config["volume"]
			else:
				print("❌ 解析用户音频设置失败")
	else:
		print("ℹ️ 用户音频设置不存在，将使用默认值")
	
	# 3. 应用音量设置
	if audio_config.has("volume"):
		var bgm_volume = audio_config["volume"].get("background_music", 0.5)
		var ambient_volume = audio_config["volume"].get("ambient", 0.3)
		bgm_player.volume_db = linear_to_db(bgm_volume)
		ambient_player.volume_db = linear_to_db(ambient_volume)
		print("🔊 音量设置: BGM=%.0f%%, 氛围音=%.0f%%" % [bgm_volume * 100, ambient_volume * 100])
	
	# 4. 恢复上次播放的BGM播放列表（从SaveManager获取）
	# 注意：不使用call_deferred，而是在play_background_music之前同步恢复
	# 这样可以确保场景切换时不会覆盖存档中的播放列表

func restore_bgm_playlist_sync():
	"""同步恢复BGM播放列表（在场景加载前调用）"""
	if not has_node("/root/SaveManager"):
		print("⚠️ SaveManager未找到，跳过恢复播放列表")
		return
	
	var save_manager = get_node("/root/SaveManager")
	var bgm_config = save_manager.get_bgm_config()
	
	# 检查是否有保存的播放列表
	if bgm_config.has("all") and bgm_config["all"].has("enabled_music"):
		var all_config = bgm_config["all"]
		var saved_playlist = all_config.get("enabled_music", [])
		
		if not saved_playlist.is_empty():
			var play_mode = all_config.get("play_mode", PlayMode.SEQUENTIAL)
			var saved_index = all_config.get("current_index", 0)
			
			# 验证音乐文件是否存在
			var valid_music = []
			for music_path in saved_playlist:
				if FileAccess.file_exists(music_path) or ResourceLoader.exists(music_path):
					valid_music.append(music_path)
			
			if not valid_music.is_empty():
				# 确保索引有效
				if saved_index >= valid_music.size():
					saved_index = 0
				
				print("🎵 从存档恢复播放列表: ", valid_music.size(), "首音乐，从第", saved_index + 1, "首开始")
				play_playlist(valid_music, play_mode, saved_index, true)
				return
	
	# 没有存档或存档为空，使用默认BGM
	print("ℹ️ 未找到保存的播放列表，使用默认BGM")
	var default_bgm = audio_config.get("default_bgm", "")
	
	if not default_bgm.is_empty() and (FileAccess.file_exists(default_bgm) or ResourceLoader.exists(default_bgm)):
		print("🎵 首次启动，播放默认BGM: ", default_bgm)
		play_playlist([default_bgm], PlayMode.SINGLE_LOOP, 0, false)  # 不锁定，允许场景切换
	else:
		print("ℹ️ 未配置默认BGM或文件不存在")

func _get_default_config() -> Dictionary:
	"""获取默认配置（当配置文件不存在时使用）"""
	return {
		"background_music": {},
		"ambient_sounds": {},
		"volume": {
			"background_music": 0.3,
			"ambient": 0.3
		},
		"default_bgm": ""
	}

func play_background_music(scene_id: String, time_id: String, weather_id: String):
	"""根据场景、时间和天气播放背景音乐和氛围音"""
	# 记录旧场景
	var old_scene = current_scene
	
	# 更新当前状态
	current_scene = scene_id
	current_time = time_id
	current_weather = weather_id
	
	# 如果用户手动锁定了BGM，不自动切换
	if user_locked_bgm:
		print("🎵 用户已锁定BGM，场景切换不改变音乐")
		# 但仍然播放氛围音
		_play_ambient_for_scene(scene_id, time_id, weather_id)
		return
	
	# 如果是首次调用（old_scene为空）且播放列表已存在（从存档恢复的）
	# 则不应用场景配置，保持存档中的播放列表
	if old_scene == "" and current_playlist.size() > 0:
		print("🎵 首次加载：保持存档中的播放列表")
		# 但仍然播放氛围音
		_play_ambient_for_scene(scene_id, time_id, weather_id)
		return
	
	# 获取场景的BGM配置
	var scene_bgm_config = _get_scene_bgm_config(scene_id)
	var old_scene_bgm_config = _get_scene_bgm_config(old_scene) if old_scene != "" else {}
	
	# 检查是否两个场景都沿用默认（配置为空）
	var both_use_default = scene_bgm_config.is_empty() and old_scene_bgm_config.is_empty()
	
	if both_use_default and current_playlist.size() > 0:
		# 两个场景都沿用默认，继续播放当前音乐，不切换
		print("🎵 场景切换：两个场景都沿用默认配置，继续播放")
	else:
		# 应用场景的BGM配置
		print("🎵 场景切换：应用场景BGM配置 (", scene_id, ")")
		_apply_scene_bgm_config(scene_bgm_config)
	
	# 播放氛围音（独立于BGM）
	_play_ambient_for_scene(scene_id, time_id, weather_id)

func _get_audio_path(scene_id: String, time_id: String, weather_id: String) -> String:
	"""获取指定场景、时间和天气的音频路径"""
	if not audio_config.has("background_music"):
		return ""
	
	var bgm_config = audio_config["background_music"]
	
	# 检查场景配置
	if not bgm_config.has(scene_id):
		return ""
	
	var scene_config = bgm_config[scene_id]
	
	# 检查时间配置
	if not scene_config.has(time_id):
		return ""
	
	var time_config = scene_config[time_id]
	
	# 检查天气配置
	if not time_config.has(weather_id):
		return ""
	
	var filename = time_config[weather_id]
	
	# 如果文件名为空，返回空字符串
	if filename.is_empty():
		return ""
	
	# 拼接完整路径
	return "res://assets/audio/" + filename

func _on_bgm_finished():
	"""背景音乐播放完毕，根据播放模式处理"""
	if not bgm_player:
		return
	
	if current_playlist.is_empty():
		# 播放列表为空，直接循环
		if bgm_player.stream:
			bgm_player.play()
			print("循环播放背景音乐")
		return
	
	match current_play_mode:
		PlayMode.SINGLE_LOOP:
			# 单曲循环
			bgm_player.play()
			print("单曲循环: ", current_bgm_path)
		
		PlayMode.SEQUENTIAL:
			# 顺序播放下一首
			_play_next_track()
		
		PlayMode.RANDOM:
			# 随机播放
			_play_random_track()

func stop_background_music():
	"""停止背景音乐"""
	if bgm_player and bgm_player.playing:
		bgm_player.stop()
		print("停止背景音乐")

func get_bgm_volume() -> float:
	"""获取背景音乐音量 (0.0 - 1.0)"""
	if not bgm_player:
		return 0.5  # 返回默认值
	return db_to_linear(bgm_player.volume_db)

func set_bgm_volume(volume: float):
	"""设置背景音乐音量 (0.0 - 1.0)"""
	if not bgm_player:
		return
	bgm_player.volume_db = linear_to_db(clamp(volume, 0.0, 1.0))
	_save_volume_config()

func set_ambient_volume(volume: float):
	"""设置环境音音量 (0.0 - 1.0)"""
	if not ambient_player:
		return
	ambient_player.volume_db = linear_to_db(clamp(volume, 0.0, 1.0))
	_save_volume_config()

func get_ambient_volume() -> float:
	"""获取环境音音量 (0.0 - 1.0)"""
	if not ambient_player:
		return 0.3  # 返回默认值
	return db_to_linear(ambient_player.volume_db)

func play_playlist(playlist: Array, play_mode: PlayMode = PlayMode.SEQUENTIAL, start_index: int = 0, lock_bgm: bool = true):
	"""播放播放列表
	
	参数:
		playlist: 音乐文件路径数组
		play_mode: 播放模式
		start_index: 起始曲目索引
		lock_bgm: 是否锁定BGM（默认true，表示用户手动选择；false表示场景自动播放）
	"""
	if playlist.is_empty():
		print("播放列表为空")
		return
	
	current_playlist = playlist.duplicate()
	current_play_mode = play_mode
	current_track_index = start_index
	played_tracks.clear()
	user_locked_bgm = lock_bgm  # 根据参数决定是否锁定BGM
	
	# 播放指定的起始曲目
	# 即使是随机模式，也先播放用户点击的音乐
	if play_mode == PlayMode.RANDOM:
		# 标记该曲目已播放
		played_tracks.append(start_index)
	
	var success = _load_and_play_bgm(current_playlist[current_track_index])
	
	# 如果是用户手动选择的音乐，保存到存档
	if success and lock_bgm and has_node("/root/SaveManager"):
		var save_manager = get_node("/root/SaveManager")
		var bgm_config = save_manager.get_bgm_config()
		
		# 保存当前播放列表和播放模式到"all"配置
		if not bgm_config.has("all"):
			bgm_config["all"] = {}
		
		bgm_config["all"]["enabled_music"] = current_playlist.duplicate()
		bgm_config["all"]["play_mode"] = current_play_mode
		bgm_config["all"]["current_index"] = current_track_index
		
		save_manager.set_bgm_config(bgm_config)
		print("💾 已保存播放列表到存档")

func _load_and_play_bgm(file_path: String) -> bool:
	"""加载并播放BGM"""
	var audio_stream = null
	var ext = file_path.get_extension().to_lower()
	
	# 检查是否为不支持的格式
	if ext in ["aac", "m4a"]:
		push_warning("AAC/M4A格式不被Godot原生支持，请转换为OGG或MP3格式")
		print("⚠️ 不支持的音频格式: ", ext)
		return false
	
	# 尝试加载音频文件
	if file_path.begins_with("res://"):
		if ResourceLoader.exists(file_path):
			audio_stream = load(file_path)
			# 为内置资源设置循环属性
			if audio_stream:
				if audio_stream is AudioStreamMP3:
					audio_stream.loop = (current_play_mode == PlayMode.SINGLE_LOOP and current_playlist.size() == 1)
				elif audio_stream is AudioStreamOggVorbis:
					audio_stream.loop = (current_play_mode == PlayMode.SINGLE_LOOP and current_playlist.size() == 1)
				elif audio_stream is AudioStreamWAV:
					if current_play_mode == PlayMode.SINGLE_LOOP and current_playlist.size() == 1:
						audio_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
					else:
						audio_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	else:
		if FileAccess.file_exists(file_path):
			if ext == "mp3":
				audio_stream = AudioStreamMP3.new()
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file:
					audio_stream.data = file.get_buffer(file.get_length())
					file.close()
					# 根据播放模式设置循环
					audio_stream.loop = (current_play_mode == PlayMode.SINGLE_LOOP and current_playlist.size() == 1)
				else:
					print("❌ 无法打开MP3文件: ", file_path)
					return false
			elif ext == "ogg":
				audio_stream = AudioStreamOggVorbis.load_from_file(file_path)
				if audio_stream:
					audio_stream.loop = (current_play_mode == PlayMode.SINGLE_LOOP and current_playlist.size() == 1)
			elif ext == "wav":
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file:
					var wav_data = file.get_buffer(file.get_length())
					file.close()
					audio_stream = AudioStreamWAV.new()
					audio_stream.data = wav_data
					if current_play_mode == PlayMode.SINGLE_LOOP and current_playlist.size() == 1:
						audio_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
					else:
						audio_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
				else:
					print("❌ 无法打开WAV文件: ", file_path)
					return false
		else:
			print("❌ 文件不存在: ", file_path)
			return false
	
	if audio_stream:
		if not bgm_player:
			push_error("❌ BGM播放器未初始化")
			return false
		
		bgm_player.stream = audio_stream
		bgm_player.play()
		current_bgm_path = file_path
		print("✅ 播放BGM: ", file_path)
		
		if not bgm_player.finished.is_connected(_on_bgm_finished):
			bgm_player.finished.connect(_on_bgm_finished)
		
		return true
	else:
		push_error("❌ 加载BGM失败: " + file_path)
		return false

func _play_next_track():
	"""播放下一首（顺序模式）"""
	if current_playlist.is_empty():
		return
	
	current_track_index = (current_track_index + 1) % current_playlist.size()
	_load_and_play_bgm(current_playlist[current_track_index])
	print("顺序播放下一首: ", current_track_index + 1, "/", current_playlist.size())
	
	# 如果BGM被锁定（用户手动选择的），保存当前索引
	if user_locked_bgm and has_node("/root/SaveManager"):
		var save_manager = get_node("/root/SaveManager")
		var bgm_config = save_manager.get_bgm_config()
		if bgm_config.has("all"):
			bgm_config["all"]["current_index"] = current_track_index
			save_manager.set_bgm_config(bgm_config)

func _play_random_track():
	"""播放随机曲目"""
	if current_playlist.is_empty():
		return
	
	# 如果所有曲目都播放过，重置已播放列表
	if played_tracks.size() >= current_playlist.size():
		played_tracks.clear()
	
	# 找到未播放的曲目
	var available_indices = []
	for i in range(current_playlist.size()):
		if not played_tracks.has(i):
			available_indices.append(i)
	
	if available_indices.is_empty():
		# 所有曲目都播放过，重新开始
		played_tracks.clear()
		available_indices = range(current_playlist.size())
	
	# 随机选择一首
	var random_index = available_indices[randi() % available_indices.size()]
	current_track_index = random_index
	played_tracks.append(random_index)
	
	_load_and_play_bgm(current_playlist[current_track_index])
	print("随机播放: ", current_track_index + 1, "/", current_playlist.size())
	
	# 如果BGM被锁定（用户手动选择的），保存当前索引
	if user_locked_bgm and has_node("/root/SaveManager"):
		var save_manager = get_node("/root/SaveManager")
		var bgm_config = save_manager.get_bgm_config()
		if bgm_config.has("all"):
			bgm_config["all"]["current_index"] = current_track_index
			save_manager.set_bgm_config(bgm_config)

func stop_custom_bgm():
	"""停止用户锁定的BGM，恢复场景音乐"""
	user_locked_bgm = false
	current_bgm_path = ""
	current_playlist.clear()
	current_track_index = 0
	played_tracks.clear()
	stop_background_music()
	
	# 清除存档中的播放列表
	if has_node("/root/SaveManager"):
		var save_manager = get_node("/root/SaveManager")
		var bgm_config = save_manager.get_bgm_config()
		if bgm_config.has("all"):
			bgm_config["all"]["enabled_music"] = []
			bgm_config["all"]["current_index"] = 0
			save_manager.set_bgm_config(bgm_config)
			print("💾 已清除存档中的播放列表")
	
	# 重新播放场景音乐
	if not current_scene.is_empty():
		play_background_music(current_scene, current_time, current_weather)

func set_play_mode(mode: PlayMode):
	"""设置播放模式"""
	current_play_mode = mode
	print("播放模式已设置为: ", ["单曲循环", "顺序播放", "随机播放"][mode])

func get_play_mode() -> PlayMode:
	"""获取当前播放模式"""
	return current_play_mode

func play_ambient_sound(file_path: String, loop: bool = true):
	"""播放环境音"""
	if not ambient_player:
		push_error("❌ 环境音播放器未初始化")
		return
	
	if not ResourceLoader.exists(file_path):
		print("环境音文件不存在: ", file_path)
		return
	
	var audio_stream = load(file_path)
	if audio_stream:
		ambient_player.stream = audio_stream
		ambient_player.play()
		print("播放环境音: ", file_path)
		
		if loop and not ambient_player.finished.is_connected(_on_ambient_finished):
			ambient_player.finished.connect(_on_ambient_finished)

func _on_ambient_finished():
	"""环境音播放完毕，循环播放"""
	if ambient_player and ambient_player.stream:
		ambient_player.play()

func stop_ambient_sound():
	"""停止环境音"""
	if ambient_player and ambient_player.playing:
		ambient_player.stop()
		print("停止环境音")

func _save_volume_config():
	"""保存音量配置到用户目录"""
	if not audio_config.has("volume"):
		audio_config["volume"] = {}
	
	audio_config["volume"]["background_music"] = get_bgm_volume()
	audio_config["volume"]["ambient"] = get_ambient_volume()
	
	_save_user_config()

func _save_user_config():
	"""保存用户配置到user://（可写目录）"""
	var user_config = {
		"volume": audio_config.get("volume", {
			"background_music": 0.3,
			"ambient": 0.3
		})
	}
	
	var config_path = "user://audio_settings.json"
	var file = FileAccess.open(config_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(user_config, "\t"))
		file.close()
		print("💾 用户音频设置已保存到: ", config_path)
	else:
		push_error("❌ 无法保存用户音频设置")
		print("错误代码: ", FileAccess.get_open_error())

func _get_scene_bgm_config(scene_id: String) -> Dictionary:
	"""获取场景的BGM配置（从SaveManager）"""
	if scene_id == "" or not has_node("/root/SaveManager"):
		return {}
	
	var save_manager = get_node("/root/SaveManager")
	var bgm_config = save_manager.get_bgm_config()
	
	# 检查场景是否有配置
	if bgm_config.has(scene_id):
		var scene_config = bgm_config[scene_id]
		var enabled_music = scene_config.get("enabled_music", [])
		
		# 如果场景有音乐列表，返回配置
		if not enabled_music.is_empty():
			return scene_config
	
	# 场景没有配置，返回空字典（表示沿用默认）
	return {}

func _apply_scene_bgm_config(scene_config: Dictionary):
	"""应用场景的BGM配置"""
	var enabled_music = []
	var play_mode = PlayMode.SEQUENTIAL
	
	if scene_config.is_empty():
		if has_node("/root/SaveManager"):
			var save_manager = get_node("/root/SaveManager")
			var bgm_config = save_manager.get_bgm_config()
			if bgm_config.has("all"):
				var all_config = bgm_config["all"]
				play_mode = all_config.get("play_mode", PlayMode.SEQUENTIAL)
		enabled_music = _get_all_bgm_paths()
	else:
		# 使用场景自己的配置
		enabled_music = scene_config.get("enabled_music", [])
		play_mode = scene_config.get("play_mode", PlayMode.SEQUENTIAL)
	
	# 验证音乐文件是否存在
	var valid_music = []
	for music_path in enabled_music:
		if FileAccess.file_exists(music_path) or ResourceLoader.exists(music_path):
			valid_music.append(music_path)
	
	if valid_music.is_empty():
		print("⚠️ 场景没有有效的音乐文件，停止播放")
		stop_background_music()
		current_playlist.clear()
		return
	
	# 检查新的播放列表是否与当前相同
	var playlist_changed = (valid_music != current_playlist)
	var mode_changed = (play_mode != current_play_mode)
	
	if not playlist_changed and not mode_changed:
		# 播放列表和模式都没变，继续播放当前音乐
		print("🎵 播放列表和模式未变化，继续播放")
		return
	
	# 检查当前播放的音乐是否在新列表中
	var current_in_new_list = valid_music.has(current_bgm_path)
	
	if current_in_new_list and bgm_player and bgm_player.playing:
		# 当前音乐在新列表中且正在播放
		# 更新播放列表和模式，但不重新播放
		current_playlist = valid_music
		current_play_mode = play_mode
		current_track_index = valid_music.find(current_bgm_path)
		print("🎵 更新播放列表，继续播放当前音乐: ", current_bgm_path)
	else:
		# 当前音乐不在新列表中，或没有在播放，开始播放新列表
		print("🎵 切换到新的播放列表")
		play_playlist(valid_music, play_mode, 0, false)  # 不锁定BGM

func _play_ambient_for_scene(_scene_id: String, _time_id: String, weather_id: String):
	"""根据场景、时间和天气播放氛围音"""
	if not ambient_player:
		return
	
	var ambient_path = ""
	
	# 检查天气氛围音（如雨声）
	if weather_id in ["rainy", "storm"]:
		ambient_path = "res://assets/audio/rain.mp3"
	elif weather_id in["snowy"]:
		ambient_path="res://assets/audio/snow.mp3"
	
	# 播放或停止氛围音
	if ambient_path.is_empty():
		stop_ambient_sound()
	else:
		# 检查是否已经在播放相同的氛围音
		if ambient_player.playing and ambient_player.stream:
			# 使用元数据来跟踪当前播放的氛围音路径
			if has_meta("current_ambient_path") and get_meta("current_ambient_path") == ambient_path:
				return # 已经在播放相同的氛围音
		
		if ResourceLoader.exists(ambient_path):
			var audio_stream = load(ambient_path)
			if audio_stream:
				ambient_player.stream = audio_stream
				ambient_player.play()
				set_meta("current_ambient_path", ambient_path)
				print("播放氛围音: ", ambient_path)
				
				# 连接循环信号
				if not ambient_player.finished.is_connected(_on_ambient_finished):
					ambient_player.finished.connect(_on_ambient_finished)
		else:
			print("氛围音文件不存在: ", ambient_path)

func get_current_bgm_path() -> String:
	"""获取当前播放的BGM路径"""
	return current_bgm_path

func _scan_bgm_directory(path: String) -> Array:
	"""扫描目录中的音频文件"""
	var result = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var ext = file_name.get_extension().to_lower()
				if ext in ["mp3", "ogg", "wav"]:
					result.append(path + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	return result

func _get_all_bgm_paths() -> Array:
	"""获取所有BGM路径（仅从用户目录）"""
	var paths = []
	# 只扫描用户目录（包含转移过来的内置BGM）
	var custom = _scan_bgm_directory("user://custom_bgm/")
	for c in custom:
		paths.append(c)
	return paths
