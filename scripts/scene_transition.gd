# scene_transition.gd
extends CanvasLayer

## 全局场景过渡管理器
## 提供黑屏淡入淡出效果、加载提示和超时强制进入功能
@onready var fade_overlay: ColorRect
@onready var loading_label: Label # 右下角的“少女祈祷中”标签
@onready var tip_label: Label     # 左下角的提示标签
@onready var timeout_message_label: Label # 中央提示信息
@onready var force_enter_button: Button # 右上角的强制进入按钮
@onready var dot_timer: Timer

const FADE_DURATION: float = 0.2
const MAX_DOTS: int = 3  # 最大点号数量
const DOT_INTERVAL: float = 0.5  # 点号更新间隔
var current_dots: int = 3  # 初始为3个点
var current_progress: float = -1.0 # 当前加载进度，-1表示不显示
var is_transitioning: bool = false # 正在进行场景切换
var pending_scene_path: String = "" # 存储待加载的场景路径

# --- 用于存储提示信息 ---
const TIPS_FILE_PATH := "res://config/tips.jsonl"
var tips_array: Array[Dictionary] = []

# --- 超时相关 ---
const LOADING_TIMEOUT_FRAMES: int = 600 # 最多等待10秒 (假设60fps)
var wait_frames: int = 0
var is_timed_out: bool = false # 是否已超时

func _ready():
	# --- 初始化提示信息 ---
	_load_tips_from_file()

	# 创建黑屏遮罩
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color(0, 0, 0, 0)  # 初始透明
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 设置为全屏
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_overlay.anchor_left = 0
	fade_overlay.anchor_top = 0
	fade_overlay.anchor_right = 1
	fade_overlay.anchor_bottom  = 1

	# 确保在最上层
	fade_overlay.z_index = 1000

	# 创建加载标签 (右下角)
	loading_label = Label.new()
	# 初始文本为 "少女祈祷中... "
	loading_label.text =  "少女祈祷中... "
	loading_label.add_theme_font_size_override("font_size", 24)
	loading_label.add_theme_color_override("font_color", Color.WHITE)

	# 设置右下角位置
	loading_label.anchor_left = 1.0
	loading_label.anchor_top = 1.0
	loading_label.anchor_right = 1.0
	loading_label.anchor_bottom = 1.0
	loading_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	loading_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# 设置偏移量，留出边距
	loading_label.offset_left = -300  # 增百分比
	loading_label.offset_top = -60    # 距离底部60像素
	loading_label.offset_right = -20  # 距离右边20像素
	loading_label.offset_bottom = -20 # 距离底部20像素
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	loading_label.visible = false  # 初始隐藏
	loading_label.z_index = 1001   # 在遮罩层之上

	# --- 创建提示标签 (左下角) ---
	tip_label = Label.new()
	tip_label.text = "" # 初始为空
	tip_label.add_theme_font_size_override("font_size", 18) # 较小的字体
	tip_label.add_theme_color_override("font_color", Color.LIGHT_GRAY) # 灰色文字

	# 设置左下角位置
	tip_label.anchor_left = 0.0
	tip_label.anchor_top = 1.0
	tip_label.anchor_right = 0.0
	tip_label.anchor_bottom = 1.0
	tip_label.grow_horizontal = Control.GROW_DIRECTION_END
	tip_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# 设置偏移量，留出边距
	tip_label.offset_left = 30    # 距离左边30像素
	tip_label.offset_top = -80    # 距离底部80像素 (与 loading_label 对齐)
	tip_label.offset_right = 700  # 空间，避免文本过长覆盖 loading_label
	tip_label.offset_bottom = -40 # 距离底部40像素
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # 自动换行

	tip_label.visible = false  # 初始隐藏
	tip_label.z_index = 1001   # 在遮罩层之上

	# --- 创建超时提示信息标签 (中央) ---
	timeout_message_label = Label.new()
	timeout_message_label.text = "游戏似乎卡死了，你可以尝试点击右上角的强制加载\n如果发现此问题很频繁，请向开发者反馈"
	timeout_message_label.add_theme_font_size_override("font_size", 20)
	timeout_message_label.add_theme_color_override("font_color", Color.YELLOW) # 黄色警告文字
	timeout_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timeout_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timeout_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 设置居中位置
	timeout_message_label.anchor_left = 0.5
	timeout_message_label.anchor_top = 0.5
	timeout_message_label.anchor_right = 0.5
	timeout_message_label.anchor_bottom = 0.5
	timeout_message_label.pivot_offset = Vector2(timeout_message_label.size.x / 2, timeout_message_label.size.y / 2)
	timeout_message_label.offset_left = -300
	timeout_message_label.offset_top = -50
	timeout_message_label.offset_right = 300
	timeout_message_label.offset_bottom = 50

	timeout_message_label.visible = false  # 初始隐藏
	timeout_message_label.z_index = 1002   # 在遮罩层之上

	# --- 创建强制进入按钮 (右上角) ---
	force_enter_button = Button.new()
	force_enter_button.text = "强制加载"
	force_enter_button.flat = false # 确保按钮可见

	# 设置右上角位置
	force_enter_button.anchor_left = 1.0
	force_enter_button.anchor_top = 0.0
	force_enter_button.anchor_right = 1.0
	force_enter_button.anchor_bottom = 0.0
	force_enter_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	force_enter_button.grow_vertical = Control.GROW_DIRECTION_END

	# 设置偏移量，留出边距
	force_enter_button.offset_left = -120  # 宽度
	force_enter_button.offset_top = 20     # 距离顶部20像素
	force_enter_button.offset_right = -20  # 距离右边20像素
	force_enter_button.offset_bottom = 60  # 高度

	force_enter_button.visible = false  # 初始隐藏
	force_enter_button.z_index = 1003   # 在所有其他元素之上
	force_enter_button.pressed.connect(_on_force_enter_pressed) # 连接按钮按压信号


	# 创建点号更新定时器
	dot_timer = Timer.new()
	dot_timer.wait_time = DOT_INTERVAL
	dot_timer.timeout.connect(_update_dots)
	dot_timer.one_shot = false

	add_child(fade_overlay)
	add_child(loading_label)
	add_child(tip_label) # --- 添加提示标签 ---
	add_child(timeout_message_label) # --- 添加超时提示标签 ---
	add_child(force_enter_button)    # --- 添加强制进入按钮 ---
	add_child(dot_timer)

	print("场景过渡管理器已初始化 ")

# --- 加载提示文件 ---
func _load_tips_from_file():
	var file = FileAccess.open(TIPS_FILE_PATH, FileAccess.READ)
	if not file:
		printerr("无法打开提示文件: ", TIPS_FILE_PATH, ". 错误: ", FileAccess.get_open_error())
		return

	tips_array.clear()
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue
		var json_res = JSON.parse_string(line)
		if json_res and json_res.has("content"):
			# 确保包含必要的字段
			var tip_entry = {
				"author": json_res.get("author", "N/A"), # 默认作者名
				"content": json_res["content"]
			}
			tips_array.append(tip_entry)
		else:
			printerr("提示文件格式错误，跳过行: ", line)

	file.close()
	print("从 ", TIPS_FILE_PATH, " 加载了 ", tips_array.size(), " 条提示。")

# --- 获取随机提示 ---
func _get_random_tip() -> Dictionary:
	if tips_array.is_empty():
		return {"author": "miHoYo", "content": "技术宅拯救世界！"}
	var random_index = randi() % tips_array.size()
	return tips_array[random_index]

func fade_out() -> void:
	"""淡出到黑屏"""
	var tween = create_tween()
	tween.tween_property(fade_overlay, "color:a", 1.0, FADE_DURATION)
	await tween.finished
	# 完全黑屏后显示加载文本（初始为3个点）
	current_progress = -1.0
	_update_label_text()

	# --- 显示加载文本和提示 ---
	loading_label.visible = true

	# 获取并设置随机提示
	var random_tip = _get_random_tip()
	var tip_text = random_tip.content + "\n— " + random_tip.author
	tip_label.text = tip_text
	tip_label.visible = true # 显示提示标签

	# --- 重置超时状态 ---
	is_timed_out = false
	wait_frames = 0
	timeout_message_label.visible = false
	force_enter_button.visible = false

	dot_timer.start()
	print("淡出完成")

func fade_in() -> void:
	"""从黑屏淡入"""
	# 先隐藏加载文本和提示
	loading_label.visible = false
	tip_label.visible = false # 隐藏提示标签
	# --- 隐藏超时相关UI ---
	timeout_message_label.visible = false
	force_enter_button.visible = false
	dot_timer.stop()
	current_progress = -1.0
	var tween = create_tween()
	tween.tween_property(fade_overlay, "color:a", 0.0, FADE_DURATION)
	await tween.finished

	# 重置为3个点，为下次使用做准备
	current_dots = 3
	_update_label_text()
	print("淡入完成")

func change_scene_with_fade(scene_path: String) -> void:
	"""带淡入淡出效果的异步场景切换"""
	if is_transitioning:
		print("[SceneTransition] 警告: 已经在进行场景切换，跳过本次请求: ", scene_path)
		return
	is_transitioning = true
	pending_scene_path = scene_path # 存储待加载的场景路径
	print("[SceneTransition] 开始切换场景: ", scene_path)

	await fade_out()

	# 检查资源是否已经加载，或者已经在加载队列中
	var load_err = ResourceLoader.load_threaded_request(scene_path)
	if load_err != OK:
		print("[SceneTransition] 错误: 无法开始异步加载场景: ", scene_path, " 错误代码: ", load_err)
		is_transitioning = false
		await fade_in()
		return

	# 等待加载完成
	var progress = []

	while true:
		var status = ResourceLoader.load_threaded_get_status(scene_path, progress)

		if status == ResourceLoader.THREAD_LOAD_LOADED:
			# status=ResourceLoader.THREAD_LOAD_IN_PROGRESS # 测试卡死
			# 加载完成
			current_progress = 1.0
			_update_label_text()
			var new_scene = ResourceLoader.load_threaded_get(scene_path)
			if new_scene:
				get_tree().change_scene_to_packed(new_scene)
				print("[SceneTransition] 场景切换成功: ", scene_path)
				break
			else:
				print("[SceneTransition] 错误: 加载到的场景资源为空: ", scene_path)
				await fade_in()
			break
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# 更新进度
			if progress.size() > 0:
				current_progress = progress[0]
				_update_label_text()
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			print("[SceneTransition] 错误: 场景加载失败: ", scene_path)
			await fade_in()
			break
		elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			print("[SceneTransition] 错误: 无效的资源路径: ", scene_path)
			await fade_in()
			break

		# --- 超时检查 ---
		wait_frames += 1
		if wait_frames > LOADING_TIMEOUT_FRAMES and not is_timed_out:
			print("[SceneTransition] 警告: 场景加载可能已卡住")
			# 触发超时逻辑
			_handle_timeout(scene_path)
			# 循环会继续，直到用户点击按钮或实际加载完成（虽然可能性很小）
			# 如果用户强制进入，循环会被 _on_force_enter_pressed 打断
			# 如果实际加载完成，status 会变成 LOADED，循环也会正常结束

		await get_tree().process_frame

	is_transitioning = false
	pending_scene_path = "" # 清空待加载路径

func _handle_timeout(_scene_path: String):
	"""处理加载超时情况"""
	is_timed_out = true
	# 显示超时提示信息
	timeout_message_label.visible = true
	# 显示强制进入按钮
	force_enter_button.visible = true
	print("[SceneTransition] 加载超时，显示强制进入选项。")

func _on_force_enter_pressed():
	"""当用户点击“强制进入”按钮时调用"""
	print("[SceneTransition] 用户点击了强制进入按钮。")
	# 检查是否有待加载的场景
	if pending_scene_path.is_empty():
		print("[SceneTransition] 错误: 没有待加载的场景路径。")
		return

	# 强制加载场景（即使它可能没有完全准备好）
	# Godot 的 ResourceLoader 通常会返回一个有效的资源引用，即使加载未完成，
	# 但这可能导致未定义行为。更好的做法是尝试中断当前加载任务，
	# 然后立即加载。但 Godot 4.x API 没有直接的中断方法。
	# 因此，我们简单地尝试加载，如果失败，则回退到主菜单或其他安全场景。
	var resource = ResourceLoader.load(pending_scene_path)
	if resource:
		print("[SceneTransition] 强制加载场景成功，即将切换: ", pending_scene_path)
		get_tree().change_scene_to_packed(resource)
	else:
		print("[SceneTransition] 强制加载场景失败，返回安全场景。")
		# TODO: 这里可以改为加载一个安全的主菜单场景
		# get_tree().change_scene_to_packed(safe_menu_scene_resource)
		await fade_in() # 作为后备，先淡入，然后让用户自己操作
	# 无论结果如何，都重置状态并结束当前流程
	is_transitioning = false
	pending_scene_path = ""

func _update_dots():
	"""更新动态点号"""
	if not is_timed_out: # 如果已超时，停止更新点号
		current_dots = (current_dots + 1) % (MAX_DOTS + 1)
		_update_label_text()

func _update_label_text():
	"""统一更新标签文本，合并点号和进度"""
	var text = "少女祈祷中"
	for i in range(current_dots):
		text += "."
	if current_progress >= 0:
		text += " %d%%" % int(current_progress * 100)

	loading_label.text = text
	# Tip label 的文本在 fade_out 时设置，这里不需要更新

# 可选：提供一个静态方法来方便访问
static func get_transition_manager() -> Node:
	return Engine.get_main_loop().root.get_node("SceneTransitionManager")
