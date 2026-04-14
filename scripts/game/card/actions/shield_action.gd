## 铁壁防御手牌行为
class_name ShieldAction
extends CardActionBase

func get_target_type() -> int:
	return 1  # 需要己方单位

func can_use(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	if player_unit_index >= 0:
		var hp = battle_scene._player_hp[player_unit_index]
		return hp > 0
	return true

func execute(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	if player_unit_index < 0:
		return false
	
	# 添加铁壁防御效果
	var shield_effect = preload("res://scripts/game/card/effects/shield_effect.gd").new(battle_scene)
	shield_effect.target_index = player_unit_index
	shield_effect.is_player_unit = true
	shield_effect.value = 2  # 每层抵挡2点伤害
	shield_effect.duration = -1  # 永久直到消耗完
	
	battle_scene._add_effect(player_unit_index, true, shield_effect)
	
	var target_name = battle_scene._player_characters[player_unit_index].card_name
	battle_scene._update_info(target_name + " 获得了【铁壁防御】!")
	
	return true

func get_hint_text(player_unit_index: int = -1) -> String:
	return "选择己方角色"
