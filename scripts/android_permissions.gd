extends Node

# Android 权限与图片选择统一管理
# 供需要「选择图片」的界面使用：先请求存储权限，再打开 FileDialog；
# 若选择结果为 content:// URI，需立即复制到 user:// 再使用，本脚本提供复制接口。

func request_storage_permission() -> bool:
	"""请求存储权限"""
	if OS.get_name() != "Android":
		# 非Android平台，直接返回true
		return true
	
	# 检查是否已有权限
	if check_storage_permission():
		print("已有存储权限")
		return true
	
	# 请求权限（Godot 4.x中OS.request_permissions()不接受参数）
	# 权限需要在export_presets.cfg中配置
	print("请求存储权限...")
	OS.request_permissions()
	
	# 等待权限结果
	await get_tree().create_timer(1.0).timeout
	
	# 再次检查权限
	var has_permission = check_storage_permission()
	if has_permission:
		print("存储权限已授予")
	else:
		print("存储权限未授予")
	
	return has_permission

func check_storage_permission() -> bool:
	"""检查是否有存储权限"""
	if OS.get_name() != "Android":
		return true
	
	var granted_perms = OS.get_granted_permissions()
	print("已授予的权限: ", granted_perms)
	
	# 检查是否有任何存储相关权限
	var has_read = granted_perms.has("android.permission.READ_EXTERNAL_STORAGE")
	var has_write = granted_perms.has("android.permission.WRITE_EXTERNAL_STORAGE")
	var has_manage = granted_perms.has("android.permission.MANAGE_EXTERNAL_STORAGE")
	
	return has_read or has_write or has_manage

func copy_content_uri_to_user_file(uri: String, user_path: String) -> bool:
	"""将 Android content:// URI 指向的文件复制到 user_path。返回是否成功。"""
	if OS.get_name() != "Android" or not uri.begins_with("content://"):
		return false
	var src = FileAccess.open(uri, FileAccess.READ)
	if not src:
		return false
	var data = src.get_buffer(src.get_length())
	src.close()
	if data.is_empty():
		return false
	# 确保父目录存在（支持多级，如 user://story/background/）
	var parts = user_path.replace("user://", "").split("/")
	var parent = "user://"
	for i in range(parts.size() - 1):
		var seg = parts[i]
		if seg.is_empty():
			continue
		var da = DirAccess.open(parent)
		if da and not da.dir_exists(seg):
			da.make_dir(seg)
		parent = parent + seg + "/"
	var dst = FileAccess.open(user_path, FileAccess.WRITE)
	if not dst:
		return false
	dst.store_buffer(data)
	dst.close()
	return FileAccess.file_exists(user_path)
