# The page calls these through addJavascriptInterface, so R8 must keep their names.
-keepclassmembers class com.paulfisher.monkeytrubble.Bridge {
    @android.webkit.JavascriptInterface <methods>;
}
