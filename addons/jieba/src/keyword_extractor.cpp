#include "keyword_extractor.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>

#include "cppjieba/Jieba.hpp"
#include "cppjieba/KeywordExtractor.hpp"

#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

using namespace godot;

// ============================================================
// 平台相关的路径处理
// ============================================================

// 桌面端（Windows/macOS/Linux）res:// 可直接读；
// Android/iOS/Web 必须走 user://（由 GDScript 侧预先复制）。
static bool is_desktop_platform() {
#if defined(ANDROID_ENABLED) || defined(IOS_ENABLED) || defined(WEB_ENABLED)
    return false;
#else
    return true;
#endif
}

// 返回 cppjieba 可用的实际文件系统路径（UTF-8 std::string）。
// 失败时返回空字符串，调用方必须检查。
static std::string resolve_cppjieba_path(const String &res_path,
                                          const String &user_name) {
    String actual;

    if (is_desktop_platform()) {
        // 桌面端优先直接用 res://
        if (!FileAccess::file_exists(res_path)) {
            UtilityFunctions::printerr("词典不存在 (res://): ", res_path);
            return std::string();
        }
        actual = ProjectSettings::get_singleton()->globalize_path(res_path);
    } else {
        // 移动端 / Web：res:// 在 C++ 侧读不到，走 user://
        String user_path = "user://" + user_name;
        if (!FileAccess::file_exists(user_path)) {
            UtilityFunctions::printerr("词典不存在 (user://): ", user_path);
            return std::string();
        }
        actual = ProjectSettings::get_singleton()->globalize_path(user_path);
    }

    if (actual.is_empty()) {
        return std::string();
    }

#ifdef _WIN32
    // Windows 上如果路径含非 ASCII（比如用户名是中文），
    // cppjieba 内部的 std::ifstream 会失败。这里尝试转成 8.3 短路径。
     // 先转成 u16string，再显式 reinterpret_cast 成 wchar_t*
    std::u16string u16path = actual.utf16().get_data();
    std::wstring wpath(reinterpret_cast<const wchar_t*>(u16path.c_str()));

    bool ascii_only = true;
    for (wchar_t c : wpath) {
        if (c > 127) {
            ascii_only = false;
            break;
        }
    }

    if (ascii_only) {
        return actual.utf8().get_data();
    }

    // 含中文：尝试 GetShortPathNameW
    DWORD len = GetShortPathNameW(wpath.c_str(), nullptr, 0);
    if (len == 0) {
        UtilityFunctions::printerr(
            "路径含中文且无法获取短路径（可能禁用了 8.3 名称）: ", actual);
        return std::string();
    }

    std::wstring short_path(len, L'\0');
    DWORD ret = GetShortPathNameW(wpath.c_str(), &short_path[0], len);
    if (ret == 0 || ret >= len) {
        UtilityFunctions::printerr("GetShortPathNameW 调用失败: ", actual);
        return std::string();
    }
    short_path.resize(ret);

    int utf8_len = WideCharToMultiByte(CP_UTF8, 0, short_path.c_str(),
                                       (int)short_path.size(),
                                       nullptr, 0, nullptr, nullptr);
    if (utf8_len <= 0) {
        return std::string();
    }

    std::string result(utf8_len, '\0');
    WideCharToMultiByte(CP_UTF8, 0, short_path.c_str(),
                        (int)short_path.size(),
                        &result[0], utf8_len, nullptr, nullptr);
    return result;
#else
    return actual.utf8().get_data();
#endif
}

// ============================================================
// 绑定方法
// ============================================================

void JiebaKeywordExtractor::_bind_methods() {
    ClassDB::bind_method(
        D_METHOD("extract_keywords", "text", "top_k"),
        &JiebaKeywordExtractor::extract_keywords,
        DEFVAL(5));
}

// ============================================================
// 构造 / 析构
// ============================================================

JiebaKeywordExtractor::JiebaKeywordExtractor() {
}

JiebaKeywordExtractor::~JiebaKeywordExtractor() {
    if (extractor_ptr_ != nullptr) {
        delete static_cast<cppjieba::KeywordExtractor *>(extractor_ptr_);
        extractor_ptr_ = nullptr;
    }
}

// ============================================================
// 延迟初始化：只在第一次调用时加载词典
// ============================================================

bool JiebaKeywordExtractor::ensure_extractor() {
    if (init_attempted_) {
        return init_ok_;
    }
    init_attempted_ = true;

    const char *res_paths[4] = {
        "res://addons/jieba/config/jieba.dict.utf8",
        "res://addons/jieba/config/hmm_model.utf8",
        "res://addons/jieba/config/idf.utf8",
        "res://addons/jieba/config/stop_words.utf8",
    };
    const char *user_names[4] = {
        "jieba.dict.utf8",
        "hmm_model.utf8",
        "idf.utf8",
        "stop_words.utf8",
    };

    std::string paths[4];
    for (int i = 0; i < 4; ++i) {
        paths[i] = resolve_cppjieba_path(res_paths[i], user_names[i]);
        if (paths[i].empty()) {
            UtilityFunctions::printerr(
                "无法解析词典路径，关键词提取不可用: ", res_paths[i]);
            init_ok_ = false;
            return false;
        }
    }

    // 构造 cppjieba::KeywordExtractor
    // 注意：如果词典文件损坏，cppjieba 内部可能抛异常。
    // Android 上异常默认关闭，所以构建时必须加 -fexceptions，
    // 否则这里会直接 terminate。详见文末的 SConstruct 修改。
    extractor_ptr_ = new cppjieba::KeywordExtractor(
        paths[0], paths[1], paths[2], paths[3]);

    init_ok_ = true;
    return true;
}

// ============================================================
// 对外接口
// ============================================================

Array JiebaKeywordExtractor::extract_keywords(const String &text, int top_k) {
    Array result;

    if (text.is_empty() || top_k <= 0) {
        return result;
    }

    if (!ensure_extractor()) {
        return result;
    }

    auto *extractor =
        static_cast<cppjieba::KeywordExtractor *>(extractor_ptr_);
    if (extractor == nullptr) {
        return result;
    }

    std::vector<std::string> keywords;
    std::string utf8_text = text.utf8().get_data();
    extractor->Extract(utf8_text, keywords, top_k);

    for (size_t i = 0; i < keywords.size(); ++i) {
        const std::string &kw = keywords[i];
        result.append(String::utf8(kw.c_str(), (int64_t)kw.size()));
    }

    return result;
}