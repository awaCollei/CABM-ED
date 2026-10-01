extends MarginContainer
## 记忆系统配置面板。
## 基础开关保持易懂，高级参数紧随所属功能，并与运行时共用 AIConfigManager 的默认值。

@onready var save_vector_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/SaveVectorCheckBox
@onready var semantic_search_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/SemanticSearchCheckBox
@onready var jieba_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/JiebaCheckBox
@onready var rerank_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/RerankCheckBox
@onready var time_aware_enhance_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/TimeAwareEnhanceCheckBox
@onready var pre_recall_reasoning_checkbox: CheckBox = $ScrollContainer/VBoxContainer/VectorContainer/PreRecallReasoningCheckBox
@onready var save_kg_checkbox: CheckBox = $ScrollContainer/VBoxContainer/KGContainer/SaveKGCheckBox
@onready var kg_search_checkbox: CheckBox = $ScrollContainer/VBoxContainer/KGContainer/KGSearchCheckBox
@onready var enable_forgetting_checkbox: CheckBox = $ScrollContainer/VBoxContainer/KGContainer/EnableForgettingCheckBox
@onready var advanced_checkbox: CheckButton = $ScrollContainer/VBoxContainer/AdvancedHeader/AdvancedCheckBox

@onready var retrieval_advanced: VBoxContainer = $ScrollContainer/VBoxContainer/VectorContainer/RetrievalAdvanced
@onready var reasoning_advanced: VBoxContainer = $ScrollContainer/VBoxContainer/VectorContainer/ReasoningAdvanced
@onready var rerank_advanced: VBoxContainer = $ScrollContainer/VBoxContainer/VectorContainer/RerankAdvanced
@onready var knowledge_advanced: VBoxContainer = $ScrollContainer/VBoxContainer/KGContainer/KnowledgeAdvanced
@onready var forgetting_advanced: VBoxContainer = $ScrollContainer/VBoxContainer/KGContainer/ForgettingAdvanced

@onready var retrieval_top_k: SpinBox = $ScrollContainer/VBoxContainer/VectorContainer/RetrievalAdvanced/RetrievalTopKRow/RetrievalTopK
@onready var lexical_weight: SpinBox = $ScrollContainer/VBoxContainer/VectorContainer/RetrievalAdvanced/LexicalWeightRow/LexicalWeight
@onready var raw_detail_max_chars: SpinBox = $ScrollContainer/VBoxContainer/VectorContainer/RetrievalAdvanced/RawDetailMaxCharsRow/RawDetailMaxChars
@onready var retrieval_min_similarity: SpinBox = $ScrollContainer/VBoxContainer/VectorContainer/RetrievalAdvanced/RetrievalMinSimilarityRow/RetrievalMinSimilarity
@onready var rerank_multiplier: SpinBox = $ScrollContainer/VBoxContainer/VectorContainer/RerankAdvanced/RerankMultiplierRow/RerankMultiplier
@onready var reasoning_count: SpinBox = $ScrollContainer/VBoxContainer/VectorContainer/ReasoningAdvanced/ReasoningCountRow/ReasoningCount
@onready var knowledge_top_k: SpinBox = $ScrollContainer/VBoxContainer/KGContainer/KnowledgeAdvanced/KnowledgeTopKRow/KnowledgeTopK
@onready var forgetting_rate: SpinBox = $ScrollContainer/VBoxContainer/KGContainer/ForgettingAdvanced/ForgettingRateRow/ForgettingRate
@onready var reset_defaults_button: Button = $ScrollContainer/VBoxContainer/ResetDefaultsButton
var config_manager: Node

func _ready() -> void:
	for checkbox in [save_vector_checkbox, semantic_search_checkbox, jieba_checkbox, rerank_checkbox, time_aware_enhance_checkbox, pre_recall_reasoning_checkbox, save_kg_checkbox, kg_search_checkbox, enable_forgetting_checkbox, advanced_checkbox]:
		checkbox.toggled.connect(_on_setting_changed)
	for field in [retrieval_top_k, lexical_weight, raw_detail_max_chars, retrieval_min_similarity, rerank_multiplier, reasoning_count, knowledge_top_k, forgetting_rate]:
		field.value_changed.connect(_on_numeric_setting_changed)
	reset_defaults_button.pressed.connect(_on_reset_defaults_pressed)

func initialize(config_mgr: Node) -> void:
	config_manager = config_mgr
	load_memory_config()

func _on_setting_changed(_enabled: bool) -> void:
	_update_dependencies()
	_update_advanced_visibility()
	_auto_save_config()

func _on_numeric_setting_changed(_value: float) -> void:
	_auto_save_config()

func _on_reset_defaults_pressed() -> void:
	if not config_manager:
		return
	_apply_memory_config(config_manager.get_memory_defaults())
	_auto_save_config()

func _update_dependencies() -> void:
	if not save_vector_checkbox.button_pressed:
		semantic_search_checkbox.button_pressed = false
		rerank_checkbox.button_pressed = false
		time_aware_enhance_checkbox.button_pressed = false
		pre_recall_reasoning_checkbox.button_pressed = false
	semantic_search_checkbox.disabled = not save_vector_checkbox.button_pressed
	rerank_checkbox.disabled = not (save_vector_checkbox.button_pressed and semantic_search_checkbox.button_pressed)
	time_aware_enhance_checkbox.disabled = not (semantic_search_checkbox.button_pressed and rerank_checkbox.button_pressed)
	pre_recall_reasoning_checkbox.disabled = not (save_vector_checkbox.button_pressed and semantic_search_checkbox.button_pressed)
	jieba_checkbox.disabled = not (save_vector_checkbox.button_pressed and semantic_search_checkbox.button_pressed)
	if not save_kg_checkbox.button_pressed:
		kg_search_checkbox.button_pressed = false
		enable_forgetting_checkbox.button_pressed = false
	kg_search_checkbox.disabled = not save_kg_checkbox.button_pressed
	enable_forgetting_checkbox.disabled = not save_kg_checkbox.button_pressed

func _update_advanced_visibility() -> void:
	var show_advanced := advanced_checkbox.button_pressed
	for section in [retrieval_advanced, reasoning_advanced, rerank_advanced, knowledge_advanced, forgetting_advanced]:
		section.visible = show_advanced

func _auto_save_config() -> void:
	if config_manager:
		config_manager.save_memory_config(collect_memory_config())

func collect_memory_config() -> Dictionary:
	return {
		"save_memory_vectors": save_vector_checkbox.button_pressed,
		"enable_semantic_search": semantic_search_checkbox.button_pressed,
		"use_jieba_tokenization": jieba_checkbox.button_pressed,
		"enable_reranking": rerank_checkbox.button_pressed,
		"enable_time_aware_reranking": time_aware_enhance_checkbox.button_pressed,
		"enable_pre_recall_reasoning": pre_recall_reasoning_checkbox.button_pressed,
		"save_knowledge_graph": save_kg_checkbox.button_pressed,
		"enable_kg_search": kg_search_checkbox.button_pressed,
		"enable_knowledge_forgetting": enable_forgetting_checkbox.button_pressed,
		"advanced_options_enabled": advanced_checkbox.button_pressed,
		"retrieval_top_k": int(retrieval_top_k.value),
		"lexical_match_weight": lexical_weight.value,
		"raw_detail_max_chars": int(raw_detail_max_chars.value),
		"retrieval_min_similarity": retrieval_min_similarity.value,
		"rerank_candidate_multiplier": int(rerank_multiplier.value),
		"reasoning_query_count": int(reasoning_count.value),
		"knowledge_top_k": int(knowledge_top_k.value),
		"knowledge_forgetting_rate": forgetting_rate.value
	}

func load_memory_config() -> void:
	_apply_memory_config(config_manager.load_memory_config())

func _apply_memory_config(config: Dictionary) -> void:
	save_vector_checkbox.button_pressed = config.save_memory_vectors
	semantic_search_checkbox.button_pressed = config.enable_semantic_search
	jieba_checkbox.button_pressed = config.use_jieba_tokenization
	rerank_checkbox.button_pressed = config.enable_reranking
	time_aware_enhance_checkbox.button_pressed = config.enable_time_aware_reranking
	pre_recall_reasoning_checkbox.button_pressed = config.enable_pre_recall_reasoning
	save_kg_checkbox.button_pressed = config.save_knowledge_graph
	kg_search_checkbox.button_pressed = config.enable_kg_search
	enable_forgetting_checkbox.button_pressed = config.get("enable_knowledge_forgetting", true)
	advanced_checkbox.button_pressed = config.advanced_options_enabled
	retrieval_top_k.value = config.retrieval_top_k
	lexical_weight.value = config.lexical_match_weight
	raw_detail_max_chars.value = config.raw_detail_max_chars
	retrieval_min_similarity.value = config.retrieval_min_similarity
	rerank_multiplier.value = config.rerank_candidate_multiplier
	reasoning_count.value = config.reasoning_query_count
	knowledge_top_k.value = config.knowledge_top_k
	forgetting_rate.value = config.knowledge_forgetting_rate
	_update_dependencies()
	_update_advanced_visibility()
