## 剧毒之刃手牌行为
class_name PoisonAction
extends CardActionBase

func get_target_type() -> int:
	return 2  # 需要敌方单位

func can_use(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	if enemy_unit_index >= 0:
		var hp = battle_scene._enemy_hp[enemy_unit_index]
		return hp > 0
	return true

func execute(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	if enemy_unit_index < 0:
		return false
	
	# 添加剧毒效果
	var poison_effect = preload("res://scripts/game/card/effects/poison_effect.gd").new(battle_scene)
	poison_effect.target_index = enemy_unit_index
	poison_effect.is_player_unit = false
	poison_effect.value = 1  # 每回合1点伤害
	poison_effect.duration = 3  # 持续3回合
	
	battle_scene._action_resolver.add_effect(enemy_unit_index, false, poison_effect)
	
	battle_scene._update_info("敌人 " + str(enemy_unit_index + 1) + " 中了【剧毒】!")
	
	return true

func get_hint_text(player_unit_index: int = -1) -> String:
	return "选择敌方单位"
