## 卡牌数据库 - 存放所有牌的定义
extends Node

const CardDataClass = preload("res://scripts/game/card/card_data.gd")
# CardType enum: 0=CHARACTER, 1=HAND

static func get_all_cards() -> Array:
	var cards: Array = []
	cards.append_array(get_character_cards())
	cards.append_array(get_hand_cards())
	return cards

static func get_character_cards() -> Array:
	var cards: Array = []

	var c1 = CardDataClass.new()
	c1.id = "snowfox"; c1.card_name = "雪狐"
	c1.card_type = 0
	c1.skill_name = "雪地幽灵"
	c1.description = "场上存在其他我方角色时，雪狐不能被敌方选中。"
	c1.flavor_text = "……"
	c1.image_path = "snowfox.png"
	c1.attack = 4; c1.defense = 1
	cards.append(c1)

	var c2 = CardDataClass.new()
	c2.id = "dark_seele"; c2.card_name = "希儿·芙乐艾"
	c2.card_type = 0
	c2.skill_name = "罪罚两断之刃"
	c2.description = "每次攻击获得一层【赤痕】。【赤痕】到达3层时，攻击消耗全部【赤痕】使本次攻击伤害+5。"
	c2.flavor_text = "希儿会保护好大家的\n这™是哪个希儿？！"
	c2.image_path = "dark_seele.png"
	c2.attack = 3; c2.defense = 10
	cards.append(c2)

	var c3 = CardDataClass.new()
	c3.id = "silver_wolf"; c3.card_name = "银狼"
	c3.card_type = 0
	c3.skill_name = "雨一直下"
	c3.description = "打败你根本不需要技能。"
	c3.flavor_text = "你看，又开"
	c3.image_path = "silver_wolf.png"
	c3.attack = 99; c3.defense = 99
	cards.append(c3)

	var c4 = CardDataClass.new()
	c4.id = "octocat"; c4.card_name = "Octocat"
	c4.card_type = 0
	c4.skill_name = "重构"
	c4.description = "生命值低于4时，恢复全部生命值并使攻击力增加3。该效果只能触发一次。"
	c4.flavor_text = "这程序居然不能跑，为什么？\n这程序居然能跑，为什么？？"
	c4.image_path = "octocat.png"
	c4.attack = 2; c4.defense = 10
	cards.append(c4)
	return cards

static func get_hand_cards() -> Array:
	var cards: Array = []

	var h1 = CardDataClass.new()
	h1.id = "hand_fireball"; h1.card_name = "火球术"
	h1.card_type = 1
	h1.description = "向目标投掷一枚炽热的火球，造成大量伤害。"
	h1.flavor_text = "\"烈焰焚尽一切。\""
	h1.emoji = "🔥"; h1.attack = 5; h1.defense = 0; h1.cost = 3
	cards.append(h1)

	var h2 = CardDataClass.new()
	h2.id = "hand_shield"; h2.card_name = "铁壁防御"
	h2.card_type = 1
	h2.description = "为己方角色提供坚固的护盾，抵挡下一次攻击。"
	h2.flavor_text = "\"最好的进攻是无懈可击的防守。\""
	h2.emoji = "🛡️"; h2.attack = 0; h2.defense = 6; h2.cost = 2
	cards.append(h2)

	var h3 = CardDataClass.new()
	h3.id = "hand_lightning"; h3.card_name = "雷霆一击"
	h3.card_type = 1
	h3.description = "召唤闪电精准打击敌方，有概率造成眩晕。"
	h3.flavor_text = "\"雷声未至，胜负已分。\""
	h3.emoji = "⚡"; h3.attack = 6; h3.defense = 0; h3.cost = 4
	cards.append(h3)

	var h4 = CardDataClass.new()
	h4.id = "hand_heal"; h4.card_name = "治愈之光"
	h4.card_type = 1
	h4.description = "恢复己方角色的生命值。"
	h4.flavor_text = "\"伤口会愈合，意志不会消散。\""
	h4.emoji = "💚"; h4.attack = 0; h4.defense = 4; h4.cost = 2
	cards.append(h4)

	var h5 = CardDataClass.new()
	h5.id = "hand_poison"; h5.card_name = "剧毒之刃"
	h5.card_type = 1
	h5.description = "涂抹毒素的匕首，每回合持续造成伤害。"
	h5.flavor_text = "\"慢慢来，死亡也可以很优雅。\""
	h5.emoji = "🗡️"; h5.attack = 2; h5.defense = 0; h5.cost = 2
	cards.append(h5)

	var h6 = CardDataClass.new()
	h6.id = "hand_ice"; h6.card_name = "冰封大地"
	h6.card_type = 1
	h6.description = "冻结所有敌方单位，使其无法行动一回合。"
	h6.flavor_text = "\"寒冰封印，时间静止。\""
	h6.emoji = "❄️"; h6.attack = 3; h6.defense = 3; h6.cost = 5
	cards.append(h6)

	var h7 = CardDataClass.new()
	h7.id = "hand_summon"; h7.card_name = "召唤骷髅"
	h7.card_type = 1
	h7.description = "从亡者之地召唤一具骷髅战士为你战斗。"
	h7.flavor_text = "\"死亡不是终点，而是新的开始。\""
	h7.emoji = "💀"; h7.attack = 3; h7.defense = 2; h7.cost = 3
	cards.append(h7)

	var h8 = CardDataClass.new()
	h8.id = "hand_draw"; h8.card_name = "命运之轮"
	h8.card_type = 1
	h8.description = "抽取三张牌，命运掌握在你手中。"
	h8.flavor_text = "\"机遇总是青睐有准备的人。\""
	h8.emoji = "🎴"; h8.attack = 0; h8.defense = 0; h8.cost = 1
	cards.append(h8)

	return cards
