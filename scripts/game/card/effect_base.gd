## 效果基类（buff/debuff）
class_name EffectBase
extends RefCounted

# 效果名称
var effect_name: String = ""

# 效果持续回合数（-1表示永久）
var duration: int = -1

# 效果数值
var value: int = 0

# 战斗场景引用
var battle_scene: Node

# 目标单位索引
var target_index: int = -1
var is_player_unit: bool = true

func _init(scene: Node):
	battle_scene = scene

# 效果应用时触发
func on_apply():
	pass

# 回合开始时触发
func on_turn_start():
	pass

# 回合结束时触发
func on_turn_end():
	pass

# 受到伤害前触发（可以修改伤害值）
func on_before_damage(damage: int) -> int:
	return damage

# 受到伤害后触发
func on_after_damage(_damage: int):
	pass

# 造成伤害前触发（可以修改伤害值）
func on_before_deal_damage(damage: int) -> int:
	return damage

# 效果移除时触发
func on_remove():
	pass

# 获取效果显示文本
func get_display_text() -> String:
	return effect_name

# 获取效果图标
func get_icon() -> String:
	return ""
