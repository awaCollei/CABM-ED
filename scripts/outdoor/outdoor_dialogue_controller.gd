extends Node

@export var input_path: NodePath
@export var send_button_path: NodePath
@export var bubble_path: NodePath
@export var character_path: NodePath

const FAKE_REPLY := "好的。现在先用固定回复把户外场景对话流程跑通，后续再接入真实 AI 接口。你可以继续点击气泡查看下一句。"
const STREAM_CHUNK_SIZE := 6

@onready var fake_stream_timer: Timer = $FakeStreamTimer

var _input: TextEdit
var _send_button: Button
var _status_label: Label
var _bubble: PanelContainer
var _character: Control

var _stream_state: SentenceSplitter.StreamState = SentenceSplitter.StreamState.new()
var _pending_pages: Array[String] = []
var _streaming_text: String = ""
var _stream_cursor: int = 0
var _is_streaming: bool = false
var _awaiting_user_continue: bool = false
var _is_showing_page := false

func _ready() -> void:
	_resolve_nodes()
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

func _connect_signals() -> void:
	if _send_button:
		_send_button.pressed.connect(_on_send_pressed)
	if _input:
		_input.gui_input.connect(_on_input_gui_input)
	if fake_stream_timer:
		fake_stream_timer.timeout.connect(_on_fake_stream_tick)
	if _bubble:
		if _bubble.has_signal("next_page_requested"):
			_bubble.connect("next_page_requested", _on_bubble_next_page_requested)
		if _bubble.has_signal("page_fully_shown"):
			_bubble.connect("page_fully_shown", _on_bubble_page_fully_shown)

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
	_set_status("正在回复...")
	_start_fake_stream(FAKE_REPLY)

func _start_fake_stream(full_text: String) -> void:
	_pending_pages.clear()
	_stream_state = SentenceSplitter.StreamState.new()
	_streaming_text = full_text
	_stream_cursor = 0
	_is_streaming = true
	_awaiting_user_continue = false
	_set_input_enabled(false)
	if _bubble and _bubble.has_method("clear_page"):
		_bubble.clear_page()
	fake_stream_timer.start()

func _on_fake_stream_tick() -> void:
	if _stream_cursor >= _streaming_text.length():
		fake_stream_timer.stop()
		_ingest_stream_chunk("", true)
		_is_streaming = false
		if not _awaiting_user_continue:
			_try_show_next_page_or_finish()
		return

	var left = _streaming_text.length() - _stream_cursor
	var step = min(STREAM_CHUNK_SIZE, left)
	var chunk = _streaming_text.substr(_stream_cursor, step)
	_stream_cursor += step
	_ingest_stream_chunk(chunk, false)
	if not _awaiting_user_continue:
		_try_show_next_page_or_finish()

func _ingest_stream_chunk(chunk: String, is_end: bool) -> void:
	# 使用统一的 SentenceSplitter 做流式分句，把每一句作为一个“页”进入队列。
	var sentence_data_list = SentenceSplitter.split_stream(_stream_state, chunk, is_end)
	for sentence_data in sentence_data_list:
		var sentence_text = str(sentence_data.get("text", "")).strip_edges()
		if sentence_text.is_empty():
			continue
		_pending_pages.append(sentence_text)

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
		var next_text = _pending_pages.pop_front()
		_is_showing_page = true   # 🔒 上锁
		if _bubble and _bubble.has_method("show_page"):
			_bubble.show_page(next_text)
		return

	if not _is_streaming:
		_finish_dialog()

func _finish_dialog() -> void:
	_awaiting_user_continue = false
	_set_input_enabled(true)
	_set_status("")
	if _bubble and _bubble.has_method("clear_page"):
		_bubble.clear_page()

func _is_dialog_busy() -> bool:
	if _is_streaming:
		return true
	if not _pending_pages.is_empty():
		return true
	if _awaiting_user_continue:
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
