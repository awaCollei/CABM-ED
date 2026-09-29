extends MarginContainer

## “风格样式”独立设置页。选择后立即保存并通知当前主界面刷新。
# const UIStyleFactory = preload("res://scripts/ui/ui_style_factory.gd")

var style_manager: Node
var _loading_opacity := false
var _opacity_save_timer: Timer
var _style_ids := [
	UIStyleFactory.STYLE_DEFAULT,
	UIStyleFactory.STYLE_NOTEBOOK,
	UIStyleFactory.STYLE_MODERN,
	UIStyleFactory.STYLE_SCIFI,
	UIStyleFactory.STYLE_RETRO_RPG,
	UIStyleFactory.STYLE_WIN_TERMINAL,
	UIStyleFactory.STYLE_UBUNTU_TERMINAL,
]
var _descriptions := {
	UIStyleFactory.STYLE_DEFAULT: "使用Godot默认主题的半透明深色样式",
	UIStyleFactory.STYLE_NOTEBOOK: "暖色纸张、便签按钮，沉浸式养成",
	UIStyleFactory.STYLE_MODERN: "明亮留白、圆角卡片，清爽易读",
	UIStyleFactory.STYLE_SCIFI: "透明面板、冷青描边，未来终端质感",
	UIStyleFactory.STYLE_RETRO_RPG: "灰色石质面板、直角边框、像素感按钮",
	UIStyleFactory.STYLE_WIN_TERMINAL: "Windows终端风格",
	UIStyleFactory.STYLE_UBUNTU_TERMINAL: "Ubuntu终端风格",
}

@onready var style_option: OptionButton = %StyleOption
@onready var description_label: Label = %DescriptionLabel
@onready var preview_panel: Panel = %PreviewPanel
@onready var preview_title: Label = %PreviewTitle
@onready var preview_button: Button = %PreviewButton
@onready var status_label: Label = %StatusLabel
@onready var sidebar_opacity: HSlider = %SidebarOpacity
@onready var dialog_opacity: HSlider = %DialogOpacity
@onready var button_opacity: HSlider = %ButtonOpacity
@onready var sidebar_value: Label = %SidebarValue
@onready var dialog_value: Label = %DialogValue
@onready var button_value: Label = %ButtonValue
@onready var reset_opacity_button: Button = %ResetOpacityButton


func _ready() -> void:
	style_option.clear()
	for display_name in [
		"Godot默认",
		"日记本",
		"现代简约",
		"未来科幻",
		"远古RPG",
		"Windows终端",
		"Ubuntu终端",
	]:
		style_option.add_item(display_name)
	# 在配置管理器返回前也保持与项目实际默认风格一致。
	style_option.select(_style_ids.find(UIStyleFactory.STYLE_NOTEBOOK))
	style_option.item_selected.connect(_on_style_selected)
	reset_opacity_button.pressed.connect(_on_reset_opacity_pressed)
	for slider in [sidebar_opacity, dialog_opacity, button_opacity]:
		slider.value_changed.connect(_on_opacity_value_changed)
	_opacity_save_timer = Timer.new()
	_opacity_save_timer.one_shot = true
	_opacity_save_timer.wait_time = 0.15
	_opacity_save_timer.timeout.connect(_save_opacity)
	add_child(_opacity_save_timer)
	if style_manager == null:
		style_manager = get_node_or_null("/root/UIStyleManager")
	_load_selection()


func initialize() -> void:
	style_manager = get_node_or_null("/root/UIStyleManager")
	if is_node_ready():
		_load_selection()


func _exit_tree() -> void:
	if _opacity_save_timer != null and not _opacity_save_timer.is_stopped():
		_opacity_save_timer.stop()
		_save_opacity()


func _load_selection() -> void:
	if style_manager == null or not style_manager.has_method("load_ui_style"):
		status_label.text = "风格管理器未加载，请重新启动 Godot 后再试"
		push_error("StyleSettingsPanel: /root/UIStyleManager 不存在")
		return
	var style_id: String = UIStyleFactory.normalize_style(style_manager.load_ui_style())
	var index := _style_ids.find(style_id)
	style_option.select(maxi(index, 0))
	_load_opacity(style_id)
	_update_preview(style_id)


func _on_style_selected(index: int) -> void:
	if index < 0 or index >= _style_ids.size():
		return
	if style_manager == null:
		status_label.text = "无法保存：风格管理器未加载"
		return
	var style_id: String = _style_ids[index]
	var saved: bool = style_manager.save_ui_style(style_id)
	# 各样式拥有独立数值；切换时滑杆恢复为新样式保存的值，未设置则为 100%。
	_load_opacity(style_id)
	_update_preview(style_id)
	status_label.text = (
		"已应用：%s" % style_option.get_item_text(index) if saved else "保存失败，请检查用户目录写入权限"
	)


func _load_opacity(style_id: String) -> void:
	var values := {"sidebar": 1.0, "dialog": 1.0, "buttons": 1.0}
	if style_manager != null and style_manager.has_method("load_ui_style_opacity"):
		values = style_manager.load_ui_style_opacity(style_id)
	_set_opacity_sliders(values)


func _set_opacity_sliders(values: Dictionary) -> void:
	_loading_opacity = true
	sidebar_opacity.value = float(values.sidebar) * 100.0
	dialog_opacity.value = float(values.dialog) * 100.0
	button_opacity.value = float(values.buttons) * 100.0
	_loading_opacity = false
	_update_opacity_labels()


func _on_opacity_value_changed(_value: float) -> void:
	_update_opacity_labels()
	_update_preview(_style_ids[style_option.selected])
	if not _loading_opacity:
		_opacity_save_timer.start()


func _on_reset_opacity_pressed() -> void:
	if style_manager == null or style_option.selected < 0:
		status_label.text = "无法重置：风格管理器未加载"
		return
	if not _opacity_save_timer.is_stopped():
		_opacity_save_timer.stop()
	var style_id: String = _style_ids[style_option.selected]
	_set_opacity_sliders(style_manager.get_default_opacity(style_id))
	_update_preview(style_id)
	_save_opacity()
	status_label.text = "已重置并应用此风格的默认透明度"


func _update_opacity_labels() -> void:
	sidebar_value.text = "%d%%" % int(round(sidebar_opacity.value))
	dialog_value.text = "%d%%" % int(round(dialog_opacity.value))
	button_value.text = "%d%%" % int(round(button_opacity.value))


func _save_opacity() -> void:
	if style_option.selected < 0:
		return
	if style_manager == null:
		status_label.text = "无法保存：风格管理器未加载"
		return
	var style_id: String = _style_ids[style_option.selected]
	var values := {
		"sidebar": sidebar_opacity.value / 100.0,
		"dialog": dialog_opacity.value / 100.0,
		"buttons": button_opacity.value / 100.0,
	}
	var saved: bool = style_manager.save_ui_style_opacity(style_id, values)
	status_label.text = "透明度已保存" if saved else "透明度保存失败"


func _update_preview(style_id: String) -> void:
	description_label.text = _descriptions[style_id]
	preview_title.text = "对话与侧边栏预览"
	match style_id:
		UIStyleFactory.STYLE_NOTEBOOK:
			preview_button.text = "便签按钮"
		UIStyleFactory.STYLE_RETRO_RPG:
			preview_button.text = "菜单项"
		UIStyleFactory.STYLE_WIN_TERMINAL:
			preview_button.text = "> run"
		UIStyleFactory.STYLE_UBUNTU_TERMINAL:
			preview_button.text = "$ sudo"
		_:
			preview_button.text = "示例按钮"
	var preview_theme := UIStyleFactory.create_theme(
		style_id, button_opacity.value / 100.0, dialog_opacity.value / 100.0
	)
	preview_panel.theme = preview_theme
	preview_button.modulate.a = (
		button_opacity.value / 100.0 if style_id == UIStyleFactory.STYLE_DEFAULT else 1.0
	)
	if style_id == UIStyleFactory.STYLE_DEFAULT:
		preview_panel.remove_theme_stylebox_override("panel")
	else:
		preview_panel.add_theme_stylebox_override(
			"panel", UIStyleFactory.create_panel_style(style_id, dialog_opacity.value / 100.0)
		)
