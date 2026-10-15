package com.paulfisher.monkeytrubble

import android.app.Activity
import android.content.Context
import com.google.android.gms.games.PlayGames as Games
import org.json.JSONObject

/**
 * Google Play Games in place of Game Center. Play Games signs the player in at launch on its own; this tells the page their name
 * (window.__gameCenterReady, which also submits their scores) and sends the leaderboard scores the page posts. The page's
 * "accessPoint" messages have no Android equivalent and are ignored.
 */
class PlayGames(private val activity: Activity, private val evaluate: (String) -> Unit) {
    private val enabled = isConfigured(activity)
    private var signedIn = false

    // The page's Game Center leaderboard IDs, mapped to the IDs Play Console generated (res/values/games-ids.xml).
    private val leaderboards = mapOf(
        "monkeytrubble.rating" to activity.getString(R.string.leaderboard_troop_rating),
        "monkeytrubble.level" to activity.getString(R.string.leaderboard_highest_level),
    ).filterValues { it.isNotBlank() }

    fun signIn() {
        if (!enabled || signedIn) return
        Games.getGamesSignInClient(activity).isAuthenticated.addOnCompleteListener { task ->
            if (!task.isSuccessful || !task.result.isAuthenticated) return@addOnCompleteListener
            signedIn = true
            Games.getPlayersClient(activity).currentPlayer.addOnSuccessListener { player ->
                val json = JSONObject().put("alias", player.displayName)
                evaluate("window.__gameCenterReady?.($json)")
            }
        }
    }

    /** The page's "gameCenter" messages: {type:'score', leaderboard, value} and {type:'accessPoint', show}. */
    fun handle(message: JSONObject) {
        if (!signedIn || message.optString("type") != "score") return
        val id = leaderboards[message.optString("leaderboard")] ?: return
        val value = message.optLong("value", -1).takeIf { it >= 0 } ?: return
        Games.getLeaderboardsClient(activity).submitScore(id, value)
    }

    companion object {
        fun isConfigured(context: Context) = context.getString(R.string.game_services_project_id).isNotBlank()
    }
}
