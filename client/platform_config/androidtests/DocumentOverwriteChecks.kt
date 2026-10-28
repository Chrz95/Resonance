package org.resonance.resonance

import java.io.File
import java.io.FilterOutputStream
import java.io.IOException

/** Same offline fault-injection checks run on the host JVM and Android. */
object DocumentOverwriteChecks {
    fun run(root: File): Int {
        root.mkdirs()
        val target = File(root, "song.mp3")
        val prepared = File(root, "prepared.mp3").apply { writeBytes(byteArrayOf(5, 6)) }
        val backup = File(root, "recovery.mp3")
        val original = byteArrayOf(1, 2, 3, 4)
        fun reset(): String {
            target.writeBytes(original); backup.delete()
            return SafeDocumentOverwrite.digest(target.inputStream())
        }
        fun same() = check(target.readBytes().contentEquals(original))
        fun fail(block: () -> Unit) { var failed = false; try { block() } catch (_: Exception) { failed = true }; check(failed) }
        var expected = reset()
        val digest = SafeDocumentOverwrite.replace(prepared, expected, backup, { target.inputStream() }, { target.outputStream() })
        check(target.readBytes().contentEquals(prepared.readBytes()) && !backup.exists())
        SafeDocumentOverwrite.replace(prepared, digest, backup, { target.inputStream() }, { target.outputStream() })
        expected = reset()
        fail { SafeDocumentOverwrite.replace(prepared, "0".repeat(64), backup, { target.inputStream() }, { target.outputStream() }) }
        same(); check(!backup.exists())
        var writes = 0
        fail { SafeDocumentOverwrite.replace(prepared, expected, backup, { target.inputStream() }, {
            writes++
            if (writes == 1) object : FilterOutputStream(target.outputStream()) {
                override fun write(bytes: ByteArray, offset: Int, length: Int) {
                    out.write(0); throw IOException("Simulated partial write")
                }
            } else target.outputStream()
        }) }
        same(); check(writes == 2 && !backup.exists())
        reset()
        fail { SafeDocumentOverwrite.replace(prepared, expected, backup, { target.inputStream() }, {
            target.writeBytes(byteArrayOf(0)); throw IOException("Provider unavailable")
        }) }
        check(backup.exists() && backup.readBytes().contentEquals(original))
        reset()
        fail { SafeDocumentOverwrite.replace(prepared, expected, backup, { throw IOException("Cannot read") }, { target.outputStream() }) }
        same(); check(!backup.exists())
        reset()
        var reads = 0
        fail { SafeDocumentOverwrite.replace(prepared, expected, backup, {
            reads++
            if (reads == 3) byteArrayOf(99).inputStream() else target.inputStream()
        }, { target.outputStream() }) }
        same(); check(!backup.exists())
        reset()
        fail { SafeDocumentOverwrite.replace(prepared, "bad", backup, { target.inputStream() }, { target.outputStream() }) }
        same()
        return 7
    }
}
