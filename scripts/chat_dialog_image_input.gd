extends Node

signal image_selected(path: String)
signal image_cleared()

var parent_dialog: Panel
var pic_button: Button
var input_field: LineEdit
var android_permissions # 动态权限管理器

var selected_image_path: String = ""

const ICON_NORMAL = "res://assets/images/chat/image.png"
const ICON_UPLOADING = "res://assets/images/chat/image_upload.png"

func setup(dialog: Panel, pic_btn: Button, input_fld: LineEdit):
	parent_dialog = dialog
	pic_button = pic_btn
	input_field = input_fld
	
	# 使用统一的 Android 权限管理（autoload）
	if OS.has_feature("android"):
		android_permissions = get_node_or_null("/root/AndroidPermissions")

	if pic_button:
		pic_button.pressed.connect(_on_pic_button_pressed)
		_update_button_icon()

func _on_pic_button_pressed():
	if has_selected_image():
		clear_selected_image()
	else:
		_show_file_dialog()

func _show_file_dialog():
	# 在安卓上先请求存储权限
	if OS.has_feature("android") and android_permissions:
		await _request_android_storage_permission()
	
	var file_dialog = FileDialog.new()
	file_dialog.name = "ImagePickerDialog"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp *.PNG, *.JPG, *.JPEG, *.WEBP", "图片")
	file_dialog.use_native_dialog = true  # 关键：启用系统原生选择器
	
	# Android: 设置常见图片目录
	if OS.has_feature("android"):
		var pics_paths = [
			"/storage/emulated/0/Pictures",
			"/storage/emulated/0/DCIM/Camera",
			"/storage/emulated/0/Download",
			"/sdcard/Pictures",
			"/sdcard/DCIM/Camera",
			OS.get_system_dir(OS.SYSTEM_DIR_PICTURES),
			OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		]
		
		for path in pics_paths:
			if path and not path.is_empty() and DirAccess.dir_exists_absolute(path):
				file_dialog.current_dir = path
				print("📸 设置图片选择器路径: ", path)
				break
		
		print("📸 打开图片文件选择器（安卓模式）")
		print("📸 如果看不到图片，请尝试点击左上角菜单切换到其他文件夹")
	else:
		# Desktop only
		var pics_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		if not pics_dir.is_empty():
			file_dialog.current_dir = pics_dir

	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.canceled.connect(file_dialog.queue_free)
	get_tree().root.add_child(file_dialog)
	file_dialog.popup_centered()

# Android 权限请求（统一走 AndroidPermissions autoload）
func _request_android_storage_permission() -> bool:
	if not android_permissions:
		print("⚠️ Android 权限管理器未就绪")
		return true
	var has_permission = await android_permissions.request_storage_permission()
	if not has_permission:
		print("⚠️ 未获得存储权限，可能无法访问图片文件")
	return has_permission

func _on_file_selected(path: String):
	print("📂 Selected: " + path)

	# ⚠️ Android: content:// URI 必须立即同步处理！
	if OS.has_feature("android") and path.begins_with("content://"):
		_process_selected_image_now(path)
	else:
		_process_selected_image_async(path)

# 同步立即复制 content:// URI（Godot 4.0-4.2 关键！），使用统一接口
func _process_selected_image_now(uri: String):
	var temp_path = "user://tmp/selected_image_" + str(Time.get_unix_time_from_system()) + ".jpg"
	var ap = get_node_or_null("/root/AndroidPermissions")
	var final_path := ""
	if ap and ap.copy_content_uri_to_user_file(uri, temp_path):
		if FileAccess.file_exists(temp_path):
			var f = FileAccess.open(temp_path, FileAccess.READ)
			if f and f.get_length() > 0:
				f.close()
				final_path = temp_path
			elif f:
				f.close()
	if final_path.is_empty():
		push_error("❌ Failed to copy URI: " + uri)
		clear_selected_image()
		return
	selected_image_path = final_path
	_update_button_icon()
	image_selected.emit(final_path)
	print("✅ Image ready: " + final_path)

# 异步处理普通路径（file:// 或绝对路径）
func _process_selected_image_async(path: String):
	var final_path = _resolve_normal_path(path)
	if final_path.is_empty():
		clear_selected_image()
		return
	selected_image_path = final_path
	_update_button_icon()
	image_selected.emit(final_path)

func _resolve_normal_path(path: String) -> String:
	if path.begins_with("file://"):
		path = path.replace("file://", "")
	if FileAccess.file_exists(path):
		return path
	MessageDisplay.show_failure_message("文件不存在: " + path)
	push_error("File not found: " + path)
	return ""

# ——— 公共接口 ———
func has_selected_image() -> bool:
	return not selected_image_path.is_empty()

func get_selected_image_path() -> String:
	return selected_image_path

func clear_selected_image():
	selected_image_path = ""
	_update_button_icon()
	image_cleared.emit()

func _update_button_icon():
	if not pic_button: return
	var tex = load(ICON_UPLOADING if has_selected_image() else ICON_NORMAL)
	if tex:
		pic_button.icon = tex
		pic_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func hide_for_history():
	if pic_button: pic_button.visible = false

func show_after_history():
	if pic_button: pic_button.visible = true

func describe_selected_image() -> String:
	if selected_image_path.is_empty(): return ""
	var svc = preload("res://scripts/ai_chat/ai_view_service.gd").new()
	add_child(svc)
	var desc = await svc.describe_image(selected_image_path)
	svc.queue_free()
	return desc
