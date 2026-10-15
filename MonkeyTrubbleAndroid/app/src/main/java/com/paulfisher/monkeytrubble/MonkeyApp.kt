package com.paulfisher.monkeytrubble

import android.app.Application
import com.google.android.gms.games.PlayGamesSdk

class MonkeyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (PlayGames.isConfigured(this)) PlayGamesSdk.initialize(this)
    }
}
