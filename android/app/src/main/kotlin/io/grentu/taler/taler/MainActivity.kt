package io.grentu.taler.taler

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATER_CHANNEL = "io.grentu.taler/updater"
        private const val NATIVE_CHANNEL = "io.grentu.taler/native"
        private const val LEGACY_NOTIFICATION_CHANNEL_ID = "taler_messages_v1"
        private const val MSG_NOTIFICATION_CHANNEL_ID = "taler_messages_v2"
        private const val EXTRA_CHAT_ID = "taler_chat_id"
        private const val REQ_CODE_NOTIF = 1041
        private const val REQ_CODE_AUDIO = 1042
    }

    private var nativeChannel: MethodChannel? = null
    private var pendingNotifResult: MethodChannel.Result? = null
    private var pendingAudioPermResult: MethodChannel.Result? = null
    private var initialNotificationChatId: Long? = null

    private var audioPlayer: MediaPlayer? = null
    private var audioPrepared = false
    private var audioCompleted = false
    private var audioError: String? = null
    private var audioPlaybackSpeed = 1.0f

    private var audioRecorder: MediaRecorder? = null
    private var recordingPath: String? = null
    private var recordingStartedAtMs: Long = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        extractChatIdFromIntent(intent)?.let { initialNotificationChatId = it }
        ensureNotificationChannel()

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "taler_video_view",
            TalerVideoViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAbi" -> {
                        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
                        result.success(abi)
                    }
                    "canRequestPackageInstalls" -> {
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(allowed)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "APK path is empty", null)
                            return@setMethodCallHandler
                        }
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("NOT_FOUND", "APK file not found", null)
                            return@setMethodCallHandler
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            val permIntent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(permIntent)
                            result.success("needs_permission")
                            return@setMethodCallHandler
                        }

                        try {
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file
                            )
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(installIntent)
                            result.success("started")
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_CHANNEL)
        nativeChannel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> handleRequestNotificationPermission(result)
                "hasNotificationPermission" -> result.success(hasNotificationPermission())
                "showMessageNotification" -> {
                    val chatId = (call.argument<Number>("chatId"))?.toLong() ?: 0L
                    val title = call.argument<String>("title") ?: "Taler"
                    val body = call.argument<String>("body") ?: "Новое сообщение"
                    val sender = call.argument<String>("sender")
                    showMessageNotification(chatId, title, body, sender)
                    result.success(true)
                }
                "openNotificationSettings" -> {
                    result.success(openNotificationChannelSettings())
                }
                "cancelChatNotification" -> {
                    val chatId = (call.argument<Number>("chatId"))?.toLong() ?: 0L
                    NotificationManagerCompat.from(this).cancel(chatNotificationId(chatId))
                    result.success(true)
                }
                "getInitialNotificationChatId" -> {
                    val id = initialNotificationChatId
                    initialNotificationChatId = null
                    result.success(id)
                }
                "openUrl" -> {
                    val url = call.argument<String>("url").orEmpty()
                    result.success(openExternalUrl(url))
                }
                "openFile" -> {
                    val path = call.argument<String>("path").orEmpty()
                    val mime = call.argument<String>("mimeType")
                    result.success(openLocalFile(path, mime))
                }
                "audioPlay" -> {
                    val source = call.argument<String>("source").orEmpty()
                    val userAgent = call.argument<String>("userAgent").orEmpty()
                    val speed = (call.argument<Number>("speed"))?.toFloat() ?: 1.0f
                    result.success(startAudioPlayback(source, userAgent, speed))
                }
                "audioPause" -> {
                    try {
                        if (audioPrepared && audioPlayer?.isPlaying == true) {
                            audioPlayer?.pause()
                        }
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "audioResume" -> {
                    try {
                        if (audioPrepared && audioPlayer?.isPlaying == false) {
                            if (audioCompleted) {
                                audioPlayer?.seekTo(0)
                            }
                            audioCompleted = false
                            audioPlayer?.start()
                            applyPlaybackSpeed(audioPlayer, audioPlaybackSpeed)
                        }
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "audioSeek" -> {
                    val pos = call.argument<Int>("positionMs") ?: 0
                    try {
                        if (audioPrepared) {
                            audioCompleted = false
                            audioPlayer?.seekTo(pos.coerceAtLeast(0))
                        }
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "audioSetSpeed" -> {
                    val speed = ((call.argument<Number>("speed"))?.toFloat() ?: 1.0f)
                        .coerceIn(0.5f, 2.5f)
                    audioPlaybackSpeed = speed
                    applyPlaybackSpeed(audioPlayer, speed)
                    result.success(true)
                }
                "audioStop" -> {
                    stopAudioPlayback()
                    result.success(true)
                }
                "audioState" -> {
                    val mp = audioPlayer
                    val playing = try { mp != null && audioPrepared && mp.isPlaying } catch (_: Exception) { false }
                    val pos = try { if (mp != null && audioPrepared) mp.currentPosition.coerceAtLeast(0) else 0 } catch (_: Exception) { 0 }
                    val dur = try { if (mp != null && audioPrepared) mp.duration.coerceAtLeast(0) else 0 } catch (_: Exception) { 0 }
                    result.success(
                        mapOf(
                            "ready" to audioPrepared,
                            "playing" to playing,
                            "positionMs" to pos,
                            "durationMs" to dur,
                            "completed" to audioCompleted,
                            "error" to audioError
                        )
                    )
                }
                "hasAudioRecordPermission" -> result.success(hasAudioRecordPermission())
                "requestAudioRecordPermission" -> handleRequestAudioPermission(result)
                "startAudioRecord" -> {
                    val outputPath = call.argument<String>("outputPath").orEmpty()
                    result.success(startAudioRecording(outputPath))
                }
                "stopAudioRecord" -> result.success(stopAudioRecording(discard = false))
                "cancelAudioRecord" -> {
                    stopAudioRecording(discard = true)
                    result.success(true)
                }
                "getAudioAmplitude" -> {
                    val amp = try {
                        val raw = audioRecorder?.maxAmplitude ?: 0
                        (raw / 32767.0).coerceIn(0.0, 1.0)
                    } catch (_: Exception) {
                        0.0
                    }
                    result.success(amp)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val chatId = extractChatIdFromIntent(intent) ?: return
        nativeChannel?.invokeMethod("onNotificationTap", chatId)
    }

    private fun extractChatIdFromIntent(intent: Intent?): Long? {
        if (intent == null || !intent.hasExtra(EXTRA_CHAT_ID)) return null
        val id = intent.getLongExtra(EXTRA_CHAT_ID, 0L)
        return if (id != 0L) id else null
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            try {
                if (manager.getNotificationChannel(LEGACY_NOTIFICATION_CHANNEL_ID) != null) {
                    manager.deleteNotificationChannel(LEGACY_NOTIFICATION_CHANNEL_ID)
                }
            } catch (_: Exception) {}

            if (manager.getNotificationChannel(MSG_NOTIFICATION_CHANNEL_ID) == null) {
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                val audioAttrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val channel = NotificationChannel(
                    MSG_NOTIFICATION_CHANNEL_ID,
                    "Сообщения Taler",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Всплывающие уведомления о входящих сообщениях"
                    setSound(soundUri, audioAttrs)
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0L, 160L, 80L, 160L)
                    enableLights(true)
                    lightColor = 0xFF3282FF.toInt()
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setShowBadge(true)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun openNotificationChannelSettings(): Boolean {
        return try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ensureNotificationChannel()
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    putExtra(Settings.EXTRA_CHANNEL_ID, MSG_NOTIFICATION_CHANNEL_ID)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                val fallback = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(fallback)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun handleRequestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pendingNotifResult?.success(false)
            pendingNotifResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_CODE_NOTIF
            )
        } else {
            result.success(true)
        }
    }

    private fun hasAudioRecordPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun handleRequestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioRecordPermission()) {
            result.success(true)
            return
        }
        pendingAudioPermResult?.success(false)
        pendingAudioPermResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            REQ_CODE_AUDIO
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            REQ_CODE_NOTIF -> {
                pendingNotifResult?.success(granted)
                pendingNotifResult = null
            }
            REQ_CODE_AUDIO -> {
                pendingAudioPermResult?.success(granted)
                pendingAudioPermResult = null
            }
        }
    }

    private fun chatNotificationId(chatId: Long): Int {
        return (chatId xor (chatId ushr 32)).toInt().let { if (it == 0) 1 else it }
    }

    private fun showMessageNotification(
        chatId: Long,
        title: String,
        body: String,
        sender: String?
    ) {
        if (!hasNotificationPermission()) return
        ensureNotificationChannel()

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CHAT_ID, chatId)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val notifId = chatNotificationId(chatId)
        val pendingIntent = PendingIntent.getActivity(this, notifId, tapIntent, flags)
        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val senderName = sender?.takeIf { it.isNotBlank() } ?: title

        val me = Person.Builder().setName("Вы").build()
        val peer = Person.Builder().setName(senderName).build()
        val msgStyle = NotificationCompat.MessagingStyle(me)
        if (senderName != title) {
            msgStyle.setConversationTitle(title)
        }
        msgStyle.addMessage(body, System.currentTimeMillis(), peer)

        val notification = NotificationCompat.Builder(this, MSG_NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_taler)
            .setColor(0xFF3282FF.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(msgStyle)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0L, 160L, 80L, 160L))
            .setOnlyAlertOnce(false)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        try {
            NotificationManagerCompat.from(this).notify(notifId, notification)
        } catch (_: SecurityException) {}
    }

    private fun openExternalUrl(url: String): Boolean {
        if (url.isBlank()) return false
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun openLocalFile(path: String, explicitMime: String?): Boolean {
        if (path.isBlank()) return false
        val file = File(path)
        if (!file.exists()) return false
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val ext = file.extension.lowercase()
            val guessedMime = explicitMime?.takeIf { it.isNotBlank() }
                ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
                ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, guessedMime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(intent, "Открыть файл"))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun applyPlaybackSpeed(mp: MediaPlayer?, speed: Float) {
        if (mp == null || !audioPrepared) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val params = mp.playbackParams
                params.speed = speed.coerceIn(0.5f, 2.5f)
                mp.playbackParams = params
            } catch (_: Exception) {}
        }
    }

    private fun startAudioPlayback(
        source: String,
        userAgent: String,
        speed: Float
    ): Boolean {
        stopAudioPlayback()
        if (source.isBlank()) {
            audioError = "Пустой источник аудио"
            return false
        }
        audioPlaybackSpeed = speed.coerceIn(0.5f, 2.5f)
        audioError = null
        return try {
            val mp = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                if (source.startsWith("http://") || source.startsWith("https://")) {
                    val headers = mutableMapOf<String, String>()
                    if (userAgent.isNotBlank()) headers["User-Agent"] = userAgent
                    setDataSource(this@MainActivity, Uri.parse(source), headers)
                } else {
                    val f = File(source)
                    if (!f.exists() || f.length() <= 0L) {
                        audioError = "Аудиофайл не найден"
                        return false
                    }
                    setDataSource(f.absolutePath)
                }
                setOnPreparedListener { player ->
                    audioPrepared = true
                    audioCompleted = false
                    audioError = null
                    player.start()
                    if (audioPlaybackSpeed != 1.0f) {
                        applyPlaybackSpeed(player, audioPlaybackSpeed)
                    }
                }
                setOnCompletionListener {
                    audioCompleted = true
                }
                setOnErrorListener { _, what, extra ->
                    audioPrepared = false
                    audioCompleted = true
                    audioError = "MediaPlayer error ($what/$extra)"
                    true
                }
                prepareAsync()
            }
            audioPlayer = mp
            true
        } catch (e: Exception) {
            audioError = e.message ?: "Ошибка запуска аудио"
            stopAudioPlayback(clearError = false)
            false
        }
    }

    private fun stopAudioPlayback(clearError: Boolean = true) {
        audioPrepared = false
        audioCompleted = false
        if (clearError) {
            audioError = null
        }
        audioPlayer?.let { mp ->
            try {
                if (mp.isPlaying) mp.stop()
            } catch (_: Exception) {}
            try {
                mp.release()
            } catch (_: Exception) {}
        }
        audioPlayer = null
    }

    private fun createRecorder(): MediaRecorder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
    }

    private fun startAudioRecording(outputPath: String): Boolean {
        if (!hasAudioRecordPermission() || outputPath.isBlank()) return false
        stopAudioRecording(discard = true)

        val preferOgg = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            outputPath.lowercase().endsWith(".ogg")

        if (preferOgg) {
            if (tryStartRecorder(outputPath, useOggOpus = true)) {
                return true
            }
            val fallbackPath = outputPath.replace(Regex("\\.ogg$", RegexOption.IGNORE_CASE), ".m4a")
            return tryStartRecorder(fallbackPath, useOggOpus = false)
        }
        return tryStartRecorder(outputPath, useOggOpus = false)
    }

    private fun tryStartRecorder(path: String, useOggOpus: Boolean): Boolean {
        var recorder: MediaRecorder? = null
        return try {
            val outFile = File(path)
            outFile.parentFile?.mkdirs()
            if (outFile.exists()) outFile.delete()
            recorder = createRecorder()
            recorder.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                if (useOggOpus && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setOutputFormat(MediaRecorder.OutputFormat.OGG)
                    setAudioEncoder(MediaRecorder.AudioEncoder.OPUS)
                    setAudioEncodingBitRate(32000)
                    setAudioSamplingRate(48000)
                } else {
                    setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioEncodingBitRate(64000)
                    setAudioSamplingRate(44100)
                }
                setOutputFile(outFile.absolutePath)
                prepare()
                start()
            }
            audioRecorder = recorder
            recordingPath = outFile.absolutePath
            recordingStartedAtMs = SystemClock.elapsedRealtime()
            true
        } catch (_: Exception) {
            try { recorder?.reset() } catch (_: Exception) {}
            try { recorder?.release() } catch (_: Exception) {}
            try { File(path).delete() } catch (_: Exception) {}
            audioRecorder = null
            recordingPath = null
            recordingStartedAtMs = 0L
            false
        }
    }

    private fun stopAudioRecording(discard: Boolean): Map<String, Any?>? {
        val recorder = audioRecorder ?: return null
        val path = recordingPath
        val durationMs = (SystemClock.elapsedRealtime() - recordingStartedAtMs).coerceAtLeast(0L)
        audioRecorder = null
        recordingPath = null
        recordingStartedAtMs = 0L

        var stoppedCleanly = false
        try {
            recorder.stop()
            stoppedCleanly = true
        } catch (_: Exception) {
        } finally {
            try {
                recorder.reset()
            } catch (_: Exception) {}
            try {
                recorder.release()
            } catch (_: Exception) {}
        }

        if (discard || !stoppedCleanly || path.isNullOrBlank()) {
            if (!path.isNullOrBlank()) {
                try {
                    File(path).delete()
                } catch (_: Exception) {}
            }
            return null
        }

        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            try {
                file.delete()
            } catch (_: Exception) {}
            return null
        }
        return mapOf(
            "path" to path,
            "durationMs" to durationMs
        )
    }

    override fun onDestroy() {
        stopAudioPlayback()
        stopAudioRecording(discard = true)
        super.onDestroy()
    }
}
