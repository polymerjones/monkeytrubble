# The page calls these through addJavascriptInterface, so R8 must keep their names.
-keepclassmembers class com.paulfisher.monkeytrubble.Bridge {
    @android.webkit.JavascriptInterface <methods>;
}

# AdMob brings in WorkManager, whose Room database is found by name (WorkDatabase_Impl) at app start. Without this the
# minified release build crashes before the first screen.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
