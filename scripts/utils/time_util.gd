# time_util.gd - 时间戳工具组件
extends Node

# 时段定义（闭区间处理，边界重叠时取前者）
const TIME_PERIODS = {
	"凌晨": [3, 6],    # 3:00 - 5:59（含边界处理）
	"早晨": [6, 8],    # 6:00 - 7:59
	"上午": [8, 11],   # 8:00 - 10:59
	"中午": [11, 13],  # 11:00 - 12:59
	"下午": [13, 17],  # 13:00 - 16:59
	"傍晚": [17, 19],  # 17:00 - 18:59
	"晚上": [19, 22],  # 19:00 - 21:59
	"夜里": [22, 3]    # 22:00 - 2:59（跨天）
}

# 获取本地时区相对于UTC的偏移（秒）
func get_timezone_offset() -> int:
	"""获取本地时区相对于UTC的偏移（秒）"""
	var local_time = Time.get_datetime_dict_from_system()
	var unix_time = Time.get_unix_time_from_system()
	var utc_time = Time.get_datetime_dict_from_unix_time(int(unix_time))

	# 计算小时差
	var hour_diff = local_time.hour - utc_time.hour

	# 处理跨日情况
	if hour_diff > 12:
		hour_diff -= 24
	elif hour_diff < -12:
		hour_diff += 24

	return hour_diff * 3600

# 将 UNIX 时间戳（秒，支持浮点）转换为 ISO 8601 格式（本地时间）
func unix_to_iso(unix_timestamp: float) -> String:
	# 加上时区偏移转换为本地时间
	var local_unix = unix_timestamp + get_timezone_offset()
	var datetime = Time.get_datetime_dict_from_system(local_unix)
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

# 将 ISO 8601 字符串（无时区，本地时间）转换为 UNIX 时间戳（秒，浮点）
func iso_to_unix(iso_string: String) -> float:
	var datetime = iso_string_to_dict(iso_string)
	# 先转换为 UTC 时间戳，再减去时区偏移
	var local_unix = Time.get_unix_time_from_datetime_dict(datetime)
	return local_unix - get_timezone_offset()

# 根据小时数获取时段名称（兼容跨天）
func get_time_period(hour: int) -> String:
	for period in TIME_PERIODS:
		var time_range = TIME_PERIODS[period]
		var start = time_range[0]
		var end = time_range[1]
		
		if start < end:  # 正常区间
			if hour >= start and hour < end:
				return period
		else:  # 跨天区间（如夜里 22-3）
			if hour >= start or hour < end:
				return period
	
	return "未知时段"  # 理论上不会执行

# 从 ISO 8601 字符串提取字典（本地时间，忽略时区）
func iso_string_to_dict(iso_string: String) -> Dictionary:
	var parts = iso_string.split("T")
	if parts.size() != 2:
		return {}
	
	var date_parts = parts[0].split("-")
	var time_parts = parts[1].split(":")
	
	if date_parts.size() != 3 or time_parts.size() < 2:
		return {}
	
	return {
		"year": int(date_parts[0]),
		"month": int(date_parts[1]),
		"day": int(date_parts[2]),
		"hour": int(time_parts[0]),
		"minute": int(time_parts[1]),
		"second": int(time_parts[2]) if time_parts.size() > 2 else 0
	}

# 获取输入时间戳的日期字典（兼容 UNIX 和 ISO 8601，返回本地时间）
func get_datetime_dict(timestamp) -> Dictionary:
	if typeof(timestamp) == TYPE_FLOAT or typeof(timestamp) == TYPE_INT:
		var local_unix = float(timestamp) + get_timezone_offset()
		return Time.get_datetime_dict_from_system(local_unix)
	elif typeof(timestamp) == TYPE_STRING:
		return iso_string_to_dict(timestamp)
	else:
		return {}

# 获取输入时间戳的 UNIX 时间（兼容 UNIX 和 ISO 8601，返回 UTC 时间戳）
func get_unix_time(timestamp) -> float:
	if typeof(timestamp) == TYPE_FLOAT or typeof(timestamp) == TYPE_INT:
		return float(timestamp)
	elif typeof(timestamp) == TYPE_STRING:
		return iso_to_unix(timestamp)
	else:
		return 0.0

# 将时间戳转换为自然语言描述（兼容两种格式）
func to_natural_description(timestamp) -> String:
	var target_unix = get_unix_time(timestamp)  # UTC 时间戳
	var target_dict = get_datetime_dict(timestamp)  # 本地时间字典
	var now_unix = Time.get_unix_time_from_system()  # 系统当前 UTC 时间戳
	var now_dict = Time.get_datetime_dict_from_system(now_unix + get_timezone_offset())  # 当前本地时间
	
	var diff = target_unix - now_unix
	
	# 1. 未来时间
	if diff > 0:
		return "以后"
	
	var abs_diff = -diff  # 正数表示过去了多久
	
	# 2. < 1分钟
	if abs_diff < 60:
		return "刚刚"
	
	# 3. < 1小时
	if abs_diff < 3600:
		var minutes = int(abs_diff / 60)
		return "%d分钟前" % minutes
	
	# 4. < 6小时
	if abs_diff < 21600:
		var hours = int(abs_diff / 3600)
		return "%d小时前" % hours
	
	# 5. 今天
	if is_same_day(target_dict, now_dict):
		return "今天%d点" % target_dict.hour
	
	# 6. 昨天
	if is_yesterday(target_dict, now_dict):
		return "昨天%d点" % target_dict.hour
	
	# 7. <= 30天前
	var days_diff = get_days_diff(target_dict, now_dict)
	if days_diff <= 30:
		var period = get_time_period(target_dict.hour)
		return "%d天前%s" % [days_diff, ("%s" % period) if period else ""]
	
	# 8. < 6个月
	var months_diff = get_months_diff(target_dict, now_dict)
	if months_diff < 6:
		return "%d个月前" % months_diff
	
	# 9. 去年
	if target_dict.year == now_dict.year - 1 and months_diff < 12:
		return "去年"
	
	# 10. < 12个月
	if months_diff < 12:
		return "%d个月前" % months_diff
	
	# 11. 其他情况：xx年前
	var years_diff = now_dict.year - target_dict.year
	return "%d年前" % years_diff

# 将时间戳转换为提示词用的"相对时间前缀"
# 例如："[3小时前]"、"[刚刚]"、"[昨天9点]"
func to_relative_time_prefix(timestamp) -> String:
	var desc = to_natural_description(timestamp)
	return "[%s]" % desc

# 辅助：判断是否为同一天
func is_same_day(dict1: Dictionary, dict2: Dictionary) -> bool:
	return dict1.year == dict2.year and dict1.month == dict2.month and dict1.day == dict2.day

# 辅助：判断是否为昨天
func is_yesterday(dict1: Dictionary, dict2: Dictionary) -> bool:
	return get_days_diff(dict1, dict2) == 1

# 辅助：计算两个日期相差的天数
func get_days_diff(dict1: Dictionary, dict2: Dictionary) -> int:
	var d1 = dict1.duplicate()
	var d2 = dict2.duplicate()
	
	# 归一化到当天 00:00:00
	d1.hour = 0
	d1.minute = 0
	d1.second = 0
	
	d2.hour = 0
	d2.minute = 0
	d2.second = 0
	
	var ts1 = Time.get_unix_time_from_datetime_dict(d1)
	var ts2 = Time.get_unix_time_from_datetime_dict(d2)
	
	return int(abs(ts2 - ts1) / 86400)

# 辅助：计算两个日期相差的月数（粗略，基于年份和月份差值）
func get_months_diff(dict1: Dictionary, dict2: Dictionary) -> int:
	var months = (dict2.year - dict1.year) * 12 + (dict2.month - dict1.month)
	return abs(months)