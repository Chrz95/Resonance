package org.resonance.resonance

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/** Stream an already-tagged file to a writable document, with verified recovery. */
object SafeDocumentOverwrite {
    fun digest(input: InputStream): String = input.use { stream ->
        val hash = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(65536)
        var total = 0L
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            total += count
            check(total <= 160L * 1024L * 1024L) { "Audio exceeds the overwrite limit." }
            hash.update(buffer, 0, count)
        }
        hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    fun replace(prepared: File, expected: String, backup: File,
        read: () -> InputStream, write: () -> OutputStream): String {
        check(Regex("^[a-f0-9]{64}$").matches(expected)) { "Invalid original checksum." }
        check(prepared.isFile && prepared.length() in 1..160L * 1024L * 1024L) { "Invalid prepared audio." }
        check(!backup.exists()) { "Recovery backup already exists." }
        val partial = File(backup.path + ".part")
        check(!partial.exists()) { "Backup preparation already exists." }
        var started = false
        var keep = false
        try {
            // Bounded copy also verifies the selected document before any truncation.
            read().use { input -> partial.outputStream().use { output ->
                val buffer = ByteArray(65536)
                var total = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    check(total <= 160L * 1024L * 1024L) { "Selected document is too large." }
                    output.write(buffer, 0, count)
                }
                output.fd.sync()
            } }
            check(digest(partial.inputStream()) == expected && digest(read()) == expected) {
                "This document differs from the imported song or its last overwrite. Import it again."
            }
            check(partial.renameTo(backup)) { "Could not finish the recovery backup." }
            val updated = digest(prepared.inputStream())
            started = true // Opening a provider stream can itself truncate the document.
            prepared.inputStream().use { input -> write().use { output -> input.copyTo(output); output.flush() } }
            check(digest(read()) == updated) { "The saved document could not be verified." }
            return updated
        } catch (error: Exception) {
            if (started) {
                try {
                    backup.inputStream().use { input -> write().use { output -> input.copyTo(output); output.flush() } }
                    check(digest(read()) == expected) { "Restore verification failed." }
                } catch (_: Exception) {
                    keep = true
                    throw IllegalStateException("Overwrite failed. The original backup is retained. Use Overwrite recovery backups to save it elsewhere.", error)
                }
            }
            throw error
        } finally { partial.delete(); if (!keep) backup.delete() }
    }
}
