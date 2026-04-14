## 治愈之光手牌行为
class_name HealAction
extends CardActionBase

func get_target_type() -> int:
	return 1  # 需要己方单位

func can_use(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	if player_unit_index >= 0:
		var hp = battle_scene._player_hp[player_unit_index]
		var max_hp = battle_scene._player_characters[player_unit_index].defense
		return hp > 0 and hp < max_hp
	return true

func execute(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	if player_unit_index < 0:
		return false
	
	var heal_amount = 2
	var max_hp = battle_scene._player_characters[player_unit_index].defense
	var old_hp = battle_scene._player_hp[player_unit_index]
	
	battle_scene._player_hp[player_unit_index] = min(old_hp + heal_amount, max_hp)
	var actual_heal = battle_scene._player_hp[player_unit_index] - old_hp
	
	var target_name = battle_scene._player_characters[player_unit_index].card_name
	battle_scene._update_info(target_name + " 恢复了 " + str(actual_heal) + " 点生命!")
	
	return true

func get_hint_text(player_unit_index: int = -1) -> String:
	return "选择己方角色"
