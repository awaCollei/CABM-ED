extends Node
class_name PlayerInventory

# 玩家背包系统 - 探索模式专用
# 使用通用的StorageContainer

const INVENTORY_SIZE = 30  # 背包格子数量

var container: StorageContainer
var items_config: Dictionary = {}  # 物品配置

func _ready():
	_load_items_config()
	_initialize_inventory()

func _load_items_config():
	"""加载物品配置"""
	var config_path = "res://config/items.json"
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		push_warning("物品配置文件不存在")
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) == OK:
		var data = json.data
		if data.has("items"):
			items_config = data.items

func _initialize_inventory():
	"""初始化背包（带武器栏）"""
	container = StorageContainer.new(INVENTORY_SIZE, items_config, true)

func get_item_config(item_id: String) -> Dictionary:
	"""获取物品配置"""
	return items_config.get(item_id, {})

func add_item(item_id: String, count: int = 1) -> bool:
	"""添加物品到背包"""
	return container.add_item(item_id, count)

func add_item_with_data(item_id: String, count: int = 1, data: Dictionary = {}) -> bool:
	count = int(count)
	if count <= 0:
		return false
	var cfg = get_item_config(item_id)
	if cfg.is_empty():
		return container.add_item(item_id, count)
	var incoming_data = data.duplicate(true)
	incoming_data.erase("count")
	incoming_data["item_id"] = item_id
	if cfg.get("type") == "武器" and cfg.get("subtype") == "远程" and not incoming_data.has("ammo"):
		incoming_data["ammo"] = 0
	var max_stack = int(cfg.get("max_stack", 1))
	var remaining = count
	var changed := false
	if cfg.get("type") == "武器" and container.has_weapon_slot and container.weapon_slot.is_empty():
		container.weapon_slot = _build_item_instance(item_id, 1, incoming_data)
		remaining -= 1
		changed = true
		if remaining <= 0:
			container.storage_changed.emit()
			return true
	for i in range(container.storage.size()):
		if remaining <= 0:
			break
		var slot = container.storage[i]
		if slot == null:
			continue
		if _is_same_stack(slot, incoming_data):
			var current_count = int(slot.get("count", 0))
			var can_add = min(remaining, max_stack - current_count)
			if can_add > 0:
				slot["count"] = current_count + can_add
				container.storage[i] = slot
				remaining -= can_add
				changed = true
	for i in range(container.storage.size()):
		if remaining <= 0:
			break
		if container.storage[i] == null:
			var add_count = min(remaining, max_stack)
			container.storage[i] = _build_item_instance(item_id, add_count, incoming_data)
			remaining -= add_count
			changed = true
	if changed:
		container.storage_changed.emit()
	return remaining <= 0

func _is_same_stack(existing_item: Dictionary, incoming_data: Dictionary) -> bool:
	if existing_item.get("item_id", "") != incoming_data.get("item_id", ""):
		return false
	var a = existing_item.duplicate(true)
	var b = incoming_data.duplicate(true)
	a.erase("count")
	b.erase("count")
	return a == b

func _build_item_instance(item_id: String, count: int, incoming_data: Dictionary) -> Dictionary:
	var item = incoming_data.duplicate(true)
	item["item_id"] = item_id
	item["count"] = int(count)
	return item

func get_inventory_data():
	"""获取背包数据用于保存"""
	return container.get_data()

func load_inventory_data(data):
	"""从保存数据加载"""
	container.load_data(data)
