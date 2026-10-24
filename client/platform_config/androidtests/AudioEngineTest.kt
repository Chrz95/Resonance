package org.resonance.resonance

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File

/** Runs the actual APK's JNI bindings and Android MediaCodec decoder offline. */
@RunWith(AndroidJUnit4::class)
class AudioEngineTest {
    @Test fun localEditAndFingerprintWithoutServer() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext
        val cover = ByteArrayOutputStream().use { output ->
            val image = Bitmap.createBitmap(32, 32, Bitmap.Config.ARGB_8888)
            image.eraseColor(0xff8866cc.toInt())
            image.compress(Bitmap.CompressFormat.JPEG, 90, output)
            image.recycle(); output.toByteArray()
        }
        for (extension in listOf("mp3", "flac", "m4a", "ogg", "opus")) {
            val local = File(app.cacheDir, "instrumentation.$extension")
            instrumentation.context.assets.open("sample.$extension").use { input -> local.outputStream().use { input.copyTo(it) } }
            try {
                val tags = linkedMapOf("title" to "Manual 🎵", "artist" to "Artist", "lyrics" to "Offline lyrics", "synced_lyrics" to "[00:01] Offline lyrics")
                NativeAudio.write(local.path, tags.keys.toTypedArray(), tags.values.toTypedArray(), "replace", cover)
                val read = NativeAudio.read(local.path)
                @Suppress("UNCHECKED_CAST") val actual = read["tags"] as Map<String, String>
                assertEquals("Manual 🎵", actual["title"])
                assertEquals("Offline lyrics", actual["lyrics"])
                assertTrue((read["cover"] as ByteArray).isNotEmpty())
                assertTrue(AudioDecoder.fingerprint(local.path).length > 8)
                NativeAudio.write(local.path, emptyArray(), emptyArray(), "remove", null)
                assertTrue((NativeAudio.read(local.path)["cover"] as ByteArray).isEmpty())
            } finally { local.delete() }
        }
    }
}
