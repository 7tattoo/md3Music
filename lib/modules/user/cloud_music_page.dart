import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/song.dart';
import '../../providers/player_provider.dart';
import '../../services/kugou_api/cloud_song_mapper.dart';
import '../../services/kugou_api/kugou_api_client.dart';
import '../../widgets/md3e_loading_indicator.dart';
import '../../widgets/md3e_refresh_indicator.dart';
import '../../widgets/song_list_item.dart';
import '../player/mini_player.dart';

class CloudMusicPage extends StatefulWidget {
  const CloudMusicPage({super.key});

  @override
  State<CloudMusicPage> createState() => _CloudMusicPageState();
}

class _CloudMusicPageState extends State<CloudMusicPage> {
  List<Song> _songs = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // 多选删除模式
  bool _isSelectMode = false;
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _loadCloudSongs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 内存过滤：根据当前搜索词匹配 title / artist（不区分大小写、子串）。
  List<Song> get _filteredSongs {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _songs;
    return _songs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q);
    }).toList();
  }

  /// 云盘歌曲加载上限，与服务端实际限制对齐。
  static const int _maxCloudSongs = 6000;

  Future<void> _loadCloudSongs() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = KugouApiClient();
      if (!api.isLoggedIn) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = '请先登录';
          });
        }
        return;
      }

      const int pageSize = 100;
      // 向上取整，保证能拉到 _maxCloudSongs 首（100*60=6000）
      const int maxPages = (_maxCloudSongs + pageSize - 1) ~/ pageSize;

      final songs = <Song>[];
      for (int page = 1; page <= maxPages; page++) {
        final result = await api.getUserCloud(page: page, pagesize: pageSize);
        if (!mounted) return;

        if (result == null) {
          // 第一页失败才报错，后续页失败静默停止
          if (page == 1) {
            setState(() {
              _isLoading = false;
              _error = '加载失败，请稍后重试';
            });
            return;
          }
          break;
        }

        final data = result['data'];
        final list = _safeExtractList(data);
        if (list == null || list.isEmpty) break;

        if (page == 1 && list.isNotEmpty && kDebugMode) {
          debugPrint('[CloudMusic] first item keys: ${list.first is Map<String, dynamic> ? (list.first as Map<String, dynamic>).keys.toList() : list.first.runtimeType}');
          debugPrint('[CloudMusic] first item: ${list.first}');
        }

        for (final e in list) {
          if (e is Map<String, dynamic>) {
            final song = mapCloudApiItemToSong(e);
            if (song.id.isNotEmpty) songs.add(song);
          }
        }

        if (songs.length >= _maxCloudSongs) {
          songs.removeRange(_maxCloudSongs, songs.length);
          break;
        }
        if (list.length < pageSize) break;
      }

      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '加载失败：$e';
        });
      }
    }
  }

  /// 安全地从响应字段提取歌曲列表。
  /// 兼容以下情况：
  /// 1. 字段本身就是 List（直接返回）。
  /// 2. 字段是 Map 且 info/list 字段本身是 List。
  /// 3. 字段是 Map 且 info/list 字段是 JSON 编码的字符串（酷狗部分接口
  ///    偶发返回 `data = {"info": "[{...},...]"}` 这种格式，
  ///    直接 `as List<dynamic>?` 会抛类型转换异常）。
  /// 4. 字段是 JSON 编码的字符串本身。
  /// 解析失败返回 null（按空列表处理）。
  static List<dynamic>? _safeExtractList(dynamic data) {
    if (data is List) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is List) return decoded;
        if (decoded is Map) {
          final inner = decoded['info'] ?? decoded['list'];
          if (inner is List) return inner;
          if (inner is String) {
            final innerDecoded = jsonDecode(inner);
            if (innerDecoded is List) return innerDecoded;
          }
        }
      } catch (_) {
        return null;
      }
      return null;
    }
    if (data is Map<String, dynamic>) {
      for (final key in const ['info', 'list']) {
        final inner = data[key];
        if (inner is List) return inner;
        if (inner is String) {
          try {
            final decoded = jsonDecode(inner);
            if (decoded is List) return decoded;
          } catch (_) {
            // 继续尝试下个字段
          }
        }
      }
    }
    return null;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectMode ? '已选 ${_selectedIndices.length} 首' : '云盘音乐',
        ),
        actions: _isSelectMode
            ? [
                IconButton(
                  tooltip: '全选',
                  icon: const Icon(Icons.select_all),
                  onPressed: _toggleSelectAll,
                ),
                IconButton(
                  tooltip: '取消',
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectMode,
                ),
              ]
            : [
                IconButton(
                  tooltip: '多选删除',
                  icon: const Icon(Icons.checklist),
                  onPressed: _enterSelectMode,
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: MD3ELoadingIndicator())
          : _error != null
              ? _buildError()
              : _songs.isEmpty
                  ? MD3ERefreshIndicator(
                      onRefresh: _loadCloudSongs,
                      child: ListView(
                        children: [_buildEmpty()],
                      ),
                    )
                  : MD3ERefreshIndicator(
                      onRefresh: _loadCloudSongs,
                      child: Column(
                        children: [
                          if (!_isSelectMode) _buildHeader(),
                          if (!_isSelectMode) _buildSearchBar(),
                          Expanded(
                            child: _filteredSongs.isEmpty
                                ? _buildNoMatch()
                                : ListView.builder(
                                    itemCount: _filteredSongs.length,
                                    itemBuilder: (context, index) {
                                      final song = _filteredSongs[index];
                                      return SongListItem(
                                        song: song,
                                        onTap: () {
                                          context
                                              .read<PlayerProvider>()
                                              .playCloudPlaylist(
                                                _filteredSongs,
                                                index,
                                              );
                                        },
                                        onMoreTap: _isSelectMode
                                            ? null
                                            : () => _showSongMoreMenu(song),
                                        isSelectMode: _isSelectMode,
                                        isSelected:
                                            _selectedIndices.contains(index),
                                        onSelectToggle: () =>
                                            _toggleSelect(index),
                                        onLongPress: _isSelectMode
                                            ? _toggleSelectAll
                                            : null,
                                      );
                                    },
                                  ),
                          ),
                          if (_isSelectMode) _buildSelectActionBar(),
                          const MiniPlayer(),
                        ],
                      ),
                    ),
    );
  }

  /// 进入批量删除多选模式。
  void _enterSelectMode() {
    setState(() {
      _isSelectMode = true;
      _selectedIndices.clear();
    });
  }

  /// 退出多选模式并清空选中。
  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedIndices.clear();
    });
  }

  /// 切换某一下标的选中状态。
  void _toggleSelect(int index) {
    setState(() {
      if (!_selectedIndices.remove(index)) {
        _selectedIndices.add(index);
      }
    });
  }

  /// 全选 / 取消全选（作用于当前过滤后的可见列表）。
  void _toggleSelectAll() {
    setState(() {
      if (_selectedIndices.length == _filteredSongs.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices
            .addAll(List.generate(_filteredSongs.length, (i) => i));
      }
    });
  }

  /// 列表项三点菜单：单曲删除入口。
  void _showSongMoreMenu(Song song) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.music_note),
              title: Text(song.displayName),
              subtitle: Text(song.artist),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colorScheme.error),
              title: Text(
                '删除',
                style: TextStyle(color: colorScheme.error),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDelete([song]);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 多选模式底部操作栏：删除所选。
  Widget _buildSelectActionBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            onPressed: _selectedIndices.isEmpty
                ? null
                : () {
                    final songs = _selectedIndices
                        .map((i) => _filteredSongs[i])
                        .toList();
                    _confirmDelete(songs);
                  },
            icon: const Icon(Icons.delete_outline),
            label: Text('删除所选 ${_selectedIndices.length} 首'),
          ),
        ),
      ),
    );
  }

  /// 删除确认对话框，确认后调用 [_deleteCloudSongs] 并刷新列表。
  Future<void> _confirmDelete(List<Song> songs) async {
    if (songs.isEmpty) return;
    // await 前捕获 messenger，避免 async gap 后使用 BuildContext
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          songs.length > 1 ? '删除所选 ${songs.length} 首歌曲？' : '删除这首歌曲？',
        ),
        content: const Text('删除后云端文件不可恢复，请谨慎操作。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final r = await _deleteCloudSongs(songs);
    if (!mounted) return;
    if (r.ok) {
      if (_isSelectMode) _exitSelectMode();
      messenger.showSnackBar(SnackBar(
        content: Text('已删除 ${songs.length} 首'),
        behavior: SnackBarBehavior.floating,
      ));
      await _loadCloudSongs();
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('删除失败：${r.reason ?? '未知错误'}'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// 删除云盘歌曲（单首/批量共用）。
  ///
  /// 优先用 fileid(kv_id)+album_audio_id（服务端精确删除），
  /// fileId 缺失（旧数据）时回退 hash。返回 (ok, reason)。
  Future<({bool ok, String? reason})> _deleteCloudSongs(
    List<Song> songs,
  ) async {
    final api = KugouApiClient();
    if (!api.isLoggedIn) return (ok: false, reason: '未登录');
    final fileids = <String>[];
    final albumAudioIds = <String>[];
    final hashes = <String>[];
    for (final s in songs) {
      if (s.fileId != null) {
        fileids.add(s.fileId.toString());
        albumAudioIds.add(s.albumAudioId ?? '0');
      } else {
          hashes.add(s.id);
        }
    }
    final result = await api.deleteCloudSongs(
      fileids: fileids.isEmpty ? null : fileids,
      albumAudioIds: albumAudioIds.isEmpty ? null : albumAudioIds,
      hashes: hashes.isEmpty ? null : hashes,
    );
    if (result?['status'] == 1) return (ok: true, reason: null);
    return (ok: false, reason: (result?['msg'] ?? '未知错误').toString());
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '共 ${_songs.length} 首',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              if (_songs.isNotEmpty) {
                context
                    .read<PlayerProvider>()
                    .playCloudPlaylist(_songs, 0);
              }
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放全部'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索云盘歌曲',
          hintStyle: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          isDense: true,
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildNoMatch() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            '没有匹配 "${_searchQuery.trim()}" 的歌曲',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: 64,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '云盘暂无音乐',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '在酷狗音乐 App 中上传歌曲后即可在此查看',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _loadCloudSongs,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('刷新'),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: cs.error.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _loadCloudSongs,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
