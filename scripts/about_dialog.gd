extends Panel

@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton
@onready var version_label: Label = $MarginContainer/VBoxContainer/VersionLabel

# 版本号变量
var current_version: String = "v2-0321-1"  # 这里设置当前版本号

# 版本状态记录
enum VersionStatus { UNCHECKED, LATEST, OUTDATED, ERROR }
var version_status: VersionStatus = VersionStatus.UNCHECKED

# 防抖相关变量
var can_request: bool = true
var debounce_time: float = 1.0  # 防抖时间（秒）
var request_timer: Timer

func _ready():
	close_button.pressed.connect(_on_close_pressed)
	
	# 设置Label文本
	_update_version_label()
	
	# 为Label连接gui_input信号
	version_label.gui_input.connect(_on_version_label_input)
	
	# 初始化防抖计时器
	_setup_debounce_timer()
	
	# 启动时检查版本（根据内存状态决定是否请求）
	_check_version_if_needed()

# 更新版本Label显示
func _update_version_label():
	version_label.text = "版本：" + current_version
	_update_label_color()

# 根据状态更新Label颜色
func _update_label_color():
	match version_status:
		VersionStatus.LATEST:
			version_label.add_theme_color_override("font_color", Color.GREEN)
		VersionStatus.OUTDATED:
			version_label.add_theme_color_override("font_color", Color.YELLOW)
		VersionStatus.ERROR:
			version_label.add_theme_color_override("font_color", Color.WHITE)
		VersionStatus.UNCHECKED:
			# 未检查状态使用默认颜色
			version_label.add_theme_color_override("font_color", Color.WHITE)

# 根据内存状态决定是否需要检查版本
func _check_version_if_needed():
	match version_status:
		VersionStatus.UNCHECKED, VersionStatus.ERROR:
			# 未检查或上次失败，需要重新检查
			_check_version(true)
		VersionStatus.LATEST, VersionStatus.OUTDATED:
			# 已经有有效状态，不需要请求
			print("使用内存中的版本状态: ", version_status)

func _setup_debounce_timer():
	request_timer = Timer.new()
	request_timer.one_shot = true
	request_timer.timeout.connect(_on_debounce_timeout)
	add_child(request_timer)

func _on_debounce_timeout():
	can_request = true

func _on_close_pressed():
	queue_free()

# 发送GET请求检查版本
func _check_version(use_debounce: bool = true):
	# 防抖检查
	if use_debounce and not can_request:
		print("请求过于频繁，请稍后再试")
		return
	
	# 设置防抖
	if use_debounce:
		can_request = false
		request_timer.start(debounce_time)
	
	# 创建HTTP请求
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	# 连接请求完成信号
	http_request.request_completed.connect(_on_version_request_completed.bind(http_request))
	
	# 发送GET请求
	var url = "https://cabm.shasnow.top/api/version"
	var error = http_request.request(url)
	
	if error != OK:
		print("请求发送失败: ", error)
		http_request.queue_free()
		version_status = VersionStatus.ERROR
		_update_label_color()
		if use_debounce:
			can_request = true  # 失败时重置防抖，允许重试

# 请求完成处理
func _on_version_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest):
	# 清理HTTP请求节点
	http_request.queue_free()
	
	# 检查请求是否成功
	if result != HTTPRequest.RESULT_SUCCESS:
		print("请求失败，结果码: ", result)
		version_status = VersionStatus.ERROR
		_update_label_color()
		return
	
	if response_code != 200:
		print("服务器返回错误码: ", response_code)
		version_status = VersionStatus.ERROR
		_update_label_color()
		return
	
	# 解析JSON响应
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		print("JSON解析失败")
		version_status = VersionStatus.ERROR
		_update_label_color()
		return
	
	var data = json.data
	
	# 提取version值
	if typeof(data) == TYPE_DICTIONARY and data.has("version"):
		var server_version = data["version"]
		
		print("当前版本: ", current_version)
		print("服务器版本: ", server_version)
		
		# 检测是否与当前版本一致
		if server_version == current_version:
			version_status = VersionStatus.LATEST
			# 版本一致时的逻辑（仅颜色变化，由_update_label_color处理）
			pass
		else:
			version_status = VersionStatus.OUTDATED
			# 版本不一致时的逻辑（仅颜色变化，由_update_label_color处理）
			pass
	else:
		print("响应数据格式错误")
		version_status = VersionStatus.ERROR
	
	# 更新Label颜色
	_update_label_color()

# 点击Label时的额外操作
func _on_version_label_clicked():
	# 这里是点击Label时的额外操作
	# 颜色变化已经在请求完成后自动处理
	match version_status:
		VersionStatus.LATEST:
			# 版本最新时的点击额外操作
			print("点击了最新版本标签")
			MessageDisplay.show_info_message("已是最新版本")
			pass
			
		VersionStatus.OUTDATED:
			# 版本过期时的点击额外操作
			print("点击了过期版本标签")
			MessageDisplay.show_failure_message("当前不是最新版本，可以前往QQ群获取最新版本")
			pass
			
		VersionStatus.ERROR:
			# 请求失败时的点击额外操作
			print("点击了错误状态的版本标签")
			MessageDisplay.show_failure_message("版本状态获取失败")
			pass
			
		VersionStatus.UNCHECKED:
			# 未检查状态的点击额外操作
			pass

# 修改点击处理，分离颜色更新和额外操作
func _on_version_label_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 颜色变化通过请求完成后的_update_label_color处理
		_check_version_if_needed()  # 触发请求，完成后会自动更新颜色
		_on_version_label_clicked()  # 执行点击额外操作

# 点击面板背景关闭
func _on_panel_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos = event.position
		if not Rect2(Vector2.ZERO, size).has_point(local_pos):
			queue_free()