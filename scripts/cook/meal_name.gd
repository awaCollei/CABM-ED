# meal_name.gd
extends RefCounted
class_name MealNameGenerator

# 食材分类常量
const MEAT_TYPES = ["beef", "chicken", "mutton", "porkchop", "rabbit"]
const VEG_TYPES = ["carrot", "potato", "beetroot", "sweet_berry"]

func _init():
	# 无需特殊初始化
	pass

# 修改函数签名，接收 CookManagerClass 作为一个参数
static func generate_meal_name(ingredients: Array, items_config: Dictionary, CookManagerClassRef) -> String:
	"""
	根据食材列表和配置生成菜品名称。
	@param ingredients: 一个包含 PanIngredient 对象的数组。
	@param items_config: 物品配置字典 (item_id -> config_dict)。
	@param CookManagerClassRef: CookManager 类的引用，用于访问其枚举。
	@return: 生成的菜品名称字符串。
	"""
	if ingredients.is_empty() or not items_config:
		return "谜之炖菜"

	# --- 1. 分析整体熟度，确定形容词 ---
	# 注意：现在使用传入的 CookManagerClassRef
	var adjective = _analyze_adjective(ingredients, CookManagerClassRef)

	# --- 2. 分析食材组成，确定菜名 ---
	var dish_name = _analyze_dish_name(ingredients, items_config)

	# --- 3. 组合形容词和菜名 ---
	return adjective + dish_name

static func get_ingredient_counts(ingredients: Array) -> Dictionary:
	"""
	统计食材中的肉类和蔬菜数量。
	@param ingredients: 一个包含 PanIngredient 对象的数组。
	@return: 包含 meat_count 和 veg_count 的字典。
	"""
	var meat_count = 0
	var veg_count = 0
	
	for ingredient in ingredients:
		var id = ingredient.item_id
		if id in MEAT_TYPES:
			meat_count += 1
		elif id in VEG_TYPES:
			veg_count += 1
			
	return {
		"meat_count": meat_count,
		"veg_count": veg_count,
		"total": ingredients.size()
	}

static func is_vegetarian(meat_count: int, veg_count: int) -> bool:
	"""
	判断是否为素菜。
	规则：素菜数量 > 荤菜数量 * 2，则是素菜。
	"""
	return veg_count > meat_count * 2

static func _analyze_adjective(ingredients: Array, CookManagerClassRef) -> String:
	"""
	根据食材的总体熟度状态分析形容词。
	@param ingredients: 一个包含 PanIngredient 对象的数组。
	@param CookManagerClassRef: CookManager 类的引用。
	@return: 形容词字符串。
	"""
	var raw_count = 0
	var light_count = 0
	var medium_count = 0
	var well_done_count = 0
	var overcooked_count = 0
	var burnt_count = 0
	var total = ingredients.size()

	for ingredient in ingredients:
		# 使用传入的 CookManagerClassRef
		match ingredient.state:
			CookManagerClassRef.IngredientState.RAW:
				raw_count += 1
			CookManagerClassRef.IngredientState.LIGHT:
				light_count += 1
			CookManagerClassRef.IngredientState.MEDIUM:
				medium_count += 1
			CookManagerClassRef.IngredientState.WELL_DONE:
				well_done_count += 1
			CookManagerClassRef.IngredientState.OVERCOOKED:
				overcooked_count += 1
			CookManagerClassRef.IngredientState.BURNT:
				burnt_count += 1

	# 定义形容词判断逻辑（负面倾向版本，去腥气化）
	# 大部分焦糊
	if burnt_count > total * 0.7:
		return "焦黑的"
	# 有过熟和焦糊，但也有正常熟的
	elif burnt_count > 0 and (well_done_count > 0 or medium_count > 0):
		return "半焦的"
	# 有过熟和焦糊，但也有生的
	elif burnt_count > 0 and raw_count > 0:
		return "外焦里生的"
	# 全部焦糊
	elif burnt_count == total:
		return "炭化的"
	# 大部分过熟
	elif overcooked_count > total * 0.7:
		return "干柴般的"
	# 有过熟，也有正常熟的
	elif overcooked_count > 0 and (well_done_count > 0 or medium_count > 0):
		return "有些过熟的"
	# 全部过熟
	elif overcooked_count == total:
		return "熟过头的"
	# 全部全熟
	elif well_done_count == total:
		return "美味的" 
	# 大部分全熟
	elif well_done_count > total * 0.7:
		return "恰到好处的"
	# 全部半熟
	elif medium_count == total:
		return "夹生的"
	# 大部分半熟
	elif medium_count > total * 0.7:
		return "半生不熟的"
	# 全部微熟
	elif light_count == total:
		return "生涩的" 
	# 大部分微熟
	elif light_count > total * 0.7:
		return "偏生的" 
	# 全部生的
	elif raw_count == total:
		return "全生的"
	# 大部分生的
	elif raw_count > total * 0.7:
		return "几乎全生的"
	# 生的和熟的都有
	elif raw_count > 0 and (well_done_count > 0 or medium_count > 0 or light_count > 0):
		return "半生半熟的"
	# 默认形容词
	else:
		return "勉强能吃的"

static func _analyze_dish_name(ingredients: Array, items_config: Dictionary) -> String:
	"""
	根据食材列表分析具体的菜名。
	@param ingredients: 一个包含 PanIngredient 对象的数组。
	@param items_config: 物品配置字典 (item_id -> config_dict)。
	@return: 菜名字符串。
	"""
	# 提取食材ID列表
	var ingredient_set = {}
	for ingredient in ingredients:
		ingredient_set[ingredient.item_id] = true

	var unique_ingredients = ingredient_set.keys()
	var num_unique = unique_ingredients.size()

	# 使用新定义的分类统计
	var meat_type_count = 0
	var veg_type_count = 0

	for id in unique_ingredients:
		if id in MEAT_TYPES:
			meat_type_count += 1
		elif id in VEG_TYPES:
			veg_type_count += 1

	# 快捷判断函数
	var has = func(id): return ingredient_set.has(id)

	# 规则优先级按顺序判断，找到第一个匹配的即返回
	# 如果包含胡萝卜和猪肉，且仅包含这两种
	if num_unique == 2 and has.call("carrot") and has.call("porkchop"):
		return "蜜酱胡萝卜煎肉"
	if meat_type_count == 1 and veg_type_count == 1 and has.call("wheat"):
		return "口袋饼"
	# 如果包含牛肉和土豆，且仅有这两种或还包含小麦（小麦可能作为辅料）
	if num_unique <= 3 and num_unique >= 2 and has.call("beef") and has.call("potato") and (num_unique <= 2 or (num_unique == 3 and has.call("wheat"))):
		var valid_keys = ["beef", "potato", "wheat"]
		var all_keys_valid = true
		for key in unique_ingredients:
			if key not in valid_keys:
				all_keys_valid = false
				break
		if all_keys_valid:
			return "经典炖牛肉"
		# 严格的双食材组合 - 必须是恰好这两种食材
	if num_unique == 2:
		var ingredients_pair = unique_ingredients.duplicate()
		ingredients_pair.sort()
		# 鸡肉+甜浆果
		if ingredients_pair == ["chicken", "sweet_berry"]:
			return "酸甜鸡丁"
		# 苹果+小麦
		if ingredients_pair == ["apple", "wheat"]:
			return "苹果派"
		# 兔肉+胡萝卜
		if ingredients_pair == ["carrot", "rabbit"]:
			return "田园兔肉煲"
		# 羊肉+土豆
		if ingredients_pair == ["mutton", "potato"]:
			return "香焖羊肉"
		# 甜菜根+土豆
		if ingredients_pair == ["beetroot", "potato"]:
			return "田园杂烩"
	# 单一食材
	if num_unique == 1:
		if has.call("apple"): return "烤苹果"
		if has.call("sweet_berry"): return "糖渍甜浆果"
		if has.call("wheat"): return "炒面粉"
		if has.call("potato"): return "烤土豆"
		if has.call("carrot"): return "胡萝卜"
		if has.call("beef"): return "香煎牛排"
		if has.call("chicken"): return "脆皮烤鸡"
		if has.call("porkchop"): return "香煎猪排"
		if has.call("mutton"): return "烤羊排"
		if has.call("rabbit"): return "香烤兔肉"
		if has.call("beetroot"): return "清炒甜菜根"
	# 双食材组合
	if num_unique == 2:
		if has.call("apple") and has.call("sweet_berry"): return "苹果甜酱"
		if has.call("potato") and has.call("carrot"): return "土豆胡萝卜泥"
		if has.call("beef") and has.call("carrot"): return "胡萝卜炖牛肉"
		if has.call("beef") and has.call("beetroot"): return "罗宋汤"
		if has.call("chicken") and has.call("potato"): return "土豆炖鸡"
		if has.call("porkchop") and has.call("apple"): return "苹果煎猪排"
		if has.call("rabbit") and has.call("sweet_berry"): return "甜酱兔肉"
		if has.call("mutton") and has.call("beetroot"): return "甜菜根焖羊肉"
		if has.call("beef") and has.call("porkchop"): return "双肉拼盘"
		if has.call("chicken") and has.call("wheat"): return "鸡肉麦片粥"
		if has.call("beetroot") and has.call("wheat"): return "甜菜根麦饭"
		if has.call("potato") and has.call("sweet_berry"): return "甜浆果土豆泥"
		if has.call("carrot") and has.call("wheat"): return "胡萝卜麦粥"
	# 三食材组合
	if num_unique == 3:
		if has.call("beef") and has.call("potato") and has.call("carrot"): return "土豆胡萝卜炖牛肉"
		if has.call("chicken") and has.call("potato") and has.call("carrot"): return "田园炖鸡"
		if has.call("porkchop") and has.call("apple") and has.call("wheat"): return "苹果猪肉麦饭"
		if has.call("rabbit") and has.call("carrot") and has.call("potato"): return "乡村炖兔肉"
		if has.call("mutton") and has.call("potato") and has.call("beetroot"): return "甜菜根焖羊肉"
		if has.call("beef") and has.call("beetroot") and has.call("carrot"): return "甜菜胡萝卜炖牛肉"
	# 四食材组合
	if num_unique == 4:
		if has.call("beef") and has.call("potato") and has.call("carrot") and has.call("wheat"): return "丰盛炖牛肉配麦饭"
		if has.call("chicken") and has.call("potato") and has.call("carrot") and has.call("sweet_berry"): return "甜浆果炖鸡"
	# 多种肉类
	if meat_type_count >= 2:
		return "大乱炖"
	# 多种蔬菜
	if veg_type_count >= 2:
		return "什锦蔬菜"
	# 肉类+蔬菜
	if meat_type_count >= 1 and veg_type_count >= 1:
		return "时蔬炖肉"
	# 默认
	return "谜之炖菜"
