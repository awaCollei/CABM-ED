## 铁壁防御效果
class_name ShieldEffect
extends EffectBase

func _init(scene: Node):
	super._init(scene)
	effect_name = "铁壁防御"

func on_before_damage(damage: int) -> int:
	if value > 0:
		var reduced = min(damage, value)
		value -= reduced
		damage -= reduced
		
		var unit_name = ""
		if is_player_unit:
			unit_name = battle_scene._player_characters[target_index].card_name
		else:
			unit_name = "敌人 " + str(target_index + 1)
		
		battle_scene._update_info(unit_name + " 的【铁壁防御】抵挡了 " + str(reduced) + " 点伤害!")
		
		# 如果护盾耗尽，标记为移除
		if value <= 0:
			duration = 0
	
	return damage

func get_display_text() -> String:
	return "🛡️ 铁壁 +" + str(value)

func get_icon() -> String:
	return "🛡️"
