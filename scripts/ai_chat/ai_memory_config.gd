extends MarginContainer
## 记忆系统配置面板。
## 采用"数据驱动的依赖图"：每个配置项声明它依赖的其它配置项，依赖关系以
## 层级标识（├└）与 tooltip 提示呈现（如"时间检索/详细检索"依赖任一存储方式）。
## 控件一律不禁用，实际生效与否由运行时（memory_system）按同样规则校验。

@onready var content: VBoxContainer = $ScrollContainer/VBoxContainer/ContentContainer
@onready var advanced_checkbox: CheckButton = $ScrollContainer/VBoxContainer/AdvancedHeader/AdvancedCheckBox
@onready var reset_defaults_button: Button = $ScrollContainer/VBoxContainer/ResetDefaultsButton

var config_manager: Node
var _loading: bool = false

# 依赖图定义。
#   kind: "section"（分组标题）/ "check"（布尔开关）/ "number"（数值参数）
#   requires_all: 依赖的其它 key，全部为真才真正生效
#   requires_any: 依赖的其它 key，任一为真即可（OR 依赖）
#   advanced: 高级项，以"·"标识，仅"高级选项"开启时显示
const GRAPH := [
	{"kind": "section", "label": "记忆存储"},
	{"kind": "check", "key": "save_memory_vectors", "label": "保存记忆向量", "default": true,
		"tooltip": "保存长期记忆；语义检索与详细检索的基础"},
	{"kind": "check", "key": "save_memory_keywords", "label": "保存记忆关键词", "default": true,
		"tooltip": "保存用于匹配的关键词；关键词检索与详细检索的基础"},
	{"kind": "number", "key": "keyword_count", "label": "关键词数量", "default": 8,
		"min": 1, "max": 50, "suffix": " 个", "indent": 1, "advanced": true,
		"requires_all": ["save_memory_keywords"],
		"tooltip": "每条记忆保存/匹配的关键词数量"},

	{"kind": "section", "label": "主动检索"},
	{"kind": "check", "key": "enable_active_semantic_search", "label": "语义检索", "default": true,
		"requires_all": ["save_memory_vectors"],
		"tooltip": "按语义相近程度回忆"},
	{"kind": "check", "key": "active_reranking", "label": "重排序", "default": true, "indent": 1,
		"requires_all": ["enable_active_semantic_search"],
		"tooltip": "优化语义检索结果"},
	{"kind": "number", "key": "active_rerank_multiplier", "label": "候选倍数", "default": 5,
		"min": 1, "max": 20, "suffix": " 倍", "indent": 2, "advanced": true,
		"requires_all": ["active_reranking"],
		"tooltip": "重排序时先取检索数量 × 倍率的候选"},
	{"kind": "check", "key": "active_time_aware", "label": "时间感知增强", "default": true, "indent": 3,
		"requires_all": ["active_reranking"],
		"tooltip": "重排序时纳入时间，提升有限"},
	{"kind": "check", "key": "enable_active_keyword_search", "label": "关键词检索", "default": true,
		"requires_all": ["save_memory_keywords"],
		"tooltip": "按关键词匹配回忆"},
	{"kind": "check", "key": "enable_active_time_search", "label": "时间检索", "default": true,
		"requires_any": ["save_memory_vectors", "save_memory_keywords"],
		"tooltip": "按时间点（更早/更晚/附近）回忆"},
	{"kind": "check", "key": "enable_active_detail_search", "label": "细节查询", "default": true,
		"requires_any": ["save_memory_vectors", "save_memory_keywords"],
		"tooltip": "回忆某条记忆的完整对话"},

	{"kind": "section", "label": "被动检索"},
	{"kind": "check", "key": "enable_passive_semantic_search", "label": "语义检索", "default": false,
		"requires_all": ["save_memory_vectors"],
		"tooltip": "被动检索时不再携带对话细节，需要细节请使用主动检索"},
	{"kind": "number", "key": "passive_retrieval_top_k", "label": "检索数量", "default": 5,
		"min": 1, "max": 20, "suffix": " 条", "indent": 1, "advanced": true,
		"requires_all": ["enable_passive_semantic_search"]},
	{"kind": "number", "key": "passive_min_similarity", "label": "相似度阈值", "default": 0.3,
		"min": 0.0, "max": 1.0, "step": 0.01, "indent": 1, "advanced": true,
		"requires_all": ["enable_passive_semantic_search"],
		"tooltip": "低于此分数的记忆会被过滤"},
	{"kind": "check", "key": "passive_pre_recall_reasoning", "label": "召回前推理", "default": false, "indent": 1,
		"requires_all": ["enable_passive_semantic_search"],
		"tooltip": "用模型把玩家输入扩展为多个检索查询"},
	{"kind": "number", "key": "passive_reasoning_count", "label": "推理条数", "default": 3,
		"min": 1, "max": 20, "suffix": " 条", "indent": 2, "advanced": true,
		"requires_all": ["passive_pre_recall_reasoning"]},
	{"kind": "check", "key": "passive_reranking", "label": "重排序", "default": false, "indent": 1,
		"requires_all": ["enable_passive_semantic_search"]},
	{"kind": "number", "key": "passive_rerank_multiplier", "label": "候选倍数", "default": 5,
		"min": 1, "max": 20, "suffix": " 倍", "indent": 2, "advanced": true,
		"requires_all": ["passive_reranking"]},
	{"kind": "check", "key": "passive_time_aware", "label": "时间感知增强", "default": false, "indent": 3,
		"requires_all": ["passive_reranking"]},
	{"kind": "check", "key": "enable_passive_keyword_search", "label": "关键词检索", "default": false,
		"requires_all": ["save_memory_keywords"],
		"tooltip": "用玩家输入的关键词与已保存关键词匹配"},

	{"kind": "section", "label": "知识图谱（被动检索）"},
	{"kind": "check", "key": "save_knowledge_graph", "label": "保存知识图谱", "default": true,
		"tooltip": "保存从对话中学习到的知识"},
	{"kind": "check", "key": "enable_kg_search", "label": "启用图谱检索", "default": true, "indent": 1,
		"requires_all": ["save_knowledge_graph"]},
	{"kind": "number", "key": "knowledge_top_k", "label": "知识检索数量", "default": 6,
		"min": 1, "max": 20, "suffix": " 条", "indent": 2, "advanced": true,
		"requires_all": ["enable_kg_search"],
		"tooltip": "每次知识图谱检索提取的结果数量"},
	{"kind": "check", "key": "enable_knowledge_forgetting", "label": "启用知识遗忘", "default": true, "indent": 1,
		"requires_all": ["save_knowledge_graph"],
		"tooltip": "遗忘掉过时的知识"},
	{"kind": "number", "key": "knowledge_forgetting_rate", "label": "遗忘速率", "default": 0.1,
		"min": 0.0, "max": 1.0, "step": 0.01, "indent": 2, "advanced": true,
		"requires_all": ["enable_knowledge_forgetting"],
		"tooltip": "每次知识遗忘时强度减少的比例"},
]

var _checks: Dictionary = {}      # key -> CheckBox
var _numbers: Dictionary = {}     # key -> SpinBox
var _rows: Array = []             # 与 GRAPH 同下标，记录生成的行控件
var _connectors: Array = []       # 与 GRAPH 同下标，记录层级竖线标识（├ / └）

func _ready() -> void:
	_connectors = _compute_connectors()
	_build_ui()
	advanced_checkbox.toggled.connect(_on_advanced_toggled)
	reset_defaults_button.pressed.connect(_on_reset_defaults_pressed)

## 由外部（ai_config_panel）注入配置管理器
func initialize(config_mgr: Node) -> void:
	config_manager = config_mgr
	load_memory_config()

# ── 层级标识 ──
## 依据同一分组内的后续同级项，计算 ├（后面还有同级）还是 └（最后一个）
func _compute_connectors() -> Array:
	var connectors: Array = []
	connectors.resize(GRAPH.size())
	connectors.fill("")
	var i := 0
	while i < GRAPH.size():
		if GRAPH[i].get("kind", "") != "section":
			i += 1
			continue
		var start := i + 1
		var end := start
		while end < GRAPH.size() and GRAPH[end].get("kind", "") != "section":
			end += 1
		for k in range(start, end):
			var depth: int = GRAPH[k].get("indent", 0)
			if depth <= 0:
				continue
			var connector := "└"
			for j in range(k + 1, end):
				var next_depth: int = GRAPH[j].get("indent", 0)
				if next_depth <= depth:
					connector = "├" if next_depth == depth else "└"
					break
			connectors[k] = connector
		i = end
	return connectors

func _label_prefix(index: int) -> String:
	var spec: Dictionary = GRAPH[index]
	var depth: int = spec.get("indent", 0)
	var prefix := ""
	if depth > 0:
		prefix = "  ".repeat(depth - 1) + str(_connectors[index]) + " "
	if spec.get("advanced", false):
		# 高级项：去掉层级连接符，只保留纯空格缩进
		prefix = "    "+"     ".repeat(depth-1) + "·"
	return prefix

# ── UI 构建 ──
func _build_ui() -> void:
	var first_section := true
	for i in range(GRAPH.size()):
		var spec: Dictionary = GRAPH[i]
		var kind: String = spec.get("kind", "check")
		if kind == "section":
			if not first_section:
				content.add_child(HSeparator.new())
			first_section = false
			var title := Label.new()
			title.text = spec.get("label", "")
			title.add_theme_font_size_override("font_size", 24)
			content.add_child(title)
			_rows.append(title)
		elif kind == "number":
			_rows.append(_create_number_row(spec, i))
		else:
			_rows.append(_create_check_row(spec, i))

func _create_check_row(spec: Dictionary, index: int) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.text = _label_prefix(index) + spec.get("label", "")
	checkbox.tooltip_text = _tooltip_with_dependency(spec)
	checkbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	checkbox.toggled.connect(_on_setting_changed)
	content.add_child(checkbox)
	_checks[spec.key] = checkbox
	return checkbox

func _create_number_row(spec: Dictionary, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = _label_prefix(index) + spec.get("label", "")
	label.tooltip_text = _tooltip_with_dependency(spec)
	label.add_theme_font_size_override("font_size", 20)
	label.custom_minimum_size = Vector2(260, 0)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = spec.get("min", 0)
	spin.max_value = spec.get("max", 100)
	spin.step = spec.get("step", 1.0)
	spin.suffix = spec.get("suffix", "")
	spin.value = spec.get("default", 0)
	spin.tooltip_text = _tooltip_with_dependency(spec)
	spin.value_changed.connect(_on_numeric_setting_changed)
	row.add_child(spin)

	content.add_child(row)
	_numbers[spec.key] = spin
	return row

func _tooltip_with_dependency(spec: Dictionary) -> String:
	var tip: String = spec.get("tooltip", "")
	var deps: Array = []
	for dep in spec.get("requires_all", []):
		deps.append(_label_of(dep))
	var any_deps: Array = spec.get("requires_any", [])
	if not any_deps.is_empty():
		var names: Array = []
		for dep in any_deps:
			names.append(_label_of(dep))
		deps.append("或".join(names))
	if deps.is_empty():
		return tip
	var hint := "（依赖：" + "、".join(deps) + "）"
	return tip + "\n" + hint if not tip.is_empty() else hint

func _label_of(key: String) -> String:
	for spec in GRAPH:
		if spec.get("key", "") == key:
			return spec.get("label", key)
	return key

# ── 事件 ──
func _on_advanced_toggled(_enabled: bool) -> void:
	_update_visibility()
	_auto_save_config()

func _on_setting_changed(_enabled: bool) -> void:
	if _loading:
		return
	_update_dependencies()
	_auto_save_config()

func _on_numeric_setting_changed(_value: float) -> void:
	if _loading:
		return
	_auto_save_config()

func _on_reset_defaults_pressed() -> void:
	if not config_manager:
		return
	_apply_memory_config(config_manager.get_memory_defaults())
	_auto_save_config()

# ── 依赖图求值 ──
## 普通项按依赖层级禁用/级联关闭；高级项（·）始终不禁用，可自由设置
func _update_dependencies() -> void:
	for spec in GRAPH:
		if spec.get("kind", "") != "check" or spec.get("advanced", false):
			continue
		var checkbox: CheckBox = _checks[spec.key]
		var allowed := _is_allowed(spec)
		checkbox.disabled = not allowed
		if not allowed and checkbox.button_pressed:
			checkbox.set_pressed_no_signal(false)

	for spec in GRAPH:
		if spec.get("kind", "") != "number" or spec.get("advanced", false):
			continue
		(_numbers[spec.key] as SpinBox).editable = _is_allowed(spec)

func _is_allowed(spec: Dictionary) -> bool:
	for dep in spec.get("requires_all", []):
		if not _is_check_on(dep):
			return false
	var any_deps: Array = spec.get("requires_any", [])
	if not any_deps.is_empty():
		var any_ok := false
		for dep in any_deps:
			if _is_check_on(dep):
				any_ok = true
				break
		if not any_ok:
			return false
	return true

func _is_check_on(key: String) -> bool:
	return _checks.has(key) and (_checks[key] as CheckBox).button_pressed

# ── 高级项显隐 ──
func _update_visibility() -> void:
	var show_advanced: bool = advanced_checkbox.button_pressed
	for i in range(GRAPH.size()):
		var row = _rows[i]
		if row == null:
			continue
		(row as Control).visible = show_advanced or not GRAPH[i].get("advanced", false)

# ── 读写配置 ──
func _auto_save_config() -> void:
	if config_manager:
		config_manager.save_memory_config(collect_memory_config())

func collect_memory_config() -> Dictionary:
	var result: Dictionary = {}
	for spec in GRAPH:
		var kind: String = spec.get("kind", "")
		if kind == "check":
			result[spec.key] = (_checks[spec.key] as CheckBox).button_pressed
		elif kind == "number":
			result[spec.key] = (_numbers[spec.key] as SpinBox).value
	result["advanced_options_enabled"] = advanced_checkbox.button_pressed
	return result

func load_memory_config() -> void:
	if not config_manager:
		return
	_apply_memory_config(config_manager.load_memory_config())

func _apply_memory_config(config: Dictionary) -> void:
	_loading = true
	for spec in GRAPH:
		var kind: String = spec.get("kind", "")
		if kind == "check":
			var value: bool = bool(config.get(spec.key, spec.get("default", false)))
			(_checks[spec.key] as CheckBox).set_pressed_no_signal(value)
		elif kind == "number":
			(_numbers[spec.key] as SpinBox).value = float(config.get(spec.key, spec.get("default", 0)))
	advanced_checkbox.set_pressed_no_signal(bool(config.get("advanced_options_enabled", false)))
	_loading = false
	_update_dependencies()
	_update_visibility()
