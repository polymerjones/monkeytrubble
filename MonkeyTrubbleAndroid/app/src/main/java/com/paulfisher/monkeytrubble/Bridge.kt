package com.paulfisher.monkeytrubble

import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import org.json.JSONObject

/**
 * What the page posts to native code. The page talks to window.webkit.messageHandlers like it does on iPhone; the shim in
 * MainActivity forwards each handler here. JavaScript calls arrive on a background thread, so the work moves to the main thread.
 */
class Bridge(
    private val store: GameStore,
    private val haptics: Haptics,
    private val playGames: PlayGames,
    private val ads: Ads,
) {
    private val main = Handler(Looper.getMainLooper())

    @JavascriptInterface
    fun haptic(event: String) {
        main.post { haptics.play(event) }
    }

    @JavascriptInterface
    fun storage(json: String) {
        store.store(json)
    }

    @JavascriptInterface
    fun gameCenter(json: String) {
        val message = try { JSONObject(json) } catch (_: Exception) { return }
        main.post { playGames.handle(message) }
    }

    @JavascriptInterface
    fun ads(json: String) {
        val message = try { JSONObject(json) } catch (_: Exception) { return }
        main.post { ads.handle(message) }
    }

    companion object {
        const val NAME = "MonkeyAndroid"

        /** Gives the page the same handlers the iPhone app registers on its WKWebView. */
        const val SHIM = "window.webkit={messageHandlers:{" +
            "haptics:{postMessage:m=>$NAME.haptic(String(m))}," +
            "storage:{postMessage:m=>$NAME.storage(String(m))}," +
            "gameCenter:{postMessage:m=>$NAME.gameCenter(JSON.stringify(m))}," +
            "ads:{postMessage:m=>$NAME.ads(JSON.stringify(m))}}};"
    }
}
