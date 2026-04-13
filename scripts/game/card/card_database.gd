## 卡牌数据库 - 从 config/ 下的 JSON 文件加载牌定义
extends Node

const CardDataClass = preload("res://scripts/game/card/card_data.gd")
# CardType enum: 0=CHARACTER, 1=HAND

static func get_all_cards() -> Array:
	var cards: Array = []
	cards.append_array(get_character_cards())
	cards.append_array(get_hand_cards())
	return cards

static func get_character_cards() -> Array:
	return _load_cards_from_json("res://config/character_cards.json")

static func get_hand_cards() -> Array:
	return _load_cards_from_json("res://config/hand_cards.json")

static func _load_cards_from_json(path: String) -> Array:
	var cards: Array = []
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("card_database: 无法打开 " + path)
		return cards
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("card_database: JSON 解析失败 " + path + " 行 " + str(json.get_error_line()))
		return cards
	for entry in json.data:
		var card = CardDataClass.new()
		card.id          = entry.get("id", "")
		card.card_name   = entry.get("card_name", "")
		card.card_type   = entry.get("card_type", 1)
		card.description = entry.get("description", "")
		card.flavor_text = entry.get("flavor_text", "")
		card.attack      = entry.get("attack", 0)
		card.defense     = entry.get("defense", 0)
		card.cost        = entry.get("cost", 1)
		card.emoji       = entry.get("emoji", "")
		card.category    = entry.get("category", "")
		card.image_path  = entry.get("image_path", "")
		card.skill_name  = entry.get("skill_name", "")
		cards.append(card)
	return cards
