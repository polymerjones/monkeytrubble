package com.paulfisher.monkeytrubble

import android.annotation.SuppressLint
import android.graphics.Color
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

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
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
        webView.addJavascriptInterface(Bridge(store, Haptics(this, webView), playGames, ads), Bridge.NAME)
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
        evaluate("window.__resumeMonkeyAudio?.()")
        tilt.start()
        playGames.signIn()
    }

    override fun onPause() {
        tilt.stop()
        webView.onPause()
        super.onPause()
    }

    override fun onDestroy() {
        tilt.stop()
        webView.removeJavascriptInterface(Bridge.NAME)
        webView.destroy()
        super.onDestroy()
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
        }
    }
}
