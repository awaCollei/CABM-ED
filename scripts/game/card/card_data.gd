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
@export var skill_name: String = ""  # 技能名

# 属性
@export var attack: int = 0
@export var defense: int = 0
@export var cost: int = 1  # 手牌专用
