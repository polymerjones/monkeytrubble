package com.paulfisher.monkeytrubble

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File

/**
 * A finished jigsaw picture (sharePuzzle in index.html, Paul 2026-10-30), the Android side of the iPhone app's save-then-share. The page
 * sends {image: PNG data URL, name}; it's saved to the Gallery (Pictures/Monkey Trubble), the page is told (__puzzleSaved), then the
 * share sheet opens with a copy from the app's cache through the FileProvider. Android 8 and 9 would need the storage permission to
 * save, so there the picture only goes to the share sheet (which has its own save options).
 */
class Share(private val activity: Activity, private val evaluate: (String) -> Unit) {
    /** Runs on the bridge's background thread: decoding and writing stay off the main thread. */
    fun handle(message: JSONObject) {
        val url = message.optString("image")
        val bytes = try { Base64.decode(url.substringAfter(","), Base64.DEFAULT) } catch (_: Exception) { return }
        val name = message.optString("name").ifEmpty { "monkey-trubble.png" }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) evaluate("window.__puzzleSaved?.(${saveToGallery(bytes, name)},'gallery')")
        val file = File(activity.cacheDir, "shared").apply { mkdirs() }.resolve(name)
        try { file.writeBytes(bytes) } catch (_: Exception) { return }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.files", file)
        val send = Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.runOnUiThread { activity.startActivity(Intent.createChooser(send, null)) }
    }

    /** Android 10+: MediaStore needs no permission for the app's own pictures. Pending until written, so the Gallery never shows half a file. */
    private fun saveToGallery(bytes: ByteArray, name: String): Boolean {
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Monkey Trubble")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("no stream")
            resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
            true
        } catch (_: Exception) {
            resolver.delete(uri, null, null)
            false
        }
    }
}
