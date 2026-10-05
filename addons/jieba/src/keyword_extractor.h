#ifndef KEYWORD_EXTRACTOR_H
#define KEYWORD_EXTRACTOR_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/binder_common.hpp>

namespace godot {

class JiebaKeywordExtractor : public RefCounted {
    GDCLASS(JiebaKeywordExtractor, RefCounted)

private:
    // 延迟初始化，避免每次调用都重新加载词典
    // 用 void* 是为了不在头文件里暴露 cppjieba 类型
    void *extractor_ptr_ = nullptr;
    bool   init_attempted_ = false;
    bool   init_ok_ = false;

    bool ensure_extractor();

protected:
    static void _bind_methods();

public:
    JiebaKeywordExtractor();
    ~JiebaKeywordExtractor();

    Array extract_keywords(const String &text, int top_k = 5);
};

}

#endif // KEYWORD_EXTRACTOR_H