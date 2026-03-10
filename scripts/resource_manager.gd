extends Node

# 资源管理器 - 自动加载单例
# 负责统一管理游戏初始资源的转移和解压

signal progress_updated(percent: float, current_item: String)
signal transfer_completed()
signal transfer_failed(error: String)

const RESOURCE_CONFIG_PATH = "res://config/resources.json"
const RESOURCE_LIST_PATH = "user://ResourceList.json"
const OLD_FILE_LIST_PATH = "user://FileList.txt"  # 旧版本兼容

var is_transferring: bool = false
var current_progress: float = 0.0

func transfer_all_resources():
	"""同步转移所有需要转移的资源（不推荐在主线程调用）"""
	_do_transfer_all()

func transfer_all_resources_async():
	"""异步转移所有需要转移的资源"""
	if is_transferring:
		return
	
	is_transferring = true
	current_progress = 0.0
	
	# 使用线程池执行转移
	WorkerThreadPool.add_task(_do_transfer_all_async)

func _do_transfer_all_async():
	var success = _do_transfer_all(true)
	is_transferring = false
	if success:
		transfer_completed.emit.call_deferred()
	else:
		transfer_failed.emit.call_deferred("资源转移过程中发生错误")

func _do_transfer_all(is_async: bool = false) -> bool:
	"""执行转移逻辑"""
	# 加载资源配置
	if not FileAccess.file_exists(RESOURCE_CONFIG_PATH):
		print("[ResourceManager] 错误: 资源配置文件不存在: ", RESOURCE_CONFIG_PATH)
		if is_async: transfer_failed.emit.call_deferred("配置文件不存在")
		return false
	
	var file = FileAccess.open(RESOURCE_CONFIG_PATH, FileAccess.READ)
	if not file:
		print("[ResourceManager] 错误: 无法打开资源配置文件")
		if is_async: transfer_failed.emit.call_deferred("无法打开配置文件")
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		print("[ResourceManager] 错误: 资源配置文件格式错误: ", json.get_error_message())
		if is_async: transfer_failed.emit.call_deferred("配置文件格式错误")
		return false
	
	var resource_config = json.data
	var resources = resource_config.get("resources", [])
	
	if resources.is_empty():
		print("[ResourceManager] 没有需要转移的资源")
		if is_async: progress_updated.emit.call_deferred(100.0, "完成")
		return true

	# 计算需要转移的资源总量
	var resources_to_transfer = []
	for resource in resources:
		if should_transfer_resource(resource):
			resources_to_transfer.append(resource)
	
	if resources_to_transfer.is_empty():
		print("[ResourceManager] 所有资源已是最新")
		if is_async: progress_updated.emit.call_deferred(100.0, "已就绪")
		return true

	var total_count = resources_to_transfer.size()
	var all_success = true
	
	for i in range(total_count):
		var resource = resources_to_transfer[i]
		var resource_id = resource.get("id", "未知")
		
		var progress_base = (float(i) / total_count) * 100.0
		var progress_weight = (1.0 / total_count) * 100.0
		
		if is_async:
			progress_updated.emit.call_deferred(progress_base, "正在准备: " + resource_id)
		
		if not _transfer_resource(resource, is_async, progress_base, progress_weight):
			all_success = false
	
	if is_async:
		progress_updated.emit.call_deferred(100.0, "完成")
	
	return all_success

func should_transfer_resource(resource: Dictionary) -> bool:
	"""检查资源是否需要转移或更新
	
	参数:
		resource: 资源配置字典
	
	返回:
		true表示需要转移，false表示已是最新版本
	"""
	var resource_id = resource.get("id", "")
	var config_version = resource.get("version", "1.0.0")
	
	if resource_id.is_empty():
		return false
	
	# 加载已安装资源列表
	var installed_resources = _load_resource_list()
	
	# 检查资源是否已安装
	if not installed_resources.has(resource_id):
		# print("[ResourceManager] 资源未安装: ", resource_id)
		return true
	
	# 检查版本
	var installed_version = installed_resources[resource_id]
	if _compare_versions(installed_version, config_version) < 0:
		# print("[ResourceManager] 发现更高版本: ", resource_id, " (", installed_version, " -> ", config_version, ")")
		return true
	
	# print("[ResourceManager] 资源已是最新版本，跳过: ", resource_id, " (", installed_version, ")")
	return false

func _transfer_resource(resource: Dictionary, is_async: bool = false, base: float = 0.0, weight: float = 0.0) -> bool:
	"""转移单个资源
	
	参数:
		resource: 资源配置字典
		is_async: 是否异步
		base: 基础进度
		weight: 进度权重
	
	返回:
		true表示成功，false表示失败
	"""
	var resource_id = resource.get("id", "")
	var resource_type = resource.get("type", "")
	var source = resource.get("source", "")
	var destination = resource.get("destination", "")
	
	if resource_id.is_empty() or source.is_empty() or destination.is_empty():
		print("[ResourceManager] 错误: 资源配置不完整: ", resource_id)
		return false
	
	print("[ResourceManager] 开始转移资源: ", resource_id, " (", resource.get("description", ""), ")")
	
	# 确保目标目录存在
	_ensure_directory(destination)
	
	# 根据资源类型执行不同的转移操作
	var success = false
	match resource_type:
		"archive":
			success = _transfer_archive(resource, is_async, base, weight)
		"file":
			success = _transfer_file(resource)
		"directory":
			success = _transfer_directory(resource)
		_:
			print("[ResourceManager] 错误: 不支持的资源类型: ", resource_type)
			return false
	
	# 更新ResourceList.json
	if success:
		_update_resource_list(resource_id, resource.get("version", "1.0.0"))
		print("[ResourceManager] ✓ 资源转移完成: ", resource_id)
	else:
		print("[ResourceManager] ✗ 资源转移失败: ", resource_id)
	
	return success

func _transfer_archive(resource: Dictionary, is_async: bool = false, base: float = 0.0, weight: float = 0.0) -> bool:
	"""转移并解压压缩包资源
	
	参数:
		resource: 资源配置字典
		is_async: 是否异步
		base: 基础进度
		weight: 进度权重
	
	返回:
		true表示成功，false表示失败
	"""
	var source = resource.get("source", "")
	var destination = resource.get("destination", "")
	var supported_extensions = resource.get("supported_extensions", [])
	var expected_id = resource.get("id", "")
	
	if not ResourceLoader.exists(source) and not FileAccess.file_exists(source):
		print("[ResourceManager] 错误: 压缩包不存在: ", source)
		return false
	
	var zip = ZIPReader.new()
	var err = zip.open(source)
	
	if err != OK:
		print("[ResourceManager] 错误: 无法打开压缩包: ", source, " 错误代码: ", err)
		return false

	# 检查version.txt进行校验
	if zip.file_exists("version.txt"):
		var version_content = zip.read_file("version.txt").get_string_from_utf8()
		var lines = version_content.split("\n")
		if lines.size() >= 2:
			var pkg_id = lines[0].strip_edges()
			var pkg_version = lines[1].strip_edges()
			
			if pkg_id != expected_id:
				print("[ResourceManager] 错误: 资源ID不匹配 (期望: ", expected_id, ", 实际: ", pkg_id, ")")
				zip.close()
				return false
			
			# 更新资源版本，以便后续保存
			resource["version"] = pkg_version
	
	var files = zip.get_files()
	var total_files = files.size()
	var extracted_count = 0
	
	# 缓存已创建的目录，避免重复系统调用
	var created_dirs = {}
	
	for i in range(total_files):
		var file_path = files[i]
		# 跳过目录条目
		if file_path.ends_with("/"):
			continue
		
		# 如果指定了支持的扩展名，则过滤
		if not supported_extensions.is_empty():
			var ext = file_path.get_extension().to_lower()
			if not ext in supported_extensions:
				continue
		
		# 读取文件内容
		var content = zip.read_file(file_path)
		if content.size() == 0:
			continue
		
		# 保留目录结构
		var full_dest_path = destination.path_join(file_path)
		
		# 确保父目录存在 (使用缓存优化)
		var parent_dir = full_dest_path.get_base_dir()
		if not created_dirs.has(parent_dir):
			if not DirAccess.dir_exists_absolute(parent_dir):
				DirAccess.make_dir_recursive_absolute(parent_dir)
			created_dirs[parent_dir] = true
		
		# 写入文件
		var dest_file = FileAccess.open(full_dest_path, FileAccess.WRITE)
		if dest_file:
			dest_file.store_buffer(content)
			dest_file.close()
			extracted_count += 1
		
		# 异步模式下更新细分进度 (每10个文件更新一次，避免过度通信)
		if is_async and i % 10 == 0:
			var sub_percent = (float(i) / total_files) * weight
			progress_updated.emit.call_deferred(base + sub_percent, "正在解压: %s (%d/%d)" % [expected_id, i, total_files])
	
	zip.close()
	return extracted_count > 0

func _transfer_file(resource: Dictionary) -> bool:
	"""转移单个文件资源
	
	参数:
		resource: 资源配置字典
	
	返回:
		true表示成功，false表示失败
	"""
	var source = resource.get("source", "")
	var destination = resource.get("destination", "")
	
	if not FileAccess.file_exists(source):
		print("[ResourceManager] 错误: 源文件不存在: ", source)
		return false
	
	# 使用 DirAccess.copy_absolute 更高效
	var err = DirAccess.copy_absolute(source, destination)
	if err != OK:
		print("[ResourceManager] 错误: 无法复制文件: ", source, " -> ", destination, " 错误码: ", err)
		return false
	
	return true

func _transfer_directory(resource: Dictionary) -> bool:
	"""转移整个目录资源
	
	参数:
		resource: 资源配置字典
	
	返回:
		true表示成功，false表示失败
	"""
	var source = resource.get("source", "")
	var destination = resource.get("destination", "")
	
	# 确保目标目录存在
	_ensure_directory(destination)
	
	# 递归复制目录
	return _copy_directory_recursive(source, destination)

func _copy_directory_recursive(source_dir: String, dest_dir: String, created_dirs: Dictionary = {}) -> bool:
	"""递归复制目录
	
	参数:
		source_dir: 源目录路径
		dest_dir: 目标目录路径
		created_dirs: 已创建目录缓存
	
	返回:
		true表示成功，false表示失败
	"""
	var dir = DirAccess.open(source_dir)
	if not dir:
		print("[ResourceManager] 错误: 无法打开源目录: ", source_dir)
		return false
	
	if not created_dirs.has(dest_dir):
		if not DirAccess.dir_exists_absolute(dest_dir):
			DirAccess.make_dir_recursive_absolute(dest_dir)
		created_dirs[dest_dir] = true
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	var success = true
	while file_name != "":
		if file_name != "." and file_name != "..":
			var source_path = source_dir.path_join(file_name)
			var dest_path = dest_dir.path_join(file_name)
			
			if dir.current_is_dir():
				if not _copy_directory_recursive(source_path, dest_path, created_dirs):
					success = false
			else:
				# 使用 copy_absolute
				var err = DirAccess.copy_absolute(source_path, dest_path)
				if err != OK:
					print("[ResourceManager] 错误: 无法复制文件: ", source_path, " 错误码: ", err)
					success = false
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return success

func _ensure_directory(dir_path: String):
	"""确保目录存在
	
	参数:
		dir_path: 目录路径
	"""
	# 移除末尾的斜杠
	var clean_path = dir_path.rstrip("/")
	
	# 获取基础目录（user:// 或 res://）
	var base_dir = "user://"
	if clean_path.begins_with("res://"):
		base_dir = "res://"
	
	# 移除基础目录前缀
	var relative_path = clean_path.replace(base_dir, "")
	
	# 分割路径
	var parts = relative_path.split("/")
	
	# 逐级创建目录
	var current_path = base_dir
	var dir = DirAccess.open(current_path)
	
	for part in parts:
		if part.is_empty():
			continue
		
		if not dir.dir_exists(part):
			var err = dir.make_dir(part)
			if err != OK:
				print("[ResourceManager] 错误: 无法创建目录: ", current_path + part)
				return
		
		current_path = current_path.path_join(part)
		dir = DirAccess.open(current_path)

func _load_resource_list() -> Dictionary:
	"""加载ResourceList.json
	
	返回:
		资源列表字典，格式: {resource_id: version}
	"""
	if not FileAccess.file_exists(RESOURCE_LIST_PATH):
		return {}
	
	var file = FileAccess.open(RESOURCE_LIST_PATH, FileAccess.READ)
	if not file:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	if json_string.is_empty():
		return {}
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		print("[ResourceManager] 错误: ResourceList.json格式错误")
		return {}
	
	return json.data

func _save_resource_list(resource_list: Dictionary):
	"""保存ResourceList.json
	
	参数:
		resource_list: 资源列表字典
	"""
	var file = FileAccess.open(RESOURCE_LIST_PATH, FileAccess.WRITE)
	if not file:
		print("[ResourceManager] 错误: 无法写入ResourceList.json")
		return
	
	var json_string = JSON.stringify(resource_list, "\t")
	file.store_string(json_string)
	file.close()

func _update_resource_list(resource_id: String, version: String):
	"""更新ResourceList.json，添加或更新资源版本
	
	参数:
		resource_id: 资源ID
		version: 资源版本
	"""
	var resource_list = _load_resource_list()
	resource_list[resource_id] = version
	_save_resource_list(resource_list)
	print("[ResourceManager] ResourceList.json已更新: ", resource_id, " -> ", version)

func _compare_versions(version1: String, version2: String) -> int:
	"""比较两个版本号
	
	参数:
		version1: 版本号1
		version2: 版本号2
	
	返回:
		-1: version1 < version2
		0: version1 == version2
		1: version1 > version2
	"""
	var v1_parts = version1.split(".")
	var v2_parts = version2.split(".")
	
	var max_length = max(v1_parts.size(), v2_parts.size())
	
	for i in range(max_length):
		var v1_num = int(v1_parts[i]) if i < v1_parts.size() else 0
		var v2_num = int(v2_parts[i]) if i < v2_parts.size() else 0
		
		if v1_num < v2_num:
			return -1
		elif v1_num > v2_num:
			return 1
	
	return 0

func get_transferred_resources() -> Dictionary:
	"""获取已转移的资源列表
	
	返回:
		已转移的资源字典，格式: {resource_id: version}
	"""
	return _load_resource_list()

func get_resource_version(resource_id: String) -> String:
	"""获取指定资源的已安装版本
	
	参数:
		resource_id: 资源ID
	
	返回:
		资源版本，如果未安装则返回空字符串
	"""
	var resource_list = _load_resource_list()
	return resource_list.get(resource_id, "")

func import_resource(resource_id: String, file_path: String) -> bool:
	"""导入资源包
	
	参数:
		resource_id: 资源ID
		file_path: 资源包路径
	
	返回:
		true表示成功，false表示失败
	"""
	var file = FileAccess.open(RESOURCE_CONFIG_PATH, FileAccess.READ)
	if not file:
		print("[ResourceManager] 错误: 无法打开资源配置文件")
		return false
	
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		print("[ResourceManager] 错误: 资源配置文件格式错误")
		return false
		
	var resources = json.data.get("resources", [])
	var target_resource = null
	
	for res in resources:
		if res.get("id") == resource_id:
			target_resource = res.duplicate()
			break
			
	if not target_resource:
		print("[ResourceManager] 错误: 未找到资源配置: ", resource_id)
		return false
		
	# 更新源路径
	target_resource["source"] = file_path
	
	# 如果是压缩包，确保类型正确
	var ext = file_path.get_extension().to_lower()
	if ext in ["zip", "pck"]:
		target_resource["type"] = "archive"
	else:
		# 假设是单个文件
		target_resource["type"] = "file"
	
	return _transfer_resource(target_resource)
