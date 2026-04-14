## 攻击手牌行为
class_name AttackAction
extends CardActionBase

func get_target_type() -> int:
	return 3  # 需要先选己方，再选敌方

func can_use(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	# 检查己方单位是否存活
	if player_unit_index >= 0:
		var hp = battle_scene._player_hp[player_unit_index]
		return hp > 0
	return true

func execute(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	if player_unit_index < 0 or enemy_unit_index < 0:
		return false
	
	# 获取攻击力
	var attacker = battle_scene._player_characters[player_unit_index]
	var damage = attacker.attack
	
	# 触发攻击前效果
	damage = battle_scene._trigger_before_deal_damage(player_unit_index, true, damage)
	
	# 造成伤害
	battle_scene._deal_damage_to_enemy(enemy_unit_index, damage)
	
	# 触发攻击后效果
	battle_scene._trigger_after_deal_damage(player_unit_index, true, damage)
	
	battle_scene._update_info(attacker.card_name + " 攻击了敌人，造成 " + str(damage) + " 点伤害!")
	
	return true

func get_hint_text(player_unit_index: int = -1) -> String:
	if player_unit_index < 0:
		return "选择己方角色"
	else:
		return "选择要攻击的敌人"
