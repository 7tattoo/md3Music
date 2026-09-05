package com.ryanheise.just_audio;

import android.os.Bundle;
import android.text.TextUtils;

import androidx.media3.session.legacy.MediaMetadataCompat;

/**
 * MD3Music fork：vivo 车机歌词协议桥（车联投屏 ucar + 原子随身听 vivomusicmix）。
 *
 * <p>协议来源：《vivo 车机滚动歌词适配开发文档》与
 * huang6668/apple-music-vivo-car-lyrics 的 docs/APK_UPDATE_GUIDE、KNOWN_ISSUES
 * （两者分别基于酷我 12.0.8.0、车联 6.0.8.3、原子随身听 6.2.5.6 的反编译结论）。
 *
 * <ul>
 *   <li><b>车联投屏（ucar）</b>：只把<b>整段 LRC</b> 交给车机
 *       （{@link #KEY_UCAR_LYRICS_WHOLE} + {@link #KEY_UCAR_LYRICS_STATUS}=0），
 *       车机按 PlaybackState 进度自己切行。App 不负责"当前是第几行"。
 *   <li><b>原子随身听（vivomusicmix）</b>：metadata 里声明能力位
 *       {@link #KEY_ATOMIC_SUPPORT_EVENT}=31（7|8|16），整段歌词经 MediaSession
 *       extras 的 {@code lrc_change} 事件下发。
 * </ul>
 *
 * <p><b>三条绝不能做</b>（每条都是踩过的坑，不是理论推测）：
 *
 * <ol>
 *   <li>绝不写 {@code ucar.media.metadata.LYRICS_LINE} —— 单行模式协议信号，
 *       车机收到即切单行卡片并忽略整段歌词。
 *   <li>绝不写 {@code music.media.extras.{LYRIC,LYRIC_IS_ALLOWED,NOTICE_CAR}} ——
 *       同为单行通道；高频推送表现为"切歌瞬间多行，十几秒后变回单行"。
 *       车联 6.0.8.3 反编译确认这三个 key 根本没有读取点（只在常量类里定义）。
 *   <li>无歌词时绝不写负状态（{@code LYRICS_STATUS=1/2}）—— 语义是"本曲确认无歌词"，
 *       而歌词是异步加载的，车机连上后第一时间收到即永久退回单行。
 * </ol>
 *
 * <p><b>热路径铁律</b>：{@link #decorateAtFunnel(MediaMetadataCompat)} 挂在 legacy
 * metadata 的唯一出口（{@code MediaSessionLegacyStub.setMetadata}）上，每次元数据刷新
 * 都会调用，且必定先于异步歌词加载完成。因此它是纯增量装饰器：无事可做原样返回
 * （连 Builder 都不进，避免拷贝封面 Bitmap）、零文件 IO、不做任何状态判定副作用。
 *
 * <p><b>为什么装饰时不校验 mediaId</b>：legacy metadata 的 MEDIA_ID 在切歌后要等
 * {@code replaceMediaItem} 传播完才更新，比 App 侧的歌词推送晚一步。若在这里做
 * "歌词 id == metadata id" 的校验，正确的歌词会被误判成过期而丢弃（表现为偶发无歌词）。
 * 防串曲交由上层负责：切歌时显式调用 {@link #setWhole(String)} 传空串清缓存。
 */
public final class VivoCarLyrics {

    private VivoCarLyrics() {}

    // ==== 车联投屏（ucar）====
    /** 整段 LRC（唯一必须字段）。车机自行按播放进度切行。 */
    public static final String KEY_UCAR_LYRICS_WHOLE = "ucar.media.metadata.LYRICS_WHOLE";
    /** 歌词状态：0 = 有歌词。1/2 = "本曲确认无歌词"，本类永不写。 */
    public static final String KEY_UCAR_LYRICS_STATUS = "ucar.media.metadata.LYRICS_STATUS";
    public static final String KEY_UCAR_TITLE = "ucar.media.metadata.UCAR_TITLE";
    public static final String KEY_UCAR_ARTIST = "ucar.media.metadata.UCAR_ARTIST";

    // ==== 原子随身听（vivomusicmix）====
    /** 能力位。合作控制器 {@code c0.k0()} 原样读取，不会自己补位。 */
    public static final String KEY_ATOMIC_SUPPORT_EVENT =
            "vivomusicmix.media.metadata.support_event";
    /**
     * 7（基础播控）| 8（歌词）| 16（进度条 / seek / 时间显示）= 31。
     *
     * <p>缺 bit 8 组件不显示歌词区；缺 bit 16 时 {@code t4/d0.Y0()/Z0()} 恒 false，
     * 进度条永远 {@code --:--} —— 这正是"加了 manifest action 进度条就没了"的真正原因
     * （通用控制器 {@code y2} 会自己按 ACTION_SEEK_TO 补出 16 位，合作控制器不会）。
     */
    public static final long ATOMIC_SUPPORT_EVENT = 7L | 8L | 16L;
    /** 注意 vivo 官方拼写错误 {@code meida}，必须照抄。 */
    public static final String KEY_ATOMIC_ACTION = "vivomusicmix.meida.extra.key.action";
    public static final String ACTION_LRC_CHANGE = "vivomusicmix.extra.lrc_change";
    /** 注意 vivo 官方拼写错误 {@code meidia}，必须照抄。 */
    public static final String KEY_ATOMIC_MEDIA_ID = "vivomusicmix.extra.key.meidia_id";
    public static final String KEY_ATOMIC_LYRIC = "vivomusicmix.extra.key.lyric";

    /** 原子随身听包名（合作控制器所在进程）。 */
    public static final String PKG_ATOMIC = "com.vivo.musicwidgetmix";
    /** 车联投屏包名（JoviInCar 车机端）。 */
    public static final String PKG_CARLINK = "com.vivo.car.networking";
    /** vivo 系包名前缀：车机固件版本不同组件包名可能有差异，统一放行补发。 */
    public static final String PKG_VIVO_PREFIX = "com.vivo.";

    /**
     * {@code lrc_change} 低频重发间隔：兜底"车机 / 组件在播放开始之后才连上"。
     *
     * <p>绝不能做成 250/500ms 级 ticker —— 那是单行方案的做法，会把车机卡片压回单行。
     */
    public static final long RESEND_INTERVAL_MS = 25_000L;

    /** 控制器连接后补发的延迟：等对端把 controller 建完再推，避免推早了被丢。 */
    public static final long CONNECT_RESYNC_DELAY_MS = 1_200L;

    /**
     * 歌词内容变化后的补发延迟（毫秒）。
     *
     * <p>切歌瞬间 legacy metadata 的 {@code MEDIA_ID} 还没跟上
     * （{@code replaceMediaItem} → legacy stub 的传播要晚一个消息，封面异步时更晚），
     * 而原子随身听要求 {@code lrc_change} 里的 {@code meidia_id} 等于它当前持有的那个，
     * 不等即静默丢弃整段歌词。所以在 ID 稳定后再补发两次。
     *
     * <p>{@link #shouldSend(long, String, String)} 按「ID 或内容变化」去重，重复调用幂等。
     */
    public static final long[] RESEND_BACKOFF_MS = {700L, 2_500L};

    /** 当前曲目的整段 LRC（空串 = 无歌词 / 已清除）。 */
    private static volatile String sWhole = "";

    // ---- lrc_change 发送节流状态 ----
    private static volatile String sSentMediaId = "";
    private static volatile String sSentWhole = "";
    private static volatile long sSentAt = 0L;

    /**
     * legacy metadata 唯一出口的<b>原始（未装饰）</b>快照，作强推时的基底。
     *
     * <p>只存引用，零分配零 IO（不违反热路径铁律）。生产者只有 media3 的 legacy stub
     * 一个，且它每次都用完整的 {@code MediaMetadata} 重新转换，所以这份快照始终是带
     * 封面的完整版 —— 不存在"通知路径的精简 metadata 覆盖完整版"的问题。
     */
    private static volatile MediaMetadataCompat sRawMetadata;

    /**
     * 缓存当前曲目的整段 LRC。
     *
     * @param lrc 整段标准 LRC；空串表示"本曲暂无歌词 / 清除上一首"
     * @return 缓存内容是否变化（变化即需要强推一次 metadata 并发 lrc_change）
     */
    public static synchronized boolean setWhole(String lrc) {
        String value = lrc == null ? "" : lrc;
        if (value.equals(sWhole)) return false;
        sWhole = value;
        return true;
    }

    /** 当前缓存的整段歌词（可能为空串）。 */
    public static String cachedWhole() {
        return sWhole;
    }

    /** legacy metadata 唯一出口的原始快照（可能为 null）。 */
    public static MediaMetadataCompat rawMetadata() {
        return sRawMetadata;
    }

    /**
     * legacy metadata 唯一出口的装饰入口（要点一）：记录原始快照并返回装饰结果。
     *
     * <p>只应由 {@code MediaSessionLegacyStub.setMetadata} 调用；其它路径用
     * {@link #decorate(MediaMetadataCompat)}，避免把已装饰的元数据存成"原始"快照。
     */
    public static MediaMetadataCompat decorateAtFunnel(MediaMetadataCompat src) {
        if (src != null) sRawMetadata = src;
        return decorate(src);
    }

    /**
     * 纯增量装饰器：补齐原子能力位与 ucar 整段歌词。
     *
     * <ul>
     *   <li>始终补齐 {@link #KEY_ATOMIC_SUPPORT_EVENT}（与歌词无关，缺 16 位进度条恒 {@code --:--}）；
     *   <li>有整段歌词 → 追加 {@code LYRICS_WHOLE} + {@code LYRICS_STATUS=0}
     *       + {@code UCAR_TITLE/UCAR_ARTIST}；
     *   <li>无歌词 → 不写任何歌词字段、<b>不写负状态</b>；若基底残留上一首的
     *       {@code LYRICS_WHOLE}（只可能来自强推基底）则清掉，防止歌词串曲；
     *   <li>无事可做 → 原样返回，连 Builder 都不进（不拷贝封面 Bitmap）。
     * </ul>
     */
    public static MediaMetadataCompat decorate(MediaMetadataCompat src) {
        if (src == null) return null;
        try {
            String lrc = sWhole;
            String existing = src.getString(KEY_UCAR_LYRICS_WHOLE);

            boolean needSupportEvent =
                    src.getLong(KEY_ATOMIC_SUPPORT_EVENT) != ATOMIC_SUPPORT_EVENT;
            boolean needLyric = !lrc.isEmpty() && !lrc.equals(existing);
            boolean needStrip = lrc.isEmpty() && !TextUtils.isEmpty(existing);

            if (!needSupportEvent && !needLyric && !needStrip) return src;

            MediaMetadataCompat.Builder builder = new MediaMetadataCompat.Builder(src);
            if (needSupportEvent) {
                builder.putLong(KEY_ATOMIC_SUPPORT_EVENT, ATOMIC_SUPPORT_EVENT);
            }
            if (needLyric) {
                builder.putString(KEY_UCAR_LYRICS_WHOLE, lrc);
                builder.putLong(KEY_UCAR_LYRICS_STATUS, 0L);
                String title = src.getString(MediaMetadataCompat.METADATA_KEY_TITLE);
                if (!TextUtils.isEmpty(title)) builder.putString(KEY_UCAR_TITLE, title);
                String artist = src.getString(MediaMetadataCompat.METADATA_KEY_ARTIST);
                if (!TextUtils.isEmpty(artist)) builder.putString(KEY_UCAR_ARTIST, artist);
            } else if (needStrip) {
                // 只清整段歌词字段本身；绝不改写成负状态
                builder.putString(KEY_UCAR_LYRICS_WHOLE, null);
            }
            return builder.build();
        } catch (Throwable t) {
            // 热路径不允许把异常抛回 metadata 推送链路
            return src;
        }
    }

    /**
     * 构造原子随身听 {@code lrc_change} 事件 Bundle。
     *
     * <p>{@code mediaId} 必须是<b>当前发布的</b> {@code android.media.metadata.MEDIA_ID}：
     * 组件在 {@code t4/d0.E0()/z1()} 里要求事件里的 id 等于它记录的当前歌曲，
     * 不等即静默丢弃整段歌词。
     *
     * <p>切歌时用空 {@code lrc} 发一次可清除组件内存里的上一首歌词；车联侧忽略
     * lyric 为空的事件，两个显示位互不干扰。
     */
    public static Bundle buildLrcChangeExtras(String mediaId, String lrc) {
        Bundle extras = new Bundle();
        extras.putString(KEY_ATOMIC_ACTION, ACTION_LRC_CHANGE);
        extras.putString(KEY_ATOMIC_MEDIA_ID, mediaId == null ? "" : mediaId);
        extras.putString(KEY_ATOMIC_LYRIC, lrc == null ? "" : lrc);
        return extras;
    }

    /**
     * 是否需要发 {@code lrc_change}。
     *
     * <p>内容或曲目 ID 变化立刻发（ID 变了必须重发，否则组件仍按旧 ID 比对而丢弃）；
     * 完全相同则按 {@link #RESEND_INTERVAL_MS} 节流。无歌词且状态未变时不发 ——
     * 绝不推空 Bundle 的 {@code setExtras}（会清掉车机已收到的 extras）。
     */
    public static synchronized boolean shouldSend(long nowMs, String mediaId, String lrc) {
        String id = mediaId == null ? "" : mediaId;
        String value = lrc == null ? "" : lrc;
        if (!id.equals(sSentMediaId) || !value.equals(sSentWhole)) return true;
        if (value.isEmpty()) return false;
        return nowMs - sSentAt >= RESEND_INTERVAL_MS;
    }

    /** 记录一次 lrc_change 发送。 */
    public static synchronized void markSent(long nowMs, String mediaId, String lrc) {
        sSentMediaId = mediaId == null ? "" : mediaId;
        sSentWhole = lrc == null ? "" : lrc;
        sSentAt = nowMs;
    }

    /** 是否是需要在连接后补发一次当前状态的 vivo 车机组件。 */
    public static boolean isVivoCarComponent(String packageName) {
        if (packageName == null || packageName.isEmpty()) return false;
        return PKG_ATOMIC.equals(packageName)
                || PKG_CARLINK.equals(packageName)
                || packageName.startsWith(PKG_VIVO_PREFIX);
    }
}
