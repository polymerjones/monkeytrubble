package com.paulfisher.monkeytrubble

import android.app.Activity
import android.os.Handler
import android.os.Looper
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback
import com.google.android.ump.ConsentDebugSettings
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/**
 * AdMob rewarded ads for the page's reward buttons (resume, shuffle, undo, Owl Eyes). The page posts {type, nonce} on the "ads"
 * handler and gets back window.__monkeyAdResult(nonce, status), status being completed, skipped, failed or unavailable, which
 * is what its requestReward expects. Consent (UMP) is gathered at launch before any ad is requested. Debug builds use Google's
 * sample rewarded unit, so test taps never touch the real one.
 */
class Ads(private val activity: Activity, private val evaluate: (String) -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private val consent = UserMessagingPlatform.getConsentInformation(activity)
    private val started = AtomicBoolean(false)
    private var ad: RewardedAd? = null
    private var loading = false
    private var showing = false
    // A tap that arrived while the ad was still loading; it plays once the load finishes or gives up after WAIT_MS.
    private var waiting: String? = null
    private val giveUp = Runnable { waiting?.let { waiting = null; report(it, "unavailable") } }

    /** Asks for consent where the law requires it (EEA, UK, some US states), then starts the SDK. Call from onCreate. */
    fun gatherConsent() {
        val params = ConsentRequestParameters.Builder()
        if (BuildConfig.UMP_EEA_TEST) {
            // Debug builds made with -PeeaTest: start from no answer and pretend to be in the EEA (see build.gradle.kts).
            consent.reset()
            params.setConsentDebugSettings(
                ConsentDebugSettings.Builder(activity)
                    .setDebugGeography(ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_EEA)
                    .build()
            )
        }
        consent.requestConsentInfoUpdate(activity, params.build(), {
            UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) {
                announcePrivacyOptions()
                start()
            }
        }, { start() })
        // A consent answer from an earlier launch is enough to start right away.
        start()
    }

    /** Tells the page whether Settings needs the "Ad privacy choices" row. Also called when the page (re)loads. */
    fun announcePrivacyOptions() {
        val required = consent.privacyOptionsRequirementStatus ==
            ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
        evaluate("window.__monkeyPrivacyOptions?.($required)")
    }

    private fun start() {
        if (!consent.canRequestAds() || !started.compareAndSet(false, true)) return
        Thread { MobileAds.initialize(activity) { main.post(::load) } }.start()
    }

    private fun load() {
        if (ad != null || loading || !started.get()) return
        loading = true
        RewardedAd.load(activity, BuildConfig.ADMOB_REWARDED_ID, AdRequest.Builder().build(), object : RewardedAdLoadCallback() {
            override fun onAdLoaded(loaded: RewardedAd) {
                loading = false
                ad = loaded
                waiting?.let { waiting = null; main.removeCallbacks(giveUp); play(it) }
            }

            override fun onAdFailedToLoad(error: LoadAdError) {
                loading = false
                waiting?.let { waiting = null; main.removeCallbacks(giveUp); report(it, "unavailable") }
            }
        })
    }

    /** The page's "ads" messages: {type, nonce} for a rewarded ad, or {type:'privacy'} to reopen the consent choices. */
    fun handle(message: JSONObject) {
        if (message.optString("type") == "privacy") {
            UserMessagingPlatform.showPrivacyOptionsForm(activity) { }
            return
        }
        val nonce = message.optString("nonce").takeIf { it.isNotEmpty() } ?: return
        when {
            showing || waiting != null -> report(nonce, "unavailable")
            ad != null -> play(nonce)
            started.get() -> {
                waiting = nonce
                main.postDelayed(giveUp, WAIT_MS)
                load()
            }
            else -> report(nonce, "unavailable")
        }
    }

    private fun play(nonce: String) {
        val current = ad ?: return report(nonce, "unavailable")
        ad = null
        showing = true
        var earned = false
        current.fullScreenContentCallback = object : FullScreenContentCallback() {
            // The page's loading screen comes down as the ad covers it, so it's gone when the ad closes.
            override fun onAdShowedFullScreenContent() {
                evaluate("window.__monkeyAdOpening?.()")
            }

            override fun onAdDismissedFullScreenContent() {
                showing = false
                report(nonce, if (earned) "completed" else "skipped")
                load()
            }

            override fun onAdFailedToShowFullScreenContent(error: AdError) {
                showing = false
                report(nonce, "failed")
                load()
            }
        }
        current.show(activity) { earned = true }
    }

    private fun report(nonce: String, status: String) {
        evaluate("window.__monkeyAdResult?.(${JSONObject.quote(nonce)},'$status')")
    }

    companion object {
        private const val WAIT_MS = 8_000L
    }
}
