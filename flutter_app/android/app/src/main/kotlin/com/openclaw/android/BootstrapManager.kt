package com.openclaw.android

import android.content.Context
import android.system.Os
import org.apache.commons.compress.archivers.ar.ArArchiveInputStream
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class BootstrapManager(
    private val context: Context,
    private val filesDir: String,
    private val nativeLibDir: String
) {
    private val glibcDir  get() = "$filesDir/glibc"
    private val nodeDir   get() = "$filesDir/node"
    private val pythonDir get() = "$filesDir/python"
    private val goDir     get() = "$filesDir/go"
    private val tmpDir    get() = "$filesDir/tmp"
    private val patchDir  get() = "$filesDir/patches"

    fun setupDirectories() {
        listOf(glibcDir, nodeDir, pythonDir, goDir, tmpDir, patchDir,
               "$filesDir/.openclaw", "$tmpDir/npm-cache",
               "$filesDir/gopath", "$tmpDir/go-cache").forEach {
            File(it).mkdirs()
        }
    }

    fun isBootstrapComplete(): Boolean {
        val ldSo = File("$nativeLibDir/libopenclaw-ld.so")
        return File("$filesDir/.bootstrap-done").exists()
            && ldSo.exists()
            && File("$nodeDir/bin/node").exists()
            && File("$nodeDir/bin/openclaw").exists()
    }

    fun isPythonInstalled(): Boolean = File("$filesDir/.python-done").exists()
        && File("$pythonDir/bin/python3").exists()

    fun isGoInstalled(): Boolean = File("$filesDir/.go-done").exists()
        && File("$goDir/bin/go").exists()

    fun getBootstrapStatus(): Map<String, Any> {
        return mapOf(
            "ldSoExists"      to File("$glibcDir/lib/ld-linux-aarch64.so.1").exists(),
            "nodeExists"      to File("$nodeDir/bin/node").exists(),
            "openclawExists"  to File("$nodeDir/bin/openclaw").exists(),
            "patchExists"     to File("$patchDir/glibc-compat.js").exists(),
            "complete"        to isBootstrapComplete()
        )
    }

    /** Ensure a file's parent directory exists as a real directory.
     *  Walks ALL ancestors from glibcDir down to the immediate parent.
     *  Removes any symlink or file that blocks directory creation.
     */
    private fun ensureParentDir(file: File) {
        val parent = file.parentFile ?: return
        if (parent.isDirectory) return // fast path

        val glibcPath = File(glibcDir).absolutePath
        val parentPath = parent.absolutePath
        if (!parentPath.startsWith(glibcPath)) { parent.mkdirs(); return }

        val relPath = parentPath.removePrefix(glibcPath).trimStart('/')
        if (relPath.isEmpty()) return

        var current = File(glibcDir)
        for (segment in relPath.split("/").filter { it.isNotEmpty() }) {
            current = File(current, segment)
            if (current.isDirectory) continue
            // Exists as non-directory (file or broken symlink) — remove and mkdir
            if (current.exists() || java.nio.file.Files.isSymbolicLink(current.toPath())) {
                current.delete()
            }
            current.mkdir()
        }
    }

    /** Extract glibc deb into filesDir/glibc/ using two-phase extraction.
     *  Phase 1: directories + regular files. Phase 2: symlinks.
     *  Strip 7 path components: ./data/data/com.termux/files/usr/glibc/ -> ""
     */
    fun extractGlibcDeb(debPath: String) {
        val destDir = File(glibcDir)
        destDir.mkdirs()
        // Deferred symlinks: Pair(linkTarget, absoluteDestPath)
        val deferredSymlinks = mutableListOf<Pair<String, String>>()

        FileInputStream(debPath).use { fis ->
            BufferedInputStream(fis).use { bis ->
                ArArchiveInputStream(bis).use { arIn ->
                    var arEntry = arIn.nextEntry
                    while (arEntry != null) {
                        if (arEntry.name.startsWith("data.tar")) {
                            val dataStream = XZCompressorInputStream(arIn)
                            TarArchiveInputStream(dataStream).use { tarIn ->
                                var entry: TarArchiveEntry? = tarIn.nextEntry
                                while (entry != null) {
                                    val stripped = stripComponents(entry.name, 6)
                                    if (stripped.isNotEmpty()) {
                                        val outFile = File(destDir, stripped)
                                        when {
                                            entry.isDirectory -> outFile.mkdirs()
                                            entry.isSymbolicLink -> {
                                                // Defer — process after all files/dirs
                                                deferredSymlinks.add(Pair(entry.linkName, outFile.absolutePath))
                                            }
                                            else -> {
                                                ensureParentDir(outFile)
                                                FileOutputStream(outFile).use { fos ->
                                                    val buf = ByteArray(65536)
                                                    var len: Int
                                                    while (tarIn.read(buf).also { len = it } != -1) {
                                                        fos.write(buf, 0, len)
                                                    }
                                                }
                                                outFile.setReadable(true, false)
                                                if (entry.mode and 0b001_001_001 != 0 || stripped.contains(".so"))
                                                    outFile.setExecutable(true, false)
                                            }
                                        }
                                    }
                                    entry = tarIn.nextEntry
                                }
                            }
                            // Phase 2: create symlinks now that all dirs/files exist
                            for ((linkTarget, path) in deferredSymlinks) {
                                try {
                                    val f = File(path)
                                    if (f.exists() || java.nio.file.Files.isSymbolicLink(f.toPath())) f.delete()
                                    f.parentFile?.mkdirs()
                                    Os.symlink(linkTarget, path)
                                } catch (_: Exception) {}
                            }
                            return
                        }
                        arEntry = arIn.nextEntry
                    }
                }
            }
        }
        val ldSo = File("$glibcDir/lib/ld-linux-aarch64.so.1")
        if (!ldSo.exists()) throw RuntimeException("glibc extraction failed: ld-linux-aarch64.so.1 not found")
    }

    /** Extract Node.js tar.xz into filesDir/node/ (strip top-level dir) */
    fun extractNodeTarball(tarPath: String) {
        val destDir = File(nodeDir)
        destDir.mkdirs()

        FileInputStream(tarPath).use { fis ->
            BufferedInputStream(fis, 256 * 1024).use { bis ->
                XZCompressorInputStream(bis).use { xzis ->
                    TarArchiveInputStream(xzis).use { tis ->
                        var entry: TarArchiveEntry? = tis.nextEntry
                        while (entry != null) {
                            val name = entry.name
                            val slashIdx = name.indexOf('/')
                            if (slashIdx < 0 || slashIdx == name.length - 1) {
                                entry = tis.nextEntry; continue
                            }
                            val relPath = name.substring(slashIdx + 1)
                            if (relPath.isEmpty()) { entry = tis.nextEntry; continue }
                            val outFile = File(destDir, relPath)
                            when {
                                entry.isDirectory -> outFile.mkdirs()
                                entry.isSymbolicLink -> {
                                    try {
                                        if (outFile.exists()) outFile.delete()
                                        outFile.parentFile?.mkdirs()
                                        Os.symlink(entry.linkName, outFile.absolutePath)
                                    } catch (_: Exception) {}
                                }
                                else -> {
                                    outFile.parentFile?.mkdirs()
                                    FileOutputStream(outFile).use { fos ->
                                        val buf = ByteArray(65536)
                                        var len: Int
                                        while (tis.read(buf).also { len = it } != -1) {
                                            fos.write(buf, 0, len)
                                        }
                                    }
                                    outFile.setReadable(true, false)
                                    if (entry.mode and 0b001_001_001 != 0 || relPath.startsWith("bin/") || relPath.contains(".so"))
                                        outFile.setExecutable(true, false)
                                }
                            }
                            entry = tis.nextEntry
                        }
                    }
                }
            }
        }
        val node = File("$nodeDir/bin/node")
        if (!node.exists()) throw RuntimeException("Node extraction failed: node binary not found")
        node.setExecutable(true, false)
        File(tarPath).delete()
    }

    /**
     * Patch @npmcli/git/lib/which.js (bundled in npm's node_modules) to use
     * /system/bin/true as a git stub when git is not installed.
     * /system/bin/true accepts any arguments, exits 0, and produces no output.
     * This means:
     *  - git rev-parse --git-dir → exits 0, empty stdout → npm thinks "not a git repo"
     *  - git clone ... → exits 0, nothing created → fine since openclaw has no git deps
     */
    /**
     * Write a package.json into filesDir so npm picks up the overrides section.
     * npm reads the project package.json from CWD, so we set CWD=filesDir when
     * running npm install. The override replaces the git+https libsignal URL
     * with our pre-packed local tarball.
     */
    fun writeNpmOverrides() {
        val libsignalPath = "$patchDir/libsignal.tgz"
        val json = """{
  "name": "openclaw-bootstrap",
  "version": "1.0.0",
  "overrides": {
    "libsignal": "file:$libsignalPath"
  }
}"""
        File("$filesDir/package.json").writeText(json)
    }

    fun patchNpmGit() {
        val npmGitDir = File("$nodeDir/lib/node_modules/npm/node_modules/@npmcli/git/lib")
        if (!npmGitDir.exists()) throw RuntimeException("patchNpmGit: @npmcli/git not found at ${npmGitDir.absolutePath}")

        // Patch clone.js to create stub packages for git-URL deps (no git on Android)
        // libsignal and other git deps are native C++ — they won't run on Android anyway.
        File(npmGitDir, "clone.js").writeText("""
// Patched: no git on Android — create stub package.json for git-URL dependencies
const path = require('path')
const fs = require('fs/promises')

const defaultTarget = (repo, cwd = process.cwd()) =>
  path.resolve(cwd, path.basename(repo.replace(/[/\\\\]?\\.git${'$'}/, '')))

module.exports = async (repo, ref = 'HEAD', target = null, opts = {}) => {
  const t = target || defaultTarget(repo, opts.cwd)
  await fs.mkdir(t, { recursive: true })
  const pkgPath = path.join(t, 'package.json')
  let hasPackage = false
  try { await fs.access(pkgPath); hasPackage = true } catch {}
  if (!hasPackage) {
    // Extract a reasonable package name from the git URL
    const name = path.basename(repo.replace(/[/\\\\]?\\.git${'$'}/, '').replace(/.*[:/]/, ''))
    await fs.writeFile(pkgPath, JSON.stringify({
      name: name || 'git-stub',
      version: '0.0.0',
      description: 'stub: git dep unavailable on Android'
    }))
  }
  return '0000000000000000000000000000000000000000'
}
""".trimIndent())

        val whichJs = File(npmGitDir, "which.js")
        if (!whichJs.exists()) throw RuntimeException("patchNpmGit: which.js not found")

        whichJs.writeText("""
const which = require('which')

let gitPath
try {
  gitPath = which.sync('git')
} catch {
  // git not installed — use /system/bin/true as a harmless no-op stub.
  // 'true' accepts any arguments and exits 0 with empty stdout/stderr,
  // so npm treats the CWD as "not a git repo" and continues normally.
  gitPath = '/system/bin/true'
}

module.exports = (opts = {}) => {
  if (opts.git) {
    return opts.git
  }
  if (!gitPath || opts.git === false) {
    return Object.assign(new Error('No git binary found in ${'$'}PATH'), { code: 'ENOGIT' })
  }
  return gitPath
}
""".trimIndent())
    }

    fun copyGlibcCompat(ctx: Context) {
        File(patchDir).mkdirs()
        // Copy glibc-compat.js
        val dest = File(patchDir, "glibc-compat.js")
        if (!dest.exists()) {
            ctx.assets.open("flutter_assets/assets/patches/glibc-compat.js").use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
        }
        // Copy libsignal tarball (pre-packed JS-only version of git+https://github.com/whiskeysockets/libsignal-node)
        val libsignal = File(patchDir, "libsignal.tgz")
        if (!libsignal.exists()) {
            ctx.assets.open("flutter_assets/assets/patches/libsignal.tgz").use { input ->
                libsignal.outputStream().use { output -> input.copyTo(output) }
            }
        }
    }

    /** Generic tar.gz extraction. Strips `stripCount` leading path components.
     *  Extracts into `destDir`. Handles dirs, files, symlinks. */
    private fun extractTarGz(tarPath: String, destDir: File, stripCount: Int = 1) {
        destDir.mkdirs()
        val deferredSymlinks = mutableListOf<Pair<String, String>>()

        FileInputStream(tarPath).use { fis ->
            BufferedInputStream(fis, 256 * 1024).use { bis ->
                GzipCompressorInputStream(bis).use { gzis ->
                    TarArchiveInputStream(gzis).use { tis ->
                        var entry: TarArchiveEntry? = tis.nextEntry
                        while (entry != null) {
                            val parts = entry.name.split("/").filter { it.isNotEmpty() && it != "." }
                            if (parts.size <= stripCount) { entry = tis.nextEntry; continue }
                            val relPath = parts.drop(stripCount).joinToString("/")
                            val outFile = File(destDir, relPath)
                            when {
                                entry.isDirectory -> outFile.mkdirs()
                                entry.isSymbolicLink -> {
                                    deferredSymlinks.add(Pair(entry.linkName, outFile.absolutePath))
                                }
                                else -> {
                                    outFile.parentFile?.mkdirs()
                                    FileOutputStream(outFile).use { fos ->
                                        val buf = ByteArray(65536)
                                        var len: Int
                                        while (tis.read(buf).also { len = it } != -1) {
                                            fos.write(buf, 0, len)
                                        }
                                    }
                                    outFile.setReadable(true, false)
                                    if (entry.mode and 0b001_001_001 != 0
                                        || relPath.startsWith("bin/")
                                        || relPath.contains(".so"))
                                        outFile.setExecutable(true, false)
                                }
                            }
                            entry = tis.nextEntry
                        }
                    }
                }
            }
        }
        for ((linkTarget, path) in deferredSymlinks) {
            try {
                val f = File(path)
                if (f.exists() || java.nio.file.Files.isSymbolicLink(f.toPath())) f.delete()
                f.parentFile?.mkdirs()
                Os.symlink(linkTarget, path)
            } catch (_: Exception) {}
        }
    }

    /** Extract Python standalone tarball into filesDir/python/ */
    fun extractPythonTarball(tarPath: String) {
        val destDir = File(pythonDir)
        if (destDir.exists()) destDir.deleteRecursively()
        extractTarGz(tarPath, destDir, stripCount = 1)
        // Ensure python3 symlink exists
        val python3 = File("$pythonDir/bin/python3")
        if (!python3.exists()) {
            // Find the versioned binary e.g. python3.13
            val versioned = File("$pythonDir/bin").listFiles()
                ?.firstOrNull { it.name.matches(Regex("python3\\.\\d+")) }
            if (versioned != null) {
                try { Os.symlink(versioned.name, python3.absolutePath) } catch (_: Exception) {}
            }
        }
        File(tarPath).delete()
        File("$filesDir/.python-done").writeText("ok")
        android.util.Log.i("OpenclawGW", "Python installed: $pythonDir")
    }

    /** Extract Go tarball into filesDir/go/ */
    fun extractGoTarball(tarPath: String) {
        val destDir = File(goDir)
        if (destDir.exists()) destDir.deleteRecursively()
        extractTarGz(tarPath, destDir, stripCount = 1)
        File(tarPath).delete()
        File("$filesDir/.go-done").writeText("ok")
        android.util.Log.i("OpenclawGW", "Go installed: $goDir")
    }

    fun extractGitBundle(tarPath: String) {
        val destDir = File("$filesDir/git")
        if (destDir.exists()) destDir.deleteRecursively()
        // git-aarch64-musl.tar.gz contains git/ at root
        extractTarGz(tarPath, File(filesDir), stripCount = 0)
        // Make binaries executable
        File("$destDir/git").setExecutable(true, false)
        File("$destDir/git-remote-http").setExecutable(true, false)
        File("$destDir/git-remote-https").setExecutable(true, false)
        File("$destDir/lib/ld-musl-aarch64.so.1").setExecutable(true, false)
        // Create wrapper script in bin/ that sets LD_LIBRARY_PATH
        val binDir = File("$filesDir/bin")
        binDir.mkdirs()
        val wrapper = File("$binDir/git")
        wrapper.writeText("""#!/bin/sh
export GIT_EXEC_PATH="$filesDir/git"
export SSL_CERT_FILE="$filesDir/git/ssl/cert.pem"
exec "$filesDir/git/lib/ld-musl-aarch64.so.1" --library-path "$filesDir/git/lib" "$filesDir/git/git" "${'$'}@"
""")
        wrapper.setExecutable(true, false)
        File(tarPath).delete()
        File("$filesDir/.git-done").writeText("ok")
        android.util.Log.i("OpenclawGW", "Git installed: $destDir")
    }

    fun markBootstrapDone() {
        File("$filesDir/.bootstrap-done").writeText("ok")
    }

    // ── Optional package installers ──────────────────────────────

    /** Install a static binary into filesDir/bin/ and optionally create busybox applet symlinks */
    fun installStaticBinary(binaryPath: String, destRelPath: String, installApplets: Boolean = false) {
        val binDir = File("$filesDir/bin")
        binDir.mkdirs()
        val dest = File("$filesDir/$destRelPath")
        dest.parentFile?.mkdirs()
        File(binaryPath).copyTo(dest, overwrite = true)
        dest.setExecutable(true, false)
        dest.setReadable(true, false)

        if (installApplets) {
            // Run busybox --list to get applet names, create symlinks
            try {
                val pb = ProcessBuilder(listOf(dest.absolutePath, "--list"))
                pb.redirectErrorStream(true)
                val proc = pb.start()
                val applets = proc.inputStream.bufferedReader().readText().trim().split("\n")
                proc.waitFor(10, java.util.concurrent.TimeUnit.SECONDS)
                for (applet in applets) {
                    val name = applet.trim()
                    if (name.isEmpty()) continue
                    val link = File(binDir, name)
                    if (link.exists() || java.nio.file.Files.isSymbolicLink(link.toPath())) continue
                    try { android.system.Os.symlink(dest.absolutePath, link.absolutePath) }
                    catch (_: Exception) {}
                }
                android.util.Log.i("OpenclawGW", "Busybox installed: ${applets.size} applets")
            } catch (e: Exception) {
                android.util.Log.w("OpenclawGW", "Busybox applet install failed: ${e.message}")
            }
        }

        android.util.Log.i("OpenclawGW", "Static binary installed: $destRelPath")
    }

    /** Extract a Termux glibc .deb into the glibc dir (reuses extractGlibcDeb logic) */
    fun installTermuxDeb(debPath: String) {
        extractGlibcDeb(debPath)
        File(debPath).delete()
        android.util.Log.i("OpenclawGW", "Termux deb installed: $debPath")
    }

    /** Write a done-marker for an optional package */
    fun markPackageDone(markerId: String) {
        File("$filesDir/$markerId").writeText("ok")
    }

    /** Check if an optional package is installed */
    fun isPackageInstalled(checkPath: String, doneMarker: String): Boolean {
        return File("$filesDir/$doneMarker").exists()
            && File("$filesDir/$checkPath").exists()
    }

    /**
     * Patch glibc's libc.so.6 to replace hardcoded Termux config paths with ours.
     * glibc was compiled with --prefix=/data/data/com.termux/files/usr/glibc so
     * it looks for resolv.conf and nsswitch.conf at that Termux path, which we
     * cannot write to (different app UID). We binary-patch the strings in place.
     * Replacement paths must be SHORTER than original to fit in the same bytes.
     */
    fun patchGlibcPaths() {
        val libcFile = File("$glibcDir/lib/libc.so.6")
        if (!libcFile.exists()) return

        val patches = mapOf(
            // resolv.conf: 53 chars → 49 chars (fits with 4 null bytes padding)
            "/data/data/com.termux/files/usr/glibc/etc/resolv.conf"
                to "$filesDir/resolv.conf",
            // nsswitch.conf: 55 chars → 51 chars (fits with 4 null bytes padding)
            "/data/data/com.termux/files/usr/glibc/etc/nsswitch.conf"
                to "$filesDir/nsswitch.conf",
        )

        var bytes = libcFile.readBytes()
        for ((oldPath, newPath) in patches) {
            if (newPath.length >= oldPath.length) continue // safety check
            val oldBytes = oldPath.toByteArray(Charsets.ISO_8859_1) + byteArrayOf(0)
            val newBytes = newPath.toByteArray(Charsets.ISO_8859_1) + byteArrayOf(0)
            var idx = 0
            while (idx <= bytes.size - oldBytes.size) {
                if (bytes.sliceArray(idx until idx + oldBytes.size).contentEquals(oldBytes)) {
                    for (i in newBytes.indices) bytes[idx + i] = newBytes[i]
                    for (i in newBytes.size until oldBytes.size) bytes[idx + i] = 0
                }
                idx++
            }
        }
        libcFile.writeBytes(bytes)
    }

    /** Write glibc etc/ config files at the patched paths. */
    fun setupGlibcEtc() {
        // resolv.conf — point to Google DNS
        File("$filesDir/resolv.conf").writeText(
            "nameserver 8.8.8.8\nnameserver 8.8.4.4\n"
        )
        // nsswitch.conf — DNS first, then files
        File("$filesDir/nsswitch.conf").writeText(
            "hosts: dns files\npasswd: files\ngroup: files\nshadow: files\n"
        )
    }

    private fun stripComponents(path: String, n: Int): String {
        val parts = path.split("/").filter { it.isNotEmpty() && it != "." }
        if (parts.size <= n) return ""
        return parts.drop(n).joinToString("/")
    }
}
