package com.openclaw.android.memory

import android.util.Log
import com.github.jelmerk.hnswlib.core.DistanceFunctions
import com.github.jelmerk.hnswlib.core.Item
import com.github.jelmerk.hnswlib.core.hnsw.HnswIndex
import java.io.File
import java.io.Serializable

/**
 * MemoryHnswIndex — HNSW ANN index wrapper.
 * Uses hnswlib-java (pure Java, no JNI, Android-safe).
 * Persists to disk as Java serialized object.
 */
class MemoryHnswIndex(
    private val indexFile: File,
    private val dims: Int = EmbeddingService.DIMS,
) {
    companion object {
        private const val TAG = "MemoryHnswIndex"
        private const val M = 16
        private const val EF_CONSTRUCTION = 200
        private const val EF_SEARCH = 50
    }

    data class VectorItem(
        val memoryId: Long,
        val vec: FloatArray,
    ) : Item<Long, FloatArray>, Serializable {
        override fun id(): Long = memoryId
        override fun vector(): FloatArray = vec
        override fun dimensions(): Int = vec.size
    }

    private var index: HnswIndex<Long, FloatArray, VectorItem, Float>? = null

    fun init() {
        index = if (indexFile.exists() && indexFile.length() > 0) {
            try {
                @Suppress("UNCHECKED_CAST")
                HnswIndex.load<Long, FloatArray, VectorItem, Float>(indexFile).also {
                    Log.i(TAG, "HNSW loaded: ${it.size()} vectors")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Index load failed, rebuilding: $e")
                buildFresh()
            }
        } else {
            Log.i(TAG, "Building fresh HNSW index")
            buildFresh()
        }
    }

    private fun buildFresh(): HnswIndex<Long, FloatArray, VectorItem, Float> =
        HnswIndex.newBuilder(dims, DistanceFunctions.FLOAT_COSINE_DISTANCE, 1_000_000)
            .withM(M)
            .withEfConstruction(EF_CONSTRUCTION)
            .withEf(EF_SEARCH)
            .build()

    fun upsert(memoryId: Long, vector: FloatArray) {
        index?.add(VectorItem(memoryId, vector))
    }

    fun remove(memoryId: Long) {
        index?.remove(memoryId, 0)
    }

    fun search(queryVector: FloatArray, k: Int): List<Pair<Long, Float>> {
        val idx = index ?: return emptyList()
        return idx.findNearest(queryVector, k).map { result ->
            Pair(result.item().memoryId, 1f - result.distance())
        }
    }

    fun save() {
        try {
            indexFile.parentFile?.mkdirs()
            index?.save(indexFile)
            Log.i(TAG, "HNSW saved: ${index?.size()} vectors")
        } catch (e: Exception) {
            Log.e(TAG, "HNSW save failed: $e")
        }
    }

    fun size(): Int = index?.size() ?: 0
}
