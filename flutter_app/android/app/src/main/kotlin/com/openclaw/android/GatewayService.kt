package com.openclaw.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

class GatewayService : Service() {
    companion object {
        const val CHANNEL_ID = "openclaw_gateway"
        const val ALERT_CHANNEL_ID = "openclaw_alerts"
        const val CHAT_CHANNEL_ID = "openclaw_chat"
        const val NOTIFICATION_ID = 1
        const val CRASH_NOTIFICATION_ID = 2
        const val CHAT_NOTIFICATION_ID = 3
        var isRunning = false
            private set
        var logSink: EventChannel.EventSink? = null
        private var instance: GatewayService? = null

        fun start(context: Context) {
            val intent = Intent(context, GatewayService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, GatewayService::class.java)
            context.stopService(intent)
        }
    }

    private var gatewayProcess: Process? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var restartCount = 0
    private val maxRestarts = 3
    private var startTime: Long = 0
    private var uptimeThread: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification("Starting..."))
        acquireWakeLock()
        startGateway()
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        instance = null
        uptimeThread?.interrupt()
        uptimeThread = null
        stopGateway()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startGateway() {
        // Kill any existing gateway process before starting a new one
        // Prevents double-response when service is restarted
        gatewayProcess?.let {
            try { it.destroyForcibly() } catch (_: Exception) {}
            gatewayProcess = null
        }
        isRunning = true
        instance = this
        startTime = System.currentTimeMillis()

        Thread {
            try {
                val filesDir = applicationContext.filesDir.absolutePath
                val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir

                // Install node/npm/openclaw wrappers in /data/local/tmp (executable on all Android)
                // This allows any subprocess or exec tool to call `node` via proper ld.so chain
                GlibcRunner(filesDir, nativeLibDir, "").installWrappers()

                // Install libsignal if missing (required by Telegram/WhatsApp channel plugins)
                installLibsignal(filesDir)
                // Patch openclaw.json: migrate legacy keys + write auth-profiles.json
                patchOpenclawConfig(filesDir)

                // Seed workspace TOOLS.md with Android environment context (if missing)
                seedWorkspaceTools(filesDir)

                // Seed SOUL.md / IDENTITY.md with agent name from config
                seedAgentIdentity(filesDir)

                // Remove BOOTSTRAP.md — the wizard already handles onboarding
                removeBootstrap(filesDir)

                // Copy glibc-compat.js from APK assets to external storage before every start.
                // External storage is accessible by both the app and ADB, avoiding any
                // path resolution issues with internal filesDir on different Android versions.
                val glibcCompatPath = try {
                    val extDir = applicationContext.getExternalFilesDir(null)
                    extDir?.mkdirs()
                    val dest = File(extDir, "glibc-compat.js")
                    applicationContext.assets.open("flutter_assets/assets/patches/glibc-compat.js").use { i ->
                        dest.outputStream().use { o -> i.copyTo(o) }
                    }
                    dest.absolutePath
                } catch (e: Exception) {
                    Log.e("OpenclawGW", "Failed to copy glibc-compat.js: ${e.message}")
                    "$filesDir/patches/glibc-compat.js" // fallback
                }
                Log.i("OpenclawGW", "glibc-compat.js at: $glibcCompatPath")

                // Verify libc.so symlink — critical for child process execution
                val libcSo = File("$filesDir/glibc/lib/libc.so")
                val libcSo6 = File("$filesDir/glibc/lib/libc.so.6")
                Log.i("OpenclawGW", "libc check: libc.so exists=${libcSo.exists()} isSymlink=${java.nio.file.Files.isSymbolicLink(libcSo.toPath())} libc.so.6 exists=${libcSo6.exists()}")
                if (libcSo.exists()) {
                    // Check if it's corrupted (should be ELF, starting with 0x7f454c46)
                    val magic = libcSo.inputStream().use { it.read().let { b1 ->
                        val b2 = it.read(); val b3 = it.read(); val b4 = it.read()
                        String(byteArrayOf(b1.toByte(), b2.toByte(), b3.toByte(), b4.toByte()))
                    }}
                    Log.i("OpenclawGW", "libc.so magic: '${magic.take(4)}' (expect ELF)")
                    if (!magic.startsWith("\u007fELF")) {
                        Log.e("OpenclawGW", "libc.so is CORRUPTED (magic='$magic')! Recreating symlink...")
                        libcSo.delete()
                        if (libcSo6.exists()) {
                            android.system.Os.symlink("libc.so.6", libcSo.absolutePath)
                            Log.i("OpenclawGW", "Recreated libc.so -> libc.so.6 symlink")
                        }
                    }
                } else if (libcSo6.exists()) {
                    Log.w("OpenclawGW", "libc.so missing! Creating symlink...")
                    android.system.Os.symlink("libc.so.6", libcSo.absolutePath)
                    Log.i("OpenclawGW", "Created libc.so -> libc.so.6 symlink")
                }

                val runner = GlibcRunner(filesDir, nativeLibDir, glibcCompatPath)

                // Check if a gateway is already running on the port
                if (isPortInUse(18789)) {
                    Log.i("OpenclawGW", "Port 18789 already in use — reusing existing gateway")
                    emitLog("Gateway already running — reusing existing instance")
                    updateNotificationRunning()
                    // Don't spawn a new process, just keep the service alive
                    // The existing gateway will handle WebSocket connections
                    startUptimeTicker()
                    return@Thread
                }

                gatewayProcess = runner.startGatewayProcess()
                updateNotificationRunning()
                emitLog("Gateway started")
                Log.i("OpenclawGW", "Gateway process spawned")
                startUptimeTicker()

                // Re-seed workspace files after gateway creates defaults
                // Poll multiple times because gateway may write defaults at any point during boot
                Thread {
                    try {
                        for (i in 1..6) {
                            Thread.sleep(3000) // Check every 3s for 18s total
                            Log.i("OpenclawGW", "Re-seed attempt $i/6")
                            seedWorkspaceTools(filesDir)
                            seedAgentIdentity(filesDir)
                            removeBootstrap(filesDir)
                        }
                    } catch (_: Exception) {}
                }.start()

                // Log file accessible via ADB
                val extDir = applicationContext.getExternalFilesDir(null)
                extDir?.mkdirs()
                val logFile = File(extDir, "gateway.log")
                logFile.writeText("=== Gateway started ===\n")

                val writeLog: (String) -> Unit = { line ->
                    Log.i("OpenclawGW", line)
                    emitLog(line)
                    try { logFile.appendText("$line\n") } catch (_: Exception) {}
                }

                // Read stdout
                val stdoutReader = BufferedReader(InputStreamReader(gatewayProcess!!.inputStream))
                Thread {
                    try {
                        var line: String?
                        while (stdoutReader.readLine().also { line = it } != null) {
                            writeLog(line ?: continue)
                        }
                    } catch (_: Exception) {}
                }.start()

                // Read stderr
                val stderrReader = BufferedReader(InputStreamReader(gatewayProcess!!.errorStream))
                Thread {
                    try {
                        var line: String?
                        while (stderrReader.readLine().also { line = it } != null) {
                            writeLog("[ERR] ${line ?: continue}")
                        }
                    } catch (_: Exception) {}
                }.start()

                val exitCode = gatewayProcess!!.waitFor()
                val exitMsg = "Gateway exited with code $exitCode"
                emitLog(exitMsg)
                Log.e("OpenclawGW", exitMsg)

                if (isRunning && restartCount < maxRestarts) {
                    restartCount++
                    val delayMs = 2000L * (1 shl (restartCount - 1)) // 2s, 4s, 8s
                    emitLog("Auto-restarting in ${delayMs / 1000}s (attempt $restartCount/$maxRestarts)...")
                    updateNotification("Restarting in ${delayMs / 1000}s (attempt $restartCount)...")
                    Thread.sleep(delayMs)
                    startGateway()
                } else if (restartCount >= maxRestarts) {
                    emitLog("Max restarts reached. Gateway stopped.")
                    updateNotification("Gateway stopped (crashed)")
                    sendCrashNotification("Gateway crashed after $maxRestarts restart attempts (exit code $exitCode)")
                    isRunning = false
                }
            } catch (e: Exception) {
                val errMsg = "Gateway error: ${e.message}"
                emitLog(errMsg)
                Log.e("OpenclawGW", errMsg, e)
                isRunning = false
                updateNotification("Gateway error")
            }
        }.start()
    }

    private fun installLibsignal(filesDir: String) {
        // Install into both locations: global + openclaw's local node_modules (which shadows global)
        val targets = listOf(
            File("$filesDir/node/lib/node_modules/libsignal"),
            File("$filesDir/node/lib/node_modules/openclaw/node_modules/libsignal")
        )
        val libsignalDir = targets[0]
        // Check if the openclaw-local copy already has src/curve.js (the key file)
        if (File(targets[1], "src/curve.js").exists()) return

        try {
            // Copy tgz from APK assets
            val tgz = File("$filesDir/patches/libsignal.tgz")
            if (!tgz.exists()) {
                applicationContext.assets.open("flutter_assets/assets/patches/libsignal.tgz").use { i ->
                    File("$filesDir/patches").mkdirs()
                    tgz.outputStream().use { o -> i.copyTo(o) }
                }
            }
            // libsignal.tgz is self-contained (includes curve25519-js, protobufjs, long in node_modules/)
            // Extract to all target locations
            for (target in targets) {
                target.mkdirs()
                val pb = ProcessBuilder("/system/bin/tar", "-xzf", tgz.absolutePath,
                    "--strip-components=1", "-C", target.absolutePath)
                pb.redirectErrorStream(true)
                val proc = pb.start()
                proc.waitFor(30, java.util.concurrent.TimeUnit.SECONDS)
                if (File(target, "src/curve.js").exists()) {
                    Log.i("OpenclawGW", "libsignal installed at ${target.absolutePath}")
                } else {
                    Log.e("OpenclawGW", "libsignal extract failed at ${target.absolutePath}")
                }
            }
        } catch (e: Exception) {
            Log.e("OpenclawGW", "installLibsignal failed: ${e.message}")
        }
    }

    /**
     * Seed workspace TOOLS.md with Android environment context.
     * Only writes if the file doesn't exist yet (gateway's writeFileIfMissing will skip it).
     */
    /** Remove BOOTSTRAP.md — the app wizard replaces the CLI onboarding flow */
    private fun removeBootstrap(filesDir: String) {
        try {
            val wsDir = File("$filesDir/.openclaw/workspace")
            val bootstrap = File(wsDir, "BOOTSTRAP.md")
            if (bootstrap.exists()) {
                bootstrap.delete()
                Log.i("OpenclawGW", "Removed BOOTSTRAP.md (wizard handles onboarding)")
            }
        } catch (e: Exception) {
            Log.e("OpenclawGW", "removeBootstrap failed: ${e.message}")
        }
    }

    /** Check if a port is already in use by attempting to connect */
    private fun isPortInUse(port: Int): Boolean {
        return try {
            java.net.Socket("127.0.0.1", port).use { true }
        } catch (_: Exception) {
            false
        }
    }

    private fun seedWorkspaceTools(filesDir: String) {
        try {
            val wsDir = File("$filesDir/.openclaw/workspace")
            wsDir.mkdirs()

            val toolsFile = File(wsDir, "TOOLS.md")

            // Detect device info
            val model = android.os.Build.MODEL ?: "Unknown"
            val brand = android.os.Build.MANUFACTURER ?: "Unknown"
            val arch = System.getProperty("os.arch") ?: "aarch64"
            val tz = java.util.TimeZone.getDefault().id
            val ram = try {
                val mi = android.app.ActivityManager.MemoryInfo()
                val am = applicationContext.getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                am.getMemoryInfo(mi)
                "${mi.totalMem / (1024 * 1024)}MB"
            } catch (_: Exception) { "unknown" }

            // OpenClaw version
            val openclawVersion = try {
                val pkgJson = File("$filesDir/node/lib/node_modules/openclaw/package.json")
                if (pkgJson.exists()) {
                    val json = org.json.JSONObject(pkgJson.readText())
                    json.optString("version", "unknown")
                } else "not installed"
            } catch (_: Exception) { "unknown" }

            // Node version
            val nodeVersion = try {
                val versionFile = File("$filesDir/node/bin/node").parentFile?.parentFile?.let {
                    File(it, "include/node/node_version.h")
                }
                if (versionFile?.exists() == true) {
                    val text = versionFile.readText()
                    val major = Regex("#define NODE_MAJOR_VERSION (\\d+)").find(text)?.groupValues?.get(1) ?: "?"
                    val minor = Regex("#define NODE_MINOR_VERSION (\\d+)").find(text)?.groupValues?.get(1) ?: "?"
                    val patch = Regex("#define NODE_PATCH_VERSION (\\d+)").find(text)?.groupValues?.get(1) ?: "?"
                    "$major.$minor.$patch"
                } else "22.x"
            } catch (_: Exception) { "22.x" }

            // Installed optional packages
            val optionalTools = listOf("python3", "go", "git", "ffmpeg", "sqlite3", "curl", "make")
            val installedTools = mutableListOf<String>()
            val missingTools = mutableListOf<String>()
            for (tool in optionalTools) {
                val paths = listOf(
                    "$filesDir/python/bin/$tool",
                    "$filesDir/go/bin/$tool",
                    "$filesDir/git/git",
                    "$filesDir/bin/$tool",
                    "$filesDir/node/bin/$tool",
                    "/data/local/tmp/$tool"
                )
                if (paths.any { File(it).exists() }) {
                    installedTools.add(tool)
                } else {
                    missingTools.add(tool)
                }
            }
            // node and npm are always available after bootstrap
            installedTools.addAll(0, listOf("node", "npm"))

            // Agent config info
            val agentName = try {
                val configFile = File("$filesDir/.openclaw/openclaw.json")
                if (configFile.exists()) {
                    val config = org.json.JSONObject(configFile.readText())
                    val agents = config.optJSONObject("agents")
                    val list = agents?.optJSONArray("list")
                    if (list != null && list.length() > 0) {
                        list.getJSONObject(0).optString("name", "")
                    } else ""
                } else ""
            } catch (_: Exception) { "" }

            val providerInfo = try {
                val configFile = File("$filesDir/.openclaw/openclaw.json")
                if (configFile.exists()) {
                    val config = org.json.JSONObject(configFile.readText())
                    val models = config.optJSONObject("models")
                    val providers = models?.optJSONObject("providers")
                    providers?.keys()?.asSequence()?.firstOrNull() ?: ""
                } else ""
            } catch (_: Exception) { "" }

            val content = buildString {
                appendLine("# TOOLS.md — Device & Environment")
                appendLine()
                appendLine("## Device")
                appendLine("- **Phone:** $brand $model ($arch)")
                appendLine("- **RAM:** $ram")
                appendLine("- **OS:** Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})")
                appendLine("- **Timezone:** $tz")
                appendLine()
                appendLine("## Runtime")
                appendLine("- **OpenClaw:** v$openclawVersion")
                appendLine("- **Node.js:** v$nodeVersion")
                appendLine("- **Home:** $filesDir")
                appendLine("- **Gateway:** http://127.0.0.1:18789")
                appendLine()
                if (agentName.isNotEmpty()) {
                    appendLine("## Agent")
                    appendLine("- **Name:** $agentName")
                    if (providerInfo.isNotEmpty()) appendLine("- **Provider:** $providerInfo")
                    appendLine()
                }
                appendLine("## Available Tools")
                appendLine(installedTools.joinToString(", "))
                appendLine()
                if (missingTools.isNotEmpty()) {
                    appendLine("## Not Installed (available in Packages)")
                    appendLine(missingTools.joinToString(", "))
                    appendLine()
                }
                appendLine("## Not Available")
                appendLine("sudo, apt, brew, docker, systemctl, X11/display server")
                appendLine()
                appendLine("## Constraints")
                appendLine("- No root — binaries are self-contained in app sandbox")
                appendLine("- Gateway runs on loopback only (127.0.0.1:18789)")
                appendLine("- No GPU compute — LLM inference is remote only")
                appendLine("- exec runs commands via glibc ld.so → node")
            }

            // Always overwrite — we generate fresh device info every start
            toolsFile.writeText(content)
            Log.i("OpenclawGW", "seedWorkspaceTools: wrote TOOLS.md (${content.length} bytes)")
        } catch (e: Exception) {
            Log.e("OpenclawGW", "seedWorkspaceTools failed: ${e.message}")
        }
    }

    private fun seedAgentIdentity(filesDir: String) {
        try {
            // Read agent name from config
            val configFile = File("$filesDir/.openclaw/openclaw.json")
            if (!configFile.exists()) return
            val config = org.json.JSONObject(configFile.readText())
            val agents = config.optJSONObject("agents") ?: return
            val list = agents.optJSONArray("list") ?: return
            if (list.length() == 0) return
            val agentName = list.getJSONObject(0).optString("name", "").ifEmpty { return }

            val wsDir = File("$filesDir/.openclaw/workspace")
            wsDir.mkdirs()

            // Seed SOUL.md — only if missing or still the default template
            val soulFile = File(wsDir, "SOUL.md")
            val shouldWriteSoul = if (soulFile.exists()) {
                val content = soulFile.readText()
                // Overwrite if it doesn't mention our agent name
                // This catches: gateway default, OpenClaw template, empty, or generic
                !content.contains(agentName, ignoreCase = true) && (
                    content.contains("OpenClaw", ignoreCase = true) ||
                    content.contains("openclaw", ignoreCase = true) ||
                    content.contains("_Fill this in") ||
                    content.contains("figuring out who you are") ||
                    content.contains("not a chatbot") ||
                    content.length < 200
                )
            } else true

            if (shouldWriteSoul) {
                val model = android.os.Build.MODEL ?: "Unknown"
                val brand = android.os.Build.MANUFACTURER ?: "Unknown"
                val arch = System.getProperty("os.arch") ?: "aarch64"
                val ram = try {
                    val mi = android.app.ActivityManager.MemoryInfo()
                    val am = applicationContext.getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                    am.getMemoryInfo(mi)
                    "${mi.totalMem / (1024 * 1024)}MB"
                } catch (_: Exception) { "unknown" }

                soulFile.writeText("""# SOUL.md — Who I Am

I'm $agentName — a personal AI assistant running on your phone.

## Identity
- My name is **$agentName**
- I run on a **$brand $model** ($arch, ${ram} RAM, Android ${android.os.Build.VERSION.RELEASE})
- I'm helpful, direct, and concise

## Style
- Match the user's language (if they write in French, respond in French)
- Be conversational, not robotic
- Short answers for short questions, detailed when needed
- Use markdown formatting when it helps readability

## Device Environment
- Phone: $brand $model ($arch), ${ram} RAM, Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT})
- Available tools: node, npm, python3, pip, go, git, curl, make, busybox
- Optional packages (verify with 'which'): ffmpeg, sqlite3, yt-dlp
- NOT available: sudo, apt, brew, docker, systemctl
- Hardware: camera (front/back), GPS, accelerometer, gyroscope, vibration, notifications, clipboard
- Constraints: no root, loopback gateway only (127.0.0.1:18789), no GPU compute, Android file paths

## Boundaries
- I don't have internet access unless tools are configured
- I can't make calls or send messages on your behalf without explicit permission
- Private things stay private
""")
                Log.i("OpenclawGW", "Seeded SOUL.md for agent: $agentName")
            }

            // Seed IDENTITY.md
            val identityFile = File(wsDir, "IDENTITY.md")
            val shouldWriteIdentity = if (identityFile.exists()) {
                val content = identityFile.readText()
                content.contains("_Fill this in") || content.contains("pick something") ||
                    (!content.contains(agentName, ignoreCase = true) && content.length < 500)
            } else true

            if (shouldWriteIdentity) {
                identityFile.writeText("""# IDENTITY.md

- **Name:** $agentName
- **Creature:** AI assistant
- **Vibe:** helpful, direct, adaptable
- **Emoji:** 🤖
""")
                Log.i("OpenclawGW", "Seeded IDENTITY.md for agent: $agentName")
            }
        } catch (e: Exception) {
            Log.e("OpenclawGW", "seedAgentIdentity failed: ${e.message}")
        }
    }

    private fun patchOpenclawConfig(filesDir: String) {
        try {
            val configFile = File("$filesDir/.openclaw/openclaw.json")
            if (!configFile.exists()) {
                Log.i("OpenclawGW", "No config file to patch")
                return
            }
            val text = configFile.readText()
            val obj = org.json.JSONObject(text)

            // gateway.mode = local
            val gw = obj.optJSONObject("gateway") ?: org.json.JSONObject()
            if (!gw.has("mode")) gw.put("mode", "local")
            obj.put("gateway", gw)

            // Migrate legacy agent.* → agents.defaults.*
            if (obj.has("agent")) {
                val agentObj = obj.getJSONObject("agent")
                val agents = obj.optJSONObject("agents") ?: org.json.JSONObject()
                val defaults = agents.optJSONObject("defaults") ?: org.json.JSONObject()
                agentObj.keys().forEach { key -> if (!defaults.has(key)) defaults.put(key, agentObj.get(key)) }
                agents.put("defaults", defaults)
                obj.put("agents", agents)
                obj.remove("agent")
                Log.i("OpenclawGW", "Migrated agent.* → agents.defaults.*")
            }

            // Detect ZAI / GROQ providers
            val providers = obj.optJSONObject("models")?.optJSONObject("providers")
            val zaiKey = providers?.optJSONObject("zai")?.optString("apiKey", "")?.takeIf { it.isNotEmpty() }
            val groqKey = providers?.optJSONObject("groq")?.optString("apiKey", "")?.takeIf { it.isNotEmpty() }
            var zaiKeyResolved = zaiKey
            var groqKeyResolved = groqKey

            // If no API keys in current config, try to read from migrate backup on sdcard
            if (zaiKeyResolved == null && groqKeyResolved == null) {
                try {
                    val extStorage = android.os.Environment.getExternalStorageDirectory()
                    val migrateFile = File(extStorage, "openclaw-migrate.json")
                    if (migrateFile.exists()) {
                        val migrate = org.json.JSONObject(migrateFile.readText())
                        val migrateProviders = migrate.optJSONObject("models")?.optJSONObject("providers")
                        val mzai = migrateProviders?.optJSONObject("zai")?.optString("apiKey", "")?.takeIf { it.isNotEmpty() }
                        val mgroq = migrateProviders?.optJSONObject("groq")?.optString("apiKey", "")?.takeIf { it.isNotEmpty() }
                        val mEnvZai = migrate.optJSONObject("env")?.optString("ZAI_API_KEY", "")?.takeIf { it.isNotEmpty() }
                        val mEnvGroq = migrate.optJSONObject("env")?.optString("GROQ_API_KEY", "")?.takeIf { it.isNotEmpty() }
                        zaiKeyResolved = mzai ?: mEnvZai
                        groqKeyResolved = mgroq ?: mEnvGroq
                        if (zaiKeyResolved != null || groqKeyResolved != null) {
                            Log.i("OpenclawGW", "patchConfig: loaded keys from openclaw-migrate.json")
                            // Also merge providers into current config
                            if (!obj.has("models")) obj.put("models", org.json.JSONObject())
                            val models = obj.getJSONObject("models")
                            if (!models.has("providers")) models.put("providers", org.json.JSONObject())
                            val destProviders = models.getJSONObject("providers")
                            migrateProviders?.keys()?.forEach { k ->
                                if (!destProviders.has(k)) destProviders.put(k, migrateProviders.get(k))
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w("OpenclawGW", "patchConfig: migrate read failed: ${e.message}")
                }
            }

            Log.i("OpenclawGW", "patchConfig: zaiKey=${zaiKeyResolved?.take(8)} groqKey=${groqKeyResolved?.take(8)}")

            // Set agents.defaults.model if missing
            val agents = obj.optJSONObject("agents") ?: org.json.JSONObject()
            val defaults = agents.optJSONObject("defaults") ?: org.json.JSONObject()
            val existingModel = defaults.optString("model", "")
            Log.i("OpenclawGW", "patchConfig: existingModel='$existingModel'")
            if (existingModel.isEmpty()) {
                val model = when {
                    zaiKeyResolved != null -> "zai/glm-4.7"
                    groqKeyResolved != null -> "groq/llama-3.3-70b-versatile"
                    else -> null
                }
                if (model != null) {
                    defaults.put("model", model)
                    agents.put("defaults", defaults)
                    obj.put("agents", agents)
                    Log.i("OpenclawGW", "Set agents.defaults.model = $model")
                }
            } else {
                Log.i("OpenclawGW", "patchConfig: model already set, skipping")
            }

            configFile.writeText(obj.toString(2))

            // Write auth-profiles.json for main agent
            val agentDir = File("$filesDir/.openclaw/agents/main/agent")
            agentDir.mkdirs()
            val authFile = File(agentDir, "auth-profiles.json")
            val auth = if (authFile.exists()) org.json.JSONObject(authFile.readText()) else org.json.JSONObject()
            if (zaiKeyResolved != null && !auth.has("zai:default")) {
                auth.put("zai:default", org.json.JSONObject().apply {
                    put("provider", "zai"); put("mode", "api_key"); put("apiKey", zaiKeyResolved)
                })
                Log.i("OpenclawGW", "Wrote zai:default to auth-profiles.json")
            }
            if (groqKeyResolved != null && !auth.has("groq:default")) {
                auth.put("groq:default", org.json.JSONObject().apply {
                    put("provider", "groq"); put("mode", "api_key"); put("apiKey", groqKeyResolved)
                })
            }
            if (auth.length() > 0) authFile.writeText(auth.toString(2))

        } catch (e: Exception) {
            Log.e("OpenclawGW", "patchOpenclawConfig failed: ${e.message}")
        }
    }

    private fun stopGateway() {
        restartCount = maxRestarts // Prevent auto-restart
        uptimeThread?.interrupt()
        uptimeThread = null
        gatewayProcess?.let {
            it.destroyForcibly()
            gatewayProcess = null
        }
        emitLog("Gateway stopped by user")
    }

    private fun startUptimeTicker() {
        uptimeThread?.interrupt()
        uptimeThread = Thread {
            try {
                while (!Thread.interrupted() && isRunning) {
                    Thread.sleep(60_000) // Update every minute
                    if (isRunning) {
                        updateNotificationRunning()
                    }
                }
            } catch (_: InterruptedException) {}
        }.apply { isDaemon = true; start() }
    }

    private fun formatUptime(): String {
        val elapsed = System.currentTimeMillis() - startTime
        val seconds = elapsed / 1000
        val minutes = seconds / 60
        val hours = minutes / 60
        return when {
            hours > 0 -> "${hours}h ${minutes % 60}m"
            minutes > 0 -> "${minutes}m"
            else -> "${seconds}s"
        }
    }

    private fun updateNotificationRunning() {
        updateNotification("Running on port 18789 \u2022 ${formatUptime()}")
    }

    private fun emitLog(message: String) {
        try {
            logSink?.success(message)
        } catch (_: Exception) {}
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "OpenClaw::GatewayWakeLock"
        )
        wakeLock?.acquire(24 * 60 * 60 * 1000L) // 24 hours max
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Foreground service channel (silent)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "OpenClaw Gateway",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the OpenClaw gateway running in the background"
            }
            manager.createNotificationChannel(channel)

            // Alert channel (for crashes, errors — shows heads-up)
            val alertChannel = NotificationChannel(
                ALERT_CHANNEL_ID,
                "Gateway Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Crash notifications and important gateway events"
                enableVibration(true)
            }
            manager.createNotificationChannel(alertChannel)

            // Chat messages channel
            val chatChannel = NotificationChannel(
                CHAT_CHANNEL_ID,
                "Chat Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications when the agent responds"
                enableVibration(true)
            }
            manager.createNotificationChannel(chatChannel)
        }
    }

    private fun sendCrashNotification(message: String) {
        try {
            val intent = Intent(this, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                this, 1, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, ALERT_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            builder.setContentTitle("⚠️ Gateway Crashed")
                .setContentText(message)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)

            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(CRASH_NOTIFICATION_ID, builder.build())
        } catch (_: Exception) {}
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setContentTitle("OpenClaw Gateway")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)

        // Show elapsed time chronometer when running
        if (isRunning && startTime > 0) {
            builder.setWhen(startTime)
            builder.setShowWhen(true)
            builder.setUsesChronometer(true)
        }

        return builder.build()
    }

    private fun updateNotification(text: String) {
        try {
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification(text))
        } catch (_: Exception) {}
    }
}
