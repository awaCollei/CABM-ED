# 故事模式新功能说明

## 功能概述

为故事模式添加了以下新功能：
1. 左侧面板切换（故事线/功能栏）
2. 消息气泡选中功能
3. 语音播放
4. 重新生成AI回复
5. 撤回用户消息
6. 继续生成AI回复

## 代码结构

### 文件组织
- `scripts/message_bubble.gd` - 消息气泡组件，支持选中功能
- `scripts/story/story_dialog_panel.gd` - 主对话面板，协调各组件
- `scripts/story/story_function_panel.gd` - 功能面板组件，独立管理操作按钮
- `scripts/story/story_dialog_save_manager.gd` - 保存管理器，处理消息存储

### 关键修改
1. **消息气泡** (`message_bubble.gd`)
   - 添加`bubble_selected`信号
   - 添加`is_selected`状态和选中样式
   - 修改`mouse_filter = 0`使其可接收点击事件

2. **功能面板** (`story_function_panel.gd`) - 新文件
   - 独立的VBoxContainer组件
   - 管理4个操作按钮和消息信息显示
   - 通过信号与主面板通信

3. **主对话面板** (`story_dialog_panel.gd`)
   - 简化代码，移除功能面板UI创建逻辑
   - 通过信号连接功能面板
   - 保留核心对话逻辑

## 使用说明

### 1. 左侧面板切换

- 在左侧面板顶部（InfoBar下方）有一个切换按钮
- 点击按钮可以在"故事线"（树状图）和"功能栏"之间切换
- 默认显示故事线

### 2. 选中消息气泡

- 点击任意消息气泡即可选中
- 选中的气泡会有高亮边框（边框加粗，颜色加深）
- 选中消息后会自动切换到功能栏显示详细信息

### 3. 功能栏按钮

功能栏显示选中消息的详细信息和操作按钮：

#### 播放语音（仅AI消息）
- 优先检查缓存，如果有缓存直接播放
- 如果没有缓存，调用TTS服务生成语音并播放
- 使用`TTSService`单例服务

#### 重新生成（仅AI消息，未存档）
- 移除选中的AI消息及其后续所有消息
- 重新发送之前的用户消息给AI
- AI响应期间按钮禁用

#### 撤回消息（仅用户消息，未存档）
- 如果输入框为空，将消息内容放回输入框
- 移除该消息及其后续所有消息
- AI响应期间按钮禁用

#### 继续生成（仅最新AI消息，未存档）
- 让AI基于当前上下文继续生成内容
- 支持AI的前缀读写功能
- AI响应期间按钮禁用

## 技术实现

### 消息气泡选中
- `message_bubble.gd`添加了`bubble_selected`信号
- 添加了`is_selected`状态和`set_selected()`方法
- 选中状态会改变气泡的边框样式（边框宽度从2变为4）
- 修改场景文件`mouse_filter`从2改为0，使其可接收鼠标事件

### 功能面板组件化
- 独立的`story_function_panel.gd`文件
- 继承自`VBoxContainer`
- 通过信号与主面板通信：
  - `play_voice_requested(message_index)`
  - `regenerate_requested(message_index)`
  - `retract_requested(message_index)`
  - `continue_requested(message_index)`

### 消息管理
- 添加了`_remove_messages_from_index()`方法批量移除消息
- 同步更新UI、消息数组、保存管理器和AI历史
- 在`story_dialog_save_manager.gd`中添加了`remove_last_message_from_current_node()`方法

### TTS集成
- 使用全局`TTSService`单例
- 通过消息哈希检查缓存
- 支持异步TTS生成和播放

## 注意事项

1. **存档检测**：当前`_is_message_archived()`方法返回false，需要根据实际存档逻辑实现
2. **AI响应状态**：所有操作在AI响应期间都会被禁用，功能面板会自动更新按钮状态
3. **消息索引**：每个气泡都有`message_index`属性，用于追踪其在消息数组中的位置
4. **继续生成**：发送空消息让AI基于上下文继续，需要AI模型支持前缀读写

## 未来改进

1. 实现真正的存档检测逻辑
2. 添加消息编辑功能
3. 支持批量操作（选中多条消息）
4. 添加语音播放进度显示
5. 支持语音播放暂停/停止
6. 添加键盘快捷键支持
