package com.paulfisher.monkeytrubble

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONObject

/**
 * Streak reminders (1.1), the Android twin of the iPhone app's Reminders.swift. The page decides everything (which days, which silly
 * line) and posts {op, on, time, items:[{slot, at (ms), title, body}]}; this replaces every pending reminder with that list, using
 * inexact alarms (no exact-alarm permission). op "ask" means the player turned REMINDERS on in Settings, the only time the Android 13+
 * permission pop-up may show; without that permission they stay off (older Android allows them from install). The on/off, time and
 * list live in their own prefs file, outside Auto Backup (permission is per phone), and the list is re-armed after a reboot. The page
 * gets the settings at launch as window.__monkeyRemind and hears back through window.__monkeyReminders({status, asked}).
 */
class Reminders(private val context: Context, private val evaluate: (String) -> Unit, private val askPermission: () -> Unit) {
    private var pending: JSONObject? = null

    private var lastDaily = false

    fun handle(message: JSONObject) {
        when (message.optString("op")) {
            "test" -> { test(message); return }
            "ready" -> return // taps are delivered by MainActivity once the page has loaded
            "diag" -> { diag(); return }
        }
        val ask = message.optString("op") == "ask"
        val on = message.optBoolean("on")
        // Older pages send only `on` (the daily reminder); 1.1.3 pages also send daily and social (FRIEND NEWS).
        lastDaily = if (message.has("daily")) message.optBoolean("daily") else on
        val social = if (message.has("social")) message.optBoolean("social") else on
        val prefs = prefs(context)
        prefs.edit { putBoolean(SOCIAL_KEY, social) }
        message.optString("time").takeIf { TIME.matches(it) }?.let { prefs.edit { putString(TIME_KEY, it) } }
        // Friends news settings for when the alarm fires (ReminderReceiver), or none (friend news off, or no friends yet).
        prefs.edit { message.optJSONObject("news")?.takeIf { on && social }?.let { putString(NEWS_KEY, it.toString()) } ?: remove(NEWS_KEY) }
        // A reminder still showing is stale once the game is open.
        NotificationManagerCompat.from(context).cancelAll()
        if (!on) {
            arm(context, JSONArray())
            finish("off", ask)
            return
        }
        if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            arm(context, message.optJSONArray("items") ?: JSONArray())
            finish("on", ask)
        } else if (ask && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pending = message
            askPermission()
        } else {
            arm(context, JSONArray())
            finish(if (ask) "denied" else "off", ask)
        }
    }

    /** Dev tools TEST: one notification `delay` seconds after permission is settled; REMINDERS stays as it is. */
    private fun test(message: JSONObject) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pending = message
            askPermission()
            return
        }
        fireTest(message)
    }

    private fun fireTest(message: JSONObject) {
        val on = NotificationManagerCompat.from(context).areNotificationsEnabled()
        if (on) {
            // TEST NEWS (dev): the friends news line, fetched the same way the alarm does (the silly line if there's none).
            val news = message.optJSONObject("news")
            Thread {
                val body = news?.let { newsLine(context, it) } ?: message.optString("body")
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    post(context, message.optString("title"), body)
                }, (message.optDouble("delay", 10.0) * 1000).toLong())
            }.start()
        }
        evaluate("window.__monkeyReminderTest?.('${if (on) "on" else "denied"}')")
    }

    /** The Android 13+ pop-up's answer (MainActivity's launcher). */
    fun permissionResult(granted: Boolean) {
        val message = pending ?: return
        if (message.optString("op") == "test") { pending = null; fireTest(message); return }
        pending = null
        if (granted && NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            arm(context, message.optJSONArray("items") ?: JSONArray())
            finish("on", true)
        } else {
            arm(context, JSONArray())
            finish("denied", true)
        }
    }

    /** Dev tools DIAGNOSTICS: permission, the armed list and the last alarm-time news check (facts only: an armed alarm isn't a delivery). */
    private fun diag() {
        val prefs = prefs(context)
        val out = JSONObject()
            .put("permission", if (NotificationManagerCompat.from(context).areNotificationsEnabled()) "on" else "off or denied")
            .put("pending", JSONArray().also { list ->
                val items = try { JSONArray(prefs.getString(ITEMS_KEY, "[]")) } catch (_: Exception) { JSONArray() }
                for (i in 0 until items.length()) items.optJSONObject(i)?.let { item ->
                    if (item.optLong("at") > System.currentTimeMillis()) list.put(JSONObject().put("id", "slot-${item.optInt("slot")}")
                        .put("at", java.util.Date(item.optLong("at")).toString()).put("kind", if (item.optBoolean("newsOnly")) "news?" else item.optString("kind", "daily")))
                }
            })
        prefs.getString(LAST_KEY, null)?.let { out.put("last", JSONObject(it)) }
        evaluate("window.__monkeyReminderDiag?.($out)")
    }

    private fun finish(status: String, asked: Boolean) {
        prefs(context).edit { putBoolean(ON_KEY, status == "on" && lastDaily) }
        evaluate("window.__monkeyReminders?.({status:'$status',asked:$asked})")
    }

    companion object {
        private const val PREFS = "monkeytrubble.reminders"
        private const val ON_KEY = "on"
        private const val TIME_KEY = "time"
        private const val ITEMS_KEY = "items"
        private const val NEWS_KEY = "news"
        private const val SOCIAL_KEY = "social"
        private const val LAST_KEY = "lastCheck"
        private const val CHANNEL = "reminders"
        private const val SLOTS = 7
        private val TIME = Regex("""^\d\d:\d\d$""")
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_KIND = "kind"
        const val EXTRA_NEWS_ONLY = "newsOnly"

        /** The last alarm-time news check, for dev DIAGNOSTICS. */
        fun record(context: Context, result: String, line: String? = null) {
            prefs(context).edit { putString(LAST_KEY, JSONObject().put("at", java.util.Date().toString()).put("result", result).apply { line?.let { put("line", it) } }.toString()) }
        }

        private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** Runs before the page: on is null until this phone has ever synced (the page then picks ON for a new install). */
        fun startScript(context: Context): String {
            val prefs = prefs(context)
            val on = if (prefs.contains(ON_KEY)) prefs.getBoolean(ON_KEY, false).toString() else "null"
            val time = prefs.getString(TIME_KEY, null)?.takeIf { TIME.matches(it) } ?: "19:00"
            val social = if (prefs.contains(SOCIAL_KEY)) prefs.getBoolean(SOCIAL_KEY, true).toString() else "null"
            return "window.__monkeyRemind={on:$on,social:$social,time:'$time'};"
        }

        private fun intent(context: Context, slot: Int, title: String = "", body: String = "", kind: String = "daily", newsOnly: Boolean = false) =
            Intent(context, ReminderReceiver::class.java)
                .setAction("com.paulfisher.monkeytrubble.REMINDER.$slot")
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_BODY, body)
                .putExtra(EXTRA_KIND, kind)
                .putExtra(EXTRA_NEWS_ONLY, newsOnly)

        /** Cancels every slot, then sets an alarm for each future item and keeps the list for a reboot. */
        fun arm(context: Context, items: JSONArray) {
            val alarms = context.getSystemService(AlarmManager::class.java)
            for (slot in 0 until SLOTS) {
                PendingIntent.getBroadcast(context, slot, intent(context, slot), PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
                    ?.let { alarms.cancel(it); it.cancel() }
            }
            val now = System.currentTimeMillis()
            for (i in 0 until items.length()) {
                val item = items.optJSONObject(i) ?: continue
                val slot = item.optInt("slot", -1)
                val at = item.optLong("at")
                if (slot !in 0 until SLOTS || at <= now) continue
                val pi = PendingIntent.getBroadcast(
                    context, slot, intent(context, slot, item.optString("title"), item.optString("body"), item.optString("kind", "daily"), item.optBoolean("newsOnly")),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
            prefs(context).edit { putString(ITEMS_KEY, items.toString()) }
        }

        /**
         * Friends news in the daily reminder (Phase B, 2026-11-17), the Android side of the iPhone's NewsRefresh: when the alarm fires, a
         * quick my_news call (6s at most); if there's news, the reminder says that instead of its silly line. Same order as the iPhone:
         * a nudge, the shared puzzle, a friend request, a shared puzzle invite, being passed. Runs off the main thread.
         */
        fun newsLine(context: Context, given: JSONObject? = null): String? = news(context, given)?.first

        /** The news line and where tapping it goes (duo, friend, leaders, tourney), or null. Records the result for DIAGNOSTICS. */
        fun news(context: Context, given: JSONObject? = null): Pair<String, String>? {
            val r = pick(context, given)
            if (given == null) record(context, if (r == null) "no news (or no answer)" else "news found", r?.first)
            return r
        }

        private fun pick(context: Context, given: JSONObject? = null): Pair<String, String>? {
            val cfg = given ?: try { JSONObject(prefs(context).getString(NEWS_KEY, null) ?: return null) } catch (_: Exception) { return null }
            val t = cfg.optJSONObject("t") ?: return null
            val key = cfg.optString("key")
            val n = try {
                val conn = (java.net.URL(cfg.optString("url") + "/rest/v1/rpc/my_news").openConnection() as java.net.HttpURLConnection).apply {
                    requestMethod = "POST"; connectTimeout = 6000; readTimeout = 6000; doOutput = true
                    setRequestProperty("apikey", key); setRequestProperty("Content-Type", "application/json")
                    if (key.startsWith("eyJ")) setRequestProperty("Authorization", "Bearer $key")
                }
                conn.outputStream.use { it.write(JSONObject().put("p_id", cfg.optString("id")).put("p_secret", cfg.optString("secret")).put("p_mark", false).toString().toByteArray()) }
                if (conn.responseCode != 200) return null
                JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
            } catch (_: Exception) { return null }
            fun fill(k: String, vararg a: String): String? {
                var s = t.optString(k).ifEmpty { return null }
                a.forEachIndexed { i, v -> s = s.replace("{$i}", v) }
                return s
            }
            n.optJSONArray("nudges")?.optJSONObject(0)?.let { nudge ->
                val lines = t.optJSONArray("lines")
                val line = lines?.optString(nudge.optInt("line"))?.ifEmpty { null } ?: lines?.optString(0).orEmpty()
                return fill("nudge", nudge.optString("name"), line)?.let { it to "friend" }
            }
            n.optJSONObject("tourney")?.let { t2 ->
                if (t2.optInt("finished") > 0) fill("tourneyDone")?.let { return it to "tourney" }
                if (t2.optInt("invites") > 0) fill("tourneyInvite", t2.optString("host", "?"))?.let { return it to "tourney" }
            }
            n.optJSONObject("duo")?.let { duo ->
                if (duo.optBoolean("done")) return fill("duoDone", duo.optString("name"))?.let { it to "duo" }
                if (duo.optInt("found") + duo.optInt("placed") > 0) return fill("duo", duo.optString("name"))?.let { it to "duo" }
            }
            if (n.optInt("requests") > 0) {
                return (n.optJSONArray("request_names")?.optString(0)?.ifEmpty { null }?.let { fill("request", it) } ?: fill("requestAny"))?.let { it to "friend" }
            }
            if (n.optInt("duo_invites") > 0) return fill("duoInvite")?.let { it to "duo" }
            n.optJSONArray("passed")?.optJSONObject(0)?.let { return fill("passed", it.optString("name"))?.let { l -> l to "leaders" } }
            return null
        }

        fun rearm(context: Context) {
            val saved = prefs(context).getString(ITEMS_KEY, null) ?: return
            arm(context, try { JSONArray(saved) } catch (_: Exception) { return })
        }

        fun post(context: Context, title: String, body: String, kind: String = "daily") {
            val manager = NotificationManagerCompat.from(context)
            if (!manager.areNotificationsEnabled()) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(CHANNEL, context.getString(R.string.reminders_channel), NotificationManager.IMPORTANCE_DEFAULT)
                )
            }
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra(EXTRA_KIND, kind),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notify)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            try {
                manager.notify(1, notification)
            } catch (_: SecurityException) {
                // Permission taken away between the check and the post: nothing to show.
            }
        }
    }
}

/** A reminder's alarm went off: show it. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra(Reminders.EXTRA_TITLE).orEmpty()
        val body = intent.getStringExtra(Reminders.EXTRA_BODY).orEmpty()
        val kind = intent.getStringExtra(Reminders.EXTRA_KIND) ?: "daily"
        val newsOnly = intent.getBooleanExtra(Reminders.EXTRA_NEWS_ONLY, false)
        // The news check needs the network, so it runs on its own thread while the broadcast is kept alive (goAsync, ~10s budget).
        // A news-only slot (daily reminder off, FRIEND NEWS on) shows nothing when there's no news.
        val result = goAsync()
        Thread {
            try {
                val news = Reminders.news(context)
                if (news != null) Reminders.post(context, title, news.first, news.second)
                else if (!newsOnly) Reminders.post(context, title, body, kind)
            } finally { result.finish() }
        }.start()
    }
}

/** Alarms don't survive a restart; set the saved week again. */
class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) Reminders.rearm(context)
    }
}
