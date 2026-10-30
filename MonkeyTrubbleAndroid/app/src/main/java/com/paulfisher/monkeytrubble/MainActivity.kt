package com.paulfisher.monkeytrubble

import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.addCallback
import androidx.activity.enableEdgeToEdge
import androidx.core.content.ContextCompat
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.WebViewAssetLoader
import java.io.ByteArrayInputStream
import java.util.Locale
import kotlin.math.abs

/**
 * Hosts the bundled game (assets/web, copied from ../web at build time) in a full-screen WebView, like the iPhone app's
 * GameWebView.swift. Portrait only, offline, edge to edge, with native haptics, card tilt, a saved game, Play Games and
 * rewarded ads.
 */
class MainActivity : ComponentActivity() {
    private lateinit var container: FrameLayout
    private lateinit var webView: WebView
    private lateinit var store: GameStore
    private lateinit var tilt: Tilt
    private lateinit var playGames: PlayGames
    private lateinit var ads: Ads
    private var systemBars = Insets.NONE
    /** Null until the page first says; older pages keep the tilt sensor on. */
    private var pageWantsMotion: Boolean? = null
    private var resumed = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)

        val background = ContextCompat.getColor(this, R.color.launch_background)
        webView = WebView(this).apply {
            setBackgroundColor(background)
            overScrollMode = View.OVER_SCROLL_NEVER
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                mediaPlaybackRequiresUserGesture = false
                // The layout is sized for the screen like on iPhone, so the system font-size setting doesn't scale the page.
                textZoom = 100
                setSupportZoom(false)
                builtInZoomControls = false
                allowFileAccess = false
                allowContentAccess = false
            }
        }
        container = FrameLayout(this).apply {
            setBackgroundColor(background)
            addView(webView, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        }
        setContentView(container)
        if (PREFER_60HZ) preferSixtyHz()
        ViewCompat.setOnApplyWindowInsetsListener(container) { _, insets ->
            systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            insets
        }

        store = GameStore(this)
        playGames = PlayGames(this, ::evaluate)
        tilt = Tilt(this) { turn, lean ->
            evaluate(String.format(Locale.US, "window.__setMonkeyTilt?.(%.4f,%.4f)", turn, lean))
        }
        ads = Ads(this, ::evaluate)
        webView.addJavascriptInterface(Bridge(store, Haptics(this, webView), playGames, ads, Perf(this, ::evaluate), motion = { on ->
            pageWantsMotion = on
            if (!on) tilt.stop() else if (resumed) tilt.start()
        }, awake = { on ->
            // Screen stays awake only during play (2026-10-24 audit); menus and idle levels let it dim.
            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }), Bridge.NAME)
        webView.webViewClient = GameClient()

        // Back closes the top dialog or leaves a level (the page decides); on the home screen it sends the app to the background.
        onBackPressedDispatcher.addCallback(this) {
            webView.evaluateJavascript("window.__monkeyBack?.()===true") { handled ->
                if (handled != "true") moveTaskToBack(true)
            }
        }

        webView.loadUrl("https://${WebViewAssetLoader.DEFAULT_DOMAIN}/web/index.html")
        ads.gatherConsent()
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
        webView.resumeTimers()
        evaluate("window.__resumeMonkeyAudio?.()")
        resumed = true
        if (pageWantsMotion != false) tilt.start()
        playGames.signIn()
    }

    override fun onPause() {
        resumed = false
        tilt.stop()
        // Fade the game's sound out before the WebView pauses (cutting it off mid-sound buzzes), unless the app is back by then.
        evaluate("window.__quietMonkeyAudio?.()")
        // pauseTimers also stops the page's JS timers while in the background (onPause alone left them firing; 2026-10-24 audit).
        webView.postDelayed({ if (!resumed) { webView.onPause(); webView.pauseTimers() } }, QUIET_MS)
        super.onPause()
    }

    override fun onDestroy() {
        tilt.stop()
        webView.removeJavascriptInterface(Bridge.NAME)
        webView.destroy()
        super.onDestroy()
    }

    /**
     * On iPhone the page draws at about 60 fps; Android's WebView follows the screen, so 120 Hz phones drew every animation twice as
     * often for the same picture (Apple's perf talk: frame rate is the biggest power dial). Asks for the screen's 60 Hz mode where it
     * has one, and on Android 15+ also tells the system the game view wants 60.
     */
    private fun preferSixtyHz() {
        val display = ContextCompat.getDisplayOrDefault(this)
        val current = display.mode
        val mode = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .minByOrNull { abs(it.refreshRate - 60f) }
        if (mode != null && mode.modeId != current.modeId) {
            window.attributes = window.attributes.apply { preferredDisplayModeId = mode.modeId }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) webView.requestedFrameRate = 60f
    }

    private fun evaluate(script: String) {
        runOnUiThread { webView.evaluateJavascript(script, null) }
    }

    /** Runs before anything on the page: the bridge shim, the build flags and the saved game, like the iOS user scripts. */
    private fun startScript(): String {
        // The hidden dev mode (three taps on the home logo) works in debug builds only, never in a Play build.
        val debug = BuildConfig.DEBUG
        val save = store.save?.let { "window.__monkeySave=${it.replace("</", "<\\/")};" } ?: ""
        return "${Bridge.SHIM}window.__monkeyDebugBuild=$debug;window.__monkeyDevTaps=$debug;window.__monkeyAds=true;$save"
    }

    /**
     * Older WebViews report 0 for env(safe-area-inset-*) even when the page is drawn under the status and navigation bars. If so,
     * the WebView is fitted between the bars instead, which keeps the HUD and cage clear of them.
     */
    private fun checkSafeArea() {
        if (systemBars.top == 0 && systemBars.bottom == 0) return
        webView.evaluateJavascript(
            "(()=>{const d=document.createElement('div');d.style.cssText='position:fixed;visibility:hidden;" +
                "padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)';document.body.appendChild(d);" +
                "const s=getComputedStyle(d),v=parseFloat(s.paddingTop)+parseFloat(s.paddingBottom);d.remove();return v>0})()"
        ) { supported ->
            if (supported != "true") {
                container.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
            }
        }
    }

    private inner class GameClient : WebViewClient() {
        private val assets = WebViewAssetLoader.AssetsPathHandler(this@MainActivity)

        // Serves assets/web at https://appassets.androidplatform.net/web/, so the page can load its sound files into Web Audio
        // (the iOS app allows file-URL access for the same reason). index.html gets the start script ahead of its own scripts.
        private val loader = WebViewAssetLoader.Builder()
            .addPathHandler("/web/") { path ->
                if (path == "index.html") indexWithStartScript() else assets.handle("web/$path")
            }
            .build()

        private fun indexWithStartScript(): WebResourceResponse {
            val html = this@MainActivity.assets.open("web/index.html").bufferedReader().use { it.readText() }
            val injected = html.replaceFirst("<head>", "<head><script>${startScript()}</script>")
            return WebResourceResponse("text/html", "utf-8", ByteArrayInputStream(injected.toByteArray()))
        }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
            loader.shouldInterceptRequest(request.url)

        // Only the bundled game loads in the WebView (the iOS app blocks every non-file URL the same way).
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
            request.url.host != WebViewAssetLoader.DEFAULT_DOMAIN

        override fun onPageFinished(view: WebView, url: String) {
            checkSafeArea()
            ads.announcePrivacyOptions()
        }
    }

    companion object {
        /** How long the page gets to fade its sound out (__quietMonkeyAudio) before the WebView pauses or an ad opens. */
        const val QUIET_MS = 120L

        /** Perf switch: false lets the game run at the screen's full refresh rate again (preferSixtyHz). */
        const val PREFER_60HZ = true
    }
}
