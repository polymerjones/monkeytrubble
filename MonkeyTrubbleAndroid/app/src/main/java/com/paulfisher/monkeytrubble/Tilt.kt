package com.paulfisher.monkeytrubble

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Card shine tilt, ported from the iPhone app: the angle comes from the gravity vector (stable upright, flat or anywhere between)
 * and is sent relative to a neutral pose that slowly follows the player's grip, so the shine reacts to movement however the phone
 * is held and never sticks.
 */
class Tilt(context: Context, private val send: (turn: Double, lean: Double) -> Unit) : SensorEventListener {
    private val sensors = context.getSystemService(SensorManager::class.java)
    private val gravity = sensors?.getDefaultSensor(Sensor.TYPE_GRAVITY)
    private var running = false
    private var neutral: Pair<Double, Double>? = null
    private var lastSent: Pair<Double, Double>? = null
    private var lastTime = 0L

    fun start() {
        if (gravity == null || running) return
        running = true
        neutral = null
        lastSent = null
        lastTime = 0L
        sensors?.registerListener(this, gravity, INTERVAL_US)
    }

    fun stop() {
        if (!running) return
        running = false
        sensors?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent) {
        // Some phones deliver faster than asked; keep to ~30 a second like iOS.
        val dt = (event.timestamp - lastTime) / 1e9
        if (lastTime != 0L && dt < 0.03) return
        lastTime = event.timestamp
        // Android reads +9.81 m/s² on z with the phone face up, where CoreMotion reads -1 g: flip and normalise to iOS's convention.
        val (ax, ay, az) = event.values.map(Float::toDouble)
        val g = sqrt(ax * ax + ay * ay + az * az).takeIf { it > 0 } ?: return
        val x = -ax / g
        val y = -ay / g
        val z = -az / g
        val turn = atan2(x, hypot(y, z))
        val lean = atan2(-y, -z)
        val base = neutral ?: run {
            neutral = turn to lean
            return
        }
        val follow = 1 - exp(-dt.coerceIn(0.0, 0.25) / 3.0)
        val dTurn = wrap(turn - base.first)
        val dLean = wrap(lean - base.second)
        neutral = wrap(base.first + dTurn * follow) to wrap(base.second + dLean * follow)
        // Skip sensor jitter below ~half a pixel of parallax so a resting phone stops waking the web view 30 times a second.
        lastSent?.let { if (abs(dTurn - it.first) + abs(dLean - it.second) < 0.002) return }
        lastSent = dTurn to dLean
        send(dTurn, dLean)
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}

    private fun wrap(angle: Double) = atan2(sin(angle), cos(angle))

    private companion object {
        const val INTERVAL_US = 33_333
    }
}
