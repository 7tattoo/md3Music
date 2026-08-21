import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:provider/provider.dart';

import '../../data/models/song.dart';
import '../../data/repositories/history_repository.dart';
import '../../providers/player_provider.dart';
import '../../widgets/song_list_item.dart';
import '../player/mini_player.dart';

class PlayHistoryPage extends StatefulWidget {
  const PlayHistoryPage({super.key});

  @override
  State<PlayHistoryPage> createState() => _PlayHistoryPageState();
}

class _PlayHistoryPageState extends State<PlayHistoryPage> {
  List<Song> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await HistoryRepository().getHistory();
    if (!mounted) return;
    setState(() {
      _songs = history;
      _isLoading = false;
    });
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空播放历史'),
        content: const Text('确定要清空所有播放历史吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await HistoryRepository().clearHistory();
      await _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displaySongs = _songs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放历史'),
        actions: [
          if (_songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: M3ELoadingIndicator())
          : _songs.isEmpty
          ? _buildEmpty()
          : Column(
              children: [
                _buildHeader(displaySongs),
                Expanded(
                  child: ListView.builder(
                    itemCount: displaySongs.length,
                    itemBuilder: (context, index) {
                      return SongListItem(
                        song: displaySongs[index],
                        onTap: () {
                          context.read<PlayerProvider>().playOnlinePlaylist(
                            displaySongs,
                            index,
                          );
                        },
                        onMoreTap: () {},
                      );
                    },
                  ),
                ),
                const MiniPlayer(),
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
            Icons.history,
            size: 64,
            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '暂无播放历史',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<Song> displaySongs) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '共 ${displaySongs.length} 首',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          if (displaySongs.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                context.read<PlayerProvider>().playOnlinePlaylist(
                  displaySongs,
                  0,
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放全部'),
            ),
        ],
      ),
    );
  }
}
