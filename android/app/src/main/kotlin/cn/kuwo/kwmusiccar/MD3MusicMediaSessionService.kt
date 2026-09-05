package cn.kuwo.kwmusiccar

import android.annotation.SuppressLint
import android.content.Intent
import android.os.IBinder
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.ryanheise.just_audio.AudioPlayer

/**
 * 媒体3 会话承载服务（方案 B 阶段1：媒体3 通知栏上线）。
 *
 * 职责：把 just_audio fork 自建的 androidx.media3.session.MediaSession 归入本服务，
 * 由 media3 的 MediaNotificationManager + DefaultMediaNotificationProvider 生成系统
 * now playing 通知（通知栏可见、可控制播放）。仅作会话承载，不承担播放/焦点逻辑。
 */
@OptIn(UnstableApi::class)
@SuppressLint("UnsafeOptInUsageError")
class MD3MusicMediaSessionService : MediaSessionService() {

    override fun onCreate() {
        super.onCreate()
        // 注册为 fork 的会话 host：fork 创建/已有活跃会话后 addSession 到本服务渲染通知
        AudioPlayer.setMediaSessionServiceHost(this)
    }

    override fun onGetSession(info: MediaSession.ControllerInfo): MediaSession? {
        // 返回 fork 当前活跃的媒体3会话；未初始化时拒绝连接
        return AudioPlayer.getActiveMediaSession()
    }

    /**
     * vivo 原子随身听兼容：把私有 action 归一化成标准 MediaBrowserService action。
     *
     * media3 的 [MediaSessionService.onBind] 只认
     * `androidx.media3.session.MediaSessionService` 与
     * `android.media.browse.MediaBrowserService` 两个 action，其余一律返回 null。
     * 原子随身听用 `com.vivo.musicwidgetmix.support.service` 发现本服务；若它直接
     * 用该 action 绑定，不归一化就拿不到 binder（歌词区不出现）。
     */
    override fun onBind(intent: Intent?): IBinder? {
        if (intent != null && intent.action == ACTION_VIVO_MUSIC_WIDGET_MIX) {
            val normalized = Intent(intent).setAction(ACTION_MEDIA_BROWSER_SERVICE)
            return super.onBind(normalized)
        }
        return super.onBind(intent)
    }

    override fun onDestroy() {
        AudioPlayer.setMediaSessionServiceHost(null)
        super.onDestroy()
    }

    // 阶段1 暂时不接管自定义通知的停止语义；播放停止时 media3 默认会取消 now playing 通知
    // 并让本服务退回后台，无需额外处理。onTaskRemoved 使用默认实现。

    companion object {
        /** vivo 原子随身听（音乐小组件）用于发现合作应用的私有 action。 */
        const val ACTION_VIVO_MUSIC_WIDGET_MIX = "com.vivo.musicwidgetmix.support.service"
        private const val ACTION_MEDIA_BROWSER_SERVICE = "android.media.browse.MediaBrowserService"
    }
}