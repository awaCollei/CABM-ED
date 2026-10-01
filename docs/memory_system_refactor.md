# 记忆系统重构说明

> 面向开发者。本文记录 2026-10 的记忆系统重构、配置字段和后续维护约束。

## 1. 重构目标

旧系统主要依赖向量相似度和对话摘要。它有两个明显问题：

- 专有名词、角色名、地点名和物品名可能被向量模型漏召回。
- 只保存摘要会压缩掉对话中的具体细节。

本次重构没有直接把全部历史对话塞入提示词，而是采用“摘要索引 + 原始细节按需展开 + 混合召回”的方案，在准确度、上下文长度、延迟和 API 成本之间取平衡。

## 2. 记忆数据结构变化

### 2.1 摘要仍然是主索引

`MemorySystem.add_text()` 继续以摘要文本生成向量。这样可以控制向量数量和嵌入请求延迟，不改变旧版向量数据库的基本格式。

### 2.2 原始对话作为元数据保存

聊天总结完成后，`SummaryManager` 会将原始对话通过 `raw_conversation` 写入同一记忆条目的 metadata：

```gdscript
{
    "raw_conversation": conversation_text
}
```

命中摘要后，`get_relevant_memory()` 才按 `raw_detail_max_chars` 展开原始细节。未命中的历史不会进入提示词。

这保留了旧数据的兼容性：没有 `raw_conversation` 的历史条目仍然可以正常作为摘要使用。

### 2.3 修复 metadata 覆盖问题

写入向量模长 `mag` 时，现在先复制业务 metadata，再补充 `mag`。避免保存原始对话、情绪或其他字段时覆盖模长缓存。

## 3. 混合检索流程

`MemorySystem.search()` 现在包含两条召回路径：

1. **关键词召回**
   - 对中文按字符拆分。
   - 对英文和数字按连续词拆分。
   - 适合角色名、地点、物品和专有名词。
   - 不需要网络请求，嵌入失败时仍然可以工作。

2. **向量召回**
   - 保留原有语义检索。
   - 适合表达不同但含义相近的记忆。

两条路径使用混合分数合并：

\[
score = semantic \times (1 - w) + lexical \times w
\]

其中 `w` 是 `lexical_match_weight`。默认值为 `0.28`，因此默认仍然偏向语义检索，同时给精确关键词命中足够权重。

召回前推理生成的查询也会受到 `reasoning_query_count` 限制，避免一次请求产生过多候选查询。

## 4. 重排序变化

重排序候选数量不再固定为 `top_k * 5`，而是使用：

```text
top_k * rerank_candidate_multiplier
```

该参数只影响启用重排序时的候选池大小，不改变最终返回数量。

## 5. 知识图谱变化

知识图谱检索和遗忘参数统一从 `AIConfigManager.MEMORY_DEFAULTS` 读取：

- `knowledge_top_k`
- `knowledge_forgetting_rate`

`PromptBuilder` 和探索场景的知识检索使用同一套高级配置，避免两个入口出现不同结果。

## 6. 配置字段

所有记忆配置默认值集中在：

```text
scripts/ai_chat/ai_config_manager.gd
```

当前字段：

| 字段 | 默认值 | 作用 |
|---|---:|---|
| `save_memory_vectors` | `true` | 是否保存向量记忆 |
| `enable_semantic_search` | `true` | 是否启用向量检索 |
| `enable_reranking` | `true` | 是否启用重排序 |
| `enable_time_aware_reranking` | `false` | 是否向重排序文本加入相对时间 |
| `enable_pre_recall_reasoning` | `false` | 是否启用召回前推理 |
| `retrieval_top_k` | `5` | 最终返回的长期记忆数量 |
| `retrieval_min_similarity` | `0.3` | 向量结果最低相似度 |
| `lexical_match_weight` | `0.28` | 混合检索中的关键词权重 |
| `raw_detail_max_chars` | `1200` | 命中后展开的原始对话长度 |
| `rerank_candidate_multiplier` | `5` | 重排序候选池倍率 |
| `reasoning_query_count` | `3` | 召回前推理最多生成的查询数 |
| `save_knowledge_graph` | `true` | 是否保存知识图谱 |
| `enable_kg_search` | `true` | 是否进行知识图谱检索 |
| `knowledge_top_k` | `6` | 知识图谱关键词和结果数量 |
| `enable_knowledge_forgetting` | `true` | 是否启用知识遗忘 |
| `knowledge_forgetting_rate` | `0.1` | 每次遗忘降低的知识强度 |

旧配置加载时会自动合并缺失字段，因此不需要手动迁移已有配置文件。

## 7. UI 约束

配置页面位于：

```text
scenes/memory_config_panel.tscn
scripts/ai_chat/ai_memory_config.gd
```

高级参数必须放在所属功能开关的下方，并遵守以下规则：

- 顶部“高级”开关负责显示/隐藏所有高级参数。
- 所属功能关闭时，对应 `SpinBox.editable = false`。
- 不要对 `SpinBox` 使用 `disabled` 属性；Godot 4 的 `SpinBox` 使用 `editable` 控制编辑状态。
- 新配置字段必须同时加入：默认值、UI 收集、UI 加载和运行时读取。

## 8. 兼容性和后续注意事项

- 旧向量文件可以继续读取。
- 没有 `raw_conversation` 的旧条目不会报错，只会显示摘要。
- 修改混合权重时应注意：关键词权重过高会增加字面匹配噪声，过低则可能重新漏掉专有名词。
- 增大 `raw_detail_max_chars` 会直接增加提示词长度，应和模型上下文上限一起评估。
- 增大 `retrieval_top_k`、`rerank_candidate_multiplier` 或 `reasoning_query_count` 会增加上下文、处理量或 API 延迟。
- 如果未来加入真正的 token 预算控制，建议优先替代 `raw_detail_max_chars`，按 token 而不是字符截断。
