import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

/// 音频焦点 / 音频会话管理。
///
/// 关键设计：
/// - [_pausedByInterruption]：标记“暂停是由音频焦点丢失引起的”。
///   仅在这种情况下才在重新获得焦点时自动恢复播放，
///   避免覆盖用户主动的暂停。
/// - 区分临时中断（pause / unknown → 之后会自动恢复）和永久丢失
///   （如电话来电、强制中断），后者由 audio_session 标记 `dispose` 状态。
/// - 与其他媒体共存：其他应用播放媒体时本应用既不暂停也不改变音量，
///   见 [_activateSession] 与中断处理里的 [AudioInterruptionType.duck] 分支。
class AudioService {
  static final AudioService _instance = AudioService._internal();

  factory AudioService() => _instance;

  AudioService._internal();

  final AudioPlayer _player = AudioPlayer(
    // Media3 (just_audio 0.10.x) 下缓冲区默认值已较合理，
    // 这里适度收紧：maxBuffer 从 60s 降到 30s（减少内存占用），
    // rebuffer 从 10s 降到 3s（缩短欠载后恢复等待，用户体验更流畅）。
    audioLoadConfiguration: AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 15),
        maxBufferDuration: Duration(seconds: 30),
        bufferForPlaybackDuration: Duration(seconds: 2),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
      ),
    ),
    // 中断处理全部由本类接管：just_audio 自带的处理器会无条件在中断时
    // pause、并在 duck 结束时把音量翻倍，与「与其他媒体共存」的行为冲突。
    handleInterruptions: false,
    // 音频焦点申请也由本类接管，见 [_activateSession]：需要显式传
    // androidWillPauseWhenDucked，just_audio 内部的 setActive 不传该参数。
    handleAudioSessionActivation: false,
  );
  final ConcatenatingAudioSource _playlistSource = ConcatenatingAudioSource(
    children: [],
  );

  AudioPlayer get player => _player;

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<bool> get playingStream => _player.playingStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  ProcessingState get processingState => _player.processingState;

  Stream<SequenceState?> get sequenceStateStream => _player.sequenceStateStream;

  Stream<double> get speedStream => _player.speedStream;

  bool get playing => _player.playing;

  Duration get position => _player.position;

  Duration? get duration => _player.duration;

  double get speed => _player.speed;

  /// Android 音频会话 ID，供均衡器绑定使用。
  /// just_audio 0.9.x 在播放器初始化后才会有值。
  int? get androidAudioSessionId => _player.androidAudioSessionId;

  /// 「忽略音频焦点」开关：开启后不响应任何音频焦点中断，与本应用音乐
  /// 同时播放的其他媒体（短视频/其他播放器/语音）都不断开、不停顿本应用，
  /// 声音叠加共存。默认由上层按用户设置写入。
  bool ignoreAudioFocus = false;

  /// 是否因为音频焦点丢失 / 设备中断（拔耳机、来电等）而处于暂停状态。
  /// 在此状态下若重新获得音频焦点，可自动恢复播放。
  /// 主动调用 [pause] 不会设置此标志。
  bool _pausedByInterruption = false;
  bool get wasPausedByInterruption => _pausedByInterruption;

  /// 恢复中的互斥锁：焦点事件流与就绪兜底流可能并发触发恢复，
  /// 用该标志防止重复进入 [play]，避免恢复瞬间的状态抖动。
  bool _resumeInProgress = false;

  /// 焦点已归还、但当时播放器还没 ready，需要等 ready 后再恢复。
  ///
  /// [_setupResumeOnReady] 必须同时检查这个标志：被中断暂停时 `pause()` 会
  /// 立刻推出一条 `(playing: false, ready)` 状态，若只看 [_pausedByInterruption]，
  /// 兜底监听会在暂停的同一瞬间就把播放恢复回去，来电暂停与拔耳机暂停都会失效。
  bool _pendingResumeOnReady = false;

  /// 各事件流的订阅句柄，dispose 时统一取消，避免单例长期持有泄漏。
  StreamSubscription<PlayerState>? _resumeSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  Future<void> init() async {
    await _player.setLoopMode(LoopMode.off);
    await _configureAudioSession();
    _setupResumeOnReady();
  }

  /// 兜底恢复：当 [tryResumeAfterFocusLoss] 因播放器未 ready 跳过时，
  /// 监听播放器状态变为 ready 后自动尝试恢复。
  void _setupResumeOnReady() {
    _resumeSub = _player.playerStateStream.listen((state) {
      if (_pendingResumeOnReady &&
          _pausedByInterruption &&
          state.processingState == ProcessingState.ready) {
        // ignore: discarded_futures
        tryResumeAfterFocusLoss();
      }
    });
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          // 忽略音频焦点：任何中断开端一律忽略，保持本应用持续播放、
          // 音量不变，与其他媒体（短视频/播放器/语音）声音共存。
          // 注意：开启后来电等系统强中断也会与本应用声音叠加。
          if (ignoreAudioFocus) return;
          _pendingResumeOnReady = false;
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 其他应用播放媒体（申请「可压低」焦点）：共存，音量与播放状态都不动。
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              // 来电等独占型中断：仍然暂停。
              if (_player.playing) {
                _pausedByInterruption = true;
                pause();
              }
              break;
          }
        } else {
          // 中断结束。焦点恢复：仅在是被动暂停时尝试恢复（不覆盖用户主动暂停）。
          // unknown 型中断（部分游戏引擎 / 游戏内通话上报）同样需要恢复，
          // 否则音乐被动暂停后无法自动恢复。
          // 置位后若播放器还没 ready，由 [_setupResumeOnReady] 兜底重试。
          _pendingResumeOnReady = true;
          // ignore: discarded_futures
          tryResumeAfterFocusLoss();
        }
      });
      // 拔耳机 / 蓝牙断开：通常伴随系统焦点变更，但 just_audio 也会收到
      // becomingNoisyEvent。统一标记为「中断暂停」以便外层恢复逻辑复用。
      // 忽略音频焦点开启时同样放行：拔线不断开本应用播放。
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (ignoreAudioFocus) return;
        if (_player.playing) {
          _pausedByInterruption = true;
          pause();
        }
      });
    } catch (e) {}
  }

  /// 申请音频焦点（替代 just_audio 内部的会话激活）。
  ///
  /// 显式传 `androidWillPauseWhenDucked: true`，让原生 AudioFocusRequest 声明
  /// 「被压低时我自己处理」，从而关掉 Android 8.0+ 的系统自动压音——否则系统会
  /// 直接把本应用音量压到约 20%、且不派发任何回调，App 既感知不到也无法恢复
  /// （只有再次申请焦点才会解除，表现为「暂停重播才恢复」）。这是「与其他媒体
  /// 共存」得以成立的前提：系统交出压音控制权后，本类选择什么都不做。
  ///
  /// 会话配置仍使用 [AudioSessionConfiguration.music]（其
  /// androidWillPauseWhenDucked 为 null）：audio_session 用**配置**里的值决定
  /// 事件类型映射，保持 null/false 才能把「其他媒体压低」映射成
  /// [AudioInterruptionType.duck]、把「来电等独占中断」映射成
  /// [AudioInterruptionType.pause]，前者放行、后者暂停才分得开；原生请求参数
  /// 则由这里的入参覆盖。改动 audio_session 版本时需要复核这两处取值来源。
  Future<void> _activateSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true, androidWillPauseWhenDucked: true);
    } catch (_) {}
  }

  /// 切换「忽略音频焦点」开关并立即使生效。
  ///
  /// 仅切换 [ignoreAudioFocus] 不足以即时生效：本应用通过
  /// `setActive(true, androidWillPauseWhenDucked: true)` 申请焦点并声明
  /// 「被压低时由 App 自处理」后，系统在其它应用抢占焦点时不再向本应用派发
  /// 中断事件，listener 自然收不到、也无法按新开关值处理，需重启/重新激活才接管。
  /// 这里在字段切换后重新激活会话（先释放、再以新策略申请），让系统立刻按
  /// 当前开关重新评估中断派发，从而无需杀 App 即可换档。
  /// [playing] 表示当前是否有播放，用于关闭开关时若处于「忽略」状态把
  /// 已暂停标记复位，避免焦点回来时误恢复。
  Future<void> setIgnoreAudioFocus(bool value) async {
    ignoreAudioFocus = value;
    try {
      final session = await AudioSession.instance;
      // 先置为不活跃，释放当前焦点，再以同样的激活参数重新申请，
      // 促使系统重新评估本应用的中断处理策略。
      await session.setActive(false);
      await session.setActive(true, androidWillPauseWhenDucked: true);
    } catch (_) {}
  }

  /// 焦点恢复时尝试自动恢复播放。
  ///
  /// 仅当：
  /// 1) 当前处于「中断暂停」状态（_pausedByInterruption=true）
  /// 2) 播放器已 ready（processingState == ready）
  /// 时才会调 play()，避免与用户主动暂停冲突。
  Future<void> tryResumeAfterFocusLoss() async {
    if (_resumeInProgress) return; // 防并发恢复
    if (!_pausedByInterruption) return;
    if (_player.processingState != ProcessingState.ready) {
      // 还没 ready，留着标志位等下次状态变化再试
      return;
    }
    _resumeInProgress = true;
    try {
      _pausedByInterruption = false;
      await play();
    } finally {
      _resumeInProgress = false;
    }
  }

  Future<void> play() async {
    // 主动 play 不影响 _pausedByInterruption 标志；
    // 若是被动恢复（_pausedByInterruption=true），play 后清掉标志。
    await _activateSession();
    await _player.play();
    _pausedByInterruption = false;
    _pendingResumeOnReady = false;
  }

  Future<void> pause() async {
    // pause() 由外部主动调用时不修改 _pausedByInterruption；
    // 中断引起的 pause 由 _configureAudioSession 内置 listener 设置标志。
    await _player.pause();
    // 关键修复：主动暂停后应释放音频焦点（setActive(false)），否则本应用
    // 一直占据媒体焦点，其它音乐 App 播放时会「抢不到焦点 / 被本应用抢占」。
    // 释放焦点后，其它 App 可正常接管；本应用恢复播放时由 play() 重新激活。
    // 因中断（来电等）被动暂停时，焦点交由系统在中断结束后自动归还，不在此释放，
    // 避免破坏中断恢复逻辑。
    if (!_pausedByInterruption) {
      try {
        final session = await AudioSession.instance;
        await session.setActive(false);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _pausedByInterruption = false;
    _pendingResumeOnReady = false;
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setUrl(String url) async {
    await _player.setUrl(url, headers: const {});
  }

  Future<void> setPlaylist(
    List<UriAudioSource> sources, {
    int startIndex = 0,
  }) async {
    _playlistSource.clear();
    if (sources.isNotEmpty) {
      _playlistSource.addAll(sources);
    }
    await _player.setAudioSource(
      _playlistSource,
      initialIndex: startIndex,
      initialPosition: Duration.zero,
    );
  }

  Future<void> addAudioSource(UriAudioSource source) async {
    await _playlistSource.add(source);
  }

  Future<void> addAllAudioSources(List<UriAudioSource> sources) async {
    await _playlistSource.addAll(sources);
  }

  /// 在指定位置插入音频源，不打断当前播放。
  /// 用于"下一首播放"等需要在队列中间插入的场景。
  Future<void> insertAudioSourceAt(int index, UriAudioSource source) async {
    await _playlistSource.insert(index, source);
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  Future<void> seekToNext() async {
    await _player.seekToNext();
  }

  Future<void> seekToPrevious() async {
    await _player.seekToPrevious();
  }

  Future<void> setLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
  }

  Future<void> setShuffleModeEnabled(bool enabled) async {
    await _player.setShuffleModeEnabled(enabled);
  }

  Future<void> dispose() async {
    await _resumeSub?.cancel();
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    await _player.dispose();
    _pausedByInterruption = false;
    _resumeInProgress = false;
  }
}

UriAudioSource createAudioSource({
  required String id,
  required String url,
  required String title,
  String? artist,
  String? album,
  Uri? artUri,
}) {
  return AudioSource.uri(
    Uri.parse(url),
    tag: {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'artUri': artUri?.toString(),
    },
  );
}
