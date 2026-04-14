## 剧毒效果
class_name PoisonEffect
extends EffectBase

func _init(scene: Node):
	super._init(scene)
	effect_name = "剧毒"

func on_turn_start():
	# 在回合开始时造成伤害
	if is_player_unit:
		battle_scene._action_resolver.deal_damage_to_player(target_index, value)
		var unit_name = battle_scene._player_characters[target_index].card_name
		battle_scene._update_info(unit_name + " 受到【剧毒】伤害!")
	else:
		battle_scene._action_resolver.deal_damage_to_enemy(target_index, value)
		battle_scene._update_info("敌人 " + str(target_index + 1) + " 受到【剧毒】伤害!")
	
	# 减少持续时间
	if duration > 0:
		duration -= 1

func get_display_text() -> String:
	return "🧪 剧毒 x" + str(duration)

func get_icon() -> String:
	return "🧪"
