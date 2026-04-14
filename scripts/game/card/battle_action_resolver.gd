## 战斗行为结算器
## 负责处理战斗中的所有行为结算逻辑
extends RefCounted

const CardDataClass = preload("res://scripts/game/card/card_data.gd")

# 引用战斗场景
var _battle_scene: Control

func _init(battle_scene: Control):
	_battle_scene = battle_scene

# ========== 效果系统 ==========

func add_effect(target_index: int, is_player: bool, effect):
	"""添加效果到目标单位"""
	var effects_array = _get_effects_array(target_index, is_player)
	effects_array.append(effect)
	effect.on_apply()

func trigger_turn_start_effects(target_index: int, is_player: bool):
	"""触发回合开始效果"""
	var effects_array = _get_effects_array(target_index, is_player)
	var to_remove = []
	
	for i in range(effects_array.size()):
		var effect = effects_array[i]
		effect.on_turn_start()
		
		# 检查效果是否过期
		if effect.duration == 0:
			to_remove.append(i)
	
	# 移除过期效果（从后往前删除）
	for i in range(to_remove.size() - 1, -1, -1):
		var effect = effects_array[to_remove[i]]
		effect.on_remove()
		effects_array.remove_at(to_remove[i])

func trigger_before_damage(target_index: int, is_player: bool, damage: int) -> int:
	"""触发受伤前效果"""
	var effects_array = _get_effects_array(target_index, is_player)
	var modified_damage = damage
	
	for effect in effects_array:
		modified_damage = effect.on_before_damage(modified_damage)
	
	return modified_damage

func trigger_after_damage(target_index: int, is_player: bool, damage: int):
	"""触发受伤后效果"""
	var effects_array = _get_effects_array(target_index, is_player)
	
	for effect in effects_array:
		effect.on_after_damage(damage)

func trigger_before_deal_damage(attacker_index: int, is_player: bool, damage: int) -> int:
	"""触发攻击前效果"""
	var effects_array = _get_effects_array(attacker_index, is_player)
	var modified_damage = damage
	
	for effect in effects_array:
		modified_damage = effect.on_before_deal_damage(modified_damage)
	
	return modified_damage

func trigger_after_deal_damage(_attacker_index: int, _is_player: bool, _damage: int):
	"""触发攻击后效果"""
	# 可以在这里添加攻击后触发的效果
	pass

func cleanup_expired_effects(target_index: int, is_player: bool):
	"""清理过期效果"""
	var effects_array = _get_effects_array(target_index, is_player)
	var to_remove = []
	
	for i in range(effects_array.size()):
		if effects_array[i].duration == 0:
			to_remove.append(i)
	
	# 从后往前删除
	for i in range(to_remove.size() - 1, -1, -1):
		var effect = effects_array[to_remove[i]]
		effect.on_remove()
		effects_array.remove_at(to_remove[i])

# ========== 伤害系统 ==========

func deal_damage_to_player(target: int, damage: int):
	"""对玩家角色造成伤害"""
	# 触发受伤前效果
	var actual_damage = trigger_before_damage(target, true, damage)
	
	_battle_scene._player_hp[target] -= actual_damage
	if _battle_scene._player_hp[target] < 0:
		_battle_scene._player_hp[target] = 0
	
	# 触发受伤后效果
	trigger_after_damage(target, true, actual_damage)
	
	# 显示伤害数字
	if actual_damage > 0:
		_show_damage_number(target, actual_damage, true)
	
	# 清理过期效果
	cleanup_expired_effects(target, true)

func deal_damage_to_enemy(target: int, damage: int):
	"""对敌人造成伤害"""
	# 触发受伤前效果
	var actual_damage = trigger_before_damage(target, false, damage)
	
	_battle_scene._enemy_hp[target] -= actual_damage
	if _battle_scene._enemy_hp[target] < 0:
		_battle_scene._enemy_hp[target] = 0
	
	# 触发受伤后效果
	trigger_after_damage(target, false, actual_damage)
	
	# 显示伤害数字
	if actual_damage > 0:
		_show_damage_number(target, actual_damage, false)
	
	# 清理过期效果
	cleanup_expired_effects(target, false)

func _show_damage_number(target: int, damage: int, is_player: bool):
	"""显示伤害数字动画"""
	# 创建伤害数字标签
	var damage_label = Label.new()
	damage_label.text = "-" + str(damage)
	damage_label.add_theme_font_size_override("font_size", 24)
	damage_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	damage_label.z_index = 100
	
	# 获取目标位置
	var area = _battle_scene.player_area if is_player else _battle_scene.enemy_area
	if target < area.get_child_count():
		var target_node = area.get_child(target)
		var pos = target_node.global_position + Vector2(60, 40)
		damage_label.global_position = pos
		_battle_scene.add_child(damage_label)
		
		# 动画效果
		var tween = _battle_scene.create_tween()
		tween.set_parallel(true)
		tween.tween_property(damage_label, "global_position:y", pos.y - 50, 0.8)
		tween.tween_property(damage_label, "modulate:a", 0.0, 0.8)
		tween.finished.connect(damage_label.queue_free)

# ========== 辅助方法 ==========

func _get_effects_array(target_index: int, is_player: bool) -> Array:
	"""获取目标单位的效果数组"""
	return _battle_scene._player_effects[target_index] if is_player else _battle_scene._enemy_effects[target_index]
