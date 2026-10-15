package com.paulfisher.monkeytrubble

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.View

/**
 * The page's haptic events, matched to the iPhone app's (GameWebView.swift). Phones with rich haptics (Android 11+ composition
 * primitives) get taps at the same strengths as the iOS impacts; others fall back to the system's standard feedback, which needs
 * no strengths. Both follow the player's system touch-feedback setting.
 */
class Haptics(context: Context, private val view: View) {
    private val vibrator: Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
    private val handler = Handler(Looper.getMainLooper())

    private val rich = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && vibrator?.hasVibrator() == true &&
        vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_CLICK, VibrationEffect.Composition.PRIMITIVE_TICK)

    fun play(event: String) {
        when (event) {
            "cardFlip" -> tick(0.55f)
            "cardSettle" -> tick(0.3f)
            "cardCaged" -> click(0.72f)
            "cardBlocked" -> click(0.45f)
            "rankPass" -> click(0.6f)
            "pairCleared", "rankClimb" -> success()
            "cageOverflow" -> error()
            // A quick triple knock, like bars rattling: three taps 60ms apart, fading slightly.
            "cageRattle", "cageRattleSoft" -> {
                val base = if (event == "cageRattle") 0.8f else 0.45f
                if (rich) {
                    compose(listOf(base to 0, base * 0.85f to 60, base * 0.7f to 60))
                } else {
                    for (i in 0..2) handler.postDelayed({ standard(HapticFeedbackConstants.VIRTUAL_KEY) }, i * 60L)
                }
            }
        }
    }

    private fun tick(scale: Float) {
        if (rich) compose(listOf(scale to 0), VibrationEffect.Composition.PRIMITIVE_TICK)
        else standard(HapticFeedbackConstants.CLOCK_TICK)
    }

    private fun click(scale: Float) {
        if (rich) compose(listOf(scale to 0)) else standard(HapticFeedbackConstants.VIRTUAL_KEY)
    }

    // iOS's success notification is two quick taps, the second stronger; its error is three firm ones.
    private fun success() {
        if (rich) compose(listOf(0.5f to 0, 1f to 70))
        else standard(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY)
    }

    private fun error() {
        if (rich) compose(listOf(0.85f to 0, 0.85f to 90, 1f to 90))
        else standard(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
    }

    /** Taps as (strength, delay in ms after the previous tap). */
    private fun compose(taps: List<Pair<Float, Int>>, primitive: Int = VibrationEffect.Composition.PRIMITIVE_CLICK) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val composition = VibrationEffect.startComposition()
        for ((scale, delay) in taps) composition.addPrimitive(primitive, scale.coerceIn(0f, 1f), delay)
        vibrator?.vibrate(composition.compose())
    }

    private fun standard(constant: Int) {
        view.performHapticFeedback(constant)
    }
}
