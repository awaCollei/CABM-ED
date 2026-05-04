extends Node

signal dialog_reply_started
signal dialog_reply_finished

@export var input_path: NodePath
@export var send_button_path: NodePath
@export var bubble_path: NodePath
@export var character_path: NodePath

var _input: TextEdit
var _send_button: Button
var _status_label: Label
var _bubble: PanelContainer
var _character: Control

var _prompt_builder: Node
var _ai_request_service: Node
var _memory_manager: Node
var _summary_manager: Node

var _stream_state: SentenceSplitter.StreamState = SentenceSplitter.StreamState.new()
var _pending_pages: Array[Dictionary] = []
var _is_streaming: bool = false
var _awaiting_user_continue: bool = false
var _is_showing_page := false
var _has_received_first_token: bool = false
var _last_user_message: String = ""

func _ready() -> void:
	_resolve_nodes()
	_init_modules()
	_connect_signals()
	_set_status("")
	_set_input_enabled(true)
	if _bubble and _character and _bubble.has_method("set_target"):
		_bubble.set_target(_character)

func _resolve_nodes() -> void:
	_input = get_node_or_null(input_path) as TextEdit
	_send_button = get_node_or_null(send_button_path) as Button
	_bubble = get_node_or_null(bubble_path) as PanelContainer
	_character = get_node_or_null(character_path) as Control
	_status_label = get_node_or_null("../FloatingBar/MarginContainer/VBox/StatusLabel") as Label

func _init_modules() -> void:
	_prompt_builder = preload("res://scripts/outdoor/outdoor_prompt_builder.gd").new()
	_prompt_builder.name = "OutdoorPromptBuilder"
	add_child(_prompt_builder)

	_ai_request_service = preload("res://scripts/outdoor/outdoor_ai_request_service.gd").new()
	_ai_request_service.name = "OutdoorAIRequestService"
	add_child(_ai_request_service)

	# 初始化户外记忆管理器
	_memory_manager = preload("res://scripts/outdoor/outdoor_memory_manager.gd").new()
	_memory_manager.name = "OutdoorMemoryManager"
	add_child(_memory_manager)

	# 初始化户外总结管理器
	_summary_manager = preload("res://scripts/outdoor/outdoor_summary_manager.gd").new()
	_summary_manager.name = "OutdoorSummaryManager"
	add_child(_summary_manager)
	_summary_manager.memory_manager = _memory_manager

	# 延迟注入依赖（等待子节点 _ready 执行完毕，config_loader 和 logger 才可用）
	call_deferred("_inject_module_dependencies")

func _connect_signals() -> void:
	if _send_button:
		_send_button.pressed.connect(_on_send_pressed)
	if _input:
		_input.gui_input.connect(_on_input_gui_input)
	if _bubble:
		if _bubble.has_signal("next_page_requested"):
			_bubble.connect("next_page_requested", _on_bubble_next_page_requested)
		if _bubble.has_signal("page_fully_shown"):
			_bubble.connect("page_fully_shown", _on_bubble_page_fully_shown)
	if _ai_request_service:
		_ai_request_service.stream_text_received.connect(_on_ai_stream_text_received)
		_ai_request_service.stream_completed.connect(_on_ai_stream_completed)
		_ai_request_service.stream_error.connect(_on_ai_stream_error)
		_ai_request_service.auto_save_started.connect(_on_auto_save_started)
		_ai_request_service.auto_save_completed.connect(_on_auto_save_completed)

func _on_send_pressed() -> void:
	if not _input:
		return
	_try_send_text(_input.text)

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# TextEdit 下手动控制回车发送：Shift+Enter 保留换行，Enter 直接发送。
			if event.shift_pressed:
				return
			_try_send_text(_input.text)
			_input.accept_event()

func _try_send_text(raw_text: String) -> void:
	var text = raw_text.strip_edges()
	if text.is_empty():
		_set_status("消息不能为空")
		return
	if _is_dialog_busy():
		_set_status("上一段对话还没完成")
		return

	if _input:
		_input.clear()
	_last_user_message = text
	_set_status("...")
	dialog_reply_started.emit()
	_start_real_stream(text)

func _start_real_stream(user_text: String) -> void:
	# 每轮回复前重置流式状态，避免上轮残留数据污染。
	_pending_pages.clear()
	_stream_state = SentenceSplitter.StreamState.new()
	_is_streaming = true
	_awaiting_user_continue = false
	_is_showing_page = false
	_has_received_first_token = false
	_set_input_enabled(false)
	_show_waiting_indicator()

	var outdoor_scene_name = _get_outdoor_scene_name()
	var costume_data = _get_selected_costume_data()
	var system_prompt = _prompt_builder.build_outdoor_prompt(user_text, outdoor_scene_name, costume_data)
	if system_prompt.strip_edges().is_empty():
		_on_ai_stream_error("提示词构建失败")
		return

	var started = _ai_request_service.start_stream_chat(system_prompt, user_text)
	if not started:
		_on_ai_stream_error("无法发起 AI 请求")

func _ingest_stream_chunk(chunk: String, is_end: bool) -> void:
	# 使用统一的 SentenceSplitter 做流式分句，把每一句作为一个“页”进入队列。
	var sentence_data_list = SentenceSplitter.split_stream(_stream_state, chunk, is_end)
	for sentence_data in sentence_data_list:
		var sentence_text = str(sentence_data.get("text", "")).strip_edges()
		if sentence_text.is_empty():
			continue
		var no_tts = bool(sentence_data.get("no_tts", false))
		var sentence_hash = _prepare_tts_for_sentence(sentence_text, no_tts)
		_pending_pages.append({
			"text": sentence_text,
			"no_tts": no_tts,
			"sentence_hash": sentence_hash
		})

func _prepare_tts_for_sentence(sentence_text: String, no_tts: bool) -> String:
	if no_tts:
		return ""
	var tts = get_node_or_null("/root/TTSService")
	if tts == null or not tts.is_enabled:
		return ""
	var sentence_hash = ""
	if tts.has_method("compute_sentence_hash"):
		sentence_hash = tts.compute_sentence_hash(sentence_text)
	tts.synthesize_speech(sentence_text)
	return sentence_hash

func _on_ai_stream_text_received(text: String) -> void:
	if text.is_empty():
		return
	if not _has_received_first_token:
		_has_received_first_token = true
		_hide_waiting_indicator()
		_set_status("正在回复...")

	_ingest_stream_chunk(text, false)
	if not _awaiting_user_continue:
		_try_show_next_page_or_finish()

func _on_ai_stream_completed(full_text: String) -> void:
	_is_streaming = false
	_hide_waiting_indicator()
	_set_status("")
	_ingest_stream_chunk("", true)

	# 兜底：如果模型空回复，避免 UI 卡住。
	if _pending_pages.is_empty() and full_text.strip_edges().is_empty():
		_pending_pages.append({
			"text": "……",
			"no_tts": true,
			"sentence_hash": ""
		})

	if not _awaiting_user_continue:
		_try_show_next_page_or_finish()

func _on_ai_stream_error(error_message: String) -> void:
	_is_streaming = false
	_awaiting_user_continue = false
	_is_showing_page = false
	_hide_waiting_indicator()
	_set_input_enabled(true)
	_set_status("请求失败：" + error_message)
	if _input and _input.text.is_empty():
		_input.text = _last_user_message
	dialog_reply_finished.emit()

func _on_bubble_next_page_requested() -> void:
	if _bubble and _bubble.has_method("is_typing") and _bubble.is_typing():
		return
	if not _awaiting_user_continue:
		return
	_awaiting_user_continue = false
	_try_show_next_page_or_finish()

func _on_bubble_page_fully_shown(_text: String) -> void:
	_is_showing_page = false   # 🔓 解锁
	_awaiting_user_continue = true

	if _is_streaming or not _pending_pages.is_empty():
		_set_status("点击角色气泡继续下一句")
	else:
		_set_status("点击角色气泡结束对话")

func _try_show_next_page_or_finish() -> void:
	if _is_showing_page:
		return

	if _bubble and _bubble.has_method("is_typing") and _bubble.is_typing():
		return

	if not _pending_pages.is_empty():
		var next_page = _pending_pages.pop_front()
		_is_showing_page = true   # 🔒 上锁
		if _bubble and _bubble.has_method("show_page"):
			_bubble.show_page(str(next_page.get("text", "")))
		_notify_tts_sentence_displayed(str(next_page.get("sentence_hash", "")), bool(next_page.get("no_tts", false)))
		return

	if not _is_streaming:
		_finish_dialog()

func _finish_dialog() -> void:
	_awaiting_user_continue = false
	_set_input_enabled(true)
	_set_status("")
	if _bubble and _bubble.has_method("clear_page"):
		_bubble.clear_page()
	dialog_reply_finished.emit()

func _on_auto_save_started(message: String) -> void:
	_set_status(message)

func _on_auto_save_completed(_summary: String) -> void:
	_set_status("")

## 延迟注入模块依赖（在子节点 _ready 执行后调用）
func _inject_module_dependencies() -> void:
	_summary_manager.config_loader = _ai_request_service.config_loader
	_summary_manager.logger = _ai_request_service.logger
	_ai_request_service.summary_manager = _summary_manager
	_prompt_builder.memory_manager = _memory_manager

## 离开场景前调用，总结未保存的对话并等待完成。
## outdoor_scene 在切换场景前 await 此函数。
func end_and_summarize() -> void:
	if _ai_request_service:
		await _ai_request_service.end_and_summarize()

## 场景退出时清除当前场景的内存记忆（持久化数据不受影响）
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if _memory_manager:
			_memory_manager.clear_scene_memory()

func _is_dialog_busy() -> bool:
	if _is_streaming:
		return true
	if not _pending_pages.is_empty():
		return true
	if _awaiting_user_continue:
		return true
	if _bubble and _bubble.has_method("has_active_page") and _bubble.has_active_page():
		return true
	if _bubble and _bubble.has_method("is_typing") and _bubble.is_typing():
		return true
	return false

func _set_input_enabled(enabled: bool) -> void:
	if _send_button:
		_send_button.disabled = not enabled
	if _input:
		_input.editable = enabled
		if enabled:
			_input.grab_focus()

func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text

func _show_waiting_indicator() -> void:
	if _bubble == null:
		return
	if _bubble.has_method("show_waiting_indicator"):
		_bubble.show_waiting_indicator("...")

func _hide_waiting_indicator() -> void:
	if _bubble == null:
		return
	if _bubble.has_method("hide_waiting_indicator"):
		_bubble.hide_waiting_indicator()

func _notify_tts_sentence_displayed(sentence_hash: String, no_tts: bool) -> void:
	if no_tts or sentence_hash.is_empty():
		return
	var tts = get_node_or_null("/root/TTSService")
	if tts and tts.is_enabled and tts.has_method("on_new_sentence_displayed"):
		tts.on_new_sentence_displayed(sentence_hash)

func _get_outdoor_scene_name() -> String:
	var scene_name = "户外场景"
	var scene_node = get_parent()
	if scene_node == null:
		return scene_name
	var cfg = scene_node.get("outdoor_config")
	if cfg is Dictionary:
		scene_name = str(cfg.get("name", scene_name))
	return scene_name

func _get_selected_costume_data() -> Dictionary:
	var scene_node = get_parent()
	if scene_node == null:
		return {}
	var costume_data = scene_node.get("selected_costume_data")
	if costume_data is Dictionary:
		return costume_data
	return {}
