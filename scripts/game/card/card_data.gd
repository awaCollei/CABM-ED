## 卡牌数据结构
class_name CardData
extends Resource

# card_type: 0=CHARACTER, 1=HAND
const TYPE_CHARACTER = 0
const TYPE_HAND = 1

# 手牌类别
const CATEGORY_ATTACK = "attack"      # 🗡攻击
const CATEGORY_DEFENSE = "defense"    # 🛡防御
const CATEGORY_DEBUFF = "debuff"      # 🍃减益
const CATEGORY_BUFF = "buff"          # 💉强化
const CATEGORY_SPECIAL = "special"    # ✨特殊

@export var id: String = ""
@export var card_name: String = ""
@export var card_type: int = TYPE_HAND
@export var description: String = ""
@export var flavor_text: String = ""

# 手牌专用
@export var emoji: String = ""
@export var category: String = ""  # 手牌类别：attack/defense/debuff/buff/special

# 角色牌专用
@export var image_path: String = ""  # 相对于 assets/images/cards/
@export var skill_name: String = ""  # 技能名

# 属性
@export var attack: int = 0  # 角色牌专用
@export var defense: int = 0  # 角色牌专用
@export var cost: int = 1  # 手牌专用

# 获取手牌类别图标
func get_category_icon() -> String:
	match category:
		CATEGORY_ATTACK: return "🗡"
		CATEGORY_DEFENSE: return "🛡"
		CATEGORY_DEBUFF: return "🍃"
		CATEGORY_BUFF: return "💉"
		CATEGORY_SPECIAL: return "✨"
		_: return ""

# 获取手牌类别名称
func get_category_name() -> String:
	match category:
		CATEGORY_ATTACK: return "攻击"
		CATEGORY_DEFENSE: return "防御"
		CATEGORY_DEBUFF: return "减益"
		CATEGORY_BUFF: return "强化"
		CATEGORY_SPECIAL: return "特殊"
		_: return ""
