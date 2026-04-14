## 卡牌战斗场景主控制器
extends Control

const CardDataClass = preload("res://scripts/game/card/card_data.gd")
const CardDatabaseClass = preload("res://scripts/game/card/card_database.gd")
const BattleActionResolverClass = preload("res://scripts/game/card/battle_action_resolver.gd")

signal battle_ended(victory: bool)

enum Phase { PLAYER_TURN, ENEMY_TURN, GAME_OVER }

# 战斗状态
var _phase: Phase = Phase.PLAYER_TURN
var _turn_number: int = 0
var _player_energy: int = 3
var _max_energy: int = 3
var _max_hand_size: int = 10

# 卡牌数据
var _player_characters: Array = []  # CardData数组
var _enemy_characters: Array = []   # CardData数组
var _hand_cards: Array = []         # CardData数组
var _deck: Array = []               # CardData数组
var _discard_pile: Array = []       # CardData数组

# 战斗单位状态
var _player_hp: Array = []  # 对应_player_characters的生命值
var _enemy_hp: Array = []   # 对应_enemy_characters的生命值
var _player_effects: Array = []  # 效果数组（每个单位一个数组）
var _enemy_effects: Array = []   # 效果数组（每个单位一个数组）

# 选择状态
var _selected_hand_card: int = -1
var _selected_player_unit: int = -1
var _current_card_action: CardActionBase = null  # 当前选中卡牌的行为
var _dragging_card: int = -1  # 正在拖动的卡牌索引
var _dragging_card_ui: Control = null  # 拖动中的卡牌UI副本
var _drag_start_pos: Vector2 = Vector2.ZERO  # 拖动起始位置
var _is_dragging: bool = false  # 是否正在拖动
var _resolving_card_ui: Control = null  # 正在结算区域的卡牌UI
const DRAG_THRESHOLD: float = 10.0  # 拖动阈值（像素）

# 行为结算器
var _action_resolver: BattleActionResolverClass = null

# UI节点
@onready var player_area = $PlayerAreaBG/PlayerArea
@onready var enemy_area = $EnemyAreaBG/EnemyArea
@onready var hand_area = $HandAreaBG/HandArea
@onready var energy_panel = $EnergyPanel/EnergyVBox
@onready var turn_panel = $TurnPanel/TurnVBox
@onready var status_label = $StatusLabel
@onready var back_btn = $BackButton
@onready var play_zone_indicator = $PlayZoneIndicator
@onready var end_turn_btn = $TurnPanel/TurnVBox/EndTurnButton
@onready var card_resolve_area = $CardResolveArea  # 卡牌结算区域

func _ready():
	back_btn.pressed.connect(_on_back_pressed)
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	_action_resolver = BattleActionResolverClass.new(self)
	_setup_styles()
	_setup_play_zone_style()

func _setup_play_zone_style():
	"""设置打出区域指示器样式"""
	if not play_zone_indicator:
		return
	
	# 设置打出区域样式
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.8, 0.3, 0.25)
	style.border_color = Color(0.3, 1.0, 0.3, 0.8)
	style.border_width_left = 5
	style.border_width_right = 5
	style.border_width_top = 5
	style.border_width_bottom = 5
	style.corner_radius_top_left = 15
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_left = 15
	style.corner_radius_bottom_right = 15
	play_zone_indicator.add_theme_stylebox_override("panel", style)
	
	# 设置标签样式
	var label = play_zone_indicator.get_node("Label")
	if label:
		label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		label.add_theme_constant_override("outline_size", 3)

func _setup_styles():
	# 设置背景面板样式
	for panel_path in ["PlayerAreaBG", "EnemyAreaBG", "HandAreaBG"]:
		var panel = get_node(panel_path) as Panel
		if panel:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.12, 0.12, 0.18, 0.9)
			style.corner_radius_top_left = 12
			style.corner_radius_top_right = 12
			style.corner_radius_bottom_left = 12
			style.corner_radius_bottom_right = 12
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.border_color = Color(0.3, 0.35, 0.5, 0.8)
			panel.add_theme_stylebox_override("panel", style)
	
	# 设置信息面板样式
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.15, 0.15, 0.22, 0.95)
	info_style.corner_radius_top_left = 10
	info_style.corner_radius_top_right = 10
	info_style.corner_radius_bottom_left = 10
	info_style.corner_radius_bottom_right = 10
	info_style.content_margin_left = 15
	info_style.content_margin_right = 15
	info_style.content_margin_top = 10
	info_style.content_margin_bottom = 10
	info_style.border_width_left = 2
	info_style.border_width_right = 2
	info_style.border_width_top = 2
	info_style.border_width_bottom = 2
	info_style.border_color = Color(0.4, 0.5, 0.7, 0.9)
	$EnergyPanel.add_theme_stylebox_override("panel", info_style)
	$TurnPanel.add_theme_stylebox_override("panel", info_style)
	
	# 设置标签样式
	for label_path in ["PlayerAreaBG/PlayerLabel", "EnemyAreaBG/EnemyLabel", "HandAreaBG/HandLabel"]:
		var label = get_node(label_path) as Label
		if label:
			label.add_theme_font_size_override("font_size", 16)
			label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	
	# 设置按钮样式
	_setup_button_style(back_btn, Color(0.5, 0.2, 0.2), Color(0.7, 0.3, 0.3))

func _setup_button_style(button: Button, normal_color: Color, hover_color: Color):
	# 正常状态
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = normal_color
	normal_style.corner_radius_top_left = 8
	normal_style.corner_radius_top_right = 8
	normal_style.corner_radius_bottom_left = 8
	normal_style.corner_radius_bottom_right = 8
	normal_style.content_margin_left = 10
	normal_style.content_margin_right = 10
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", normal_style)
	
	# 悬停状态
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = hover_color
	hover_style.corner_radius_top_left = 8
	hover_style.corner_radius_top_right = 8
	hover_style.corner_radius_bottom_left = 8
	hover_style.corner_radius_bottom_right = 8
	hover_style.content_margin_left = 10
	hover_style.content_margin_right = 10
	hover_style.content_margin_top = 8
	hover_style.content_margin_bottom = 8
	button.add_theme_stylebox_override("hover", hover_style)
	
	# 按下状态
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = normal_color.darkened(0.2)
	pressed_style.corner_radius_top_left = 8
	pressed_style.corner_radius_top_right = 8
	pressed_style.corner_radius_bottom_left = 8
	pressed_style.corner_radius_bottom_right = 8
	pressed_style.content_margin_left = 10
	pressed_style.content_margin_right = 10
	pressed_style.content_margin_top = 8
	pressed_style.content_margin_bottom = 8
	button.add_theme_stylebox_override("pressed", pressed_style)
	
	# 字体颜色
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	button.add_theme_font_size_override("font_size", 16)

func _on_back_pressed():
	_game_over(false)

func start_battle(player_cards: Array):
	_player_characters = player_cards.duplicate()
	
	# 初始化玩家生命值和效果
	_player_hp.clear()
	_player_effects.clear()
	for card in _player_characters:
		_player_hp.append(card.defense)
		_player_effects.append([])  # 每个单位一个效果数组
	
	# 创建3个普通敌人
	_create_enemies()
	
	# 初始化牌库
	_init_deck()
	
	# 绘制初始手牌（减少初始抽牌数）
	_draw_cards(3)
	
	# 刷新UI
	_refresh_all_ui()
	
	# 开始玩家回合
	_start_player_turn()

func _create_enemies():
	_enemy_characters.clear()
	_enemy_hp.clear()
	_enemy_effects.clear()
	
	# 创建3个普通敌人角色卡
	for i in range(3):
		var enemy = CardDataClass.new()
		enemy.id = "enemy_" + str(i)
		enemy.card_name = "普通敌人"
		enemy.card_type = CardDataClass.TYPE_CHARACTER
		enemy.attack = 2 + i
		enemy.defense = 5 + i * 2
		enemy.description = "一个普通的敌人"
		_enemy_characters.append(enemy)
		_enemy_hp.append(enemy.defense)
		_enemy_effects.append([])  # 每个单位一个效果数组

func _init_deck():
	_deck.clear()
	_discard_pile.clear()
	
	# 获取所有手牌并复制多份到牌库
	var all_hand_cards = CardDatabaseClass.get_hand_cards()
	for card in all_hand_cards:
		for i in range(3):  # 每种牌3张
			_deck.append(card)
	
	# 洗牌
	_deck.shuffle()

func _draw_cards(count: int):
	for i in range(count):
		# 检查手牌上限
		if _hand_cards.size() >= _max_hand_size:
			_update_info("手牌已满！")
			break
		
		if _deck.is_empty():
			# 牌库空了，将弃牌堆洗回牌库
			_deck = _discard_pile.duplicate()
			_discard_pile.clear()
			_deck.shuffle()
			if _deck.is_empty():
				break
		
		var card = _deck.pop_back()
		_hand_cards.append(card)

func _start_player_turn():
	_phase = Phase.PLAYER_TURN
	_turn_number += 1
	_player_energy = _max_energy
	
	# 触发玩家回合开始效果
	for i in range(_player_characters.size()):
		if _player_hp[i] <= 0:
			continue
		_action_resolver.trigger_turn_start_effects(i, true)
	
	# 检查游戏结束
	if _check_game_over():
		return
	
	# 抽牌
	_draw_cards(2)
	
	# 清除选择
	_selected_hand_card = -1
	_selected_player_unit = -1
	_current_card_action = null
	
	_refresh_all_ui()
	_update_info("你的回合 - 回合 " + str(_turn_number))

func _start_enemy_turn():
	_phase = Phase.ENEMY_TURN
	_update_info("敌人回合...")
	_refresh_all_ui()
	
	await get_tree().create_timer(1.0).timeout
	
	# 触发敌人回合开始效果
	for i in range(_enemy_characters.size()):
		if _enemy_hp[i] <= 0:
			continue
		_action_resolver.trigger_turn_start_effects(i, false)
		_refresh_all_ui()
		await get_tree().create_timer(0.5).timeout
	
	# 检查游戏结束
	if _check_game_over():
		return
	
	# 敌人AI：随机攻击玩家角色
	for i in range(_enemy_characters.size()):
		if _enemy_hp[i] <= 0:
			continue
		
		# 找到存活的玩家角色
		var alive_players = []
		for j in range(_player_characters.size()):
			if _player_hp[j] > 0:
				alive_players.append(j)
		
		if alive_players.is_empty():
			break
		
		# 随机选择一个目标
		var target = alive_players[randi() % alive_players.size()]
		var damage = _enemy_characters[i].attack
		
		# 触发攻击前效果
		damage = _action_resolver.trigger_before_deal_damage(i, false, damage)
		
		_update_info("敌人 " + str(i+1) + " 攻击你的角色 " + str(target+1) + "!")
		await get_tree().create_timer(0.8).timeout
		
		_action_resolver.deal_damage_to_player(target, damage)
		
		# 触发攻击后效果
		_action_resolver.trigger_after_deal_damage(i, false, damage)
		
		_refresh_all_ui()
		await get_tree().create_timer(0.5).timeout
	
	# 检查游戏结束
	if _check_game_over():
		return
	
	# 回到玩家回合
	_start_player_turn()

func _on_end_turn_pressed():
	if _phase != Phase.PLAYER_TURN:
		return
	
	# 回合结束保留手牌（不再弃牌）
	# _discard_pile.append_array(_hand_cards)
	# _hand_cards.clear()
	
	_start_enemy_turn()

func _on_hand_card_mouse_down(index: int, start_pos: Vector2):
	"""鼠标按下"""
	print("[拖动] 鼠标按下, index=", index, " start_pos=", start_pos)
	
	if _phase != Phase.PLAYER_TURN:
		print("[拖动] 不是玩家回合，返回")
		return
	
	var card = _hand_cards[index]
	
	# 检查费用
	if card.cost > _player_energy:
		print("[拖动] 费用不足，返回")
		return
	
	# 记录拖动起始位置
	_drag_start_pos = start_pos
	_dragging_card = index
	_is_dragging = false  # 还未确定是拖动
	print("[拖动] 记录拖动起始位置, _dragging_card=", _dragging_card)

func _on_hand_card_mouse_up(index: int, end_pos: Vector2):
	"""鼠标松开"""
	print("[拖动] 鼠标松开, index=", index, " end_pos=", end_pos)
	print("[拖动] _dragging_card=", _dragging_card, " _is_dragging=", _is_dragging)
	
	if _dragging_card != index:
		print("[拖动] 索引不匹配，返回")
		return
	
	# 如果是拖动状态，处理拖动结束
	if _is_dragging:
		print("[拖动] 调用 _on_hand_card_drag_end")
		_on_hand_card_drag_end(index, end_pos)
		# 注意：_on_hand_card_drag_end 内部会调用 _cleanup_drag_state()
	else:
		# 如果不是拖动（只是点击），清理拖动状态
		print("[拖动] 只是点击，清理拖动状态")
		_cleanup_drag_state()

func _on_hand_card_drag_start(index: int, start_pos: Vector2):
	"""开始拖动（超过阈值后才真正开始）"""
	print("[拖动] 开始拖动, index=", index, " start_pos=", start_pos)
	
	if _phase != Phase.PLAYER_TURN:
		print("[拖动] 不是玩家回合，返回")
		return
	
	if _dragging_card != index:
		print("[拖动] 索引不匹配，返回")
		return
	
	_is_dragging = true
	_selected_hand_card = -1  # 拖动时清除选择状态
	
	# 显示打出区域指示器（只在开始拖动时显示）
	if play_zone_indicator:
		play_zone_indicator.visible = true
		print("[拖动] 显示打出区域指示器")
	else:
		print("[拖动] play_zone_indicator 不存在！")
	
	# 创建拖动卡牌的视觉副本
	_create_dragging_card_visual(index, start_pos)
	
	# 刷新UI以显示拖动反馈
	_refresh_all_ui()

func _create_dragging_card_visual(index: int, start_pos: Vector2):
	"""创建拖动卡牌的视觉副本"""
	if index >= hand_area.get_child_count():
		return
	
	var original_card = hand_area.get_child(index)
	
	# 复制卡牌UI
	_dragging_card_ui = original_card.duplicate()
	_dragging_card_ui.global_position = start_pos - _dragging_card_ui.size / 2
	_dragging_card_ui.z_index = 1000
	_dragging_card_ui.modulate = Color(1.0, 1.0, 1.0, 0.8)
	
	# 添加发光效果（绑定到_dragging_card_ui，这样删除时会自动停止）
	var tween = _dragging_card_ui.create_tween()
	tween.set_loops()
	tween.tween_property(_dragging_card_ui, "modulate:a", 0.6, 0.5)
	tween.tween_property(_dragging_card_ui, "modulate:a", 0.9, 0.5)
	
	add_child(_dragging_card_ui)

func _process(_delta):
	# 安全检查：如果鼠标左键没有按下，但仍在拖动状态，处理拖动结束
	if (_is_dragging or _dragging_card >= 0) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		print("[拖动] _process 检测到鼠标松开")
		if _is_dragging and _dragging_card >= 0:
			# 正在拖动，处理拖动结束
			var mouse_pos = get_global_mouse_position()
			_on_hand_card_drag_end(_dragging_card, mouse_pos)
		else:
			# 还没开始拖动，只是清理状态
			_cleanup_drag_state()
			_refresh_all_ui()
		return
	
	# 检查是否超过拖动阈值
	if _dragging_card >= 0 and not _is_dragging:
		var current_pos = get_global_mouse_position()
		var distance = _drag_start_pos.distance_to(current_pos)
		if distance > DRAG_THRESHOLD:
			# 超过阈值，开始拖动
			_on_hand_card_drag_start(_dragging_card, current_pos)
	
	# 更新拖动卡牌的位置（只在真正拖动时）
	if _is_dragging and _dragging_card >= 0 and _dragging_card_ui:
		var mouse_pos = get_global_mouse_position()
		_dragging_card_ui.global_position = mouse_pos - _dragging_card_ui.size / 2

func _on_hand_card_drag_end(index: int, end_pos: Vector2):
	"""拖动结束"""
	print("[拖动] _on_hand_card_drag_end 被调用, index=", index, " end_pos=", end_pos)
	print("[拖动] _is_dragging=", _is_dragging, " _dragging_card=", _dragging_card)
	
	if not _is_dragging:
		print("[拖动] 不在拖动状态，返回")
		return
	
	# 检查是否在打出区域内（使用当前鼠标位置而不是end_pos）
	var mouse_pos = get_global_mouse_position()
	var is_in_zone = false
	if play_zone_indicator:
		var zone_rect = play_zone_indicator.get_global_rect()
		is_in_zone = zone_rect.has_point(mouse_pos)
		print("[拖动] mouse_pos=", mouse_pos)
		print("[拖动] zone_rect=", zone_rect)
		print("[拖动] is_in_zone=", is_in_zone)
	else:
		print("[拖动] play_zone_indicator 不存在！")
	
	# 立即清理拖动状态
	_cleanup_drag_state()
	
	if is_in_zone:
		# 在打出区域内，执行卡牌
		print("[拖动] 在打出区域内，执行卡牌")
		_play_card_from_drag(index)
	else:
		# 不在打出区域，取消
		print("[拖动] 不在打出区域，取消")
		_update_info("拖动到上方绿色区域以打出卡牌")
		_refresh_all_ui()

func _cleanup_drag_state():
	"""清理所有拖动相关状态"""
	print("[拖动] 清理拖动状态")
	_is_dragging = false
	_dragging_card = -1
	
	# 清理拖动卡牌视觉副本
	if _dragging_card_ui:
		_dragging_card_ui.queue_free()
		_dragging_card_ui = null
		print("[拖动] 清理拖动卡牌UI")
	
	# 隐藏打出区域指示器
	if play_zone_indicator:
		play_zone_indicator.visible = false
		print("[拖动] 隐藏打出区域指示器")

func _on_player_unit_clicked(index: int):
	if _phase != Phase.PLAYER_TURN:
		return
	
	if _player_hp[index] <= 0:
		_update_info("该角色已阵亡")
		return
	
	if _current_card_action != null:
		var target_type = _current_card_action.get_target_type()
		if target_type == 1:
			# 只需要己方单位
			_execute_current_card(index, -1)
		elif target_type == 3:
			# 需要先选己方，再选敌方
			_selected_player_unit = index
			var hint = _current_card_action.get_hint_text(index)
			_update_info(hint)
			_refresh_all_ui()
		else:
			_update_info("该卡牌不能对己方使用")
	else:
		# 没有选中卡牌，角色牌不能直接攻击
		_update_info("角色不能直接攻击，请使用【攻击】手牌")

func _on_enemy_unit_clicked(index: int):
	if _phase != Phase.PLAYER_TURN:
		return
	
	if _enemy_hp[index] <= 0:
		_update_info("该敌人已阵亡")
		return
	
	if _current_card_action != null:
		var target_type = _current_card_action.get_target_type()
		if target_type == 2:
			# 只需要敌方单位
			_execute_current_card(-1, index)
		elif target_type == 3:
			# 需要先选己方，再选敌方
			if _selected_player_unit >= 0:
				_execute_current_card(_selected_player_unit, index)
			else:
				_update_info("请先选择己方角色")
		else:
			_update_info("该卡牌不能对敌方使用")
	else:
		_update_info("请先选择手牌")

func _execute_current_card(player_unit: int = -1, enemy_unit: int = -1):
	if _current_card_action == null or _selected_hand_card < 0:
		return
	
	var card = _hand_cards[_selected_hand_card]
	
	# 检查是否可以使用
	if not _current_card_action.can_use(player_unit, enemy_unit):
		_update_info("无法使用该卡牌")
		return
	
	# 注意：费用已经在拖动打出时扣除了
	# 注意：卡牌已经在结算区域了
	
	# 执行卡牌效果
	var success = _current_card_action.execute(player_unit, enemy_unit)
	
	if success:
		# 弃牌
		_discard_pile.append(_hand_cards[_selected_hand_card])
		_hand_cards.remove_at(_selected_hand_card)
		_update_info("卡牌已打出")
		
		# 等待一小段时间后让结算区域的卡牌消失
		await get_tree().create_timer(0.3).timeout
		await _remove_resolving_card()
	else:
		# 执行失败，返还费用
		_player_energy += card.cost
		_update_info("卡牌执行失败")
		await _remove_resolving_card()
	
	# 清除选择
	_selected_hand_card = -1
	_selected_player_unit = -1
	_current_card_action = null
	
	_refresh_all_ui()
	_check_game_over()

func _play_card_from_drag(index: int):
	"""从拖动打出卡牌 - 先打出，再选择目标"""
	print("[拖动] _play_card_from_drag 被调用, index=", index)
	
	if index < 0 or index >= _hand_cards.size():
		print("[拖动] 索引无效，返回")
		_refresh_all_ui()
		return
	
	var card = _hand_cards[index]
	print("[拖动] 卡牌: ", card.card_name, " 费用: ", card.cost)
	
	# 创建卡牌行为
	var card_action = CardActionFactory.create_action(card, self)
	if card_action == null:
		print("[拖动] 卡牌行为未实现")
		_update_info("该卡牌暂未实现")
		_refresh_all_ui()
		return
	
	var target_type = card_action.get_target_type()
	print("[拖动] 目标类型: ", target_type)
	
	# 扣除费用
	_player_energy -= card.cost
	print("[拖动] 扣除费用后剩余: ", _player_energy)
	
	# 先播放动画移动到结算区域（所有卡牌都先移动，且不消失）
	await _move_card_to_resolve_area(card, index)
	
	if target_type == 0:
		# 无需目标，直接执行
		print("[拖动] 无需目标，直接执行")
		var success = card_action.execute(-1, -1)
		
		if success:
			# 弃牌
			_discard_pile.append(_hand_cards[index])
			_hand_cards.remove_at(index)
			_update_info("卡牌已打出")
			print("[拖动] 卡牌执行成功")
		else:
			_player_energy += card.cost
			_update_info("卡牌执行失败")
			print("[拖动] 卡牌执行失败")
		
		# 等待一小段时间后让结算区域的卡牌消失
		await get_tree().create_timer(0.3).timeout
		await _remove_resolving_card()
		
		_refresh_all_ui()
		_check_game_over()
	else:
		# 需要选择目标 - 卡牌已经在结算区域，等待选择目标
		print("[拖动] 需要选择目标")
		_selected_hand_card = index
		_current_card_action = card_action
		
		var hint = card_action.get_hint_text()
		_update_info("请选择目标 - " + hint)
		_refresh_all_ui()

# ========== 游戏结束检查 ==========

func _check_game_over() -> bool:
	# 检查玩家是否全灭
	var player_alive = false
	for hp in _player_hp:
		if hp > 0:
			player_alive = true
			break
	
	if not player_alive:
		_game_over(false)
		return true
	
	# 检查敌人是否全灭
	var enemy_alive = false
	for hp in _enemy_hp:
		if hp > 0:
			enemy_alive = true
			break
	
	if not enemy_alive:
		_game_over(true)
		return true
	
	return false

func _game_over(victory: bool):
	_phase = Phase.GAME_OVER
	if victory:
		_update_info("胜利！")
	else:
		_update_info("失败...")
	
	await get_tree().create_timer(2.0).timeout
	battle_ended.emit(victory)

# ========== UI刷新 ==========

func _refresh_all_ui():
	_refresh_player_area()
	_refresh_enemy_area()
	_refresh_hand_area()
	_refresh_energy_panel()
	_refresh_turn_panel()

func _refresh_energy_panel():
	# 清空现有UI
	for child in energy_panel.get_children():
		child.queue_free()
	
	var title_label = Label.new()
	title_label.text = "费用"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	energy_panel.add_child(title_label)
	
	var energy_label = Label.new()
	energy_label.text = "💎 " + str(_player_energy) + " / " + str(_max_energy)
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_label.add_theme_font_size_override("font_size", 20)
	if _player_energy == 0:
		energy_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	else:
		energy_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	energy_panel.add_child(energy_label)
	
	var deck_label = Label.new()
	deck_label.text = "牌库: " + str(_deck.size())
	deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deck_label.add_theme_font_size_override("font_size", 12)
	deck_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	energy_panel.add_child(deck_label)
	
	var discard_label = Label.new()
	discard_label.text = "弃牌: " + str(_discard_pile.size())
	discard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discard_label.add_theme_font_size_override("font_size", 12)
	discard_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	energy_panel.add_child(discard_label)

func _refresh_turn_panel():
	# 清空现有UI（除了按钮）
	for child in turn_panel.get_children():
		if child != end_turn_btn:
			child.queue_free()
	
	var turn_label = Label.new()
	turn_label.text = "回合 " + str(_turn_number)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.add_theme_font_size_override("font_size", 18)
	turn_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	turn_panel.add_child(turn_label)
	turn_panel.move_child(turn_label, 0)
	
	var phase_label = Label.new()
	if _phase == Phase.PLAYER_TURN:
		phase_label.text = "你的回合"
		phase_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	elif _phase == Phase.ENEMY_TURN:
		phase_label.text = "敌人回合"
		phase_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	else:
		phase_label.text = "游戏结束"
		phase_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 14)
	turn_panel.add_child(phase_label)
	turn_panel.move_child(phase_label, 1)
	
	# 添加分隔线
	var separator = HSeparator.new()
	turn_panel.add_child(separator)
	turn_panel.move_child(separator, 2)
	
	# 根据回合状态禁用/启用按钮（置灰而不是隐藏）
	var can_end_turn = (_phase == Phase.PLAYER_TURN and _current_card_action == null)
	end_turn_btn.disabled = not can_end_turn
	
	# 更新按钮样式
	if not can_end_turn:
		var disabled_style = StyleBoxFlat.new()
		disabled_style.bg_color = Color(0.3, 0.3, 0.3)
		disabled_style.corner_radius_top_left = 8
		disabled_style.corner_radius_top_right = 8
		disabled_style.corner_radius_bottom_left = 8
		disabled_style.corner_radius_bottom_right = 8
		disabled_style.content_margin_left = 10
		disabled_style.content_margin_right = 10
		disabled_style.content_margin_top = 8
		disabled_style.content_margin_bottom = 8
		end_turn_btn.add_theme_stylebox_override("disabled", disabled_style)
		end_turn_btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	else:
		_setup_button_style(end_turn_btn, Color(0.2, 0.5, 0.3), Color(0.3, 0.7, 0.4))

func _refresh_player_area():
	# 清空现有UI
	for child in player_area.get_children():
		child.queue_free()
	
	# 创建玩家角色卡
	for i in range(_player_characters.size()):
		var card_ui = _create_character_ui(_player_characters[i], _player_hp[i], true, i)
		player_area.add_child(card_ui)

func _refresh_enemy_area():
	# 清空现有UI
	for child in enemy_area.get_children():
		child.queue_free()
	
	# 创建敌人角色卡
	for i in range(_enemy_characters.size()):
		var card_ui = _create_character_ui(_enemy_characters[i], _enemy_hp[i], false, i)
		enemy_area.add_child(card_ui)

func _refresh_hand_area():
	# 清空现有UI
	for child in hand_area.get_children():
		child.queue_free()
	
	# 创建手牌UI
	for i in range(_hand_cards.size()):
		var card_ui = _create_hand_card_ui(_hand_cards[i], i)
		hand_area.add_child(card_ui)

func _create_character_ui(card: CardDataClass, hp: int, is_player: bool, index: int) -> Control:
	var container = Control.new()
	container.custom_minimum_size = Vector2(140, 180)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(140, 180)
	container.add_child(panel)
	
	# 设置面板样式
	var style = StyleBoxFlat.new()
	if is_player:
		style.bg_color = Color(0.15, 0.25, 0.35, 0.95)
		style.border_color = Color(0.3, 0.5, 0.7, 1.0)
	else:
		style.bg_color = Color(0.35, 0.15, 0.15, 0.95)
		style.border_color = Color(0.7, 0.3, 0.3, 1.0)
	
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	
	# 高亮选中
	if is_player and _selected_player_unit == index:
		style.border_color = Color(1.0, 0.9, 0.3, 1.0)
		style.border_width_left = 4
		style.border_width_right = 4
		style.border_width_top = 4
		style.border_width_bottom = 4
	
	# 死亡变灰
	if hp <= 0:
		style.bg_color = Color(0.2, 0.2, 0.2, 0.7)
		style.border_color = Color(0.3, 0.3, 0.3, 0.5)
	
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)
	
	# 名称
	var name_label = Label.new()
	name_label.text = card.card_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(name_label)
	
	# 分隔线
	var separator1 = HSeparator.new()
	vbox.add_child(separator1)
	
	# HP
	var hp_label = Label.new()
	hp_label.text = "❤️ " + str(hp) + "/" + str(card.defense)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 14)
	if hp <= 0:
		hp_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	elif hp < card.defense * 0.3:
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	elif hp < card.defense * 0.6:
		hp_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	else:
		hp_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	vbox.add_child(hp_label)
	
	# ATK
	var atk_label = Label.new()
	atk_label.text = "⚔️ " + str(card.attack)
	atk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	atk_label.add_theme_font_size_override("font_size", 14)
	atk_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	vbox.add_child(atk_label)
	
	# 显示效果状态
	var effects = _player_effects[index] if is_player else _enemy_effects[index]
	for effect in effects:
		var effect_label = Label.new()
		effect_label.text = effect.get_display_text()
		effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		effect_label.add_theme_font_size_override("font_size", 12)
		effect_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		vbox.add_child(effect_label)
	
	# 添加点击按钮
	var btn = Button.new()
	btn.text = ""
	btn.custom_minimum_size = panel.custom_minimum_size
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	container.add_child(btn)
	
	if is_player:
		btn.pressed.connect(_on_player_unit_clicked.bind(index))
	else:
		btn.pressed.connect(_on_enemy_unit_clicked.bind(index))
	
	return container

func _create_hand_card_ui(card: CardDataClass, index: int) -> Control:
	var container = Control.new()
	container.custom_minimum_size = Vector2(110, 150)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(110, 150)
	panel.tooltip_text = card.description  # 使用内置tooltip
	container.add_child(panel)
	
	# 设置面板样式
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.25, 0.95)
	style.border_color = Color(0.5, 0.5, 0.6, 1.0)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	
	# 等待选择目标时高亮（拖动打出后）
	if _selected_hand_card == index and _current_card_action != null:
		style.border_color = Color(1.0, 0.9, 0.3, 1.0)
		style.border_width_left = 4
		style.border_width_right = 4
		style.border_width_top = 4
		style.border_width_bottom = 4
		style.bg_color = Color(0.3, 0.3, 0.2, 0.95)
		# 高亮时向上移动
		container.position.y -= 20
	
	# 拖动时隐藏原始卡牌
	if _dragging_card == index:
		panel.modulate = Color(1.0, 1.0, 1.0, 0.3)  # 半透明显示原位置
	
	# 费用不足变灰
	if card.cost > _player_energy:
		style.bg_color = Color(0.15, 0.15, 0.15, 0.7)
		style.border_color = Color(0.3, 0.3, 0.3, 0.5)
	
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)
	
	# 类型图标（顶部）
	var category_icon = Label.new()
	category_icon.text = card.get_category_icon()
	category_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	category_icon.add_theme_font_size_override("font_size", 16)
	category_icon.custom_minimum_size = Vector2(0, 20)
	category_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(category_icon)
	
	# Emoji图标
	var emoji_label = Label.new()
	emoji_label.text = card.emoji
	emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji_label.add_theme_font_size_override("font_size", 36)
	vbox.add_child(emoji_label)
	
	# 卡牌名称
	var name_label = Label.new()
	name_label.text = card.card_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_label)
	
	# 费用
	var cost_label = Label.new()
	cost_label.text = "💎 " + str(card.cost)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 14)
	if card.cost > _player_energy:
		cost_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		cost_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(cost_label)
	
	# 创建可拖动的按钮
	var drag_btn = _create_draggable_card_button(index, card)
	container.add_child(drag_btn)
	
	return container

func _create_draggable_card_button(index: int, card: CardDataClass) -> Button:
	"""创建可拖动的卡牌按钮"""
	var btn = Button.new()
	btn.text = ""
	btn.custom_minimum_size = Vector2(110, 150)
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = card.description
	
	# 费用不足时禁用
	if card.cost > _player_energy:
		btn.disabled = true
		btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	else:
		# 拖动事件（使用gui_input）
		btn.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton:
				if event.button_index == MOUSE_BUTTON_LEFT:
					if event.pressed:
						# 鼠标按下
						_on_hand_card_mouse_down(index, event.global_position)
					else:
						# 鼠标松开
						_on_hand_card_mouse_up(index, event.global_position)
		)
	
	return btn

func _update_info(text: String):
	print("[战斗] " + text)
	if status_label:
		status_label.text = text
		# 添加文字动画效果
		status_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var tween = create_tween()
		tween.tween_property(status_label, "modulate:a", 1.0, 0.3)

func _move_card_to_resolve_area(card: CardDataClass, index: int):
	"""将卡牌移动到结算区域（不消失，保持显示）"""
	print("[动画] 开始移动卡牌到结算区域")
	
	# 获取原始卡牌位置
	var start_pos = Vector2(get_viewport_rect().size.x / 2, get_viewport_rect().size.y - 100)
	var original_card = hand_area.get_child(index) if index < hand_area.get_child_count() else null
	if original_card:
		start_pos = original_card.global_position
	
	# 立即刷新UI，移除原卡牌（避免分身）
	_refresh_hand_area()
	
	# 创建卡牌UI副本用于结算区域显示
	var card_ui = _create_hand_card_ui(card, -1)  # 使用-1避免交互
	card_ui.z_index = 2000
	card_ui.global_position = start_pos
	
	add_child(card_ui)
	_resolving_card_ui = card_ui  # 保存引用
	
	# 目标位置：结算区域
	var target_pos = card_resolve_area.global_position if card_resolve_area else Vector2(100, get_viewport_rect().size.y / 2)
	
	# 创建动画
	var tween = create_tween()
	tween.set_parallel(true)
	
	# 移动到结算区域
	tween.tween_property(card_ui, "global_position", target_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# 稍微放大
	tween.tween_property(card_ui, "scale", Vector2(1.2, 1.2), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# 等待移动完成
	await tween.finished
	
	print("[动画] 卡牌移动到结算区域完成，保持显示")

func _remove_resolving_card():
	"""移除结算区域的卡牌（淡出消失）"""
	if not _resolving_card_ui:
		return
	
	print("[动画] 开始移除结算区域的卡牌")
	
	# 淡出消失
	var fade_tween = create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(_resolving_card_ui, "modulate:a", 0.0, 0.3)
	fade_tween.tween_property(_resolving_card_ui, "scale", Vector2(0.8, 0.8), 0.3)
	
	await fade_tween.finished
	
	print("[动画] 卡牌淡出完成")
	_resolving_card_ui.queue_free()
	_resolving_card_ui = null

