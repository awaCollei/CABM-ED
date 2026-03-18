extends Node

# 人物设定加载器 - 通用组件，负责加载和管理人物设定
# 自动加载单例

signal identity_reloaded()

var current_identity: String = ""
var current_relationship: String = ""

func _ready():
	load_identity()

func load_identity():
	"""加载人物设定，优先从存档，失败则使用默认配置"""
	var save_mgr = get_node_or_null("/root/SaveManager")
	if not save_mgr:
		push_error("CharacterIdentityLoader: SaveManager未加载")
		_load_default_identity()
		return
	
	# 尝试从存档加载
	if save_mgr.save_data.has("character_identity"):
		var identity_data = save_mgr.save_data.character_identity
		current_identity = identity_data.get("identity", "")
		current_relationship = identity_data.get("relationship", "")
		
		if not current_identity.is_empty():
			print("CharacterIdentityLoader: 从存档加载人物设定成功")
			return
	
	# 如果存档中没有，使用默认配置并保存
	print("CharacterIdentityLoader: 存档中无人物设定，使用默认配置")
	_load_default_identity()
	save_identity()

func _load_default_identity():
	"""加载默认人物设定"""
	var preset = load_preset("default")
	if preset:
		current_identity = preset.identity
		current_relationship = preset.relationship
	else:
		MessageDisplay.show_failure_message("加载预设人物设定失败，请向开发者反馈此问题")
	print("CharacterIdentityLoader: 加载默认人物设定")

func save_identity():
	"""保存当前人物设定到存档"""
	var save_mgr = get_node_or_null("/root/SaveManager")
	if not save_mgr:
		push_error("CharacterIdentityLoader: SaveManager未加载")
		return
	
	save_mgr.save_data.character_identity = {
		"identity": current_identity,
		"relationship": current_relationship
	}
	
	# 只有在初始设置完成后才保存
	if save_mgr.is_initial_setup_completed:
		save_mgr.save_game()
		print("CharacterIdentityLoader: 人物设定已保存")

func set_identity(identity: String, relationship: String):
	"""设置人物设定"""
	current_identity = identity
	current_relationship = relationship
	save_identity()
	identity_reloaded.emit()
	print("CharacterIdentityLoader: 人物设定已更新")

func get_identity() -> String:
	"""获取当前人物设定（不含固定后缀）"""
	return current_identity

func get_full_identity(user_address: String, character_prompt: String) -> String:
	"""获取完整的人物设定（包含固定后缀）
	
	Args:
		user_address: 用户称呼
		character_prompt: 角色提示词
	
	Returns:
		完整的identity文本
	"""
	var full_identity = current_identity
	
	# 添加固定后缀
	if not user_address.is_empty():
		full_identity += "你习惯称呼他为\"%s\"。" % user_address
	
	if not character_prompt.is_empty():
		full_identity += character_prompt
	
	return full_identity

func get_relationship() -> String:
	"""获取当前初始关系"""
	return current_relationship

func reload():
	"""重新加载人物设定"""
	load_identity()
	identity_reloaded.emit()
	print("CharacterIdentityLoader: 人物设定已重新加载")

func load_preset(preset_id: String) -> Dictionary:
	"""加载预设模板
	
	Returns:
		{
			"identity": String,
			"relationship": String
		}
	"""
	var config_path = "res://config/character_presets.json"
	if not FileAccess.file_exists(config_path):
		push_error("CharacterIdentityLoader: 预设配置文件不存在")
		return {}
	
	var file = FileAccess.open(config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		push_error("CharacterIdentityLoader: 预设配置解析失败")
		return {}
	
	var config = json.data
	if not config.has("presets"):
		return {}
	
	for preset in config.presets:
		if preset.id == preset_id:
			return {
				"identity": preset.identity,
				"relationship": preset.relationship
			}
	
	return {}

func get_all_presets() -> Array:
	"""获取所有预设模板列表
	
	Returns:
		Array of {id: String, name: String}
	"""
	var config_path = "res://config/character_presets.json"
	if not FileAccess.file_exists(config_path):
		return []
	
	var file = FileAccess.open(config_path, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return []
	
	var config = json.data
	if not config.has("presets"):
		return []
	
	var result = []
	for preset in config.presets:
		result.append({
			"id": preset.id,
			"name": preset.name
		})
	
	return result

func validate_identity(identity: String, user_name: String, character_name: String) -> Dictionary:
	"""验证人物设定是否包含玩家名和角色名
	
	Returns:
		{
			"valid": bool,
			"message": String
		}
	"""
	var has_user_name = identity.contains(user_name)
	var has_character_name = identity.contains(character_name)
	
	if not has_user_name and not has_character_name:
		return {
			"valid": false,
			"message": "警告：人物设定中未包含玩家名和角色名"
		}
	elif not has_user_name:
		return {
			"valid": false,
			"message": "警告：人物设定中未包含玩家名"
		}
	elif not has_character_name:
		return {
			"valid": false,
			"message": "警告：人物设定中未包含角色名"
		}
	
	return {
		"valid": true,
		"message": ""
	}
