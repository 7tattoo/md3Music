import re

path = r'C:\Users\32732\Desktop\TRAE SOLO\md3Music\lib\services\kugou_api\kugou_api_client.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 冲突1: _fetchLyricContent - 采用 fix 分支（带诊断日志）
block1 = """      final data = json['data'] as Map<String, dynamic>? ?? json;
      if (kDebugMode) {
        debugPrint('[LyriconDebug._fetchLyricContent] fmt=$fmt, lyricId=$lyricId, '
            'response top-level keys=${json.keys.toList()..sort()}, '
            'data keys=${data.keys.toList()..sort()}');
      }
      return data;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LyriconDebug._fetchLyricContent] error fmt=$fmt: $e');
      }"""

# 冲突2: mergeLyricResponses 日志 - 合并诊断日志 + HEAD 多行格式
block2 = """    // 诊断日志：打印 API 返回的所有顶层字段，确认翻译字段名
    if (kDebugMode) {
      if (lrcJson != null) {
        final keys = lrcJson.keys.toList()..sort();
        debugPrint('[LyriconDebug.mergeLyric] lrcJson keys: $keys');
        // 找出可能是翻译的字段
        for (final k in keys) {
          if (k.toLowerCase().contains('trans') ||
              k.toLowerCase().contains('chi') ||
              k.toLowerCase().contains('translate') ||
              k.toLowerCase().contains('bilingual')) {
            final v = lrcJson[k];
            final preview = v == null ? 'null' : (v.toString().length > 100 ? '${v.toString().substring(0, 100)}...' : v.toString());
            debugPrint('[LyriconDebug.mergeLyric] lrcJson[$k] = $preview');
          }
        }
      }
      if (krcJson != null) {
        final keys = krcJson.keys.toList()..sort();
        debugPrint('[LyriconDebug.mergeLyric] krcJson keys: $keys');
        for (final k in keys) {
          if (k.toLowerCase().contains('trans') ||
              k.toLowerCase().contains('chi') ||
              k.toLowerCase().contains('translate') ||
              k.toLowerCase().contains('bilingual')) {
            final v = krcJson[k];
            final preview = v == null ? 'null' : (v.toString().length > 100 ? '${v.toString().substring(0, 100)}...' : v.toString());
            debugPrint('[LyriconDebug.mergeLyric] krcJson[$k] = $preview');
          }
        }
      }
    }
    final lrcLyric =
        lrcJson != null ? KugouLyric.fromJson(lrcJson) : null;
    final krcLyric =
        krcJson != null ? KugouLyric.fromJson(krcJson) : null;
    // KRC 明文：优先用专用字段，否则把 KRC 响应的 decodeContent 当作 KRC 明文"""

# 冲突3: 返回值 - 采用 fix 分支翻译提取逻辑 + HEAD 多行格式
block3 = """    // 从 KRC [language:] 字段提取翻译（酷狗翻译只在 KRC 里，LRC 接口无翻译）
    // 格式：[language:<base64>] 解码后是 {"content":[{"language":0,"lyricContent":[["行1"],["行2"],...]},{"language":1,...}]}
    // language=0 是中文翻译，language=1 是音译（罗马音）
    // lyricContent 按行序对应 KRC 歌词行，无时间戳，需要从 KRC 明文提取每行时间戳合成 LRC
    String? translationLrc =
        lrcLyric?.translatedContent ?? krcLyric?.translatedContent;
    if (translationLrc == null && krcContent != null) {
      translationLrc = _extractTranslationFromKrc(krcContent);
    }

    final merged = KugouLyric(
      content: lrcLyric?.content ?? krcLyric?.content ?? '',
      decodedContent: lrcLyric?.decodedContent,
      decodedKrcContent: krcContent,
      translatedContent: translationLrc,"""


def replace_conflict(text, resolved):
    pattern = r'<<<<<<< HEAD\n.*?\n=======\n.*?\n>>>>>>> fix-lyricon-provider-init-g6QqED\n'
    return re.sub(pattern, lambda m: resolved + '\n', text, count=1, flags=re.DOTALL)


content = replace_conflict(content, block1)
content = replace_conflict(content, block2)
content = replace_conflict(content, block3)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Remaining conflict markers:', content.count('<<<<<<< HEAD'))
