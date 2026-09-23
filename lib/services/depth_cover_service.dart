import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/services/depth_cover_cache.dart';

/// 3D 封面总编排：模型导入 + 缓存 + 原生通道。全局单例。
///
/// 深度模型由用户通过文件选择器导入（设置页入口，sha256 校验后落盘到应用目录）；
/// 原生 [DepthCoverPlugin] 的 loadModel 按路径建立会话；调用前仍需先 loadModel，
/// 否则返回 `MODEL_NOT_LOADED`。失败的生成会被 [DepthCoverCache] 视为未命中，
/// UI 回退平面封面。
class DepthCoverService {
  DepthCoverService._();

  static final instance = DepthCoverService._();

  final cache = DepthCoverCache();

  /// 3D 封面总开关的统一状态源：设置页 / 两播放页界面设置弹层写入，
  /// DepthCoverHost 监听（值变化即重走初始化，开关即时生效）。
  /// 初始 false，由各 UI 首次加载时写入真实值。
  static final ValueNotifier<bool> enabledSignal = ValueNotifier(false);
  static const _channel = MethodChannel('com.md3music.md3music/depth_cover');

  /// 内置模型的资产路径（未导入用户模型时的兜底，原生自动从 APK 提取）。
  static const String _modelAsset = 'models/depth_anything_v2_vits_fp16.onnx';

  /// 原生侧是否已 loadModel（仅当前进程会话有效）。
  bool _modelLoaded = false;

  /// 深度模型文件规格表：字节数 → sha256。导入时按大小查表后校验 sha256，
  /// 避免导错文件后在 ORT 加载阶段报晦涩错误。
  /// fp16（内置主资产，HF onnx-community 导出）+ fp32（历史导入兼容）。
  static const Map<int, String> _kModelSpecs = {
    49642442: '2df6223f206b5164e21f664ace61dabeb9bb6a49b8b5a3e00510b4807d0f5b04',
    99373606: 'd2b11a11c1d4a12b47608fa65a17ee9a4c605b55ee1730c8e3b526304f2562be',
  };
  static const String _modelFileName = 'depth_anything_v2_vits.onnx';

  /// 用户导入的模型在应用目录内的落盘路径。
  Future<String> get modelPath async =>
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}depth_model${Platform.pathSeparator}$_modelFileName';

  /// 模型是否已导入（文件存在且大小在规格表内）。
  Future<bool> isModelImported() async {
    final f = File(await modelPath);
    return f.existsSync() && _kModelSpecs.containsKey(f.lengthSync());
  }

  /// 原生 Toast 提示（3D 封面降级告知用户）。standard 包无该插件 → 静默忽略。
  Future<void> showNativeToast(String message) async {
    try {
      await _channel.invokeMethod<void>('showToast', {'message': message});
    } on PlatformException {
      // 忽略：通道未注册或原生侧异常都不应影响主流程
    } on MissingPluginException {
      // standard 包无 DepthCoverPlugin 属正常
    }
  }

  /// 从文件选择器选中的路径导入模型：按大小查规格表 → sha256 校验 → .part 原子落盘。
  /// 校验失败返回 false 并删除半成品。
  Future<bool> importModel(String pickedPath) async {
    final src = File(pickedPath);
    final expectedSha = _kModelSpecs[src.lengthSync()];
    if (!src.existsSync() || expectedSha == null) {
      debugPrint('[DepthCover] importModel: 文件大小不符（$pickedPath）');
      return false;
    }
    final hash = (await sha256.bind(src.openRead()).first).toString();
    if (hash != expectedSha) {
      debugPrint('[DepthCover] importModel: sha256 不符（$hash）');
      return false;
    }
    final target = File(await modelPath);
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    await src.openRead().pipe(part.openWrite());
    if (!_kModelSpecs.containsKey(await part.length())) {
      await part.delete();
      return false;
    }
    if (target.existsSync()) await target.delete();
    await part.rename(target.path);
    debugPrint('[DepthCover] importModel OK: ${target.path}');
    return true;
  }

  /// 每次封面变化时调用：命中/生成完成都会触发 cache 监听回调。
  ///
  /// 返回 false 仅表示「当前无现成结果」，不代表流程结束（未命中时 UI 先展示平面封面，
  /// 等原生生成后经缓存监听切换为 3D）。
  Future<bool> request(String artworkUri) async {
    debugPrint('[DepthCover] request: uri=${_brief(artworkUri)}');
    if (!_modelLoaded) {
      final loaded = await _ensureNativeModelLoaded();
      debugPrint('[DepthCover] native loadModel → $loaded');
      if (!loaded) return false;
    }
    final ok = await cache.requestLayers(
      artworkUri: artworkUri,
      generate: _generate,
      resolveSource: _resolveSource,
    );
    debugPrint('[DepthCover] requestLayers → $ok');
    return ok;
  }

  /// shader 路径编排：生成单张深度图；封面源同时落缓存目录（shader 需要原图纹理）。
  Future<bool> requestDepth(String artworkUri) async {
    debugPrint('[DepthCover] requestDepth: uri=${_brief(artworkUri)}');
    if (!_modelLoaded) {
      final loaded = await _ensureNativeModelLoaded();
      debugPrint('[DepthCover] native loadModel → $loaded');
      if (!loaded) return false;
    }
    final ok = await cache.requestDepth(
      artworkUri: artworkUri,
      generate: _generateDepth,
      resolveSource: _resolveSourceAndKeep,
    );
    debugPrint('[DepthCover] requestDepth → $ok');
    return ok;
  }

  Future<Map<String, Object?>?> _generateDepth(
    String sourcePath,
    String outDir,
    String key,
  ) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'generateDepth',
        {'sourcePath': sourcePath, 'outDir': outDir, 'key': key},
      );
      if (res == null) {
        debugPrint('[DepthCover] generateDepth → null（同 key 在途）');
        return null;
      }
      final depth = res['depth'];
      final std = res['depthStd'];
      if (depth is String && std is double) {
        return {'depth': depth, 'depthStd': std};
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('[DepthCover] generateDepth failed: ${e.code} ${e.message}');
      return null;
    }
  }

  static String _brief(String uri) =>
      uri.length <= 48 ? uri : '${uri.substring(0, 48)}…';

  /// 先查原生是否已在加载，未加载则先 loadModel（计划遗漏的一环）。
  Future<bool> _ensureNativeModelLoaded() async {
    try {
      final loaded =
          await _channel.invokeMethod<bool>('isModelLoaded');
      if (loaded == true) {
        _modelLoaded = true;
        return true;
      }
      // 优先用用户导入的模型；未导入则用 APK 内置资产（原生自动提取）。
      final args = await isModelImported()
          ? {'modelPath': await modelPath}
          : {'modelAsset': _modelAsset};
      final ok = await _channel.invokeMethod<bool>('loadModel', args);
      if (ok == true) {
        _modelLoaded = true;
        return true;
      }
    } on PlatformException catch (e) {
      debugPrint('[DepthCover] loadModel/isModelLoaded failed: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException catch (e) {
      // standard 包无 DepthCoverPlugin（通道未注册）走这里；depth3d 包不应出现。
      debugPrint('[DepthCover] 通道未注册（standard 包属正常）: $e');
      return false;
    }
    return false;
  }

  Future<List<String>?> _generate(
    String sourcePath,
    String outDir,
    String key,
  ) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'generate',
        {
          'sourcePath': sourcePath,
          'outDir': outDir,
          'key': key,
        },
      );
      if (res == null) {
        debugPrint('[DepthCover] generate → null（同 key 在途）');
        return null;
      }
      final layers = res['layers'];
      if (layers is List) {
        debugPrint('[DepthCover] generate → ${layers.length} 层');
        return layers.cast<String>();
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('[DepthCover] generate failed: ${e.code} ${e.message}');
      return null;
    }
  }

  /// 把各种协议封面解析为本地可解码文件路径；无法解析返回 null（保持平面封面）。
  Future<String?> _resolveSource(String uri) async {
    if (uri.isEmpty) return null;
    if (uri.startsWith('http')) {
      // http(s):// 网络封面 → 下载到临时文件（原生 BitmapFactory 直解 http 不稳妥）。
      final p = await _downloadToTemp(uri);
      debugPrint('[DepthCover] resolveSource http → ${p == null ? "下载失败" : "ok"}');
      return p;
    }
    if (uri.startsWith('file://')) {
      final p = Uri.parse(uri).toFilePath();
      return File(p).existsSync() ? p : null;
    }
    if (uri.startsWith('local://')) {
      // local://<filePath> 内嵌封面懒加载路径，去掉前缀取本地路径。
      final p = uri.substring('local://'.length);
      return File(p).existsSync() ? p : null;
    }
    if (uri.startsWith('content://')) {
      // content:// MediaStore albumart 无法解析为本地文件：保持平面封面，不报错。
      return null;
    }
    // 裸本地路径（非上述任何协议）兜底：存在即可用。
    return File(uri).existsSync() ? uri : null;
  }

  /// 与 [_resolveSource] 协议分发一致，但网络封面不再落临时目录，而是下载到
  /// `cache.ensureEntryDir(key)/cover.img`，避免临时文件被系统清理后 shader 无原图可取。
  Future<String?> _resolveSourceAndKeep(String uri) async {
    if (uri.isEmpty) return null;
    if (uri.startsWith('http')) {
      // http(s):// 网络封面 → 下载到缓存目录（shader 每次构建都要读原图）。
      final key = DepthCoverCache.cacheKey(uri);
      final dir = await cache.ensureEntryDir(key);
      final path = '$dir${Platform.pathSeparator}cover.img';
      try {
        await Dio().download(uri, path);
      } on DioException {
        debugPrint('[DepthCover] resolveSourceAndKeep http → 下载失败');
        return null;
      } catch (_) {
        debugPrint('[DepthCover] resolveSourceAndKeep http → 下载失败');
        return null;
      }
      debugPrint('[DepthCover] resolveSourceAndKeep http → ok');
      return path;
    }
    if (uri.startsWith('file://')) {
      final p = Uri.parse(uri).toFilePath();
      return File(p).existsSync() ? p : null;
    }
    if (uri.startsWith('local://')) {
      final p = uri.substring('local://'.length);
      return File(p).existsSync() ? p : null;
    }
    if (uri.startsWith('content://')) {
      return null;
    }
    return File(uri).existsSync() ? uri : null;
  }

  Future<String?> _downloadToTemp(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/depth_src_${DepthCoverCache.cacheKey(url)}.img';
      await Dio().download(url, path);
      return path;
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
