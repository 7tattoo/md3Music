// 临时端到端诊断：Dart 侧用 FFI 起真实 Rust 服务器，再走真正的 KugouApiClient
// 调用 /comment/music -> /comment/music/topliked -> /comment/floor，看 _get 实际拿到什么。
// 用完即删。
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md3music/services/kugou_api/kugou_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _StartNative = Int32 Function(Int32, Pointer<Utf8>);
typedef _Start = int Function(int, Pointer<Utf8>);

void main() {
  test('real client end-to-end against real rust server', () async {
    SharedPreferences.setMockInitialValues({});
    final lib = DynamicLibrary.open(
      r'D:\app\GitHub\md3Music\kugou_api_server\rust\target\release\kugou_server.dll',
    );
    final start = lib.lookupFunction<_StartNative, _Start>('start_server');
    final dir = Directory.systemTemp.createTempSync('kge2e');
    final p = dir.path.toNativeUtf8();
    final port = start(0, p);
    calloc.free(p);
    print('rust server port = $port');
    expect(port, greaterThan(0));

    final api = KugouApiClient();
    api.updateBaseUrl('http://127.0.0.1:$port');
    KugouApiClient.markServerReady();

    final list = await api.getComments('', albumAudioId: '302362878', page: 1);
    print('getComments -> ${list == null ? "NULL" : "n=${list.comments.length} "
        "childrenId=\"${list.childrenId}\" total=${list.total}"}');
    if (list == null) return;

    final hot = await api.getToplikedComments(list.childrenId, page: 1);
    print('getToplikedComments -> ${hot == null ? "NULL  <<<< 最热接口拿不到" : "n=${hot.comments.length}"}');

    final source = (hot != null && hot.comments.isNotEmpty) ? hot : list;
    print('楼层测试用的评论来自: ${source == hot ? "topliked" : "cmtlist"}');

    var tested = 0;
    for (final c in source.comments) {
      if (c.replyCount <= 0) continue;
      final floor = await api.getFloorComments(
        specialId: c.specialId ?? '',
        tid: c.tid ?? c.id,
        mixSongId: (c.mixSongId ?? '').isNotEmpty ? c.mixSongId : null,
        code: c.code,
        page: 1,
        pagesize: 50,
      );
      print('  floor tid=${c.tid ?? c.id} replyCount=${c.replyCount} '
          'specialId="${c.specialId}" code="${c.code}" '
          '-> ${floor == null ? "NULL  <<<< 楼层评论暂不可用" : "n=${floor.comments.length} total=${floor.total}"}');
      if (++tested >= 6) break;
    }
    print('已测楼层 $tested 个');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
