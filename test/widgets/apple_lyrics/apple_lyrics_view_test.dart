import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/widgets/apple_lyrics/apple_lyrics_view.dart';
import '../../../lib/widgets/apple_lyrics/models/lyric_line.dart';

/// AppleLyricsView 行为测试。
///
/// 覆盖 PR12 引入的：
/// - [AppleLyricsView.effectiveLineEndTime]（人声实际结束时间，KRC 间奏 gap 判定）
/// - P0-A 播放中静止省电：非逐字歌词（LRC 逐行/纯文本）收敛后停止 Ticker，
///   逐字歌词（KRC/字级 LRC）保持 Ticker 推进动画。
void main() {
  group('AppleLyricsView.effectiveLineEndTime', () {
    test('无逐字行（LRC/纯文本）返回 endTime = startTime + duration', () {
      const line = LyricLine(startTime: 1000, duration: 0, text: 'A');
      expect(AppleLyricsView.effectiveLineEndTime(line), 1000);
      const line2 = LyricLine(startTime: 1000, duration: 500, text: 'A');
      expect(AppleLyricsView.effectiveLineEndTime(line2), 1500);
    });

    test('逐字行（KRC）：行 duration 覆盖空白时取最后一个字结束时间', () {
      const line = LyricLine(
        startTime: 12500,
        duration: 4200, // 行 duration 覆盖到 16700（含尾音/空白）
        text: '運命の華',
        words: [
          LyricWord(startTime: 12500, duration: 300, text: '運'),
          LyricWord(startTime: 12800, duration: 400, text: '命'),
          LyricWord(startTime: 13700, duration: 600, text: '華'), // 结束于 14300
        ],
      );
      // 最后一个字结束 14300 < 行 duration 结束 16700 → 取 14300
      expect(AppleLyricsView.effectiveLineEndTime(line), 14300);
    });

    test('逐字行（KRC）：行 duration 精确覆盖到最后字时不改变行为', () {
      const line = LyricLine(
        startTime: 12500,
        duration: 1800, // 恰好 = 最后字结束偏移（12500+1800=14300）
        text: '運命の華',
        words: [
          LyricWord(startTime: 12500, duration: 300, text: '運'),
          LyricWord(startTime: 13700, duration: 600, text: '華'),
        ],
      );
      expect(AppleLyricsView.effectiveLineEndTime(line), 14300);
    });
  });

  group('AppleLyricsView P0-A Ticker 停止（非逐字省电）', () {
    testWidgets('非逐字歌词（LRC 逐行/纯文本）播放中收敛后停止 Ticker', (tester) async {
      // gap = 1000 - 0 = 1000 < 4000 → 无间奏，画面可完全静止
      final lines = <LyricLine>[
        LyricLine(startTime: 0, duration: 0, text: 'Line 1'),
        LyricLine(startTime: 1000, duration: 0, text: 'Line 2'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: AppleLyricsView(
                lines: lines,
                currentTimeMs: 0,
                isPlaying: true,
              ),
            ),
          ),
        ),
      );
      // 推进足够帧：首帧动画 + posY 弹簧（过阻尼，0→targetY≈190px
      // 收敛到 settle 阈值需约 2s）全部收敛后触发 Ticker 停止
      for (int i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.binding.transientCallbackCount, 0,
          reason: '非逐字歌词播放中画面静止后应停止 Ticker');
    });

    testWidgets('逐字歌词（KRC/字级 LRC，含本地/云盘 LRC 逐字）播放中保持 Ticker', (tester) async {
      final lines = <LyricLine>[
        LyricLine(
          startTime: 0,
          duration: 5000,
          text: '逐字歌词',
          words: const [
            LyricWord(startTime: 0, duration: 5000, text: '逐字歌词'),
          ],
        ),
        LyricLine(startTime: 5000, duration: 5000, text: '第二行'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: AppleLyricsView(
                lines: lines,
                currentTimeMs: 0,
                isPlaying: true,
              ),
            ),
          ),
        ),
      );
      // 字内渐变/上浮动画推进中（5 帧 < 字时长），不应停止
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: '逐字歌词（含本地/云盘 LRC 逐字）播放中必须保持 Ticker');
    });
  });
}
