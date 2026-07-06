#include <jni.h>
#include <string>
#include <vector>
#include <cstdlib>
#include <cstring>
#include <pthread.h>
#include <android/log.h>
#include "node.h"
#include "uv.h"

#define ADBTAG "KUGOU-NODEJS"

// ========== Node.js 分步初始化（参考 Toyo 教程） ==========
namespace {
    std::vector<std::string> args;
    std::vector<std::string> exec_args;
    std::vector<std::string> errors;
    std::unique_ptr<node::MultiIsolatePlatform> platform;
}

// ========== JNI 共享状态（需在所有函数定义前声明） ==========
static volatile int g_running = 0;
static volatile int g_stop_requested = 0;

class Args {
public:
    Args() noexcept : p(nullptr), len(0) {}
    ~Args() { if (p) { for (size_t i = 0; i < len; i++) free(p[i]); free(p); } }
    void parse(const std::vector<std::string>& arr) {
        len = arr.size();
        p = (char**)calloc(len, sizeof(char*));
        for (size_t i = 0; i < len; i++) p[i] = strdup(arr[i].c_str());
    }
    char** data() const noexcept { return p; }
    size_t size() const noexcept { return len; }
private:
    char** p;
    size_t len;
};

int initializeNode() {
    Args cliArgs;
    args = { "node" };
    cliArgs.parse(args);
    uv_setup_args(cliArgs.size(), cliArgs.data());

    int exit_code = node::InitializeNodeWithArgs(&args, &exec_args, &errors);
    for (const std::string& error : errors)
        __android_log_print(ANDROID_LOG_ERROR, ADBTAG, "%s", error.c_str());
    if (exit_code != 0) return exit_code;

    platform = node::MultiIsolatePlatform::Create(4);
    v8::V8::InitializePlatform(platform.get());
    v8::V8::Initialize();
    return 0;
}

// ========== Node.js 运行实例 ==========
uv_loop_t loop;
std::shared_ptr<node::ArrayBufferAllocator> allocator;
v8::Isolate* isolate = nullptr;
node::IsolateData* isolate_data = nullptr;
node::Environment* env = nullptr;
v8::Global<v8::Context> context;
int node_initialized = 0;

int setupNodeInstance() {
    if (node_initialized) return 0;

    int ret = uv_loop_init(&loop);
    if (ret != 0) {
        __android_log_print(ANDROID_LOG_ERROR, ADBTAG, "Failed to init uv_loop: %s", uv_err_name(ret));
        return ret;
    }

    allocator = node::ArrayBufferAllocator::Create();
    isolate = node::NewIsolate(allocator.get(), &loop, platform.get());
    if (!isolate) {
        __android_log_print(ANDROID_LOG_ERROR, ADBTAG, "Failed to create V8 Isolate");
        return -1;
    }

    v8::Locker locker(isolate);
    v8::Isolate::Scope isolate_scope(isolate);
    isolate_data = node::CreateIsolateData(isolate, &loop, platform.get(), allocator.get());

    v8::HandleScope handle_scope(isolate);
    v8::Local<v8::Context> ctx = node::NewContext(isolate);
    context.Reset(isolate, ctx);

    if (ctx.IsEmpty()) {
        __android_log_print(ANDROID_LOG_ERROR, ADBTAG, "Failed to create V8 Context");
        return -1;
    }

    v8::Context::Scope context_scope(ctx);
    env = node::CreateEnvironment(isolate_data, ctx, args, exec_args);

    // 用 node::LoadEnvironment 引导模块系统（设置 require 等）
    v8::TryCatch trycatch(isolate);
    v8::MaybeLocal<v8::Value> loadenv_ret = node::LoadEnvironment(env,
        "(function () {"
        "  globalThis.require = require('module').createRequire(process.cwd() + '/');"
        "})();"
    );
    if (loadenv_ret.IsEmpty()) {
        if (trycatch.HasCaught()) {
            v8::String::Utf8Value err(isolate, trycatch.Exception());
            __android_log_print(ANDROID_LOG_ERROR, ADBTAG, "LoadEnvironment failed: %s", *err);
        }
        return -1;
    }

    node_initialized = 1;
    __android_log_print(ANDROID_LOG_INFO, ADBTAG, "Node.js instance initialized with require");
    return 0;
}

void spinEventLoop() {
    v8::SealHandleScope seal(isolate);
    bool more;
    do {
        uv_run(&loop, UV_RUN_DEFAULT);
        // 收到停止请求时立即退出事件循环（uv_stop 已打断 uv_run）
        if (g_stop_requested) break;
        platform->DrainTasks(isolate);
        more = uv_loop_alive(&loop);
        if (more) continue;
        node::EmitBeforeExit(env);
        more = uv_loop_alive(&loop);
    } while (more);
    g_running = 0;
}

// ========== 执行 JS 脚本 ==========
int evalScript(const char* scriptPath) {
    v8::Locker locker(isolate);
    v8::Isolate::Scope isolate_scope(isolate);
    v8::HandleScope handle_scope(isolate);
    auto ctx = context.Get(isolate);
    v8::Context::Scope context_scope(ctx);

    // 使用 module._load 加载打包好的 JS 文件
    std::string loadCmd = "(function(){ return require('module')._load('" +
        std::string(scriptPath) + "', null, true) })()";
    v8::Local<v8::String> runScript = v8::String::NewFromUtf8(isolate, loadCmd.c_str()).ToLocalChecked();
    auto maybe_script = v8::Script::Compile(ctx, runScript);

    if (maybe_script.IsEmpty()) {
        __android_log_print(ANDROID_LOG_ERROR, ADBTAG, "Failed to compile script");
        return 1;
    }

    v8::TryCatch trycatch(isolate);
    auto result = maybe_script.ToLocalChecked()->Run(ctx);
    if (result.IsEmpty()) {
        if (trycatch.HasCaught()) {
            v8::String::Utf8Value err(isolate, trycatch.Exception());
            __android_log_print(ANDROID_LOG_ERROR, ADBTAG, "Script error: %s", *err);
        }
        return 1;
    }

    spinEventLoop();
    return 0;
}

// ========== JNI 接口 ==========
static void* node_thread(void *arg) {
    char* scriptPath = (char*)arg;
    g_running = 1;
    g_stop_requested = 0;
    __android_log_print(ANDROID_LOG_INFO, ADBTAG, "Starting Node.js...");

    int result = evalScript(scriptPath);

    g_running = 0;
    g_stop_requested = 0;
    __android_log_print(ANDROID_LOG_INFO, ADBTAG, "Node.js exited with code: %d", result);

    free(scriptPath);
    return NULL;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_md3music_md3music_NodeJsService_nativeStartNode(
    JNIEnv *env, jobject thiz, jobjectArray args, jstring modulesPath) {

    if (g_running) return -1;

    // 设置 NODE_PATH
    const char* path = env->GetStringUTFChars(modulesPath, 0);
    setenv("NODE_PATH", path, 1);
    env->ReleaseStringUTFChars(modulesPath, path);

    // 初始化 Node.js（如果尚未初始化）
    int init_result = initializeNode();
    if (init_result != 0) {
        __android_log_print(ANDROID_LOG_ERROR, ADBTAG, "Node.js init failed: %d", init_result);
        return -1;
    }

    // 创建 Node.js 实例
    int instance_result = setupNodeInstance();
    if (instance_result != 0) {
        __android_log_print(ANDROID_LOG_ERROR, ADBTAG, "Node.js instance failed: %d", instance_result);
        return -1;
    }

    // 获取脚本路径
    jstring scriptJStr = (jstring)env->GetObjectArrayElement(args, 0);
    const char* scriptCStr = env->GetStringUTFChars(scriptJStr, NULL);
    char* scriptCopy = strdup(scriptCStr);
    env->ReleaseStringUTFChars(scriptJStr, scriptCStr);

    // 在后台线程运行脚本
    pthread_t thread;
    pthread_create(&thread, NULL, node_thread, scriptCopy);
    pthread_detach(thread);

    return 0;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_md3music_md3music_NodeJsService_nativeIsNodeRunning(
    JNIEnv *env, jobject thiz) {
    return g_running ? JNI_TRUE : JNI_FALSE;
}

// 显式停止 Node.js 事件循环：设置停止标志并打断 uv_run。
// 由于 Node 运行在应用进程内的原生线程上，进程退出/被系统回收时 OS 也会一并销毁，
// 这里提供确定性关闭，确保在确认退出或 Activity 销毁时能立即停止对外服务。
extern "C" JNIEXPORT void JNICALL
Java_com_md3music_md3music_NodeJsService_nativeStopNode(
    JNIEnv *env, jobject thiz) {
    if (!g_running) return;
    g_stop_requested = 1;
    // uv_stop 可从任意线程安全调用，会让正在运行的 uv_run 在下一次迭代前返回
    uv_stop(&loop);
    __android_log_print(ANDROID_LOG_INFO, ADBTAG, "Node.js stop requested");
}
