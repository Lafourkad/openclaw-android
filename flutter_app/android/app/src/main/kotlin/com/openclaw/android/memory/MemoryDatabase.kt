package com.openclaw.android.memory

import androidx.room.*
import kotlinx.coroutines.flow.Flow

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

@Entity(tableName = "memories")
data class MemoryEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val instanceId: String,
    val memoryType: String,
    val subject: String? = null,
    val content: String,
    val project: String? = null,       // comma-separated if multiple
    val tags: String? = null,          // comma-separated
    val keywords: String? = null,      // comma-separated
    val foundational: Boolean = false,
    val archived: Boolean = false,
    val accessCount: Int = 0,
    val centrality: Float = 0f,
    val sourceType: String = "explicit",
    val sourceContext: String? = null,
    val sourceSessionId: String? = null,
    val supersededById: Long? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val lastAccessedAt: Long? = null,
)

@Entity(tableName = "edges")
data class EdgeEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val sourceId: Long,
    val targetId: Long,
    val relationType: String,
    val strength: Float = 1.0f,
    val createdBy: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
)

// Embedding vectors stored separately (large blobs)
@Entity(tableName = "embeddings")
data class EmbeddingEntity(
    @PrimaryKey val memoryId: Long,
    val vector: ByteArray,             // float32 array serialized as bytes
    val model: String = "embeddinggemma-300m",
    val dimensions: Int = 768,
    val updatedAt: Long = System.currentTimeMillis(),
)

// ---------------------------------------------------------------------------
// DAOs
// ---------------------------------------------------------------------------

@Dao
interface MemoryDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(memory: MemoryEntity): Long

    @Update
    suspend fun update(memory: MemoryEntity)

    @Query("SELECT * FROM memories WHERE id = :id")
    suspend fun getById(id: Long): MemoryEntity?

    @Query("SELECT * FROM memories WHERE archived = 0 ORDER BY updatedAt DESC LIMIT :limit")
    suspend fun getRecent(limit: Int): List<MemoryEntity>

    @Query("SELECT * FROM memories WHERE archived = 0 AND instanceId = :instanceId ORDER BY updatedAt DESC LIMIT :limit")
    suspend fun getRecentForInstance(instanceId: String, limit: Int): List<MemoryEntity>

    @Query("SELECT * FROM memories WHERE archived = 0 AND content LIKE '%' || :query || '%' LIMIT :limit")
    suspend fun keywordSearch(query: String, limit: Int): List<MemoryEntity>

    @Query("UPDATE memories SET accessCount = accessCount + 1, lastAccessedAt = :now WHERE id = :id")
    suspend fun incrementAccess(id: Long, now: Long = System.currentTimeMillis())

    @Query("UPDATE memories SET archived = 1, updatedAt = :now WHERE id = :id AND foundational = 0")
    suspend fun archive(id: Long, now: Long = System.currentTimeMillis())

    @Query("SELECT COUNT(*) FROM memories WHERE archived = 0")
    suspend fun count(): Int

    @Query("SELECT * FROM memories WHERE archived = 0")
    suspend fun getAll(): List<MemoryEntity>
}

@Dao
interface EdgeDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(edge: EdgeEntity): Long

    @Query("SELECT * FROM edges WHERE sourceId = :id OR targetId = :id")
    suspend fun getEdgesForMemory(id: Long): List<EdgeEntity>

    @Query("DELETE FROM edges WHERE (sourceId = :src AND targetId = :tgt) OR (sourceId = :tgt AND targetId = :src)")
    suspend fun unlink(src: Long, tgt: Long)
}

@Dao
interface EmbeddingDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(embedding: EmbeddingEntity)

    @Query("SELECT * FROM embeddings WHERE memoryId = :id")
    suspend fun getForMemory(id: Long): EmbeddingEntity?

    @Query("SELECT * FROM embeddings")
    suspend fun getAll(): List<EmbeddingEntity>
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@Database(
    entities = [MemoryEntity::class, EdgeEntity::class, EmbeddingEntity::class],
    version = 1,
    exportSchema = false,
)
abstract class MemoryDatabase : RoomDatabase() {
    abstract fun memoryDao(): MemoryDao
    abstract fun edgeDao(): EdgeDao
    abstract fun embeddingDao(): EmbeddingDao

    companion object {
        @Volatile private var INSTANCE: MemoryDatabase? = null

        fun getInstance(context: android.content.Context): MemoryDatabase =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    MemoryDatabase::class.java,
                    "memory_palace.db"
                ).build().also { INSTANCE = it }
            }
    }
}
