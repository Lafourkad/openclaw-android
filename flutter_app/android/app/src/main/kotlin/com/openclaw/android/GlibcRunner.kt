package com.openclaw.android

import java.io.File
import java.util.concurrent.TimeUnit

class GlibcRunner(
    private val filesDir: String,
    private val nativeLibDir: String,
    private val glibcCompatPath: String = "$filesDir/patches/glibc-compat.js"
) {
    val glibcDir  = "$filesDir/glibc"
    val nodeDir   = "$filesDir/node"
    val pythonDir = "$filesDir/python"
    val goDir     = "$filesDir/go"
    // ld.so bundled in APK → extracted to nativeLibDir (executable even on GrapheneOS)
    val ldSo     = "$nativeLibDir/libopenclaw-ld.so"
    val nodeBin  = "$nodeDir/bin/node"

    /**
     * Write executable wrapper scripts into filesDir/bin/.
     * These wrappers use ld.so to bypass noexec on filesDir and allow any subprocess
     * or shell to invoke node, npm, openclaw etc. via execve.
     * Note: /data/local/tmp/ is EACCES on Android 16 (Pixel 9a), so we use filesDir/bin/.
     * The wrappers themselves are shell scripts interpreted by /system/bin/sh (always executable).
     */
    val binDir    = "$filesDir/bin"

    fun installWrappers() {
        val wrapperDir = binDir
        File(wrapperDir).mkdirs()
        val wrapperContent = mapOf(
            "node" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib" "$nodeBin" "$@"
""",
            "npm" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib" "$nodeBin" "$nodeDir/lib/node_modules/npm/bin/npm-cli.js" "$@"
""",
            "openclaw" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib" "$nodeBin" "$nodeDir/bin/openclaw" "$@"
""",
            "python3" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib:$pythonDir/lib" "$pythonDir/bin/python3" "$@"
""",
            "python" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib:$pythonDir/lib" "$pythonDir/bin/python3" "$@"
""",
            "pip3" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib:$pythonDir/lib" "$pythonDir/bin/python3" -m pip "$@"
""",
            "pip" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib:$pythonDir/lib" "$pythonDir/bin/python3" -m pip "$@"
""",
            "go" to """#!/system/bin/sh
export GOROOT="$goDir"
export GOPATH="$filesDir/gopath"
export GOCACHE="$filesDir/tmp/go-cache"
exec "$ldSo" --library-path "$glibcDir/lib" "$goDir/bin/go" "$@"
""",
            "gofmt" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib" "$goDir/bin/gofmt" "$@"
""",
            "git" to """#!/system/bin/sh
export GIT_EXEC_PATH="$filesDir/git"
export SSL_CERT_FILE="$filesDir/git/ssl/cert.pem"
exec "$filesDir/git/lib/ld-musl-aarch64.so.1" --library-path "$filesDir/git/lib" "$filesDir/git/git" "$@"
""",
            "make" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib" "$glibcDir/bin/make" "$@"
""",
            "curl" to """#!/system/bin/sh
exec "$ldSo" --library-path "$glibcDir/lib" "$glibcDir/bin/curl" "$@"
""",
            "busybox" to """#!/system/bin/sh
exec "$binDir/busybox" "$@"
"""
        )
        for ((name, content) in wrapperContent) {
            try {
                val f = File("$wrapperDir/$name")
                f.writeText(content)
                Runtime.getRuntime().exec(arrayOf("/system/bin/chmod", "755", f.absolutePath)).waitFor()
                android.util.Log.i("OpenclawGW", "wrapper installed: $wrapperDir/$name")
            } catch (e: Exception) {
                android.util.Log.w("OpenclawGW", "wrapper install failed for $name: ${e.message}")
            }
        }
    }

    /** Full runtime env — includes NODE_OPTIONS with glibc-compat shim.
     *  NOTE: LD_LIBRARY_PATH is intentionally ABSENT here.
     *  Node.js is launched via glibc's ld.so with --library-path, so it doesn't need
     *  LD_LIBRARY_PATH. Setting it would break ALL child processes (Android bionic
     *  binaries like /bin/sh) because the linker would find glibc's libc.so instead
     *  of Android's bionic libc.
     *  The wrapper scripts in binDir already use ld.so --library-path for glibc binaries.
     */
    fun buildEnv(): Map<String, String> = mapOf(
        "HOME"                to filesDir,
        "TMPDIR"              to "$filesDir/tmp",
        "NODE_OPTIONS"        to "--require $glibcCompatPath",
        "npm_config_prefix"   to nodeDir,
        "npm_config_cache"    to "$filesDir/tmp/npm-cache",
        "UV_USE_IO_URING"     to "0",
        "CHOKIDAR_USEPOLLING" to "true",
        "MALLOC_ARENA_MAX"    to "1",
        "GOROOT"              to goDir,
        "GOPATH"              to "$filesDir/gopath",
        "GOCACHE"             to "$filesDir/tmp/go-cache",
        "PATH"                to "$binDir:$nodeDir/bin:$pythonDir/bin:$goDir/bin:$glibcDir/bin:$filesDir/gopath/bin:/system/bin",
    )

    /** Bootstrap env — no NODE_OPTIONS, glibc-compat.js not yet in place */
    fun buildBootstrapEnv(): Map<String, String> = mapOf(
        "HOME"                    to filesDir,
        "TMPDIR"                  to "$filesDir/tmp",
        "npm_config_prefix"       to nodeDir,
        "npm_config_cache"        to "$filesDir/tmp/npm-cache",

        // /system/bin/true accepts any args and exits 0 — acts as a no-op git stub.
        "npm_config_git"          to "/system/bin/true",
        "UV_USE_IO_URING"         to "0",
        "CHOKIDAR_USEPOLLING"     to "true",

        // Limit glibc malloc to 1 arena — prevents heap corruption on GrapheneOS/stock Android
        // ("corrupted size vs. prev_size" is caused by concurrent multi-arena malloc)
        "MALLOC_ARENA_MAX"        to "1",
        "MALLOC_MMAP_THRESHOLD_"  to "131072",  // 128KB — more aggressive mmap, less sbrk
        // Cap Node.js heap and reduce thread pool during bootstrap
        "NODE_OPTIONS"            to "--max-old-space-size=512",
        "UV_THREADPOOL_SIZE"      to "2",       // fewer worker threads = fewer concurrent mallocs
        // Limit npm network concurrency
        "npm_config_maxsockets"   to "4",
        "npm_config_network_concurrency" to "4",

        "PATH"                    to "$nodeDir/bin:/system/bin",
    )

    fun nodeProcessBuilder(args: List<String>, bootstrap: Boolean = false): ProcessBuilder {
        val cmd = listOf(ldSo, "--library-path", "$glibcDir/lib", nodeBin) + args
        val pb = ProcessBuilder(cmd)
        pb.environment().clear()
        pb.environment().putAll(if (bootstrap) buildBootstrapEnv() else buildEnv())
        // Use filesDir as CWD so npm reads our package.json with overrides
        if (bootstrap) pb.directory(java.io.File(filesDir))
        return pb
    }

    fun runNodeSync(args: List<String>, timeout: Long = 900, bootstrap: Boolean = false): String {
        val pb = nodeProcessBuilder(args, bootstrap)
        pb.redirectErrorStream(true)
        val process = pb.start()
        val output = process.inputStream.bufferedReader().readText()
        val exited = process.waitFor(timeout, TimeUnit.SECONDS)
        if (!exited) { process.destroyForcibly(); throw RuntimeException("Timeout after ${timeout}s") }
        val code = process.exitValue()
        if (code != 0) throw RuntimeException("Exit $code: ${output.takeLast(2000)}")
        return output
    }

    /**
     * Kill any orphaned gateway processes left over from a previous app install/crash.
     * Uses `openclaw gateway stop` which handles pid-file cleanup.
     * Falls back to killing node processes listening on port 18789.
     */
    fun killOrphanedGateway() {
        // Method 1: openclaw gateway stop (uses pid file)
        try {
            val openclawBin = "$nodeDir/bin/openclaw"
            val stopPb = nodeProcessBuilder(listOf(openclawBin, "gateway", "stop"))
            stopPb.redirectErrorStream(true)
            val stopProc = stopPb.start()
            stopProc.waitFor(10, TimeUnit.SECONDS)
            if (stopProc.isAlive) stopProc.destroyForcibly()
        } catch (_: Exception) {}

        // Method 2: kill all node processes (brute force but reliable)
        try {
            val pkillPb = ProcessBuilder(listOf("/system/bin/sh", "-c",
                "pkill -f 'node.*openclaw' 2>/dev/null; pkill -f 'node.*gateway' 2>/dev/null; true"))
            pkillPb.redirectErrorStream(true)
            val pkillProc = pkillPb.start()
            pkillProc.waitFor(5, TimeUnit.SECONDS)
            if (pkillProc.isAlive) pkillProc.destroyForcibly()
        } catch (_: Exception) {}

        // Give the old process a moment to die
        try { Thread.sleep(2000) } catch (_: InterruptedException) {}
    }

    fun startGatewayProcess(): Process {
        // Kill any orphaned gateway from previous install/crash
        killOrphanedGateway()

        val openclawBin = "$nodeDir/bin/openclaw"
        val pb = nodeProcessBuilder(listOf(
            openclawBin, "gateway", "run",
            "--verbose",
            "--allow-unconfigured",
            "--bind", "loopback" // loopback only — auth handled by config token
        ))
        pb.redirectErrorStream(false)
        return pb.start()
    }

    fun isReady() = File(ldSo).exists() && File(nodeBin).exists()
}
