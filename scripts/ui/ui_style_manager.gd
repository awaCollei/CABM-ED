extends Node

## 界面风格配置独立于 AI/API 配置保存。
signal ui_style_changed(style_id: String)
signal ui_opacity_changed(style_id: String, sidebar: float, dialog: float, buttons: float)

const CONFIG_PATH := "user://ui_style.json"
const VALID_STYLES := ["default", "notebook", "modern", "scifi"]
# 每套风格的独立默认透明度。需要调整初始观感时只修改这里。
const DEFAULT_OPACITY := {
	"default": {"sidebar": 1.0, "dialog": 1.0, "buttons": 1.0},
	"notebook": {"sidebar": 1.0, "dialog": 0.85, "buttons": 0.8},
	"modern": {"sidebar": 0.9, "dialog": 0.8, "buttons": 0.8},
	"scifi": {"sidebar": 0.0, "dialog": 0.0, "buttons": 0.5},
}
const DEFAULT_CONFIG := {
	"style": "notebook",	
	"opacity": {},
}

var _config: Dictionary = {}
var _initialized := false


func _ready() -> void:
	_ensure_initialized()


func load_ui_style() -> String:
	_ensure_initialized()
	var style_id: String = str(_config.get("style", "notebook"))
	return style_id if style_id in VALID_STYLES else "notebook"


func save_ui_style(style_id: String) -> bool:
	if style_id not in VALID_STYLES:
		push_error("UIStyleManager: 非法界面风格 %s" % style_id)
		return false
	_ensure_initialized()
	_config["style"] = style_id
	var saved := _write_config()
	if saved:
		ui_style_changed.emit(style_id)
	return saved


func load_ui_style_opacity(style_id: String) -> Dictionary:
	_ensure_initialized()
	var defaults := get_default_opacity(style_id)
	var all_values: Dictionary = _config.get("opacity", {})
	var values: Dictionary = all_values.get(style_id, {})
	return {
		"sidebar": clampf(float(values.get("sidebar", defaults.sidebar)), 0.0, 1.0),
		"dialog": clampf(float(values.get("dialog", defaults.dialog)), 0.0, 1.0),
		"buttons": clampf(float(values.get("buttons", defaults.buttons)), 0.0, 1.0),
	}


func get_default_opacity(style_id: String) -> Dictionary:
	var normalized := style_id if style_id in VALID_STYLES else "notebook"
	return DEFAULT_OPACITY[normalized].duplicate(true)


func save_ui_style_opacity(style_id: String, values: Dictionary) -> bool:
	if style_id not in VALID_STYLES:
		return false
	_ensure_initialized()
	var all_values: Dictionary = _config.get("opacity", {})
	all_values[style_id] = {
		"sidebar": clampf(float(values.get("sidebar", 1.0)), 0.0, 1.0),
		"dialog": clampf(float(values.get("dialog", 1.0)), 0.0, 1.0),
		"buttons": clampf(float(values.get("buttons", 1.0)), 0.0, 1.0),
	}
	_config["opacity"] = all_values
	var result := _write_config()
	if result:
		var saved: Dictionary = all_values[style_id]
		ui_opacity_changed.emit(style_id, saved.sidebar, saved.dialog, saved.buttons)
	return result


func get_config_path() -> String:
	return ProjectSettings.globalize_path(CONFIG_PATH)


func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_config = _read_config()
	if _config.is_empty():
		_config = DEFAULT_CONFIG.duplicate(true)
		if not _write_config():
			push_error("UIStyleManager: 无法创建默认风格配置")
	_config["style"] = str(_config.get("style", "notebook"))
	if _config.style not in VALID_STYLES:
		_config.style = "notebook"
	if not _config.get("opacity", {}) is Dictionary:
		_config.opacity = {}
	print("UIStyleManager: 配置文件 = %s，当前风格 = %s" % [get_config_path(), _config.style])


func _read_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error(
			"UIStyleManager: 无法读取 %s，错误码 %s" % [get_config_path(), FileAccess.get_open_error()]
		)
		return {}
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(content)
	if error != OK or not json.data is Dictionary:
		push_error(
			(
				"UIStyleManager: 配置 JSON 无效：%s（第 %d 行）"
				% [json.get_error_message(), json.get_error_line()]
			)
		)
		return {}
	return json.data


func _write_config() -> bool:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		push_error(
			"UIStyleManager: 无法写入 %s，错误码 %s" % [get_config_path(), FileAccess.get_open_error()]
		)
		return false
	file.store_string(JSON.stringify(_config, "\t"))
	file.flush()
	file.close()
	# 写完立即验证文件确实存在，避免界面报告成功但内容没有落盘。
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("UIStyleManager: 写入后找不到 %s" % get_config_path())
		return false
	return true
