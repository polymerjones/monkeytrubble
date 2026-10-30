package com.paulfisher.monkeytrubble

import android.app.Application
import android.os.StrictMode
import com.google.android.gms.games.PlayGamesSdk

class MonkeyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Debug builds log main-thread disk and network work and leaked objects (the hang hunt from Apple's perf talk), never crash.
        if (BuildConfig.DEBUG) {
            StrictMode.setThreadPolicy(StrictMode.ThreadPolicy.Builder().detectAll().penaltyLog().build())
            StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().detectAll().penaltyLog().build())
        }
        if (PlayGames.isConfigured(this)) PlayGamesSdk.initialize(this)
    }
}
