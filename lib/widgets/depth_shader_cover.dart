import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// ShengChao ParallaxCoverView.swift:118-121 同款自适应强度：
/// 目标 std 0.18（层次丰富），平缓封面放大 0.6~2.5 倍；std=0 异常兜底 1.0。
double _shiftScaleFor(double std) {
  if (std <= 0.02) return 1.0;
  return (0.18 / std).clamp(0.6, 2.5).toDouble();
}

/// 逐像素深度位移封面（fragment shader 渲染，ShengChao 同款算法）。
///
/// 输入：原封面文件 + 8-bit 灰度深度图 + 归一化倾斜（已平滑）。
/// [strengthPx] 为背景层最大位移像素（沿用设置项语义，18px ≈ ShengChao 的 0.033×518）。
class DepthShaderCover extends StatefulWidget {
  /// shader 编译/加载失败时回调（宿主据此降级到多层视差并提示用户）。
  final VoidCallback? onFailed;

  /// 倾斜传感器流错误回调（如设备无加速计 → NO_SENSOR）。
  final void Function(Object error)? onTiltError;

  const DepthShaderCover({
    super.key,
    required this.coverPath,
    required this.depthPath,
    required this.depthStd,
    required this.tiltStream,
    required this.strengthPx,
    this.onFailed,
    this.onTiltError,
  });

  final String coverPath;
  final String depthPath;
  final double depthStd;
  final Stream<(double, double)> tiltStream;
  final double strengthPx;

  /// 供测试与调用方使用的自适应强度换算。
  static double shiftScaleFor(double std) => _shiftScaleFor(std);

  @override
  State<DepthShaderCover> createState() => _DepthShaderCoverState();
}

class _DepthShaderCoverState extends State<DepthShaderCover> {
  static ui.FragmentProgram? _program; // 进程级缓存，加载一次

  /// 帧节拍间隔：60fps 上限（高刷屏不再 120 次/秒重绘，观感足够且功耗减半）。
  static const Duration _frameInterval = Duration(milliseconds: 16);

  StreamSubscription<(double, double)>? _sub;
  final ValueNotifier<Offset> _tilt = ValueNotifier(Offset.zero);
  ui.Image? _cover;
  ui.Image? _depth;
  bool _loadFailed = false;

  /// 性能：FragmentShader 实例与纹理采样器绑定只做一次，每帧仅更新 float uniform。
  /// （原先每帧 `program.fragmentShader()` + 两次 setImageSampler，是跟手卡顿主因。）
  ui.FragmentShader? _shader;

  /// 传感器回调只写目标值；由按需定时泵（16ms，约 60fps）推进 EMA 插值。
  ///
  /// **不用常驻 Ticker**：Ticker 活跃时引擎每个 vsync 都会请求一帧（高刷屏 =
  /// 120fps 出帧），即使内容未变也会耗电。按需 Timer 泵只在需要时调度下一拍，
  /// 收敛后无任何存活回调 → 引擎完全不出帧（真静止、真 60fps 上限）。
  Offset _target = Offset.zero;
  Timer? _pump;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = widget.tiltStream.listen(
      (v) {
        _target = Offset(v.$1, v.$2);
        _ensurePump();
      },
      // 传感器不可用（sensors_plus 发 NO_SENSOR）等错误：上报宿主，避免静默失效
      onError: (Object e) {
        debugPrint('[DepthCover] 倾斜传感器错误: $e');
        widget.onTiltError?.call(e);
      },
    );
  }

  /// 确保有一拍在途（在途则不重复调度）。
  void _ensurePump() {
    if (_pump != null) return;
    _pump = Timer(_frameInterval, _pumpStep);
  }

  /// 一拍：EMA(α=0.35) 推进一步；未收敛则继续排下一拍，收敛则吸附到位并停泵。
  void _pumpStep() {
    _pump = null;
    const a = 0.35;
    const eps = 0.0005;
    final cur = _tilt.value;
    final next = Offset(
      cur.dx + (_target.dx - cur.dx) * a,
      cur.dy + (_target.dy - cur.dy) * a,
    );
    if ((_target - next).distance < eps) {
      if (_tilt.value != _target) _tilt.value = _target;
      return; // 收敛：不再排拍（无存活回调 → 零帧请求）
    }
    _tilt.value = next;
    _ensurePump();
  }

  Future<void> _load() async {
    try {
      _program ??= await ui.FragmentProgram.fromAsset('shaders/depth_parallax.frag');
      final results = await Future.wait([
        _decode(widget.coverPath),
        _decode(widget.depthPath),
      ]);
      if (!mounted) return;
      // shader 实例 + 纹理绑定一次性完成（纹理只在加载时变化）
      final shader = _program!.fragmentShader()
        ..setImageSampler(0, results[0])
        ..setImageSampler(1, results[1]);
      setState(() {
        _cover = results[0];
        _depth = results[1];
        _shader = shader;
      });
    } catch (e) {
      debugPrint('[DepthCover] shader 加载失败，回退多层: $e');
      if (mounted) setState(() => _loadFailed = true);
      widget.onFailed?.call(); // 宿主切多层视差 + 原生 toast 提示
    }
  }

  Future<ui.Image> _decode(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pump?.cancel();
    _tilt.dispose();
    _cover?.dispose();
    _depth?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed) {
      // 回退：调用方（DepthCoverHost）会切到多层渲染；这里给原封面占位。
      return Image.file(File(widget.coverPath), fit: BoxFit.cover);
    }
    if (_shader == null || _cover == null || _depth == null) {
      return Image.file(File(widget.coverPath), fit: BoxFit.cover);
    }
    return ClipRect(
      child: RepaintBoundary(
        child: ValueListenableBuilder<Offset>(
          valueListenable: _tilt,
          builder: (context, tilt, _) => CustomPaint(
            painter: _DepthParallaxPainter(
              shader: _shader!,
              cover: _cover!,
              depth: _depth!,
              tilt: tilt,
              strengthPx: widget.strengthPx,
              depthStd: widget.depthStd,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _DepthParallaxPainter extends CustomPainter {
  _DepthParallaxPainter({
    required this.shader,
    required this.cover,
    required this.depth,
    required this.tilt,
    required this.strengthPx,
    required this.depthStd,
  });

  /// 已绑定纹理的 shader 实例（由 State 缓存，每帧仅 setFloat）。
  final ui.FragmentShader shader;
  final ui.Image cover;
  final ui.Image depth;
  final Offset tilt;
  final double strengthPx;
  final double depthStd;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = DepthShaderCover.shiftScaleFor(depthStd);
    // 位移比例 = 用户强度像素 / 画布宽 × 自适应缩放（18px@500px ≈ 0.036 ≈ ShengChao 0.033）
    final shift = (strengthPx / size.width) * scale;
    // 自适应步数（降功耗）：每步 ≈ 1.2px 位移量化；静止=2 步，明显倾斜才用满 10 步。
    final shiftPxNow = strengthPx * scale * tilt.distance.clamp(0.0, 1.0);
    final maxStep = (shiftPxNow / 1.2 + 2.0).clamp(2.0, 10.0);
    // 复用已绑纹理的 shader 实例：每帧只更新 float uniform（无分配、无纹理重绑）
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, tilt.dx)
      ..setFloat(3, tilt.dy)
      ..setFloat(4, shift)
      ..setFloat(5, maxStep);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_DepthParallaxPainter old) =>
      old.tilt != tilt ||
      old.strengthPx != strengthPx ||
      !identical(old.shader, shader) ||
      identical(old.cover, cover) == false ||
      identical(old.depth, depth) == false;
}
