package io.grentu.taler.taler

import android.content.Context
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

class TalerVideoViewFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return TalerVideoPlatformView(context, messenger, viewId, params)
    }
}

class TalerVideoPlatformView(
    private val context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    params: Map<String, Any?>
) : PlatformView, TextureView.SurfaceTextureListener, MethodChannel.MethodCallHandler {

    private val container = FrameLayout(context).apply {
        setBackgroundColor(Color.BLACK)
    }
    private val textureView = TextureView(context)
    private val channel = MethodChannel(messenger, "io.grentu.taler/video_$viewId")

    private val source: String = (params["source"] as? String).orEmpty()
    private val userAgent: String = (params["userAgent"] as? String).orEmpty()
    private val autoPlay: Boolean = (params["autoPlay"] as? Boolean) ?: true

    private var surface: Surface? = null
    private var mediaPlayer: MediaPlayer? = null
    private var isPrepared = false
    private var isDisposed = false
    private var videoWidth = 0
    private var videoHeight = 0
    private var lastError: String? = null
    private var currentVolume = 1.0f

    init {
        val lp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
            Gravity.CENTER
        )
        container.addView(textureView, lp)
        textureView.surfaceTextureListener = this
        channel.setMethodCallHandler(this)
    }

    override fun getView(): View = container

    override fun onSurfaceTextureAvailable(st: SurfaceTexture, width: Int, height: Int) {
        if (isDisposed) return
        surface?.release()
        surface = Surface(st)
        initPlayer()
    }

    override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, width: Int, height: Int) {
        applyAspectRatio()
    }

    override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
        releasePlayer()
        return true
    }

    override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}

    private fun initPlayer() {
        releasePlayer()
        if (source.isBlank() || isDisposed) {
            lastError = "Пустой источник видео"
            return
        }
        try {
            val mp = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build()
                )
                setSurface(surface)
                isLooping = false
                if (source.startsWith("http://") || source.startsWith("https://")) {
                    val headers = mutableMapOf<String, String>()
                    if (userAgent.isNotBlank()) {
                        headers["User-Agent"] = userAgent
                    }
                    setDataSource(context, Uri.parse(source), headers)
                } else {
                    setDataSource(File(source).absolutePath)
                }
                setOnVideoSizeChangedListener { _, w, h ->
                    videoWidth = w
                    videoHeight = h
                    container.post { applyAspectRatio() }
                }
                setOnPreparedListener { player ->
                    if (isDisposed) return@setOnPreparedListener
                    isPrepared = true
                    lastError = null
                    videoWidth = player.videoWidth
                    videoHeight = player.videoHeight
                    player.setVolume(currentVolume, currentVolume)
                    container.post { applyAspectRatio() }
                    if (autoPlay) {
                        player.start()
                    }
                }
                setOnErrorListener { _, what, extra ->
                    lastError = "Ошибка воспроизведения ($what/$extra)"
                    isPrepared = false
                    true
                }
                prepareAsync()
            }
            mediaPlayer = mp
        } catch (e: Exception) {
            lastError = e.message ?: "Не удалось открыть видео"
            isPrepared = false
        }
    }

    private fun applyAspectRatio() {
        val cw = container.width
        val ch = container.height
        if (cw <= 0 || ch <= 0 || videoWidth <= 0 || videoHeight <= 0) return
        val containerRatio = cw.toFloat() / ch.toFloat()
        val videoRatio = videoWidth.toFloat() / videoHeight.toFloat()
        val targetW: Int
        val targetH: Int
        if (videoRatio > containerRatio) {
            targetW = cw
            targetH = (cw / videoRatio).toInt().coerceAtLeast(1)
        } else {
            targetH = ch
            targetW = (ch * videoRatio).toInt().coerceAtLeast(1)
        }
        val lp = textureView.layoutParams as? FrameLayout.LayoutParams ?: return
        if (lp.width != targetW || lp.height != targetH) {
            lp.width = targetW
            lp.height = targetH
            lp.gravity = Gravity.CENTER
            textureView.layoutParams = lp
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val mp = mediaPlayer
        when (call.method) {
            "play" -> {
                if (mp != null && isPrepared && !mp.isPlaying) {
                    mp.start()
                }
                result.success(true)
            }
            "pause" -> {
                if (mp != null && isPrepared && mp.isPlaying) {
                    mp.pause()
                }
                result.success(true)
            }
            "seekTo" -> {
                val ms = call.argument<Int>("positionMs") ?: 0
                if (mp != null && isPrepared) {
                    mp.seekTo(ms.coerceAtLeast(0))
                }
                result.success(true)
            }
            "setVolume" -> {
                val vol = (call.argument<Double>("volume") ?: 1.0).toFloat().coerceIn(0f, 1f)
                currentVolume = vol
                if (mp != null && isPrepared) {
                    mp.setVolume(vol, vol)
                }
                result.success(true)
            }
            "getState" -> {
                val playing = try { mp != null && isPrepared && mp.isPlaying } catch (_: Exception) { false }
                val pos = try { if (mp != null && isPrepared) mp.currentPosition else 0 } catch (_: Exception) { 0 }
                val dur = try { if (mp != null && isPrepared) mp.duration.coerceAtLeast(0) else 0 } catch (_: Exception) { 0 }
                result.success(
                    mapOf(
                        "ready" to isPrepared,
                        "playing" to playing,
                        "positionMs" to pos,
                        "durationMs" to dur,
                        "videoWidth" to videoWidth,
                        "videoHeight" to videoHeight,
                        "error" to lastError
                    )
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun releasePlayer() {
        isPrepared = false
        mediaPlayer?.let { mp ->
            try {
                if (mp.isPlaying) mp.stop()
            } catch (_: Exception) {}
            try {
                mp.release()
            } catch (_: Exception) {}
        }
        mediaPlayer = null
    }

    override fun dispose() {
        isDisposed = true
        channel.setMethodCallHandler(null)
        releasePlayer()
        surface?.release()
        surface = null
    }
}
