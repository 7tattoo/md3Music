import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/kugou_provider.dart';
import '../../widgets/app_animation.dart';
import '../../widgets/md3e_loading_indicator.dart';
import '../../widgets/md3e_refresh_indicator.dart';
import '../../widgets/scroll_aware_app_bar.dart';
import '../login/login_page.dart';
import '../settings/settings_page.dart';
import 'cloud_music_page.dart';
import 'listen_ranking_page.dart';
import 'play_history_page.dart';

class UserCenterPage extends StatefulWidget {
  const UserCenterPage({super.key});

  @override
  State<UserCenterPage> createState() => _UserCenterPageState();
}

class _UserCenterPageState extends State<UserCenterPage> {
  /// 顶栏渐变 ScrollController：与 ScrollAwareAppBar 共享
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final kugou = context.read<KugouProvider>();
      if (kugou.isLoggedIn) {
        kugou.getVipDetail();
        kugou.getVipMonthRecord();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final isDark = baseTheme.brightness == Brightness.dark;

    // iOS 语义色（与设置页一致：中性色固定，tint 用主题品牌色）
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final card = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final label = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final secondary =
        isDark ? const Color(0xFFAEAEB2) : const Color(0xFF8E8E93);
    final separator =
        isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5E5);

    final cs = baseTheme.colorScheme.copyWith(
      surface: card,
      onSurface: label,
      onSurfaceVariant: secondary,
      surfaceContainerLowest: bg,
    );
    final tt = baseTheme.textTheme;

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: cs,
        scaffoldBackgroundColor: bg,
        dividerColor: separator,
        appBarTheme: baseTheme.appBarTheme.copyWith(
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      child: Scaffold(
        backgroundColor: bg,
        appBar: ScrollAwareAppBar(
          title: '我的',
          scrollController: _scrollController,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
            Consumer<KugouProvider>(
              builder: (context, kugou, _) => IconButton(
                icon: Icon(kugou.isLoggedIn ? Icons.logout : Icons.login),
                onPressed: kugou.isLoggedIn
                    ? () => showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('退出登录'),
                          content: const Text('确定要退出登录吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () {
                                kugou.logout();
                                Navigator.pop(ctx);
                              },
                              child: const Text('确定'),
                            ),
                          ],
                        ),
                      )
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LoginPage(),
                        ),
                      ),
              ),
            ),
          ],
        ),
        body: Consumer<KugouProvider>(
          builder: (context, kugou, _) {
            if (!kugou.isLoggedIn) return _buildNotLoggedIn(cs, tt);
            return MD3ERefreshIndicator(
              onRefresh: () async {
                await kugou.getVipDetail();
                await kugou.getVipMonthRecord();
              },
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  _buildUserHeader(cs, tt, kugou),
                  _buildVipCard(cs, tt, kugou),
                  _buildSectionLabel('常用功能', cs),
                  _buildActionGrid(cs),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  _buildVipCalendar(cs, tt, kugou, context),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// iOS 风格分区小标题。
  Widget _buildSectionLabel(String title, ColorScheme cs) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 20, 16, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotLoggedIn(ColorScheme cs, TextTheme tt) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 80,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              '登录后享受更多精彩',
              style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              '同步歌单、收藏、云盘等',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.person),
              label: const Text('登录'),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LoginPage())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAvatar(KugouProvider kugou, ColorScheme cs) {
    final avatarUrl = kugou.userInfo?.avatar;
    final userId = kugou.userid ?? 'default';

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return CircleAvatar(
        radius: 32,
        backgroundColor: cs.primary.withValues(alpha: 0.2),
        child: Icon(Icons.person, size: 32, color: cs.onPrimaryContainer),
      );
    }

    // 修复：使用更安全的缓存键，避免 userId 为 null 导致的问题
    final safeUserId = userId.toString().replaceAll(
      RegExp(r'[^a-zA-Z0-9]'),
      '_',
    );
    final cacheKey = 'avatar_$safeUserId';

    return CircleAvatar(
      radius: 32,
      backgroundColor: cs.primary.withValues(alpha: 0.2),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          cacheKey: cacheKey,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Icon(Icons.person, size: 32, color: cs.onPrimaryContainer),
          errorWidget: (context, url, error) =>
              Icon(Icons.person, size: 32, color: cs.onPrimaryContainer),
        ),
      ),
    );
  }

  Widget _buildUserHeader(ColorScheme cs, TextTheme tt, KugouProvider kugou) {
    return SliverToBoxAdapter(
      child: FadeInUp(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.surface,
          ),
          child: Row(
            children: [
              _buildUserAvatar(kugou, cs),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kugou.userInfo?.nickname ?? '用户',
                      style: tt.titleLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${kugou.userid ?? ''}',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVipCard(ColorScheme cs, TextTheme tt, KugouProvider kugou) {
    final vip = kugou.vipInfo;
    final isVip = vip?.isVip == true;
    return SliverToBoxAdapter(
      child: FadeInUp(
        delayMs: 50,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.surface,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isVip
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                ),
                child: Icon(
                  isVip
                      ? Icons.workspace_premium
                      : Icons.workspace_premium_outlined,
                  color: isVip ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isVip
                          ? (kugou.isTodayYouthVip ? '概念版VIP会员' : 'VIP会员')
                          : '开通VIP会员',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isVip
                          ? '概念版VIP 有效期至: ${vip?.conceptExpireTime ?? vip?.expireTime ?? '永久'}'
                          : '畅享无损音质、个性皮肤等',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionGrid(ColorScheme cs) {
    return SliverToBoxAdapter(
      child: FadeInUp(
        delayMs: 100,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _actionRow(cs, Icons.history, '历史', () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlayHistoryPage()),
                );
              }),
              const Divider(height: 0.5, thickness: 0.5, indent: 16),
              _actionRow(cs, Icons.bar_chart, '排行', () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ListenRankingPage()),
                );
              }),
              const Divider(height: 0.5, thickness: 0.5, indent: 16),
              _actionRow(cs, Icons.cloud, '云盘', () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CloudMusicPage()),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// 操作区单行（iOS 设置式：图标 + 标题 + 右箭头）。
  Widget _actionRow(
    ColorScheme cs,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.primaryContainer,
        ),
        child: Icon(icon, size: 18, color: cs.primary),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }

  Widget _buildVipCalendar(
    ColorScheme cs,
    TextTheme tt,
    KugouProvider kugou,
    BuildContext context,
  ) {
    final record = kugou.vipMonthRecord;
    final now = DateTime.now();
    final curYear = now.year;
    final curMonth = now.month;
    final receivedDays = <int>{};
    if (record != null) {
      final data = record['data'] as Map<String, dynamic>?;
      final list = data?['list'] ?? data?['record_list'] ?? record['list'];
      if (list is List) {
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            // 只显示概念版(svip)签到记录，过滤畅听(tvip)
            final vipType = item['vip_type']?.toString() ?? '';
            if (vipType != 'svip') continue;
            final dm = _parseReceivedYearMonthDay(item);
            if (dm != null && dm.year == curYear && dm.month == curMonth) {
              receivedDays.add(dm.day);
            }
          }
        }
      }
    }
    // 本地兜底：服务端记录不及时时，合并本地已签日期，保证今天立即打勾
    for (final key in kugou.localSignedDays) {
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(key);
      if (m != null &&
          int.parse(m.group(1)!) == curYear &&
          int.parse(m.group(2)!) == curMonth) {
        receivedDays.add(int.parse(m.group(3)!));
      }
    }
    final monthLabel = DateFormat('yyyy 年 M 月', 'zh_CN').format(now);
    final daysInMonth = DateTime(curYear, curMonth + 1, 0).day;
    // weekday: Mon=1..Sun=7 → 周一开头 0 个前导
    final leading = DateTime(curYear, curMonth, 1).weekday - 1;

    return SliverToBoxAdapter(
      child: FadeInUp(
        delayMs: 80,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCalendarHeader(cs, tt, monthLabel, kugou, context),
                  const SizedBox(height: 16),
                  _buildWeekdayHeader(cs),
                  const SizedBox(height: 8),
                  _buildCalendarGrid(
                    cs,
                    curYear,
                    curMonth,
                    leading,
                    daysInMonth,
                    receivedDays,
                    now,
                  ),
                  const SizedBox(height: 20),
                  _buildStatFooter(cs, tt, receivedDays.length),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarHeader(
    ColorScheme cs,
    TextTheme tt,
    String monthLabel,
    KugouProvider kugou,
    BuildContext context,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.chevron_left),
                color: cs.onSurfaceVariant,
                onPressed: () {},
              ),
              Expanded(
                child: Text(
                  monthLabel,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.chevron_right),
                color: cs.onSurfaceVariant,
                onPressed: () {},
              ),
              // 概念版会员徽章 —— 今天签到后显示
              if (kugou.isTodayYouthVip) ...[
                const SizedBox(width: 4),
                _buildConceptVipBadge(cs, tt),
              ],
              const SizedBox(width: 4),
              Flexible(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: const Size(0, 32),
                    textStyle: tt.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: kugou.manualSignInRunning
                      ? null
                      : () => _handleManualSignIn(context, kugou),
                  icon: kugou.manualSignInRunning
                      ? MD3ELoadingIndicator(
                          size: 16,
                          color: cs.onSecondaryContainer,
                        )
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(kugou.manualSignInRunning ? '签到中' : '签到'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  minimumSize: const Size(0, 32),
                  textStyle: tt.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: kugou.listenClaimRunning
                    ? null
                    : () => _handleListenSongClaim(context, kugou),
                icon: kugou.listenClaimRunning
                    ? MD3ELoadingIndicator(
                        size: 16,
                        color: cs.onSecondaryContainer,
                      )
                    : const Icon(Icons.headphones, size: 16),
                label: Text(kugou.listenClaimRunning ? '领取中' : '听歌领'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  minimumSize: const Size(0, 32),
                  textStyle: tt.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: kugou.adClaimRunning
                    ? null
                    : () => _handleAdVipClaim(context, kugou),
                icon: kugou.adClaimRunning
                    ? MD3ELoadingIndicator(
                        size: 16,
                        color: cs.onSecondaryContainer,
                      )
                    : const Icon(Icons.play_circle_outline, size: 16),
                label: Text(kugou.adClaimRunning ? '领取中' : '看广告领'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 仅签到异常时点击 —— 提示语
          Text(
            '仅签到异常时点击',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 概念版会员徽章 —— 显示在签到按钮左侧，仅今天已签时显示
  Widget _buildConceptVipBadge(ColorScheme cs, TextTheme tt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        // 金/紫色调 —— Material 3 expressive：primary + tertiary 渐变近似
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.85),
            cs.tertiary.withValues(alpha: 0.85),
          ],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: 12, color: cs.onPrimary),
          const SizedBox(width: 3),
          Text(
            '概念版',
            style: tt.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleManualSignIn(
    BuildContext context,
    KugouProvider kugou,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final (ok, msg) = await kugou.manualSignIn();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.errorContainer,
      ),
    );
  }

  Future<void> _handleListenSongClaim(
    BuildContext context,
    KugouProvider kugou,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final (ok, msg) = await kugou.listenSongClaim();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.errorContainer,
      ),
    );
  }

  Future<void> _handleAdVipClaim(
    BuildContext context,
    KugouProvider kugou,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final (ok, msg) = await kugou.claimAdVip();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.errorContainer,
      ),
    );
  }

  Widget _buildWeekdayHeader(ColorScheme cs) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          for (final l in labels)
            Expanded(
              child: Center(
                child: Text(
                  l,
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatFooter(ColorScheme cs, TextTheme tt, int receivedCount) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final progress = receivedCount / daysInMonth;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // 进度环
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    backgroundColor: cs.surfaceContainerLow,
                    color: cs.primary,
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 文字统计
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本月已打卡',
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$receivedCount',
                      style: tt.headlineMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '/ $daysInMonth 天',
                      style: tt.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 连续打卡激励
          if (receivedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: cs.secondaryContainer,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 14,
                    color: cs.onSecondaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '坚持中',
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(
    ColorScheme cs,
    int year,
    int month,
    int leading,
    int daysInMonth,
    Set<int> receivedDays,
    DateTime now,
  ) {
    final tt = Theme.of(context).textTheme;
    final rows = <Widget>[];
    var cells = <Widget>[];

    void addCell(Widget w) {
      cells.add(w);
      if (cells.length == 7) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: cells),
          ),
        );
        cells = [];
      }
    }

    Widget buildEmptyCell() {
      return Expanded(
        child: AspectRatio(aspectRatio: 1, child: const SizedBox()),
      );
    }

    for (var i = 0; i < leading; i++) {
      addCell(buildEmptyCell());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final isReceived = receivedDays.contains(day);
      final isToday = day == now.day;
      final isFuture = day > now.day;
      addCell(
        Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 背景圆
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isReceived
                            ? cs.primary
                            : (isToday
                                  ? cs.primary.withValues(alpha: 0.1)
                                  : Colors.transparent),
                        border: isToday && !isReceived
                            ? Border.all(color: cs.primary, width: 2)
                            : null,
                      ),
                    ),
                    // 签到勾选图标覆盖层
                    if (isReceived)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.secondary,
                            border: Border.all(color: cs.surface, width: 1.5),
                          ),
                          child: Icon(
                            Icons.check,
                            size: 9,
                            color: cs.onSecondary,
                          ),
                        ),
                      ),
                    // 日期文字
                    Text(
                      '$day',
                      style: tt.bodySmall?.copyWith(
                        fontWeight: isToday || isReceived
                            ? FontWeight.w700
                            : null,
                        color: isReceived
                            ? cs.onPrimary
                            : (isToday
                                  ? cs.primary
                                  : (isFuture
                                        ? cs.onSurfaceVariant.withValues(
                                            alpha: 0.35,
                                          )
                                        : cs.onSurface)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    while (cells.isNotEmpty && cells.length < 7) {
      addCell(buildEmptyCell());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  DateTime? _parseReceivedYearMonthDay(Map<String, dynamic> item) {
    // 实际返回结构: {"day":"2026-06-07","receive_vip":1,"vip_type":"tvip",...}
    final day = item['day'];
    if (day is String) {
      final m = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(day);
      if (m != null) {
        return DateTime(
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
        );
      }
    }
    if (day is int && day > 1000000000) {
      final ms = day > 1e12 ? day : day * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }
}
