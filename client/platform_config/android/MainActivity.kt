package org.resonance.resonance

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.content.pm.PackageManager
import android.os.Process
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
    private var pendingPick: MethodChannel.Result? = null
    private var pendingSave: MethodChannel.Result? = null
    private var pendingFile: File? = null
    private var pendingOverwrite = false
    private var pendingExpected: String? = null
    private var pendingName = "song"
    private val recoveryRoot get() = File(filesDir, "overwrite-recovery").apply { mkdirs() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val root = File(cacheDir, "resonance").apply { mkdirs() }
        root.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86_400_000L }?.forEach { it.deleteRecursively() }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.resonance/audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "pickSongs") {
                    try {
                        check(pendingSave == null && pendingPick == null) { "A document dialog is already open." }
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "application/ogg", "application/octet-stream"))
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        pendingPick = result
                        startActivityForResult(intent, 7320)
                    } catch (e: Exception) {
                        pendingPick = null; result.error("PICK_ERROR", e.message, null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "saveFile" || call.method == "overwriteFile") {
                    try {
                        check(pendingSave == null && pendingPick == null) { "A document dialog is already open." }
                        val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
                        val overwrite = call.method == "overwriteFile"
                        check(file.isFile && (file.path.startsWith(root.canonicalPath + File.separator) ||
                            (!overwrite && file.path.startsWith(recoveryRoot.canonicalPath + File.separator)))) { "Invalid export file." }
                        val originalUri = call.argument<String>("original_uri")
                        if (overwrite && originalUri != null) {
                            val uri = Uri.parse(originalUri)
                            check(uri.scheme == "content") { "Invalid original document URI." }
                            worker.execute {
                                try {
                                    val value = overwriteDocument(file, uri,
                                        requireNotNull(call.argument<String>("expected_digest")),
                                        call.argument<String>("filename") ?: "song")
                                    main.post { result.success(value) }
                                } catch (e: Exception) { main.post { result.error("SAVE_ERROR", e.message, null) } }
                            }
                            return@setMethodCallHandler
                        }
                        val mimeType = when (file.extension) { "mp3" -> "audio/mpeg"; "flac" -> "audio/flac"; "m4a" -> "audio/mp4"; else -> "audio/ogg" }
                        val intent = Intent(if (overwrite) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = if (overwrite) "*/*" else mimeType
                            if (overwrite) addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("filename"))
                        }
                        pendingSave = result; pendingFile = file
                        pendingOverwrite = overwrite
                        pendingExpected = call.argument<String>("expected_digest")
                        pendingName = (call.argument<String>("filename") ?: "song").substringAfterLast('/').substringAfterLast('\\')
                        startActivityForResult(intent, 7319)
                    } catch (e: Exception) {
                        pendingSave = null; pendingFile = null; pendingOverwrite = false; pendingExpected = null
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
        if (requestCode == 7320) {
            val result = pendingPick ?: return
            pendingPick = null
            if (resultCode != Activity.RESULT_OK || data == null) { result.success(null); return }
            val uris = linkedSetOf<Uri>()
            data.data?.let { uris.add(it) }
            data.clipData?.let { clip -> for (index in 0 until clip.itemCount) uris.add(clip.getItemAt(index).uri) }
            worker.execute {
                val files = mutableListOf<Map<String, String>>()
                val warnings = mutableListOf<String>()
                if (uris.size > 50) warnings.add("Only the first 50 selected songs were imported.")
                var totalImported = 0L
                for (uri in uris.take(50)) {
                    val folder = File(File(cacheDir, "resonance"), "picker-${UUID.randomUUID()}").apply { mkdirs() }
                    try {
                        check(uri.scheme == "content") { "Choose a document-provider audio file." }
                        val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (cursor.moveToFirst() && column >= 0) cursor.getString(column) else null
                        }?.substringAfterLast('/')?.substringAfterLast('\\') ?: "song"
                        val extension = name.substringAfterLast('.', "").lowercase()
                        check(extension in listOf("mp3", "flac", "m4a", "ogg", "opus")) { "Unsupported audio file: $name" }
                        val file = File(folder, "source.$extension")
                        contentResolver.openInputStream(uri)?.use { input -> file.outputStream().use { output ->
                            val buffer = ByteArray(65536)
                            var total = 0L
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                total += count
                                check(total <= limit) { "Song exceeds 120 MiB: $name" }
                                check(totalImported + total <= 2L * 1024L * 1024L * 1024L) { "Selected audio exceeds 2 GiB." }
                                output.write(buffer, 0, count)
                            }
                            check(total > 0) { "Song is empty: $name" }
                        } } ?: error("Cannot read $name")
                        totalImported += file.length()
                        if (!rememberDocument(uri, data.flags)) warnings.add("$name: persistent access is unavailable; locating the original may be needed after restart.")
                        files.add(mapOf("path" to file.absolutePath, "filename" to name, "original_uri" to uri.toString()))
                    } catch (e: Exception) { folder.deleteRecursively(); warnings.add(e.message ?: "Could not import audio.") }
                }
                main.post { result.success(mapOf("files" to files, "warnings" to warnings)) }
            }
            return
        }
        if (requestCode != 7319) return
        val result = pendingSave ?: return
        val file = pendingFile
        val overwrite = pendingOverwrite
        val expected = pendingExpected
        val filename = pendingName
        pendingOverwrite = false; pendingExpected = null
        pendingSave = null; pendingFile = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || file == null) { result.success(if (overwrite) null else false); return }
        worker.execute {
            try {
                if (overwrite) {
                    rememberDocument(uri, data?.flags ?: 0)
                    val value = overwriteDocument(file, uri, requireNotNull(expected), filename)
                    main.post { result.success(value) }
                } else {
                    file.inputStream().use { input ->
                        (contentResolver.openOutputStream(uri, "wt") ?: error("Cannot open the selected destination.")).use { output -> input.copyTo(output) }
                    }
                    main.post { result.success(true) }
                }
            } catch (e: Exception) { main.post { result.error("SAVE_ERROR", e.message, null) } }
        }
    }

    private fun rememberDocument(uri: Uri, flags: Int): Boolean {
        return try {
            val access = flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, access)
            contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission && it.isWritePermission }
        } catch (_: Exception) { false }
    }

    private fun overwriteDocument(file: File, uri: Uri, expected: String, filename: String): Map<String, String> {
        check(listOf(Intent.FLAG_GRANT_READ_URI_PERMISSION, Intent.FLAG_GRANT_WRITE_URI_PERMISSION).all {
            checkUriPermission(uri, Process.myPid(), Process.myUid(), it) == PackageManager.PERMISSION_GRANTED
        }) {
            "Original document access is missing or read-only. Use Locate original for overwrite to grant access again."
        }
        val name = filename.substringAfterLast('/').substringAfterLast('\\')
        val backup = File(recoveryRoot, "${UUID.randomUUID()}-$name")
        val digest = SafeDocumentOverwrite.replace(file, expected, backup,
            read = { contentResolver.openInputStream(uri) ?: error("Cannot read the original song.") },
            write = { contentResolver.openOutputStream(uri, "rwt") ?: error("Cannot overwrite the original song.") })
        return mapOf("digest" to digest, "original_uri" to uri.toString())
    }

    private fun track(call: MethodCall): File = tracks[call.argument<String>("id")]?.takeIf { it.isFile }
        ?: error("This audio session expired. Import the file again.")

    private fun dispatch(call: MethodCall, root: File): Any? {
        val preferences = getSharedPreferences("online-services", MODE_PRIVATE)
        return when (call.method) {
            "releasePickedSongs" -> {
                for (path in (call.argument<List<String>>("paths") ?: emptyList()).take(50)) {
                    val folder = File(path).canonicalFile.parentFile ?: continue
                    check(folder.parentFile?.canonicalPath == root.canonicalPath && folder.name.startsWith("picker-")) { "Invalid picker cache path." }
                    folder.deleteRecursively()
                }
                null
            }
            "listOverwriteBackups" -> recoveryRoot.listFiles()?.filter { it.isFile && !it.name.endsWith(".part") }?.sortedByDescending { it.lastModified() }?.map {
                mapOf("path" to it.absolutePath, "filename" to it.name)
            } ?: emptyList<Map<String, String>>()
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
