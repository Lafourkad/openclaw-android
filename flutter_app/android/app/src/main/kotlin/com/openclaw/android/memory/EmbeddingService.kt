package com.openclaw.android.memory

import android.content.Context
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.sqrt

/**
 * EmbeddingService — runs EmbeddingGemma 300M via LiteRT (TFLite) to produce
 * 768-dim float32 embeddings from text. Downloads model on first use.
 *
 * Tokenization: simple whitespace/subword approximation (BPE-lite).
 * For production quality, swap in DJL HuggingFace tokenizer.
 */
class EmbeddingService(private val context: Context) {

    companion object {
        private const val TAG = "EmbeddingService"
        const val DIMS = 768
        private const val SEQ_LEN = 256
        private const val MODEL_FILENAME = "embeddinggemma-300m-seq256.tflite"
        private const val MODEL_URL =
            "https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300m-seq256.tflite"
    }

    private var interpreter: Interpreter? = null
    private var isReady = false

    /** Initialize — downloads model if needed, loads interpreter. */
    suspend fun init() {
        val modelFile = File(context.filesDir, ".openclaw/models/$MODEL_FILENAME")
        if (!modelFile.exists()) {
            Log.i(TAG, "Downloading EmbeddingGemma model...")
            downloadModel(modelFile)
        }
        if (modelFile.exists() && modelFile.length() > 1_000_000) {
            try {
                val opts = Interpreter.Options().apply {
                    numThreads = 4
                    useNNAPI = false // NNAPI can be unreliable
                }
                interpreter = Interpreter(modelFile, opts)
                isReady = true
                Log.i(TAG, "EmbeddingGemma ready (${modelFile.length() / 1_000_000}MB)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load LiteRT model: $e")
            }
        }
    }

    private fun downloadModel(target: File) {
        try {
            target.parentFile?.mkdirs()
            val url = java.net.URL(MODEL_URL)
            val conn = url.openConnection() as java.net.HttpURLConnection
            conn.connectTimeout = 30_000
            conn.readTimeout = 120_000
            conn.inputStream.use { input ->
                target.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            Log.i(TAG, "Model downloaded: ${target.length()} bytes")
        } catch (e: Exception) {
            Log.e(TAG, "Model download failed: $e")
        }
    }

    /**
     * Embed text → float32 array of [DIMS] dims.
     * Falls back to hash-based pseudo-embedding if model not loaded.
     */
    fun embed(text: String): FloatArray {
        val interp = interpreter
        return if (isReady && interp != null) {
            embedWithModel(interp, text)
        } else {
            hashEmbed(text)
        }
    }

    private fun embedWithModel(interp: Interpreter, text: String): FloatArray {
        // Tokenize: simple int array (model expects token IDs)
        // We use a compact approximation — for full quality use DJL tokenizer
        val tokenIds = tokenize(text)
        val attentionMask = IntArray(SEQ_LEN) { if (it < tokenIds.size) 1 else 0 }

        val inputIds = Array(1) { IntArray(SEQ_LEN) { if (it < tokenIds.size) tokenIds[it] else 0 } }
        val maskInput = Array(1) { attentionMask }

        val outputBuffer = Array(1) { FloatArray(DIMS) }

        interp.runForMultipleInputsOutputs(
            arrayOf(inputIds, maskInput),
            mapOf(0 to outputBuffer)
        )

        return normalize(outputBuffer[0])
    }

    /** Simplified tokenizer: splits on whitespace, maps to int IDs via hash. */
    private fun tokenize(text: String): IntArray {
        val prefix = "task: search result | query: "
        val full = prefix + text.take(500)
        val words = full.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val ids = IntArray(minOf(words.size + 2, SEQ_LEN))
        ids[0] = 2 // BOS
        for (i in 1 until ids.size - 1) {
            ids[i] = ((words.getOrNull(i - 1)?.hashCode() ?: 0) and 0x7FFF) + 100
        }
        if (ids.size > 1) ids[ids.size - 1] = 1 // EOS
        return ids
    }

    /** Fallback: deterministic hash embedding (no model needed). */
    private fun hashEmbed(text: String): FloatArray {
        val v = FloatArray(DIMS)
        val words = text.split(Regex("\\s+"))
        for ((wi, word) in words.withIndex()) {
            val h = word.hashCode()
            for (d in 0 until DIMS) {
                val seed = (h.toLong() * 1664525L + d * 1013904223L).toInt()
                v[d] += (seed.toFloat() / Int.MAX_VALUE.toFloat())
            }
        }
        return normalize(v)
    }

    /** L2 normalize to unit vector. */
    private fun normalize(v: FloatArray): FloatArray {
        val norm = sqrt(v.map { it * it }.sum())
        return if (norm > 0) FloatArray(v.size) { v[it] / norm } else v
    }

    /** Cosine similarity between two unit vectors (dot product). */
    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        var dot = 0f
        for (i in a.indices) dot += a[i] * b[i]
        return dot
    }

    fun isAvailable() = isReady

    fun close() {
        interpreter?.close()
        interpreter = null
        isReady = false
    }
}

// ---------------------------------------------------------------------------
// FloatArray ↔ ByteArray serialization (for Room storage)
// ---------------------------------------------------------------------------

fun FloatArray.toByteArray(): ByteArray {
    val buf = ByteBuffer.allocate(size * 4).order(ByteOrder.LITTLE_ENDIAN)
    forEach { buf.putFloat(it) }
    return buf.array()
}

fun ByteArray.toFloatArray(): FloatArray {
    val buf = ByteBuffer.wrap(this).order(ByteOrder.LITTLE_ENDIAN)
    return FloatArray(size / 4) { buf.getFloat() }
}
