extends Control
class_name WallpaperPanel

signal wallpaper_changed(wallpaper_id: String)
signal panel_closed

const BUILTIN_WALLPAPERS = [
	{"id": "none", "name": "简约线条", "file": ""},
	{"id": "deepsea", "name": "深海少女", "file": "res://assets/images/wallpaper/1.jpg"},
	{"id": "ide", "name": "「她」的诞生", "file": "res://assets/images/wallpaper/2.jpg"},
	{"id": "silverwolf", "name": "你好，世界！", "file": "res://assets/images/wallpaper/3.jpg"},
	{"id": "summer", "name": "夏日闲情", "file": "res://assets/images/wallpaper/4.jpg"},
	{"id": "battlefiled", "name": "雪地幽灵", "file": "res://assets/images/wallpaper/5.jpg"},
	{"id": "home", "name": "幸福宅女", "file": "res://assets/images/wallpaper/6.jpg"},
	{"id": "minecraft", "name": "异界冒险", "file": "res://assets/images/wallpaper/7.jpg"},
]

const CUSTOM_WALLPAPER_DIR = "user://wallpapers/"
const TARGET_HEIGHT = 200
const ITEM_WIDTH = 140
const ITEM_HEIGHT=80

var current_wallpaper_id: String = "none"

var _blue_theme: Theme = null
var _green_theme: Theme = null
var _red_theme: Theme = null

# 记录处于"删除模式"的自定义壁纸 id -> 复位 timer
var _delete_mode: Dictionary = {}

@onready var builtin_container: HBoxContainer = $PanelContainer/VBox/ScrollContainer/BuiltinContainer
@onready var custom_container: HBoxContainer = $PanelContainer/VBox/CustomScroll/CustomContainer
@onready var upload_button: Button = $PanelContainer/VBox/UploadButton
@onready var close_button: Button = $PanelContainer/VBox/TopBar/CloseButton

func _ready():
	_blue_theme = load("res://theme/blue_button.tres")
	_green_theme = load("res://theme/green_button.tres")
	_red_theme = load("res://theme/red_button.tres")
	close_button.pressed.connect(_on_close)
	upload_button.pressed.connect(_on_upload_pressed)
	_ensure_custom_dir()

func open_panel(current_id: String):
	current_wallpaper_id = current_id
	_refresh_builtin_list()
	_refresh_custom_list()
	visible = true

func _ensure_custom_dir():
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("wallpapers"):
		dir.make_dir("wallpapers")

# ── 内置壁纸 ──────────────────────────────────────────────

func _refresh_builtin_list():
	for c in builtin_container.get_children():
		c.queue_free()
	for wp in BUILTIN_WALLPAPERS:
		builtin_container.add_child(_make_item(wp["name"], wp["id"], wp["file"], false))

# ── 自定义壁纸 ────────────────────────────────────────────

func _refresh_custom_list():
	for c in custom_container.get_children():
		c.queue_free()
	var dir = DirAccess.open(CUSTOM_WALLPAPER_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".png") or fname.ends_with(".jpg")):
			var wp_id = "custom_" + fname.get_basename()
			custom_container.add_child(_make_item(fname.get_basename(), wp_id, CUSTOM_WALLPAPER_DIR + fname, true))
		fname = dir.get_next()
	dir.list_dir_end()

# ── 壁纸条目（固定宽度）──────────────────────────────────

func _make_item(label: String, wp_id: String, file_path: String, is_custom: bool) -> Control:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(ITEM_WIDTH, 0)
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# 预览图
	var preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(ITEM_WIDTH, ITEM_HEIGHT)
	preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if file_path != "":
		if is_custom:
			var img = Image.new()
			if img.load(file_path) == OK:
				preview.texture = ImageTexture.create_from_image(img)
		else:
			if ResourceLoader.exists(file_path):
				preview.texture = load(file_path)

	# 名称
	var name_label = Label.new()
	name_label.text = label
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.clip_text=true
	name_label.custom_minimum_size = Vector2(ITEM_WIDTH, 0)

	# 选择/删除按钮
	var is_selected = (wp_id == current_wallpaper_id)
	var in_delete_mode = is_custom and _delete_mode.has(wp_id)
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(ITEM_WIDTH, 0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	if in_delete_mode:
		btn.text = "🗑 删除"
		if _red_theme:
			btn.theme = _red_theme
		btn.pressed.connect(_on_delete_pressed.bind(wp_id, file_path))
	elif is_selected:
		btn.text = "✓ 已选"
		if _green_theme:
			btn.theme = _green_theme
		if is_custom:
			btn.pressed.connect(_enter_delete_mode.bind(wp_id))
	else:
		btn.text = "选择"
		if _blue_theme:
			btn.theme = _blue_theme
		btn.pressed.connect(_on_select_wallpaper.bind(wp_id))

	vbox.add_child(preview)
	vbox.add_child(name_label)
	vbox.add_child(btn)
	return vbox

# ── 选择 ──────────────────────────────────────────────────

func _on_select_wallpaper(wp_id: String):
	current_wallpaper_id = wp_id
	wallpaper_changed.emit(wp_id)
	_refresh_builtin_list()
	_refresh_custom_list()

# ── 删除模式（仅自定义壁纸）──────────────────────────────

func _enter_delete_mode(wp_id: String):
	# 取消已有的复位 timer
	if _delete_mode.has(wp_id):
		var old_timer = _delete_mode[wp_id]
		if is_instance_valid(old_timer):
			old_timer.stop()
			old_timer.queue_free()

	# 创建 2 秒复位 Timer 节点
	var timer = Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	add_child(timer)
	_delete_mode[wp_id] = timer
	timer.timeout.connect(_exit_delete_mode.bind(wp_id))
	timer.start()

	_refresh_custom_list()

func _exit_delete_mode(wp_id: String):
	if _delete_mode.has(wp_id):
		var t = _delete_mode[wp_id]
		if is_instance_valid(t):
			t.queue_free()
		_delete_mode.erase(wp_id)
	_refresh_custom_list()

func _on_delete_pressed(wp_id: String, file_path: String):
	# 取消复位 timer
	if _delete_mode.has(wp_id):
		var t = _delete_mode[wp_id]
		if is_instance_valid(t):
			t.stop()
			t.queue_free()
		_delete_mode.erase(wp_id)

	# 弹出确认对话框
	var dialog = ConfirmationDialog.new()
	dialog.title = "删除壁纸"
	dialog.dialog_text = "确定要删除这张壁纸吗？"
	dialog.ok_button_text = "删除"
	dialog.cancel_button_text = "取消"
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(_do_delete.bind(wp_id, file_path, dialog))
	dialog.canceled.connect(_on_delete_canceled.bind(wp_id, dialog))

func _on_delete_canceled(wp_id: String, dialog: ConfirmationDialog):
	dialog.queue_free()
	_exit_delete_mode(wp_id)

func _do_delete(wp_id: String, file_path: String, dialog: ConfirmationDialog):
	dialog.queue_free()
	# 删除文件
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
	# 如果当前选中的就是被删除的，切回空白
	if current_wallpaper_id == wp_id:
		_on_select_wallpaper("none")
	else:
		_refresh_custom_list()

# ── 上传（系统文件管理器）────────────────────────────────

func _on_upload_pressed():
	if OS.get_name() == "Android":
		_upload_android()
	else:
		_upload_desktop()

func _upload_desktop():
	# 使用系统原生文件对话框（异步，结果通过回调返回）
	DisplayServer.file_dialog_show(
		"选择壁纸图片",
		OS.get_system_dir(OS.SYSTEM_DIR_PICTURES),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		["*.png ; PNG图片", "*.jpg,*.jpeg ; JPEG图片"],
		_on_desktop_file_selected
	)

func _on_desktop_file_selected(status: bool, selected_paths: PackedStringArray, _filter_idx: int):
	if not status or selected_paths.is_empty():
		return
	_import_image(selected_paths[0])

func _upload_android():
	# Android 权限检查
	var perm = "android.permission.READ_MEDIA_IMAGES"
	var granted = OS.get_granted_permissions()
	if not granted.has(perm) and not granted.has("android.permission.READ_EXTERNAL_STORAGE"):
		OS.request_permissions()
		await get_tree().create_timer(1.5).timeout
	# Android 上用 Godot FileDialog 作为回退
	_open_godot_file_dialog()

func _open_godot_file_dialog():
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = ["*.png,*.jpg,*.jpeg ; 图片文件"]
	dialog.title = "选择壁纸图片"
	add_child(dialog)
	dialog.popup_centered(Vector2(600, 400))
	dialog.file_selected.connect(_import_image)
	dialog.canceled.connect(dialog.queue_free)

# ── 图片导入处理 ──────────────────────────────────────────

func _import_image(path: String):
	var img = Image.new()
	if img.load(path) != OK:
		push_error("WallpaperPanel: 无法加载图片 " + path)
		return
	# 压缩到高度 TARGET_HEIGHT，维持比例
	var orig_w = img.get_width()
	var orig_h = img.get_height()
	if orig_h > TARGET_HEIGHT:
		var new_w = int(orig_w * TARGET_HEIGHT / float(orig_h))
		img.resize(new_w, TARGET_HEIGHT, Image.INTERPOLATE_LANCZOS)
	_ensure_custom_dir()
	var base_name = path.get_file().get_basename()
	var save_path = CUSTOM_WALLPAPER_DIR + base_name + ".png"
	img.save_png(save_path)
	_on_select_wallpaper("custom_" + base_name)

func _on_close():
	visible = false
	panel_closed.emit()
