# AI 配置管理模块
# 负责：配置的加载、保存、迁移等

extends Node

const CONFIG_PATH = "user://ai_keys.json"

# 配置模板定义
const CONFIG_TEMPLATES = {
    "free": {
        "name": "免费",
        "description": "没有语音，而且不太聪明，但是免费",
        "chat_model": {
            "model": "Qwen/Qwen3-8B",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "summary_model": {
            "model": "Qwen/Qwen3-8B",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "tts_model": {
            "model": "【DISABLED】",
            "base_url": "【DISABLED】",
        },
        "embedding_model": {
            "model": "BAAI/bge-m3",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "view_model": {
            "model": "THUDM/GLM-4.1V-9B-Thinking",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "stt_model": {
            "model": "FunAudioLLM/SenseVoiceSmall",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "rerank_model": {
            "model": "BAAI/bge-reranker-v2-m3",
            "base_url": "https://api.siliconflow.cn/v1"
        }
    },
    "standard": {
        "name": "标准",
        "description": "以高性价比获得更佳的体验",
        "chat_model": {
            "model": "deepseek-ai/DeepSeek-V3.2",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "summary_model": {
            "model": "Qwen/Qwen3-30B-A3B-Instruct-2507",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "tts_model": {
            "model": "FunAudioLLM/CosyVoice2-0.5B",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "embedding_model": {
            "model": "BAAI/bge-m3",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "view_model": {
            "model": "Qwen/Qwen3-Omni-30B-A3B-Captioner",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "stt_model": {
            "model": "FunAudioLLM/SenseVoiceSmall",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "rerank_model": {
            "model": "BAAI/bge-reranker-v2-m3",
            "base_url": "https://api.siliconflow.cn/v1"
        }
    },
    "alternate": {
        "name": "备用",
        "description": "比标准稍微差点，可以作为备选",
        "chat_model": {
            "model": "deepseek-ai/DeepSeek-V3",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "summary_model": {
            "model": "Qwen/Qwen3-30B-A3B-Instruct-2507",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "tts_model": {
            "model": "IndexTeam/IndexTTS-2",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "embedding_model": {
            "model": "BAAI/bge-m3",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "view_model": {
            "model": "Qwen/Qwen3-Omni-30B-A3B-Captioner",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "stt_model": {
            "model": "FunAudioLLM/SenseVoiceSmall",
            "base_url": "https://api.siliconflow.cn/v1"
        },
        "rerank_model": {
            "model": "BAAI/bge-reranker-v2-m3",
            "base_url": "https://api.siliconflow.cn/v1"
        }
    }
}

## 加载现有配置
func load_config() -> Dictionary:
    var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
    if file == null:
        return {}
    
    var json_string = file.get_as_text()
    file.close()
    
    var json = JSON.new()
    if json.parse(json_string) != OK:
        return {}
    
    return json.data as Dictionary

## 保存配置到文件
func save_config(config: Dictionary) -> bool:
    # 先加载现有配置，避免覆盖其他设置
    var existing_config = load_config()
    
    # 合并新配置到现有配置中
    for key in config.keys():
        existing_config[key] = config[key]
    
    var file = FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
    if file == null:
        return false
    
    file.store_string(JSON.stringify(existing_config, "\t"))
    file.close()
    
    print("AI配置已保存")
    return true

## 获取模板配置
func get_template(template_name: String) -> Dictionary:
    if CONFIG_TEMPLATES.has(template_name):
        return CONFIG_TEMPLATES[template_name]
    return {}

## 获取所有模板
func get_all_templates() -> Dictionary:
    return CONFIG_TEMPLATES

## 验证API密钥
func verify_api_key(input_key: String) -> bool:
    if not FileAccess.file_exists(CONFIG_PATH):
        return false
    
    var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
    var json_string = file.get_as_text()
    file.close()
    
    var json = JSON.new()
    if json.parse(json_string) != OK:
        return false
    
    var config = json.data
    
    # 检查 chat_model 的 api_key
    if config.has("chat_model") and config.chat_model.has("api_key"):
        if config.chat_model.api_key == input_key:
            return true
    
    # 检查快速配置的 api_key
    if config.has("api_key"):
        if config.api_key == input_key:
            return true
    
    return false

## 加载特定模型的配置
func load_model_config(model_type: String) -> Dictionary:
    var config = load_config()
    
    if config.has(model_type):
        return config[model_type] as Dictionary
    
    return {}

## 保存响应模式
func save_response_mode(mode: String) -> bool:
    var config = load_config()
    config["response_mode"] = mode
    return save_config(config)

## 加载响应模式
func load_response_mode() -> String:
    var config = load_config()
    return config.get("response_mode", "verbal")

## 保存记忆系统配置
func save_memory_config(memory_config: Dictionary) -> bool:
    var config = load_config()
    config["memory_system"] = memory_config
    return save_config(config)

## 加载记忆系统配置
func load_memory_config() -> Dictionary:
    var config = load_config()
    var default_config = {
        "save_memory_vectors": true,
        "enable_semantic_search": true,
        "enable_reranking": true,
        "enable_pre_recall_reasoning": false,
        "save_knowledge_graph": true,
        "enable_kg_search": true
    }

    if config.has("memory_system"):
        var memory_config = config.memory_system
        # 合并默认配置，确保所有字段都存在
        for key in default_config.keys():
            if not memory_config.has(key):
                memory_config[key] = default_config[key]
        return memory_config

    return default_config

## 保存表情差分设置
func save_expression_diff(enabled: bool) -> bool:
    var config = load_config()
    config["expression_diff"] = enabled
    return save_config(config)

## 加载表情差分设置
func load_expression_diff() -> bool:
    var config = load_config()
    return config.get("expression_diff", true) # 默认开启

## 保存生成选项设置
func save_generation_options(enabled: bool) -> bool:
    var config = load_config()
    config["generation_options"] = enabled
    return save_config(config)

## 加载生成选项设置
func load_generation_options() -> bool:
    var config = load_config()
    return config.get("generation_options", true) # 默认开启

## 保存上方输入框设置
func save_top_input_box(enabled: bool) -> bool:
    var config = load_config()
    config["top_input_box"] = enabled
    var result = save_config(config)
    print("ConfigManager: 保存顶部输入框设置 = %s, 结果 = %s" % [enabled, result])
    return result

## 加载上方输入框设置
func load_top_input_box() -> bool:
    var config = load_config()
    var value = config.get("top_input_box", false) # 默认关闭
    print("ConfigManager: 加载顶部输入框设置 = %s (配置文件: %s)" % [value, CONFIG_PATH])
    return value

## 保存使用内置密钥设置
func save_use_builtin_key(enabled: bool) -> bool:
    var config = load_config()
    config["use_builtin_key"] = enabled
    return save_config(config)

## 加载使用内置密钥设置
func load_use_builtin_key() -> bool:
    var config = load_config()
    return config.get("use_builtin_key", false) # 默认关闭

## 保存呼唤触发对话设置
func save_call_trigger_dialog(enabled: bool) -> bool:
    var config = load_config()
    config["call_trigger_dialog"] = enabled
    return save_config(config)

## 加载呼唤触发对话设置
func load_call_trigger_dialog() -> bool:
    var config = load_config()
    return config.get("call_trigger_dialog", true) # 默认开启

## 保存文本输出速度（秒/字）
func save_typing_speed(speed: float) -> bool:
    var config = load_config()
    # 防止异常值写入配置
    var clamped_speed = clampf(speed, 0.01, 0.09)
    config["typing_speed"] =clamped_speed
    return save_config(config)

## 加载文本输出速度（秒/字）
func load_typing_speed() -> float:
    var config = load_config()
    var speed = float(config.get("typing_speed", 0.05))
    return clampf(speed, 0.01, 0.09)

## 保存自动播放设置
func save_auto_continue(enabled: bool) -> bool:
    var config = load_config()
    config["auto_continue"] = enabled
    var result = save_config(config)
    print("ConfigManager: 保存自动播放设置 = %s, 结果 = %s" % [enabled, result])
    return result

## 加载自动播放设置
func load_auto_continue() -> bool:
    var config = load_config()
    var value = config.get("auto_continue", false) # 默认关闭
    return value

## 遮蔽密钥显示
func mask_key(key: String) -> String:
    if key.length() <= 10:
        return "***"
    return key.substr(0, 7) + "..." + key.substr(key.length() - 4)
