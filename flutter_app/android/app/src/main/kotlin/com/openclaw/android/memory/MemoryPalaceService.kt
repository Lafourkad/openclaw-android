package com.openclaw.android.memory

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * MemoryPalaceService — on-device semantic memory.
 *
 * Provides the same 13 tools as the desktop Memory Palace:
 *   memory_set, memory_recall, memory_get, memory_recent,
 *   memory_link, memory_unlink, memory_archive, memory_stats,
 *   memory_audit, memory_reembed, memory_reflect (stub),
 *   palace_message (stub), code_remember_tool (stub)
 *
 * Storage: Room (SQLite) + HNSW index + LiteRT EmbeddingGemma
 */
class MemoryPalaceService(private val context: Context) {

    companion object {
        private const val TAG = "MemoryPalace"
    }

    private val db by lazy { MemoryDatabase.getInstance(context) }
    private val embedding by lazy { EmbeddingService(context) }
    private val hnsw by lazy {
        MemoryHnswIndex(
            indexFile = File(context.filesDir, ".openclaw/memory/hnsw.index"),
            dims = EmbeddingService.DIMS,
        )
    }

    // ---------------------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------------------

    suspend fun init() = withContext(Dispatchers.IO) {
        embedding.init()
        hnsw.init()
        // Rebuild HNSW from DB if index is empty but DB has memories
        if (hnsw.size() == 0) {
            val embeddings = db.embeddingDao().getAll()
            if (embeddings.isNotEmpty()) {
                Log.i(TAG, "Rebuilding HNSW from ${embeddings.size} stored embeddings")
                embeddings.forEach { e ->
                    hnsw.upsert(e.memoryId, e.vector.toFloatArray())
                }
                hnsw.save()
            }
        }
        Log.i(TAG, "MemoryPalace ready — ${db.memoryDao().count()} memories, ${hnsw.size()} indexed")
    }

    fun close() {
        hnsw.save()
        embedding.close()
    }

    // ---------------------------------------------------------------------------
    // memory_set
    // ---------------------------------------------------------------------------

    suspend fun memorySet(
        instanceId: String,
        memoryType: String,
        content: String,
        subject: String? = null,
        project: String? = null,
        tags: List<String>? = null,
        keywords: List<String>? = null,
        foundational: Boolean = false,
        sourceType: String = "explicit",
        sourceContext: String? = null,
        sourceSessionId: String? = null,
        supersedesId: Long? = null,
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val entity = MemoryEntity(
            instanceId = instanceId,
            memoryType = memoryType,
            content = content,
            subject = subject,
            project = project,
            tags = tags?.joinToString(","),
            keywords = keywords?.joinToString(","),
            foundational = foundational,
            sourceType = sourceType,
            sourceContext = sourceContext,
            sourceSessionId = sourceSessionId,
            supersededById = supersedesId,
        )
        val id = db.memoryDao().insert(entity)

        // Embed and index
        val vector = embedding.embed(content + (subject?.let { " $it" } ?: ""))
        db.embeddingDao().insert(EmbeddingEntity(memoryId = id, vector = vector.toByteArray()))
        hnsw.upsert(id, vector)
        hnsw.save()

        // Archive superseded
        if (supersedesId != null) {
            db.memoryDao().archive(supersedesId)
            hnsw.remove(supersedesId)
        }

        Log.i(TAG, "memory_set id=$id type=$memoryType")
        mapOf("id" to id, "status" to "stored")
    }

    // ---------------------------------------------------------------------------
    // memory_recall (semantic search)
    // ---------------------------------------------------------------------------

    suspend fun memoryRecall(
        query: String,
        limit: Int = 20,
        instanceId: String? = null,
        memoryType: String? = null,
        project: String? = null,
        includeArchived: Boolean = false,
        synthesize: Boolean = true,
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val queryVector = embedding.embed(query)

        // Semantic search via HNSW
        val candidates = hnsw.search(queryVector, limit * 3)
            .filter { it.second > 0.3f } // minimum similarity threshold

        // Fetch metadata and filter
        val results = candidates.mapNotNull { (id, score) ->
            val mem = db.memoryDao().getById(id) ?: return@mapNotNull null
            if (!includeArchived && mem.archived) return@mapNotNull null
            if (instanceId != null && mem.instanceId != instanceId) return@mapNotNull null
            if (memoryType != null && !matchesType(mem.memoryType, memoryType)) return@mapNotNull null
            if (project != null && !matchesProject(mem.project, project)) return@mapNotNull null
            db.memoryDao().incrementAccess(id)
            Triple(mem, score, id)
        }.take(limit)

        // Keyword fallback if semantic gave nothing
        val finalResults = if (results.isEmpty()) {
            db.memoryDao().keywordSearch(query, limit).map { Triple(it, 0.5f, it.id) }
        } else results

        mapOf(
            "memories" to finalResults.map { (mem, score, _) -> memoryToMap(mem, score) },
            "count" to finalResults.size,
            "query" to query,
        )
    }

    // ---------------------------------------------------------------------------
    // memory_get
    // ---------------------------------------------------------------------------

    suspend fun memoryGet(ids: List<Long>, graphDepth: Int = 1): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            val memories = ids.mapNotNull { id ->
                db.memoryDao().getById(id)?.also { db.memoryDao().incrementAccess(id) }
            }
            val graph = if (graphDepth > 0) {
                ids.flatMap { db.edgeDao().getEdgesForMemory(it) }
                    .map { edge -> mapOf("source" to edge.sourceId, "target" to edge.targetId, "type" to edge.relationType, "strength" to edge.strength) }
            } else emptyList()

            mapOf(
                "memories" to memories.map { memoryToMap(it) },
                "graph" to graph,
            )
        }

    // ---------------------------------------------------------------------------
    // memory_recent
    // ---------------------------------------------------------------------------

    suspend fun memoryRecent(
        limit: Int = 20,
        instanceId: String? = null,
        memoryType: String? = null,
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val memories = if (instanceId != null) {
            db.memoryDao().getRecentForInstance(instanceId, limit * 2)
        } else {
            db.memoryDao().getRecent(limit * 2)
        }.filter { mem ->
            memoryType == null || matchesType(mem.memoryType, memoryType)
        }.take(limit)

        mapOf("memories" to memories.map { memoryToMap(it) }, "count" to memories.size)
    }

    // ---------------------------------------------------------------------------
    // memory_link
    // ---------------------------------------------------------------------------

    suspend fun memoryLink(
        sourceId: Long,
        targetId: Long,
        relationType: String,
        strength: Float = 1.0f,
        bidirectional: Boolean = false,
        archiveOld: Boolean = false,
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        db.edgeDao().insert(EdgeEntity(sourceId = sourceId, targetId = targetId, relationType = relationType, strength = strength))
        if (bidirectional) {
            db.edgeDao().insert(EdgeEntity(sourceId = targetId, targetId = sourceId, relationType = relationType, strength = strength))
        }
        if (archiveOld) {
            db.memoryDao().archive(targetId)
            hnsw.remove(targetId)
        }
        mapOf("status" to "linked", "sourceId" to sourceId, "targetId" to targetId)
    }

    // ---------------------------------------------------------------------------
    // memory_unlink
    // ---------------------------------------------------------------------------

    suspend fun memoryUnlink(sourceId: Long, targetId: Long): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            db.edgeDao().unlink(sourceId, targetId)
            mapOf("status" to "unlinked")
        }

    // ---------------------------------------------------------------------------
    // memory_archive
    // ---------------------------------------------------------------------------

    suspend fun memoryArchive(ids: List<Long>, dryRun: Boolean = true): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            val toArchive = ids.mapNotNull { id ->
                db.memoryDao().getById(id)?.takeIf { !it.foundational }
            }
            if (!dryRun) {
                toArchive.forEach {
                    db.memoryDao().archive(it.id)
                    hnsw.remove(it.id)
                }
                hnsw.save()
            }
            mapOf(
                "archived" to toArchive.size,
                "dryRun" to dryRun,
                "ids" to toArchive.map { it.id },
            )
        }

    // ---------------------------------------------------------------------------
    // memory_stats
    // ---------------------------------------------------------------------------

    suspend fun memoryStats(): Map<String, Any?> = withContext(Dispatchers.IO) {
        val total = db.memoryDao().count()
        mapOf(
            "total" to total,
            "indexed" to hnsw.size(),
            "embeddingModel" to "embeddinggemma-300m",
            "embeddingAvailable" to embedding.isAvailable(),
            "backend" to "sqlite+hnsw",
        )
    }

    // ---------------------------------------------------------------------------
    // memory_audit
    // ---------------------------------------------------------------------------

    suspend fun memoryAudit(): Map<String, Any?> = withContext(Dispatchers.IO) {
        val dbCount = db.memoryDao().count()
        val hnswCount = hnsw.size()
        val embCount = db.embeddingDao().getAll().size
        mapOf(
            "dbMemories" to dbCount,
            "hnswVectors" to hnswCount,
            "embeddingsStored" to embCount,
            "hnswDbSync" to (hnswCount == dbCount),
            "missingEmbeddings" to (dbCount - embCount),
        )
    }

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    private fun matchesType(type: String, pattern: String): Boolean {
        if (pattern.endsWith("*")) return type.startsWith(pattern.dropLast(1))
        return type == pattern
    }

    private fun matchesProject(projects: String?, filter: String): Boolean {
        if (projects == null) return false
        return projects.split(",").any { it.trim() == filter }
    }

    private fun memoryToMap(mem: MemoryEntity, score: Float? = null): Map<String, Any?> = buildMap {
        put("id", mem.id)
        put("instanceId", mem.instanceId)
        put("memoryType", mem.memoryType)
        put("content", mem.content)
        put("subject", mem.subject)
        put("project", mem.project)
        put("tags", mem.tags?.split(",")?.filter { it.isNotEmpty() })
        put("keywords", mem.keywords?.split(",")?.filter { it.isNotEmpty() })
        put("foundational", mem.foundational)
        put("archived", mem.archived)
        put("accessCount", mem.accessCount)
        put("createdAt", mem.createdAt)
        put("updatedAt", mem.updatedAt)
        if (score != null) put("score", score)
    }
}
