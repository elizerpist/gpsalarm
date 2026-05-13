package com.gpsalarm.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

class GpsAlarmMonitoringService : Service() {
    companion object {
        private const val prefsName = "gps_alarm_background_monitor"
        private const val payloadKey = "payload"
        private const val triggeredKey = "triggered_ids"
        private const val actionStart = "com.gpsalarm.app.START_MONITORING"
        private const val actionStopAlarm = "com.gpsalarm.app.STOP_ALARM_OUTPUT"
        private const val monitorChannelId = "gps_alarm_monitoring"
        private const val alarmAlertChannelId = "gps_alarm_alerts"
        private const val alarmSilentChannelId = "gps_alarm_silent_alerts"
        private const val monitorNotificationId = 1001

        private var ringtone: Ringtone? = null
        private var mediaPlayer: MediaPlayer? = null

        fun sync(context: Context, payloadJson: String) {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .putString(payloadKey, payloadJson)
                .apply()

            val intent = Intent(context, GpsAlarmMonitoringService::class.java)
                .setAction(actionStart)
            if (hasActiveAlarms(payloadJson)) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } else {
                context.stopService(intent)
            }
        }

        fun consumeTriggeredAlarmIds(context: Context): List<String> {
            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            val ids = prefs.getStringSet(triggeredKey, emptySet())
                ?.toList()
                ?: emptyList()
            prefs.edit().remove(triggeredKey).apply()
            return ids
        }

        fun stopAlarmOutput(context: Context) {
            try {
                ringtone?.stop()
            } catch (_: Exception) {
            }
            ringtone = null
            try {
                mediaPlayer?.stop()
                mediaPlayer?.release()
            } catch (_: Exception) {
            }
            mediaPlayer = null
            vibrator(context)?.cancel()
        }

        private fun hasActiveAlarms(payloadJson: String?): Boolean {
            if (payloadJson.isNullOrBlank()) return false
            return try {
                hasActiveAlarms(JSONObject(payloadJson))
            } catch (_: Exception) {
                false
            }
        }

        private fun hasActiveAlarms(payload: JSONObject): Boolean {
            val alarms = payload.optJSONArray("alarms") ?: return false
            for (i in 0 until alarms.length()) {
                if (alarms.optJSONObject(i)?.optBoolean("isActive", false) == true) {
                    return true
                }
            }
            return false
        }

        private fun vibrator(context: Context): Vibrator? {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(VibratorManager::class.java)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        }
    }

    private lateinit var locationManager: LocationManager
    private var payload = JSONObject()
    private val insideState = mutableMapOf<String, Boolean>()
    private val recentSpeedsKmh = ArrayDeque<Double>()
    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            handleLocation(location)
        }

        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == actionStopAlarm) {
            stopAlarmOutput(this)
            loadPayload()
            if (!hasActiveAlarms(payload)) stopSelf()
            return START_STICKY
        }

        loadPayload()
        if (!hasActiveAlarms(payload)) {
            stopLocationUpdates()
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(monitorNotificationId, buildMonitoringNotification())
        startLocationUpdates()
        return START_STICKY
    }

    override fun onDestroy() {
        stopLocationUpdates()
        stopAlarmOutput(this)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun loadPayload() {
        val raw = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(payloadKey, null)
        payload = try {
            JSONObject(raw ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun savePayload() {
        getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(payloadKey, payload.toString())
            .apply()
    }

    private fun startLocationUpdates() {
        stopLocationUpdates()
        if (!hasLocationPermission()) return

        val intervalMs = pollingIntervalMs()
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        for (provider in providers) {
            try {
                if (locationManager.isProviderEnabled(provider)) {
                    locationManager.requestLocationUpdates(
                        provider,
                        intervalMs,
                        0f,
                        locationListener,
                        Looper.getMainLooper()
                    )
                }
            } catch (_: Exception) {
            }
        }
    }

    private fun stopLocationUpdates() {
        try {
            locationManager.removeUpdates(locationListener)
        } catch (_: Exception) {
        }
    }

    private fun hasLocationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun pollingIntervalMs(): Long {
        val settings = payload.optJSONObject("settings") ?: JSONObject()
        val mode = settings.optInt("gpsPollingMode", 0)
        if (mode == 1) {
            return max(10, settings.optInt("customPollingIntervalSeconds", 10)) * 1000L
        }
        return 3000L
    }

    private fun handleLocation(location: Location) {
        if (location.hasSpeed()) {
            recentSpeedsKmh.addLast(location.speed.toDouble() * 3.6)
            while (recentSpeedsKmh.size > 5) recentSpeedsKmh.removeFirst()
        }

        val alarms = payload.optJSONArray("alarms") ?: JSONArray()
        val activeIds = mutableSetOf<String>()
        for (i in 0 until alarms.length()) {
            val alarm = alarms.optJSONObject(i) ?: continue
            if (!alarm.optBoolean("isActive", false)) continue
            val id = alarm.optString("id")
            activeIds.add(id)
            val distance = distanceMeters(
                location.latitude,
                location.longitude,
                alarm.optDouble("latitude"),
                alarm.optDouble("longitude")
            )
            val inside = distance <= effectiveRadius(alarm)
            val wasInside = insideState[id]
            insideState[id] = inside
            if (wasInside == null) continue

            val zoneTrigger = alarm.optInt("zoneTrigger", 0)
            val shouldTrigger = if (zoneTrigger == 0) {
                !wasInside && inside
            } else {
                wasInside && !inside
            }
            if (shouldTrigger) triggerAlarm(alarm, distance)
        }
        insideState.keys.retainAll(activeIds)
    }

    private fun effectiveRadius(alarm: JSONObject): Double {
        val triggerType = alarm.optInt("triggerType", 0)
        if (triggerType == 1 && !alarm.isNull("timeTriggerMinutes")) {
            val seconds = alarm.optInt("timeTriggerMinutes", 0) * 60.0
            return max(200.0, averageSpeedKmh() / 3.6 * seconds)
        }
        return alarm.optDouble("radiusMeters", 0.0)
    }

    private fun averageSpeedKmh(): Double {
        if (recentSpeedsKmh.isEmpty()) return 0.0
        return recentSpeedsKmh.sum() / recentSpeedsKmh.size
    }

    private fun triggerAlarm(alarm: JSONObject, distance: Double) {
        alarm.put("isActive", false)
        savePayload()
        rememberTriggeredId(alarm.optString("id"))

        val settings = payload.optJSONObject("settings") ?: JSONObject()
        val type = if (alarm.isNull("customAlarmType")) {
            settings.optInt("defaultAlarmType", 0)
        } else {
            alarm.optInt("customAlarmType", 0)
        }
        val sound = if (alarm.isNull("customAlarmSound")) {
            settings.optString("defaultAlarmSound", "system_alarm")
        } else {
            alarm.optString("customAlarmSound", "system_alarm")
        }
        val title = alarm.optString("name").ifBlank { "GPS Alarm" }
        val body = alarmBody(alarm, distance)

        if (type != 1) {
            playAlarmOutput(
                sound = sound,
                volume = settings.optDouble("volume", 0.7),
                vibrate = settings.optBoolean("vibrationEnabled", true)
            )
        }
        showAlarmNotification(type, title, body, alarm.optString("id").hashCode())

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val hasMoreActiveAlarms = hasActiveAlarms(payload)
        if (!hasMoreActiveAlarms) {
            stopLocationUpdates()
            if (type == 1) {
                stopSelf()
                return
            }
        }
        manager.notify(monitorNotificationId, buildMonitoringNotification())
    }

    private fun rememberTriggeredId(id: String) {
        if (id.isBlank()) return
        val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val ids = prefs.getStringSet(triggeredKey, emptySet())?.toMutableSet()
            ?: mutableSetOf()
        ids.add(id)
        prefs.edit().putStringSet(triggeredKey, ids).apply()
    }

    private fun alarmBody(alarm: JSONObject, distance: Double): String {
        val zone = if (alarm.optInt("zoneTrigger", 0) == 0) "Belepes" else "Kilepes"
        return if (alarm.optInt("triggerType", 0) == 1) {
            "$zone - ${alarm.optInt("timeTriggerMinutes", 0)} min"
        } else {
            "$zone - ${distance.toInt()}m / ${alarm.optDouble("radiusMeters", 0.0).toInt()}m"
        }
    }

    private fun playAlarmOutput(sound: String, volume: Double, vibrate: Boolean) {
        stopAlarmOutput(this)
        try {
            if (sound.startsWith("/")) {
                mediaPlayer = MediaPlayer().apply {
                    setDataSource(sound)
                    isLooping = true
                    setVolume(volume.toFloat(), volume.toFloat())
                    prepare()
                    start()
                }
            } else {
                val type = when (sound) {
                    "system_notification" -> RingtoneManager.TYPE_NOTIFICATION
                    "system_ringtone" -> RingtoneManager.TYPE_RINGTONE
                    else -> RingtoneManager.TYPE_ALARM
                }
                val uri = RingtoneManager.getDefaultUri(type)
                ringtone = RingtoneManager.getRingtone(this, uri)?.apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        audioAttributes = AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        isLooping = true
                        this.volume = volume.toFloat()
                    }
                    play()
                }
            }
        } catch (_: Exception) {
        }

        if (vibrate) {
            val pattern = longArrayOf(0, 700, 300, 700)
            val vibrator = vibrator(this) ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, 0)
            }
        }
    }

    private fun showAlarmNotification(type: Int, title: String, body: String, id: Int) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val openApp = PendingIntent.getActivity(
            this,
            id,
            Intent(this, MainActivity::class.java),
            pendingIntentFlags()
        )
        val stopIntent = PendingIntent.getService(
            this,
            id + 1,
            Intent(this, GpsAlarmMonitoringService::class.java).setAction(actionStopAlarm),
            pendingIntentFlags()
        )
        val channelId = if (type == 1) alarmAlertChannelId else alarmSilentChannelId
        val builder = notificationBuilder(channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("GPS Alarm: $title")
            .setContentText(body)
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setPriority(Notification.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_ALARM)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopIntent)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            builder.setDefaults(
                if (type == 1) Notification.DEFAULT_SOUND or Notification.DEFAULT_VIBRATE else 0
            )
        }

        if (type == 2) {
            val fullScreenIntent = Intent(this, AlarmActivity::class.java)
                .putExtra("title", title)
                .putExtra("body", body)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val fullScreenPendingIntent = PendingIntent.getActivity(
                this,
                id + 2,
                fullScreenIntent,
                pendingIntentFlags()
            )
            builder.setFullScreenIntent(fullScreenPendingIntent, true)
            startActivity(fullScreenIntent)
        }

        manager.notify(id, builder.build())
    }

    private fun buildMonitoringNotification(): Notification {
        val count = activeAlarmCount()
        val openApp = PendingIntent.getActivity(
            this,
            10,
            Intent(this, MainActivity::class.java),
            pendingIntentFlags()
        )
        return notificationBuilder(monitorChannelId)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("GPS Alarm")
            .setContentText("Monitoring $count active alarm${if (count == 1) "" else "s"}")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    private fun activeAlarmCount(): Int {
        val alarms = payload.optJSONArray("alarms") ?: return 0
        var count = 0
        for (i in 0 until alarms.length()) {
            if (alarms.optJSONObject(i)?.optBoolean("isActive", false) == true) count++
        }
        return count
    }

    private fun notificationBuilder(channelId: String): Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val monitorChannel = NotificationChannel(
            monitorChannelId,
            "GPS Alarm monitoring",
            NotificationManager.IMPORTANCE_LOW
        )
        val alarmAlertChannel = NotificationChannel(
            alarmAlertChannelId,
            "GPS Alarm alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        val alarmSilentChannel = NotificationChannel(
            alarmSilentChannelId,
            "GPS Alarm silent alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(monitorChannel)
        manager.createNotificationChannel(alarmAlertChannel)
        manager.createNotificationChannel(alarmSilentChannel)
    }

    private fun pendingIntentFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun distanceMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val r = 6371000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
            sin(dLng / 2) * sin(dLng / 2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}
