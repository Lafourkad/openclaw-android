"use strict";
/**
 * memory-palace-android — OpenClaw plugin
 *
 * Lightweight HTTP proxy to the on-device Memory Palace server
 * running on Android (Room + HNSW + EmbeddingGemma).
 *
 * The Android app (MemoryPalaceServer.kt) exposes:
 *   GET  /health        → { status: "ok" }
 *   GET  /tools         → tool definitions
 *   POST /tools/call    → { name, parameters } → { result, tool }
 *
 * This plugin registers each tool with OpenClaw and proxies execute()
 * calls to the Android HTTP server.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = register;
// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------
async function palaceCall(baseUrl, toolName, params, timeoutMs = 30_000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const res = await fetch(`${baseUrl}/tools/call`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ name: toolName, parameters: params }),
            signal: controller.signal,
        });
        if (!res.ok) {
            const text = await res.text().catch(() => "");
            throw new Error(`Palace server returned ${res.status}: ${text}`);
        }
        const json = await res.json();
        if (json.error)
            throw new Error(json.error);
        return json.result ?? json;
    }
    finally {
        clearTimeout(timer);
    }
}
async function palaceHealth(baseUrl) {
    try {
        const res = await fetch(`${baseUrl}/health`, { signal: AbortSignal.timeout(3000) });
        return res.ok;
    }
    catch {
        return false;
    }
}
// ---------------------------------------------------------------------------
// Tool definitions (match Android MemoryPalaceServer tools)
// ---------------------------------------------------------------------------
const TOOL_DEFS = [
    {
        name: "memory_set",
        description: "Store new memory in palace. AUTO-LINKING: >=0.75 similarity auto-creates edges. " +
            "memory_type is open-ended (fact, preference, event, insight, architecture, gotcha, solution, design_decision). " +
            "foundational memories are never archived.",
        parameters: {
            type: "object",
            properties: {
                instance_id: { type: "string", description: "Instance identifier" },
                memory_type: { type: "string", description: "Memory type (fact, event, gotcha, etc.)" },
                content: { type: "string", description: "Memory content text" },
                subject: { type: "string", description: "Subject/title" },
                project: { type: "string", description: "Project name" },
                tags: { type: "array", items: { type: "string" }, description: "Tags" },
                keywords: { type: "array", items: { type: "string" }, description: "Keywords" },
                foundational: { type: "boolean", default: false, description: "Never archived if true" },
                source_type: { type: "string", default: "explicit" },
                source_context: { type: "string" },
                source_session_id: { type: "string" },
                supersedes_id: { type: "integer", description: "ID of memory this supersedes" },
            },
            required: ["instance_id", "memory_type", "content"],
        },
    },
    {
        name: "memory_recall",
        description: "Semantic search (HNSW vector similarity). Returns ranked memories matching the query.",
        parameters: {
            type: "object",
            properties: {
                query: { type: "string", description: "Search query" },
                limit: { type: "integer", default: 20, description: "Max results" },
                instance_id: { type: "string" },
                memory_type: { type: "string", description: "Filter by type (supports wildcards like 'code_*')" },
                project: { type: "string" },
                include_archived: { type: "boolean", default: false },
                synthesize: { type: "boolean", default: true, description: "LLM synthesis (not available on-device, returns raw)" },
            },
            required: ["query"],
        },
    },
    {
        name: "memory_get",
        description: "Fetch memories by ID with optional graph context.",
        parameters: {
            type: "object",
            properties: {
                memory_ids: {
                    anyOf: [
                        { type: "integer" },
                        { type: "array", items: { type: "integer" } },
                    ],
                    description: "Memory ID(s) to fetch",
                },
                graph_depth: { type: "integer", default: 1, description: "Graph traversal depth (1-3)" },
            },
            required: ["memory_ids"],
        },
    },
    {
        name: "memory_recent",
        description: "Last N memories, newest first.",
        parameters: {
            type: "object",
            properties: {
                limit: { type: "integer", default: 20, description: "Max results" },
                instance_id: { type: "string" },
                memory_type: { type: "string" },
            },
        },
    },
    {
        name: "memory_link",
        description: "Create relationship edge between memories. Standard types: supersedes, relates_to, derived_from, contradicts, exemplifies, refines.",
        parameters: {
            type: "object",
            properties: {
                source_id: { type: "integer" },
                target_id: { type: "integer" },
                relation_type: { type: "string", description: "Edge type" },
                strength: { type: "number", default: 1.0 },
                bidirectional: { type: "boolean", default: false },
                archive_old: { type: "boolean", default: false },
            },
            required: ["source_id", "target_id", "relation_type"],
        },
    },
    {
        name: "memory_unlink",
        description: "Remove edge(s) between memories.",
        parameters: {
            type: "object",
            properties: {
                source_id: { type: "integer" },
                target_id: { type: "integer" },
            },
            required: ["source_id", "target_id"],
        },
    },
    {
        name: "memory_archive",
        description: "Archive memories. Foundational always protected. dry_run: true by default.",
        parameters: {
            type: "object",
            properties: {
                memory_ids: { type: "array", items: { type: "integer" } },
                dry_run: { type: "boolean", default: true },
            },
            required: ["memory_ids"],
        },
    },
    {
        name: "memory_stats",
        description: "Overview statistics: total memories, indexed count, embedding status.",
        parameters: { type: "object", properties: {} },
    },
    {
        name: "memory_audit",
        description: "Audit palace health: DB/HNSW sync, missing embeddings.",
        parameters: { type: "object", properties: {} },
    },
];
// ---------------------------------------------------------------------------
// Session tracking (for primer)
// ---------------------------------------------------------------------------
const sessionRegistry = new Map();
const toolNames = new Set(TOOL_DEFS.map((t) => t.name));
// ---------------------------------------------------------------------------
// Plugin entry point
// ---------------------------------------------------------------------------
function register(api) {
    const cfg = api.config ?? {};
    const baseUrl = cfg.baseUrl ?? "http://127.0.0.1:18795";
    const defaultInstanceId = cfg.instanceId ?? "android";
    const logger = api.logger;
    logger.info(`[memory-palace-android] Registering tools → ${baseUrl}`);
    // -------------------------------------------------------------------------
    // Register tools
    // -------------------------------------------------------------------------
    for (const def of TOOL_DEFS) {
        api.registerTool({
            name: def.name,
            description: def.description,
            parameters: def.parameters,
            async execute(_toolCallId, params) {
                // Inject default instance_id only for write operations (not reads/queries)
                const writeOps = new Set(["memory_set"]);
                if (writeOps.has(def.name) && "instance_id" in (def.parameters.properties ?? {}) && !params.instance_id) {
                    params.instance_id = defaultInstanceId;
                }
                try {
                    const result = await palaceCall(baseUrl, def.name, params);
                    return {
                        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
                    };
                }
                catch (err) {
                    const msg = err?.message ?? String(err);
                    // Check if server is down
                    if (msg.includes("ECONNREFUSED") || msg.includes("fetch failed")) {
                        return {
                            content: [
                                {
                                    type: "text",
                                    text: JSON.stringify({
                                        error: "Memory Palace server unreachable",
                                        hint: "The Android Memory Palace server on :18795 is not running. Start the gateway service in the OpenClaw Android app.",
                                        baseUrl,
                                    }),
                                },
                            ],
                        };
                    }
                    return {
                        content: [{ type: "text", text: JSON.stringify({ error: msg }) }],
                    };
                }
            },
        });
    }
    // -------------------------------------------------------------------------
    // Health check service
    // -------------------------------------------------------------------------
    api.registerService({
        id: "memory-palace-android-health",
        start: async () => {
            const healthy = await palaceHealth(baseUrl);
            if (healthy) {
                logger.info(`[memory-palace-android] Palace server healthy on ${baseUrl}`);
            }
            else {
                logger.warn(`[memory-palace-android] Palace server NOT reachable at ${baseUrl} — tools will return errors until server starts`);
            }
        },
        stop: () => {
            logger.info("[memory-palace-android] Plugin stopped");
        },
    });
    // -------------------------------------------------------------------------
    // Session Primer (inject context on new sessions)
    // -------------------------------------------------------------------------
    const primerCfg = cfg.sessionPrimer;
    const enqueue = api.runtime?.system?.enqueueSystemEvent;
    if (primerCfg?.enabled && api.context) {
        api.context.on("before_tool_call", (event, ctx) => {
            if (!toolNames.has(event.toolName))
                return;
            const instanceId = event.params?.instance_id ?? defaultInstanceId;
            const sessionKey = ctx?.sessionKey ?? ctx?.sessionId;
            if (!instanceId || !sessionKey)
                return;
            const existing = sessionRegistry.get(instanceId);
            const isNew = !existing || existing.sessionKey !== sessionKey;
            sessionRegistry.set(instanceId, { sessionKey, lastSeen: Date.now() });
            if (!isNew)
                return;
            logger.info(`[memory-palace-android/primer] New session detected — priming instance=${instanceId}`);
            const queries = primerCfg.queries ?? [
                "recent work, active projects, current state",
                "important decisions, gotchas, and preferences",
            ];
            const limit = primerCfg.limit ?? 5;
            const primerInstanceId = primerCfg.instance_id ?? instanceId;
            // Fire async — don't block the tool call
            (async () => {
                try {
                    const sections = [];
                    for (const query of queries) {
                        const result = await palaceCall(baseUrl, "memory_recall", {
                            query,
                            limit,
                            instance_id: primerInstanceId,
                            synthesize: false, // no LLM on device
                        });
                        const memories = result?.memories;
                        if (Array.isArray(memories) && memories.length > 0) {
                            const summaries = memories
                                .map((m) => `• [${m.memoryType}] ${m.subject ?? "(no subject)"}: ${(m.content ?? "").slice(0, 200)}`)
                                .join("\n");
                            sections.push(`**${query}**\n${summaries}`);
                        }
                    }
                    if (sections.length > 0 && enqueue) {
                        const text = `[Memory Palace — Session Primed (on-device)]\n\n${sections.join("\n\n---\n\n")}`;
                        enqueue(text, { sessionKey });
                        logger.info(`[memory-palace-android/primer] Primed session=${sessionKey} (${sections.length} sections)`);
                    }
                }
                catch (err) {
                    logger.warn(`[memory-palace-android/primer] Primer failed: ${err.message}`);
                }
            })();
        });
    }
}
