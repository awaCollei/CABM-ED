## 卡牌行为基类
class_name CardActionBase
extends RefCounted

# 卡牌数据引用
var card_data: CardData

# 战斗场景引用
var battle_scene: Node

func _init(data: CardData, scene: Node):
	card_data = data
	battle_scene = scene

# 检查是否可以使用（费用、目标等）
func can_use(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	return true

# 获取需要的目标类型
# 返回值：0=无需目标, 1=需要己方单位, 2=需要敌方单位, 3=需要己方然后敌方
func get_target_type() -> int:
	return 0

# 执行卡牌效果
# 返回是否成功执行
func execute(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	return false

# 获取提示信息
func get_hint_text(player_unit_index: int = -1) -> String:
	return ""
