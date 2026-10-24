package org.resonance.resonance

internal object NativeAudio {
    init { System.loadLibrary("resonance_audio") }
    external fun read(path: String): HashMap<String, Any>
    external fun write(path: String, keys: Array<String>, values: Array<String>, action: String, cover: ByteArray?)
    external fun createFingerprint(rate: Int, channels: Int): Long
    external fun feedFingerprint(handle: Long, samples: ShortArray)
    external fun finishFingerprint(handle: Long): String
    external fun freeFingerprint(handle: Long)
}
