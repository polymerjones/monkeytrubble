package com.paulfisher.monkeytrubble

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Trace
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

/**
 * Performance data for the game page, the Android side of the iPhone app's Perf.swift (Apple's perf talk, Paul 2026-10-29).
 *
 * Signposts: the page's perf.begin/end (index.html) arrive as {op:"begin"|"end", name, id} and become android.os.Trace async
 * sections, so a System Trace (Android Studio Profiler, or Perfetto) shows slices like "Game:startLevel" or "Game:levelTransition".
 * {op:"event"} (a hang the page caught, a fake hang) and {op:"state"} (the game's mode, which FX switches are off) become instant
 * slices named "Game event …" and "State mode=playing", Android's nearest thing to StateReporting.
 *
 * Exit reports: {op:"metrics"} (dev tools' COPY PERF LOG) gets the app's recent exits from the system (ANRs, crashes, low-memory
 * kills; Android 11+), the MetricKit stand-in. They're read on the phone only and nothing is uploaded. Play Console's Android
 * vitals has the same numbers across all players.
 */
class Perf(private val context: Context, private val evaluate: (String) -> Unit) {
    /** Async sections end by the same name and cookie they began with, so the id's name is kept until its end arrives. */
    private val open = ConcurrentHashMap<Int, String>()

    fun handle(message: JSONObject) {
        when (message.optString("op")) {
            "begin" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
                val id = message.optInt("id", -1).takeIf { it >= 0 } ?: return
                val name = section("Game:${message.optString("name")}")
                open[id] = name
                Trace.beginAsyncSection(name, id)
            }
            "end" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
                val id = message.optInt("id", -1)
                val name = open.remove(id) ?: return
                Trace.endAsyncSection(name, id)
            }
            "event" -> instant("Game event ${message.optString("name")} ${message.optString("info")}")
            "state" -> instant("State ${message.optString("feature")}=${message.optString("label")}")
            "metrics" -> evaluate("window.perfMetrics?.(${exitReports()})")
        }
    }

    /** A zero-length slice marks the moment in the trace. */
    private fun instant(name: String) {
        Trace.beginSection(section(name))
        Trace.endSection()
    }

    /** The newest exits as a JSON array, newest first; an empty array before Android 11. */
    private fun exitReports(limit: Int = 8): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return "[]"
        val manager = context.getSystemService(ActivityManager::class.java) ?: return "[]"
        val exits = try { manager.getHistoricalProcessExitReasons(context.packageName, 0, limit) } catch (_: Exception) { emptyList() }
        val list = JSONArray()
        for (exit in exits) {
            list.put(JSONObject().apply {
                put("at", Instant.ofEpochMilli(exit.timestamp).toString())
                put("reason", REASONS[exit.reason] ?: "reason ${exit.reason}")
                put("description", exit.description ?: "")
                put("status", exit.status)
                put("importance", exit.importance)
                put("pssKb", exit.pss)
                put("rssKb", exit.rss)
                // An ANR comes with the main thread's stack: the start of it says where the app was stuck.
                if (exit.reason == ApplicationExitInfo.REASON_ANR) {
                    val trace = try { exit.traceInputStream?.bufferedReader()?.use { it.readText() } } catch (_: Exception) { null }
                    trace?.let { put("trace", it.take(TRACE_CHARS)) }
                }
            })
        }
        return list.toString()
    }

    private companion object {
        /** Trace section names are cut off by the system at 127 characters. */
        fun section(name: String) = name.take(127)

        const val TRACE_CHARS = 6000

        val REASONS = mapOf(
            ApplicationExitInfo.REASON_ANR to "anr",
            ApplicationExitInfo.REASON_CRASH to "crash",
            ApplicationExitInfo.REASON_CRASH_NATIVE to "crash-native",
            ApplicationExitInfo.REASON_LOW_MEMORY to "low-memory",
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE to "excessive-resource-use",
            ApplicationExitInfo.REASON_EXIT_SELF to "exit-self",
            ApplicationExitInfo.REASON_SIGNALED to "signaled",
            ApplicationExitInfo.REASON_USER_REQUESTED to "user-requested",
            ApplicationExitInfo.REASON_USER_STOPPED to "user-stopped",
            ApplicationExitInfo.REASON_DEPENDENCY_DIED to "dependency-died",
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE to "initialization-failure",
            ApplicationExitInfo.REASON_PERMISSION_CHANGE to "permission-change",
            ApplicationExitInfo.REASON_OTHER to "other",
        )
    }
}
