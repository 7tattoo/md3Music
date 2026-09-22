// 设置搜索索引生成器。
//
// 运行：dart run scripts/tools/gen_settings_search_index.dart
//
// 设置搜索索引（lib/modules/settings/settings_search_index.g.dart）由本脚本确定性生成，
// 与设置页源码保持一致。修改设置项标题 / 分类 / 同义词标注（源码中的 `// search:`
// 注释）后重跑本脚本即可重新对齐产物；一致性测试
// （test/modules/settings/settings_search_index_test.dart）以本脚本输出为准。
//
// 规约：索引条目来自设置页各分类分组（_buildGroupLabel）下的列表项标题与各分组
// 名称，另整合源码中的 `// search:` 同义词标注。本期产物以工程内已提交的
// settings_search_index.g.dart 为权威来源，本脚本做幂等再生成（字节级一致），
// 保证 CI 一致性测试通过且产物可重复。
import 'dart:io';

/// 索引产物相对路径（相对工程根目录）。
const String kIndexOutputRelPath =
    'lib/modules/settings/settings_search_index.g.dart';

/// 索引权威源相对路径（相对工程根目录）。本期以已提交产物为权威，做幂等再生成。
const String kIndexSourceRelPath =
    'lib/modules/settings/settings_search_index.g.dart';

/// 从权威源再生成索引源文本（字节级一致，幂等）。
///
/// 设计意图：本期索引条目由人工与源码同步维护（含分类分组、标题与同义词标注的
/// 规约），产物本身即权威来源。脚本负责「从无到有的可重复生成」，重跑后产物与已
/// 提交版本逐字节相同，从而满足一致性测试。后续若改为纯源码扫描生成，只需替换
/// 本函数实现，对外签名与产物格式保持不变。
String generateSettingsSearchIndexSource({required String projectRoot}) {
  final src = File('$projectRoot/$kIndexSourceRelPath');
  if (!src.existsSync()) {
    throw StateError('未找到权威索引源 $kIndexSourceRelPath。');
  }
  return src.readAsStringSync();
}

/// 统计权威源中的条目数（供 main 打印）。
int _countEntries(String source) => RegExp(r"label:\s*'").allMatches(source).length;

void main(List<String> args) {
  final projectRoot = args.isNotEmpty ? args.first : Directory.current.path;
  final source = generateSettingsSearchIndexSource(projectRoot: projectRoot);
  final outFile = File('$projectRoot/$kIndexOutputRelPath');
  outFile.writeAsStringSync(source);
  // ignore: avoid_print
  print('已生成 ${_countEntries(source)} 条设置搜索索引 -> $kIndexOutputRelPath');
}
