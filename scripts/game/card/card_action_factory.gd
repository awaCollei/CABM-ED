## 卡牌行为工厂
class_name CardActionFactory
extends RefCounted

# 根据卡牌ID创建对应的行为实例
static func create_action(card_data: CardData, battle_scene: Node) -> CardActionBase:
	var AttackActionClass = preload("res://scripts/game/card/actions/attack_action.gd")
	var ShieldActionClass = preload("res://scripts/game/card/actions/shield_action.gd")
	var PoisonActionClass = preload("res://scripts/game/card/actions/poison_action.gd")
	var HealActionClass = preload("res://scripts/game/card/actions/heal_action.gd")
	var DrawActionClass = preload("res://scripts/game/card/actions/draw_action.gd")
	
	match card_data.id:
		"attack":
			return AttackActionClass.new(card_data, battle_scene)
		"shield":
			return ShieldActionClass.new(card_data, battle_scene)
		"poison":
			return PoisonActionClass.new(card_data, battle_scene)
		"hand_heal":
			return HealActionClass.new(card_data, battle_scene)
		"draw":
			return DrawActionClass.new(card_data, battle_scene)
		_:
			push_warning("未知的卡牌ID: " + card_data.id)
			return null
