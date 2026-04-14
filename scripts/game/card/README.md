# 卡牌游戏架构说明

## 架构概述

这个卡牌游戏采用了基于类的行为系统，每个卡牌和效果都有自己独立的类来管理逻辑，避免代码堆积。

## 核心组件

### 1. 基类系统

#### CardActionBase (card_action_base.gd)
所有手牌行为的基类，定义了卡牌的基本接口：
- `can_use()` - 检查是否可以使用
- `get_target_type()` - 返回需要的目标类型（0=无需目标, 1=己方, 2=敌方, 3=己方+敌方）
- `execute()` - 执行卡牌效果
- `get_hint_text()` - 获取提示文本

#### EffectBase (effect_base.gd)
所有效果（buff/debuff）的基类，定义了效果的生命周期：
- `on_apply()` - 效果应用时
- `on_turn_start()` - 回合开始时
- `on_turn_end()` - 回合结束时
- `on_before_damage()` - 受到伤害前（可修改伤害值）
- `on_after_damage()` - 受到伤害后
- `on_before_deal_damage()` - 造成伤害前（可修改伤害值）
- `on_remove()` - 效果移除时

### 2. 具体实现

#### 手牌行为 (actions/)
- `AttackAction` - 攻击手牌：选择己方角色，再选择敌方角色进行攻击
- `ShieldAction` - 铁壁防御：为己方角色添加护盾效果
- `PoisonAction` - 剧毒之刃：为敌方角色添加剧毒效果
- `HealAction` - 治愈之光：为己方角色恢复生命值
- `DrawAction` - 命运之轮：抽取3张牌

#### 效果实现 (effects/)
- `ShieldEffect` - 铁壁防御效果：在受到伤害前抵挡伤害
- `PoisonEffect` - 剧毒效果：每回合开始时造成伤害

### 3. 工厂模式

#### CardActionFactory (card_action_factory.gd)
根据卡牌ID创建对应的行为实例，统一管理所有卡牌行为的创建。

## 添加新卡牌的步骤

### 1. 添加新的手牌

1. 在 `config/hand_cards.json` 中添加卡牌数据
2. 在 `scripts/game/card/actions/` 创建新的行为类，继承 `CardActionBase`
3. 实现必要的方法：
   - `get_target_type()` - 定义目标类型
   - `execute()` - 实现卡牌效果
   - `get_hint_text()` - 提供用户提示
4. 在 `CardActionFactory` 中添加对应的创建逻辑

示例：
```gdscript
class_name MyNewCardAction
extends CardActionBase

func get_target_type() -> int:
	return 1  # 需要己方单位

func execute(player_unit_index: int = -1, enemy_unit_index: int = -1) -> bool:
	if player_unit_index < 0:
		return false
	
	# 实现你的卡牌效果
	battle_scene._update_info("卡牌效果触发！")
	
	return true

func get_hint_text(player_unit_index: int = -1) -> String:
	return "选择目标"
```

### 2. 添加新的效果

1. 在 `scripts/game/card/effects/` 创建新的效果类，继承 `EffectBase`
2. 实现需要的生命周期方法
3. 在对应的卡牌行为中使用 `battle_scene._add_effect()` 添加效果

示例：
```gdscript
class_name MyNewEffect
extends EffectBase

func _init(scene: Node):
	super._init(scene)
	effect_name = "我的效果"

func on_turn_start():
	# 回合开始时的逻辑
	duration -= 1

func get_display_text() -> String:
	return "✨ " + effect_name + " x" + str(duration)
```

## 重要改动

### 1. 角色牌不能直接攻击
角色牌现在只能通过【攻击】手牌来进行攻击，点击角色牌不会触发攻击。

### 2. 结束回合按钮始终显示
在己方回合时，【结束回合】按钮始终可见且可用，无需选择角色。

### 3. 效果系统
旧的 `_player_buffs` 和 `_enemy_buffs` 字典已被 `_player_effects` 和 `_enemy_effects` 数组替代，每个单位拥有一个效果对象数组。

## 效果触发流程

1. 回合开始 → `on_turn_start()`
2. 受到伤害 → `on_before_damage()` → 计算伤害 → `on_after_damage()`
3. 造成伤害 → `on_before_deal_damage()` → 计算伤害
4. 效果过期 → `on_remove()`

## 优势

- 代码模块化，易于维护
- 添加新卡牌无需修改主战斗逻辑
- 效果系统灵活，支持复杂的buff/debuff机制
- 遵循开闭原则（对扩展开放，对修改封闭）
