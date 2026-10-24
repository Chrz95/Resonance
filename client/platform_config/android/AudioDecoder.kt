package org.resonance.resonance

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import java.nio.ByteOrder

/** Decode locally using Android codecs. No recording permission or network call. */
internal object AudioDecoder {
    fun fingerprint(path: String): String {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var started = false
        var handle = 0L
        try {
            extractor.setDataSource(path)
            val index = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("No audio stream in this file.")
            extractor.selectTrack(index)
            val format = extractor.getTrackFormat(index)
            format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
            started = true
            var inputEnded = false
            var outputEnded = false
            var fedFrames = 0L
            var rate = 0
            var channels = 0
            var outputFormat: MediaFormat? = null
            val info = MediaCodec.BufferInfo()
            val deadline = SystemClock.elapsedRealtime() + 180_000L
            while (!outputEnded) {
                check(SystemClock.elapsedRealtime() < deadline) { "Audio decoding timed out." }
                if (!inputEnded) {
                    val inputIndex = decoder.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val input = decoder.getInputBuffer(inputIndex)!!
                        input.clear()
                        val time = extractor.sampleTime
                        val count = if (time >= 120_000_000L) -1 else extractor.readSampleData(input, 0)
                        if (count < 0) {
                            decoder.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            decoder.queueInputBuffer(inputIndex, 0, count, time.coerceAtLeast(0), 0)
                            extractor.advance()
                        }
                    }
                }
                when (val outputIndex = decoder.dequeueOutputBuffer(info, 10_000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> { outputFormat = decoder.outputFormat }
                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    else -> if (outputIndex >= 0) {
                        try {
                            if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                                val actual = outputFormat ?: decoder.outputFormat
                                val sampleRate = actual.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                                val channelCount = actual.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                                check(channelCount in 1..2) { "Fingerprinting supports mono or stereo audio." }
                                if (handle == 0L) {
                                    rate = sampleRate; channels = channelCount
                                    handle = NativeAudio.createFingerprint(rate, channels)
                                }
                                check(rate == sampleRate && channels == channelCount) { "Audio format changed while decoding." }
                                val encoding = if (actual.containsKey(MediaFormat.KEY_PCM_ENCODING)) actual.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                                check(encoding == AudioFormat.ENCODING_PCM_16BIT || encoding == AudioFormat.ENCODING_PCM_FLOAT) { "Unsupported decoder PCM format." }
                                val output = decoder.getOutputBuffer(outputIndex)!!.duplicate().order(ByteOrder.nativeOrder())
                                output.position(info.offset); output.limit(info.offset + info.size)
                                val bytesPerSample = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
                                val availableFrames = info.size / bytesPerSample / channels
                                val frames = minOf(availableFrames.toLong(), rate * 120L - fedFrames).toInt()
                                if (frames > 0) {
                                    val samples = ShortArray(frames * channels)
                                    if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
                                        for (i in samples.indices) samples[i] = (output.float.coerceIn(-1f, 1f) * 32767f).toInt().toShort()
                                    } else output.asShortBuffer().get(samples)
                                    NativeAudio.feedFingerprint(handle, samples)
                                    fedFrames += frames
                                }
                                if (fedFrames >= rate * 120L) outputEnded = true
                            }
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputEnded = true
                        } finally { decoder.releaseOutputBuffer(outputIndex, false) }
                    }
                }
            }
            check(handle != 0L && fedFrames >= rate * 5L) { "At least five seconds of decodable audio is required." }
            return NativeAudio.finishFingerprint(handle)
        } finally {
            if (handle != 0L) NativeAudio.freeFingerprint(handle)
            if (started) runCatching { codec?.stop() }
            codec?.release()
            extractor.release()
        }
    }
}
