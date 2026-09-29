extends Node

# 平台管理器 - 统一管理平台检测
# 作为自动加载单例使用

var is_mobile: bool = false
var platform_name: String = ""

# 权限检测结果缓存：只探测一次，避免每次切换风格都起进程。
var _elevated_checked: bool = false
var _elevated: bool = false

func _ready():
	_detect_platform()

func _detect_platform():
	"""检测当前平台"""
	platform_name = OS.get_name()
	is_mobile = platform_name == "Android" or platform_name == "IOS"
	
	print("平台检测: ", platform_name, " | 移动设备: ", is_mobile)

func is_mobile_platform() -> bool:
	"""返回是否为移动平台"""
	return is_mobile

func get_platform_name() -> String:
	"""返回平台名称"""
	return platform_name

func is_android() -> bool:
	"""是否为Android平台"""
	return platform_name == "Android"

func is_ios() -> bool:
	"""是否为iOS平台"""
	return platform_name == "iOS"

func is_windows() -> bool:
	"""是否为Windows平台"""
	return platform_name == "Windows"

func is_macos() -> bool:
	"""是否为macOS平台"""
	return platform_name == "macOS"

func is_linux() -> bool:
	"""是否为Linux平台"""
	return platform_name == "Linux"

func is_web() -> bool:
	"""是否为Web平台"""
	return platform_name == "Web"

func is_elevated() -> bool:
	"""是否以管理员（Windows）或 root（类 Unix）身份运行，结果只探测一次。"""
	if not _elevated_checked:
		_elevated_checked = true
		_elevated = _detect_elevation()
		print("权限检测: 管理员/root = ", _elevated)
	return _elevated

func _detect_elevation() -> bool:
	if is_mobile_platform() or is_web():
		# 移动端与 Web 没有“管理员”概念：Android 的 root 只能靠 su 探测，
		# 既不可靠又会弹授权框，因此一律按普通用户处理。
		return false
	if is_windows():
		# 提权后的进程令牌完整性级别为 High(S-1-16-12288) 或 System(S-1-16-16384)；
		# 未提权时为 Medium，whoami 不会列出该行。SID 不随系统语言变化。
		var output: Array = []
		if OS.execute("whoami", ["/groups"], output) != 0:
			return false
		for line in output:
			if "S-1-16-12288" in line or "S-1-16-16384" in line:
				return true
		return false
	if is_linux() or is_macos():
		return OS.get_environment("USER") == "root" or OS.get_environment("LOGNAME") == "root"
	return false
