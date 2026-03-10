# AI ASMR 打断功能说明

## 功能概述

实现了智能打断机制，允许用户在不同阶段打断AI的响应和操作。

## 打断场景

### 1. AI响应期间或TTS播放期间打断

**触发条件**：
- AI正在流式响应（`is_streaming = true`）
- TTS正在播放或等待音频（`tts_controller.is_playing` 或 `tts_controller.is_waiting_for_audio`）

**行为**：
- 立即停止流式请求
- 保存当前已接收的文本（即使不完整）到对话历史
- 清理TTS队列和状态
- 立即处理新的用户消息

**实现方法**：`_interrupt_and_send(user_message)`

### 2. 工具执行期间（播放音频）打断

**触发条件**：
- 正在执行工具（`is_executing_tool = true`）
- 例如：采耳、头部按摩、梳头等音频播放

**行为**：
- 递增 `current_tool_execution_id`，使旧的工具执行流程失效
- 清理 `pending_tool_calls`（待执行的工具）
- **立即发送新的用户请求**给AI（不等待工具完成）
- **旧的工具执行流程**：
  - 音频播放循环检测到 `execution_id` 不匹配，提前结束循环
  - 记录实际播放时长（`tool_duration`）
  - 添加工具结果到对话历史
  - 后续工具检测到 `execution_id` 不匹配，被跳过
- **新的工具执行流程**：
  - 使用新的 `execution_id`，不受旧流程影响
  - 可以正常执行工具
- **当AI开始响应时**（在`_call_ai_api`中），停止当前音频
- AI处理新请求

**实现方法**：`_interrupt_tool_and_queue_message(user_message)`

**关键特性**：
- 使用执行ID机制隔离新旧工具流程
- 新请求的工具不会被旧的打断标志影响
- 当前工具结果会被保留（使用实际时长）
- 后续工具会被完全跳过
- 音频平滑过渡（不会突然中断）

## 关键变量

```gdscript
# 打断控制
var interrupt_requested: bool = false  # 打断标志（用于AI响应/TTS打断）
var current_tool_execution_id: int = 0  # 当前工具执行流程的ID（用于工具执行打断）
var tool_duration: float = 0.0         # 实际工具执行时长
```

**工具执行ID机制**：
- 每次开始执行工具时，使用当前的 `current_tool_execution_id`
- 打断时递增 `current_tool_execution_id`，使旧的工具执行流程失效
- 工具执行过程中通过比较 `execution_id` 和 `current_tool_execution_id` 来判断是否被打断
- 这样新请求的工具不会受到旧打断标志的影响

## 工作流程

### 场景1：AI响应时打断

```
用户输入 → 检测到is_streaming → _interrupt_and_send()
  ↓
停止流式请求 + 保存不完整文本 + 清理TTS
  ↓
立即发送新消息 → AI开始新的响应
```

### 场景2：工具执行时打断

```
用户输入 → 检测到is_executing_tool → _interrupt_tool_and_queue_message()
  ↓
递增current_tool_execution_id（使旧流程失效）+ 清理pending_tool_calls + 立即发送新消息
  ↓
（旧流程）当前工具继续执行（音频继续播放）→ 检测到execution_id不匹配 → 提前结束音频循环
  ↓
记录实际播放时长 → 添加工具结果到历史
  ↓
工具循环检测到execution_id不匹配 → 停止后续工具 → 返回
  ↓
（新流程）新请求已发送 → AI开始响应（_call_ai_api） → 停止当前音频 → 处理新请求
```

**关键点**：
- 使用 `current_tool_execution_id` 来区分不同的工具执行流程
- 打断时递增ID，使旧流程失效，新流程不受影响
- 旧流程会自然结束并添加结果（使用实际时长）
- 新流程可以正常执行工具，不会被旧的打断标志影响

## 代码修改点

1. **send_message()** - 添加打断检测逻辑
2. **_interrupt_and_send()** - 新增：处理AI响应/TTS打断
3. **_interrupt_tool_and_queue_message()** - 新增：处理工具执行打断（立即发送新请求）
4. **_send_message_internal()** - 新增：内部发送消息方法
5. **_call_ai_api()** - 添加工具执行期间的音频停止逻辑
6. **_execute_tool_calls()** - 添加打断检测
7. **_execute_single_tool()** - 添加工具执行状态标记
8. **_play_audio_for_duration()** - 添加打断检测和实际时长记录
9. **_tool_ear_cleaning/head_massage/hair_brushing()** - 使用实际播放时长

## 用户体验

- **流畅打断**：用户可以随时打断AI，无需等待
- **保留上下文**：不完整的AI回复也会被保存，保持对话连贯性
- **智能音频处理**：工具执行时不会突然中断音频，提供更好的体验
- **准确反馈**：工具结果会反映实际执行时长，而非预期时长
