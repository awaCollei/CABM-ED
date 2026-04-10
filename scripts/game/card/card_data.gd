## 卡牌数据结构
class_name CardData
extends Resource

# card_type: 0=CHARACTER, 1=HAND
const TYPE_CHARACTER = 0
const TYPE_HAND = 1

@export var id: String = ""
@export var card_name: String = ""
@export var card_type: int = TYPE_HAND
@export var description: String = ""
@export var flavor_text: String = ""

# 手牌专用
@export var emoji: String = ""

# 角色牌专用
@export var image_path: String = ""  # 相对于 assets/images/cards/

# 属性
@export var attack: int = 0
@export var defense: int = 0
@export var cost: int = 1
@export var rarity: int = 1  # 1=普通 2=稀有 3=史诗 4=传说

func get_rarity_name() -> String:
	match rarity:
		1: return "普通"
		2: return "稀有"
		3: return "史诗"
		4: return "传说"
	return "未知"

func get_rarity_color() -> Color:
	match rarity:
		1: return Color(0.7, 0.7, 0.7)
		2: return Color(0.2, 0.5, 1.0)
		3: return Color(0.6, 0.2, 0.9)
		4: return Color(1.0, 0.7, 0.1)
	return Color.WHITE
