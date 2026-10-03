package com.bilge.bilge

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Üç iş yapar:
 * 1. Başka uygulamalardan gelen kurs dosyalarını (.bilge.json) Dart tarafına iletir:
 *    dosyaya dokunulduğunda (VIEW) ya da Bilge ile paylaşıldığında (SEND) içeriği okur.
 *    Dart karşılığı: lib/ui/incoming.dart
 * 2. Dil kurslarındaki dinleme adımları için metni cihazın kendi sesiyle okur.
 *    Dart karşılığı: lib/ui/speech.dart
 * 3. Günlük çalışma hatırlatıcısını kurar ya da iptal eder.
 *    Dart karşılığı: lib/ui/io.dart (scheduleReminder)
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val ttsWaiting = mutableListOf<(Boolean) -> Unit>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = read(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bilge/incoming").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "take") {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bilge/tts").setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    val lang = call.argument<String>("lang") ?: ""
                    val rate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                    withTts { ok -> result.success(ok && speak(text, lang, rate)) }
                }
                "stop" -> {
                    tts?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bilge/reminder").setMethodCallHandler { call, result ->
            if (call.method == "schedule") {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val hour = call.argument<Int>("hour") ?: 20
                val title = call.argument<String>("title") ?: "Bilge"
                val body = call.argument<String>("body") ?: ""
                val lastActive = call.argument<String>("lastActive")
                if (enabled && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1002)
                }
                scheduleAlarm(applicationContext, enabled, hour, title, body, lastActive)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    /** Ses motoru ilk istekte kurulur; hazır olana kadar gelen istekler bekletilir. */
    private fun withTts(block: (Boolean) -> Unit) {
        if (ttsReady) return block(true)
        ttsWaiting.add(block)
        if (tts != null) return
        tts = TextToSpeech(applicationContext) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (!ttsReady) tts = null
            val waiting = ttsWaiting.toList()
            ttsWaiting.clear()
            runOnUiThread { waiting.forEach { it(ttsReady) } }
        }
    }

    /** Dilin sesi cihazda yoksa false döner; Dart tarafı kullanıcıya adımı geçme seçeneği sunar. */
    private fun speak(text: String, lang: String, rate: Float): Boolean {
        val engine = tts ?: return false
        return try {
            val locale = Locale.forLanguageTag(lang)
            if (engine.isLanguageAvailable(locale) < TextToSpeech.LANG_AVAILABLE) return false
            engine.language = locale
            engine.setSpeechRate(rate)
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "bilge") == TextToSpeech.SUCCESS
        } catch (e: Exception) {
            false
        }
    }

    override fun onDestroy() {
        tts?.shutdown()
        tts = null
        ttsReady = false
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        read(intent)?.let { channel?.invokeMethod("incoming", it) }
    }

    private fun read(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> return null
        }
        if (uri == null) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
            return if (text.length > MAX_BYTES) TOO_BIG else text
        }
        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                // Sınır aşılınca okuma kesilir: dev bir dosya belleğe alınmaz
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                while (out.size() <= MAX_BYTES) {
                    val n = stream.read(buffer)
                    if (n < 0) break
                    out.write(buffer, 0, n)
                }
                if (out.size() > MAX_BYTES) TOO_BIG else String(out.toByteArray(), Charsets.UTF_8)
            }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        /** Dart tarafındaki sınırla aynı (lib/ui/io.dart, maxCourseBytes). */
        const val MAX_BYTES = 8 * 1024 * 1024

        /** Dosya çok büyükse içerik yerine bu gönderilir (lib/ui/incoming.dart, Incoming.tooBig). */
        const val TOO_BIG = "bilge:too-big"

        const val PREFS_NAME = "bilge_reminder"
        const val KEY_ENABLED = "enabled"
        const val KEY_HOUR = "hour"
        const val KEY_TITLE = "title"
        const val KEY_BODY = "body"
        const val KEY_LAST_ACTIVE = "last_active"

        fun scheduleAlarm(context: Context, enabled: Boolean, hour: Int, title: String, body: String, lastActive: String?) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()
                .putBoolean(KEY_ENABLED, enabled)
                .putInt(KEY_HOUR, hour)
                .putString(KEY_TITLE, title)
                .putString(KEY_BODY, body)
            if (lastActive != null) {
                editor.putString(KEY_LAST_ACTIVE, lastActive)
            }
            editor.apply()

            val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, ReminderReceiver::class.java).apply {
                putExtra("title", title)
                putExtra("body", body)
            }
            val pi = PendingIntent.getBroadcast(
                context,
                1001,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarm.cancel(pi)
            if (!enabled) return

            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
            }
            alarm.setInexactRepeating(AlarmManager.RTC_WAKEUP, cal.timeInMillis, AlarmManager.INTERVAL_DAY, pi)
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences(MainActivity.PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(MainActivity.KEY_ENABLED, false)
        val hour = prefs.getInt(MainActivity.KEY_HOUR, 20)
        val title = prefs.getString(MainActivity.KEY_TITLE, "Bilge") ?: "Bilge"
        val body = prefs.getString(MainActivity.KEY_BODY, "") ?: ""

        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Telefon yeniden başlayınca alarmı SharedPreferences'taki ayarlara göre yeniden kur
            if (enabled) {
                MainActivity.scheduleAlarm(context, enabled, hour, title, body, null)
            }
            return
        }

        if (!enabled) return

        // Bugün ders çalışıldıysa hatırlatıcı gösterme
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val lastActive = prefs.getString(MainActivity.KEY_LAST_ACTIVE, "")
        if (lastActive == today) return

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channelId = "bilge_daily"
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(channelId, "Bilge", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = Intent(context, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
        val pi = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(context, channelId) else @Suppress("DEPRECATION") android.app.Notification.Builder(context)
        val notif = builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        nm.notify(1001, notif)
    }
}

