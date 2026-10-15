package com.paulfisher.monkeytrubble

import android.content.Context
import androidx.core.content.edit
import org.json.JSONObject
import org.json.JSONTokener

/**
 * The page's progress JSON, kept in SharedPreferences. Android Auto Backup copies this one file to the player's Google account
 * (the backup rules in res/xml), so a reinstall or a new phone gets the save back: the iCloud equivalent, though not live sync between
 * devices, so the page's __monkeyCloudSave/__monkeyCloudChanged go unused here.
 */
class GameStore(context: Context) {
    private val prefs = context.getSharedPreferences("monkeytrubble", Context.MODE_PRIVATE)

    val save: String? get() = validSave(prefs.getString(SAVE_KEY, null))

    fun store(json: String) = prefs.edit { putString(SAVE_KEY, json) }

    companion object {
        const val SAVE_KEY = "monkeyTrubbleSave"

        /** Only a single JSON object is passed into the page as a script literal. */
        private fun validSave(json: String?): String? {
            json ?: return null
            return try {
                val tokener = JSONTokener(json)
                if (tokener.nextValue() is JSONObject && tokener.nextClean() == 0.toChar()) json else null
            } catch (_: Exception) {
                null
            }
        }
    }
}
