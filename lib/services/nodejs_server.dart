import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// NodeStart function signature: int node_start(int argc, char** argv)
typedef NodeStartNative = Int32 Function(Int32 argc, Pointer<Pointer<Utf8>> argv);
typedef NodeStart = int Function(int argc, Pointer<Pointer<Utf8>> argv);

class NodeJsServer {
  static const _channel = MethodChannel('com.md3music.md3music/nodejs');
  static bool _started = false;

  static Future<void> start() async {
    if (_started || kIsWeb || !Platform.isAndroid) return;

    // 先尝试通过 MethodChannel（原 JNI 方式）
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        await _channel.invokeMethod('startServer');
        _started = true;
        await _waitForReady();
        return;
      } catch (e) {
        print('MethodChannel start failed (attempt ${attempt + 1}): $e');
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // MethodChannel 失败，尝试 dart:ffi 方式
    print('Falling back to dart:ffi approach...');
    try {
      await _startViaFfi();
    } catch (e) {
      print('dart:ffi start also failed: $e');
    }
  }

  static Future<void> _startViaFfi() async {
    // 在独立 Isolate 中运行 Node.js 以避免阻塞 UI
    await Isolate.run(() async {
      try {
        final lib = DynamicLibrary.open('libnode.so');
        final nodeStart = lib
            .lookupFunction<NodeStartNative, NodeStart>('node_start');

        // 构建 argv: ["node", "/path/to/server_bundle.js"]
        final scriptPath = '/data/user/0/com.md3music.md3music/files/nodejs-project/server_bundle.js';
        
        final argv = calloc<Pointer<Utf8>>(3);
        argv[0] = 'node'.toNativeUtf8();
        argv[1] = scriptPath.toNativeUtf8();
        argv[2] = nullptr;

        // 设置 NODE_PATH
        final modulesPath = '/data/user/0/com.md3music.md3music/files/nodejs-project';
        setenv('NODE_PATH', modulesPath);

        final result = nodeStart(2, argv);

        // 释放内存
        calloc.free(argv[0]);
        calloc.free(argv[1]);
        calloc.free(argv);

        print('Node.js exited with code: $result');
      } catch (e) {
        print('Node.js FFI error: $e');
      }
    });

    _started = true;
    await _waitForReady();
  }

  static void setenv(String name, String value) {
    final lib = DynamicLibrary.open('libc.so');
    final setenvFn = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, Pointer<Utf8>, int)>('setenv');
    final namePtr = name.toNativeUtf8();
    final valuePtr = value.toNativeUtf8();
    setenvFn(namePtr, valuePtr, 1);
    calloc.free(namePtr);
    calloc.free(valuePtr);
  }

  static Future<void> _waitForReady() async {
    for (int i = 0; i < 30; i++) {
      try {
        final socket = await Socket.connect('127.0.0.1', 8080,
            timeout: const Duration(seconds: 1));
        await socket.close();
        print('Local Node.js server is ready');
        return;
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    print('Node.js server did not become ready within 30 seconds');
  }

  static Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod('isRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 显式停止本地 Node.js 服务器。要求在确认退出 / Activity onDestroy / 进程被销毁前
  /// 调用，让 libuv 事件循环立即退出，释放 8080 端口，避免下一次冷启动时端口冲突
  /// （cpp 端的 nativeStartNode 会因为 g_running=1 直接拒绝启动）。
  ///
  /// 注意：Android 在后台直接划掉应用时，进程会被系统直接 kill，libuv 线程会随之
  /// 终止；这里仍然调用是为了「确认退出」和「系统通知 Activity 销毁」这两种温和
  /// 退出场景能确定性关停。
  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopServer');
    } catch (e) {
      print('NodeJsServer stop error: $e');
    }
  }
}
