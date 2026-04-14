## 命运之轮手牌行为
class_name DrawAction
extends CardActionBase

func get_target_type() -> int:
	return 0  # 无需目标

func execute(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	battle_scene._draw_cards(3)
	battle_scene._update_info("抽取了3张牌!")
	return true

func get_hint_text(player_unit_index: int = -1) -> String:
	return "抽取3张牌"
