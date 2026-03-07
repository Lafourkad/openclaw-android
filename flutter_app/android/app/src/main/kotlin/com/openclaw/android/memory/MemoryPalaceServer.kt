package com.openclaw.android.memory

import android.util.Log
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*

/**
 * MemoryPalaceServer — HTTP server on localhost:18791
 * Exposes Memory Palace tools as a JSON-RPC-like API consumed by
 * the OpenClaw gateway as a local HTTP plugin.
 *
 * Gateway config:
 *   plugins:
 *     - type: http
 *       url: http://localhost:18791
 *
 * Tool endpoints: POST /tools/call { name, parameters }
 * Tool list:      GET  /tools
 */
class MemoryPalaceServer(
    private val palace: MemoryPalaceService,
    private val port: Int = 18791,
) {
    companion object {
        private const val TAG = "MemoryPalaceServer"
    }

    private var server: ApplicationEngine? = null
    private val scope = CoroutineScope(Dispatchers.IO)

    fun start() {
        server = embeddedServer(Netty, port = port, host = "127.0.0.1") {
            install(ContentNegotiation) { json() }
            routing {
                get("/tools") { call.respond(toolDefinitions()) }
                get("/health") { call.respond(mapOf("status" to "ok", "port" to port)) }
                post("/tools/call") { handleToolCall(call) }
            }
        }.start(wait = false)
        Log.i(TAG, "Memory Palace HTTP server started on port $port")
    }

    fun stop() {
        server?.stop(1000, 5000)
        Log.i(TAG, "Memory Palace HTTP server stopped")
    }

    private suspend fun handleToolCall(call: ApplicationCall) {
        val body = try {
            call.receive<JsonObject>()
        } catch (e: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid JSON"))
            return
        }

        val toolName = body["name"]?.jsonPrimitive?.content ?: run {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Missing tool name"))
            return
        }

        val params = body["parameters"]?.jsonObject ?: JsonObject(emptyMap())

        try {
            val result = when (toolName) {
                "memory_set" -> palace.memorySet(
                    instanceId = params["instance_id"]?.str ?: "android",
                    memoryType = params["memory_type"]?.str ?: "fact",
                    content = params["content"]?.str ?: "",
                    subject = params["subject"]?.str,
                    project = params["project"]?.str,
                    tags = params["tags"]?.jsonArray?.map { it.jsonPrimitive.content },
                    keywords = params["keywords"]?.jsonArray?.map { it.jsonPrimitive.content },
                    foundational = params["foundational"]?.jsonPrimitive?.boolean ?: false,
                    sourceType = params["source_type"]?.str ?: "explicit",
                    sourceContext = params["source_context"]?.str,
                    sourceSessionId = params["source_session_id"]?.str,
                    supersedesId = params["supersedes_id"]?.jsonPrimitive?.longOrNull,
                )
                "memory_recall" -> palace.memoryRecall(
                    query = params["query"]?.str ?: "",
                    limit = params["limit"]?.int ?: 20,
                    instanceId = params["instance_id"]?.str,
                    memoryType = params["memory_type"]?.str,
                    project = params["project"]?.str,
                    includeArchived = params["include_archived"]?.bool ?: false,
                    synthesize = params["synthesize"]?.bool ?: true,
                )
                "memory_get" -> palace.memoryGet(
                    ids = params["memory_ids"]?.jsonArray?.map { it.jsonPrimitive.long }
                        ?: listOfNotNull(params["memory_ids"]?.jsonPrimitive?.longOrNull),
                    graphDepth = params["graph_depth"]?.int ?: 1,
                )
                "memory_recent" -> palace.memoryRecent(
                    limit = params["limit"]?.int ?: 20,
                    instanceId = params["instance_id"]?.str,
                    memoryType = params["memory_type"]?.str,
                )
                "memory_link" -> palace.memoryLink(
                    sourceId = params["source_id"]?.long ?: 0,
                    targetId = params["target_id"]?.long ?: 0,
                    relationType = params["relation_type"]?.str ?: "relates_to",
                    strength = params["strength"]?.float ?: 1.0f,
                    bidirectional = params["bidirectional"]?.bool ?: false,
                    archiveOld = params["archive_old"]?.bool ?: false,
                )
                "memory_unlink" -> palace.memoryUnlink(
                    sourceId = params["source_id"]?.long ?: 0,
                    targetId = params["target_id"]?.long ?: 0,
                )
                "memory_archive" -> palace.memoryArchive(
                    ids = params["memory_ids"]?.jsonArray?.map { it.jsonPrimitive.long } ?: emptyList(),
                    dryRun = params["dry_run"]?.bool ?: true,
                )
                "memory_stats" -> palace.memoryStats()
                "memory_audit" -> palace.memoryAudit()
                else -> mapOf("error" to "Unknown tool: $toolName")
            }
            call.respond(mapOf("result" to result, "tool" to toolName))
        } catch (e: Exception) {
            Log.e(TAG, "Tool call failed: $toolName — $e")
            call.respond(HttpStatusCode.InternalServerError, mapOf("error" to e.message))
        }
    }

    // ---------------------------------------------------------------------------
    // Tool definitions (returned to gateway for schema)
    // ---------------------------------------------------------------------------

    private fun toolDefinitions() = listOf(
        tool("memory_set", "Store new memory in palace",
            "instance_id" to "string", "memory_type" to "string", "content" to "string",
            "subject" to "string?", "project" to "string?", "tags" to "array?",
            "keywords" to "array?", "foundational" to "boolean?",
        ),
        tool("memory_recall", "Semantic search for memories",
            "query" to "string", "limit" to "integer?", "instance_id" to "string?",
            "memory_type" to "string?", "project" to "string?",
            "include_archived" to "boolean?", "synthesize" to "boolean?",
        ),
        tool("memory_get", "Fetch memories by ID with graph context",
            "memory_ids" to "array", "graph_depth" to "integer?",
        ),
        tool("memory_recent", "Last N memories, newest first",
            "limit" to "integer?", "instance_id" to "string?", "memory_type" to "string?",
        ),
        tool("memory_link", "Create relationship edge between memories",
            "source_id" to "integer", "target_id" to "integer", "relation_type" to "string",
            "strength" to "number?", "bidirectional" to "boolean?", "archive_old" to "boolean?",
        ),
        tool("memory_unlink", "Remove edge between memories",
            "source_id" to "integer", "target_id" to "integer",
        ),
        tool("memory_archive", "Archive memories (foundational protected)",
            "memory_ids" to "array", "dry_run" to "boolean?",
        ),
        tool("memory_stats", "Overview statistics"),
        tool("memory_audit", "Audit palace health"),
    )

    private fun tool(name: String, description: String, vararg params: Pair<String, String>) = mapOf(
        "name" to name,
        "description" to description,
        "parameters" to params.associate { (k, v) ->
            k to mapOf("type" to v.removeSuffix("?"), "required" to !v.endsWith("?"))
        },
    )

    // ---------------------------------------------------------------------------
    // JsonElement helpers
    // ---------------------------------------------------------------------------

    private val JsonElement?.str get() = this?.jsonPrimitive?.contentOrNull
    private val JsonElement?.int get() = this?.jsonPrimitive?.intOrNull ?: 20
    private val JsonElement?.long get() = this?.jsonPrimitive?.longOrNull ?: 0L
    private val JsonElement?.bool get() = this?.jsonPrimitive?.booleanOrNull ?: false
    private val JsonElement?.float get() = this?.jsonPrimitive?.floatOrNull ?: 1.0f
}
