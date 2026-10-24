package org.resonance.resonance

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val tracks = mutableMapOf<String, File>()
    private val limit = 120L * 1024L * 1024L
    private var pendingSave: MethodChannel.Result? = null
    private var pendingFile: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val root = File(cacheDir, "resonance").apply { mkdirs() }
        root.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86_400_000L }?.forEach { it.deleteRecursively() }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.resonance/audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "saveFile") {
                    try {
                        check(pendingSave == null) { "A save dialog is already open." }
                        val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                        check(file.isFile && file.path.startsWith(root.canonicalPath + File.separator)) { "Invalid export file." }
                        val mimeType = when (file.extension) { "mp3" -> "audio/mpeg"; "flac" -> "audio/flac"; "m4a" -> "audio/mp4"; else -> "audio/ogg" }
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mimeType
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("filename"))
                        }
                        pendingSave = result; pendingFile = file
                        startActivityForResult(intent, 7319)
                    } catch (e: Exception) {
                        pendingSave = null; pendingFile = null
                        result.error("SAVE_ERROR", e.message, null)
                    }
                    return@setMethodCallHandler
                }
                worker.execute {
                    try {
                        val value = dispatch(call, root)
                        main.post { result.success(value) }
                    } catch (e: Exception) {
                        main.post { result.error("AUDIO_ERROR", e.message ?: "Audio operation failed.", null) }
                    } catch (e: UnsatisfiedLinkError) {
                        main.post { result.error("NATIVE_LIBRARY", "Native audio library is missing from this build.", null) }
                    }
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7319) return
        val result = pendingSave ?: return
        val file = pendingFile
        pendingSave = null; pendingFile = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || file == null) { result.success(false); return }
        worker.execute {
            try {
                file.inputStream().use { input ->
                    (contentResolver.openOutputStream(uri, "wt") ?: error("Cannot open the selected destination.")).use { output -> input.copyTo(output) }
                }
                main.post { result.success(true) }
            } catch (e: Exception) { main.post { result.error("SAVE_ERROR", e.message, null) } }
        }
    }

    private fun track(call: MethodCall): File = tracks[call.argument<String>("id")]?.takeIf { it.isFile }
        ?: error("This audio session expired. Import the file again.")

    private fun dispatch(call: MethodCall, root: File): Any? {
        val preferences = getSharedPreferences("online-services", MODE_PRIVATE)
        return when (call.method) {
            "normalizeCover" -> normalizeImage(requireNotNull(call.argument<ByteArray>("cover")))
            "getSettings" -> mapOf("acoustid_key" to preferences.getString("acoustid_key", ""), "user_agent" to preferences.getString("user_agent", ""))
            "saveSettings" -> {
                // AcoustID application keys identify the app, not a user's account.
                check(preferences.edit().putString("acoustid_key", call.argument<String>("acoustid_key"))
                    .putString("user_agent", call.argument<String>("user_agent")).commit()) { "Could not save settings." }
                null
            }
            "import" -> {
                tracks.entries.removeAll { !it.value.isFile }
                val source = File(requireNotNull(call.argument<String>("path")))
                check(source.isFile && source.length() in 1..limit) { "Choose an audio file up to 120 MiB." }
                check(tracks.size < 50 && tracks.values.sumOf { it.length() } + source.length() <= 2L * 1024L * 1024L * 1024L) { "Local session storage is full. Remove an imported file first." }
                val filename = requireNotNull(call.argument<String>("filename")).substringAfterLast('/').substringAfterLast('\\')
                val extension = filename.substringAfterLast('.', "").lowercase()
                check(extension in listOf("mp3", "flac", "m4a", "ogg", "opus")) { "Unsupported audio extension." }
                val id = UUID.randomUUID().toString()
                val folder = File(root, id).apply { mkdirs() }
                val local = File(folder, "original.$extension")
                try {
                    source.copyTo(local)
                    val data = NativeAudio.read(local.absolutePath)
                    tracks[id] = local
                    data["id"] = id; data["filename"] = filename; data["size"] = local.length()
                    data
                } catch (e: Exception) { folder.deleteRecursively(); throw e }
            }
            "fingerprint" -> AudioDecoder.fingerprint(track(call).absolutePath)
            "export" -> {
                val original = track(call)
                val tags = requireNotNull(call.argument<Map<String, String>>("tags"))
                for ((key, value) in tags) check(value.length <= if (key == "lyrics" || key == "synced_lyrics") 200_000 else 2000) { "The $key field is too long." }
                val action = call.argument<String>("cover_action") ?: "keep"
                val cover = if (action == "replace") normalizeImage(requireNotNull(call.argument<ByteArray>("cover"))) else null
                val output = File(root, "export-${UUID.randomUUID()}.${original.extension}")
                try {
                    original.copyTo(output)
                    NativeAudio.write(output.absolutePath, tags.keys.toTypedArray(), tags.values.toTypedArray(), action, cover)
                    NativeAudio.read(output.absolutePath) // Verify the resulting container can be reopened.
                    output.absolutePath
                } catch (e: Exception) { output.delete(); throw e }
            }
            "delete" -> { track(call).parentFile!!.deleteRecursively(); tracks.remove(call.argument<String>("id")); null }
            else -> error("Unknown audio operation.")
        }
    }

    private fun normalizeImage(data: ByteArray): ByteArray {
        check(data.size <= 5 * 1024 * 1024) { "Choose a cover up to 5 MiB." }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        check(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 25_000_000) { "Invalid image or resolution above 25 megapixels." }
        val options = BitmapFactory.Options().apply {
            inSampleSize = 1
            while (bounds.outWidth / inSampleSize > 3200 || bounds.outHeight / inSampleSize > 3200) inSampleSize *= 2
        }
        val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size, options) ?: error("Could not decode the cover image.")
        val scale = minOf(1.0, 1600.0 / maxOf(bitmap.width, bitmap.height))
        val resized = if (scale < 1) Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * scale).toInt()), maxOf(1, (bitmap.height * scale).toInt()), true) else bitmap
        try {
            return ByteArrayOutputStream().use { output ->
                check(resized.compress(Bitmap.CompressFormat.JPEG, 90, output)) { "Could not encode cover image." }
                output.toByteArray()
            }
        } finally { if (resized !== bitmap) resized.recycle(); bitmap.recycle() }
    }

    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
}
