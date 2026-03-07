package com.openclaw.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.util.Log
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.app.Activity
import android.content.Context
import android.os.Environment
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.projection.MediaProjectionManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.openclaw.android/native"
    private val EVENT_CHANNEL = "com.openclaw.android/gateway_logs"

    private lateinit var bootstrapManager: BootstrapManager
    private var screenCaptureResult: MethodChannel.Result? = null
    private var screenCaptureDurationMs: Long = 5000L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val filesDir = applicationContext.filesDir.absolutePath
        val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir

        bootstrapManager = BootstrapManager(applicationContext, filesDir, nativeLibDir)

        // Ensure directories exist on every app start.
        Thread {
            try {
                bootstrapManager.setupDirectories()
                // Always ensure glibc-compat.js is present (needed by gateway at runtime)
                bootstrapManager.copyGlibcCompat(applicationContext)
                // Seed workspace with TOOLS.md, USER.md if not already present
                bootstrapManager.seedWorkspace(applicationContext)
            } catch (_: Exception) {}
        }.start()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getArch" -> {
                    result.success(ArchUtils.getArch())
                }
                "getFilesDir" -> {
                    result.success(filesDir)
                }
                "copyNpmLogToExternal" -> {
                    Thread {
                        try {
                            val logsDir = java.io.File("$filesDir/tmp/npm-cache/_logs")
                            val logs = logsDir.listFiles()?.sortedBy { it.name } ?: emptyList()
                            if (logs.isNotEmpty()) {
                                val src = logs.last()
                                val extDir = applicationContext.getExternalFilesDir(null)
                                extDir?.mkdirs()
                                val dst = java.io.File(extDir, "npm-debug-last.log")
                                src.copyTo(dst, overwrite = true)
                                runOnUiThread { result.success(dst.absolutePath) }
                            } else {
                                runOnUiThread { result.success(null) }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("LOG_COPY_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "getNativeLibDir" -> {
                    result.success(nativeLibDir)
                }
                "isBootstrapComplete" -> {
                    result.success(bootstrapManager.isBootstrapComplete())
                }
                "importMigrateConfig" -> {
                    // Copy /sdcard/openclaw-migrate.json → filesDir/.openclaw/openclaw.json
                    Thread {
                        try {
                            val sdcard = android.os.Environment.getExternalStorageDirectory()
                            val migrateFile = java.io.File(sdcard, "openclaw-migrate.json")
                            if (!migrateFile.exists()) {
                                runOnUiThread { result.error("NOT_FOUND", "openclaw-migrate.json not found on sdcard", null) }
                                return@Thread
                            }
                            val configDir = java.io.File("$filesDir/.openclaw")
                            configDir.mkdirs()
                            migrateFile.copyTo(java.io.File(configDir, "openclaw.json"), overwrite = true)
                            runOnUiThread { result.success("ok") }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("IMPORT_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "readGatewayToken" -> {
                    // Read the gateway auth token from openclaw.json config file
                    Thread {
                        try {
                            val configFile = java.io.File("$filesDir/.openclaw/openclaw.json")
                            if (configFile.exists()) {
                                val json = configFile.readText()
                                // Extract auth.token value with simple regex (no JSON lib needed)
                                val match = Regex(""""token"\s*:\s*"([^"]+)"""").find(json)
                                runOnUiThread { result.success(match?.groupValues?.get(1) ?: "") }
                            } else {
                                runOnUiThread { result.success("") }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.success("") }
                        }
                    }.start()
                }
                "debugConfigKeys" -> {
                    Thread {
                        try {
                            val f = java.io.File("$filesDir/.openclaw/openclaw.json")
                            if (f.exists()) {
                                val j = org.json.JSONObject(f.readText())
                                // Dump top-level keys and auth sub-keys
                                val keys = j.keys().asSequence().toList()
                                val authKeys = j.optJSONObject("auth")?.keys()?.asSequence()?.toList() ?: emptyList()
                                val gwKeys = j.optJSONObject("gateway")?.keys()?.asSequence()?.toList() ?: emptyList()
                                val cuiKeys = j.optJSONObject("gateway")?.optJSONObject("controlUi")?.keys()?.asSequence()?.toList() ?: emptyList()
                                Log.i("OpenclawGW", "CONFIG_KEYS top=${keys} auth=${authKeys} gw=${gwKeys} cui=${cuiKeys}")
                                // Also dump full raw content for inspection
                                val raw = f.readText().take(2000)
                                Log.i("OpenclawGW", "CONFIG_RAW: $raw")
                                runOnUiThread { result.success("keys=$keys auth=$authKeys") }
                            } else {
                                Log.i("OpenclawGW", "CONFIG_KEYS: file not found")
                                runOnUiThread { result.success("file not found") }
                            }
                        } catch (e: Exception) {
                            Log.e("OpenclawGW", "CONFIG_KEYS error: ${e.message}")
                            runOnUiThread { result.success("error: ${e.message}") }
                        }
                    }.start()
                }
                "readDashboardUrl" -> {
                    // Find dashboard URL with token from gateway log files
                    Thread {
                        try {
                            val tokenRegex = Regex("""https?://(?:localhost|127\.0\.0\.1):18789/#token=[0-9a-f]+""")
                            var foundUrl: String? = null

                            // Search in gateway log files (tmp dir)
                            val tmpDir = java.io.File("$filesDir/tmp")
                            tmpDir.walkTopDown()
                                .filter { it.name.endsWith(".log") }
                                .sortedByDescending { it.lastModified() }
                                .take(3)
                                .forEach { logFile ->
                                    if (foundUrl != null) return@forEach
                                    logFile.useLines { lines ->
                                        lines.forEach { line ->
                                            val m = tokenRegex.find(line)
                                            if (m != null) foundUrl = m.value
                                        }
                                    }
                                }

                            // Fallback: use gateway auth token to build URL
                            if (foundUrl == null) {
                                val configFile = java.io.File("$filesDir/.openclaw/openclaw.json")
                                if (configFile.exists()) {
                                    val json = org.json.JSONObject(configFile.readText())
                                    val authToken = json.optJSONObject("auth")
                                        ?.optString("token", "")
                                        ?.takeIf { it.isNotEmpty() }
                                    if (authToken != null) {
                                        foundUrl = "http://localhost:18789/#token=$authToken"
                                    }
                                }
                            }

                            runOnUiThread { result.success(foundUrl ?: "http://localhost:18789") }
                        } catch (e: Exception) {
                            runOnUiThread { result.success("http://localhost:18789") }
                        }
                    }.start()
                }
                "getBootstrapStatus" -> {
                    result.success(bootstrapManager.getBootstrapStatus())
                }
                "setupDirs" -> {
                    Thread {
                        try {
                            bootstrapManager.setupDirectories()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SETUP_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "extractGlibcDeb" -> {
                    val tarPath = call.argument<String>("tarPath")
                    if (tarPath != null) {
                        Thread {
                            try {
                                bootstrapManager.extractGlibcDeb(tarPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("GLIBC_EXTRACT_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "tarPath required", null)
                    }
                }
                "extractNodeTarball" -> {
                    val tarPath = call.argument<String>("tarPath")
                    if (tarPath != null) {
                        Thread {
                            try {
                                bootstrapManager.extractNodeTarball(tarPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("NODE_EXTRACT_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "tarPath required", null)
                    }
                }
                "patchGlibcPaths" -> {
                    Thread {
                        try {
                            bootstrapManager.patchGlibcPaths()
                            bootstrapManager.setupGlibcEtc()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("PATCH_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "writeNpmOverrides" -> {
                    Thread {
                        try {
                            bootstrapManager.writeNpmOverrides()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("PATCH_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "patchNpmGit" -> {
                    Thread {
                        try {
                            bootstrapManager.patchNpmGit()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("PATCH_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "copyGlibcCompat" -> {
                    Thread {
                        try {
                            bootstrapManager.copyGlibcCompat(applicationContext)
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("COPY_COMPAT_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "isPythonInstalled" -> {
                    result.success(bootstrapManager.isPythonInstalled())
                }
                "isGoInstalled" -> {
                    result.success(bootstrapManager.isGoInstalled())
                }
                "extractPythonTarball" -> {
                    val tarPath = call.argument<String>("tarPath")
                    if (tarPath != null) {
                        Thread {
                            try {
                                bootstrapManager.extractPythonTarball(tarPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("PYTHON_EXTRACT_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "tarPath required", null)
                    }
                }
                "extractGoTarball" -> {
                    val tarPath = call.argument<String>("tarPath")
                    if (tarPath != null) {
                        Thread {
                            try {
                                bootstrapManager.extractGoTarball(tarPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("GO_EXTRACT_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "tarPath required", null)
                    }
                }
                "extractGitBundle" -> {
                    val tarPath = call.argument<String>("tarPath")
                    if (tarPath != null) {
                        Thread {
                            try {
                                bootstrapManager.extractGitBundle(tarPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("GIT_EXTRACT_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "tarPath required", null)
                    }
                }
                "markBootstrapDone" -> {
                    try {
                        bootstrapManager.markBootstrapDone()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MARK_DONE_ERROR", e.message, null)
                    }
                }
                // ── Optional package installation ──────────────────
                "installStaticBinary" -> {
                    val binaryPath = call.argument<String>("binaryPath")
                    val destRelPath = call.argument<String>("destRelPath")
                    val installApplets = call.argument<Boolean>("installApplets") ?: false
                    if (binaryPath != null && destRelPath != null) {
                        Thread {
                            try {
                                bootstrapManager.installStaticBinary(binaryPath, destRelPath, installApplets)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("INSTALL_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "binaryPath and destRelPath required", null)
                    }
                }
                "installTermuxDeb" -> {
                    val debPath = call.argument<String>("debPath")
                    if (debPath != null) {
                        Thread {
                            try {
                                bootstrapManager.installTermuxDeb(debPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("INSTALL_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "debPath required", null)
                    }
                }
                "markPackageDone" -> {
                    val markerId = call.argument<String>("markerId")
                    if (markerId != null) {
                        bootstrapManager.markPackageDone(markerId)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "markerId required", null)
                    }
                }
                "isPackageInstalled" -> {
                    val checkPath = call.argument<String>("checkPath")
                    val doneMarker = call.argument<String>("doneMarker")
                    if (checkPath != null && doneMarker != null) {
                        result.success(bootstrapManager.isPackageInstalled(checkPath, doneMarker))
                    } else {
                        result.error("INVALID_ARGS", "checkPath and doneMarker required", null)
                    }
                }
                "installWrappers" -> {
                    Thread {
                        try {
                            val runner = GlibcRunner(filesDir, nativeLibDir)
                            runner.installWrappers()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("WRAPPER_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "runNode" -> {
                    val args = call.argument<List<String>>("args")
                    val timeout = call.argument<Int>("timeout")?.toLong() ?: 900L
                    if (args != null) {
                        Thread {
                            try {
                                val runner = GlibcRunner(filesDir, nativeLibDir)
                                val output = runner.runNodeSync(args, timeout)
                                runOnUiThread { result.success(output) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("NODE_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "args required", null)
                    }
                }
                "runNodeBootstrap" -> {
                    val args = call.argument<List<String>>("args")
                    val timeout = call.argument<Int>("timeout")?.toLong() ?: 1800L
                    if (args != null) {
                        Thread {
                            try {
                                val runner = GlibcRunner(filesDir, nativeLibDir)
                                val output = runner.runNodeSync(args, timeout, bootstrap = true)
                                runOnUiThread { result.success(output) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("NODE_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "args required", null)
                    }
                }
                "startGateway" -> {
                    try {
                        GatewayService.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopGateway" -> {
                    try {
                        GatewayService.stop(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "isGatewayRunning" -> {
                    result.success(GatewayService.isRunning)
                }
                "getAutoStart" -> {
                    result.success(BootReceiver.isAutoStartEnabled(applicationContext))
                }
                "setAutoStart" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    BootReceiver.setAutoStartEnabled(applicationContext, enabled)
                    result.success(true)
                }
                "startTerminalService" -> {
                    try {
                        TerminalSessionService.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopTerminalService" -> {
                    try {
                        TerminalSessionService.stop(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "isTerminalServiceRunning" -> {
                    result.success(TerminalSessionService.isRunning)
                }
                "startNodeService" -> {
                    try {
                        NodeForegroundService.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopNodeService" -> {
                    try {
                        NodeForegroundService.stop(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "isNodeServiceRunning" -> {
                    result.success(NodeForegroundService.isRunning)
                }
                "updateNodeNotification" -> {
                    val text = call.argument<String>("text") ?: "Node connected"
                    NodeForegroundService.updateStatus(text)
                    result.success(true)
                }
                "startSshd" -> {
                    val port = call.argument<Int>("port") ?: 8022
                    try {
                        SshForegroundService.start(applicationContext, port)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopSshd" -> {
                    try {
                        SshForegroundService.stop(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "isSshdRunning" -> {
                    result.success(SshForegroundService.isRunning)
                }
                "getSshdPort" -> {
                    result.success(SshForegroundService.currentPort)
                }
                "getDeviceIps" -> {
                    result.success(SshForegroundService.getDeviceIps())
                }
                "requestBatteryOptimization" -> {
                    try {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:${packageName}")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BATTERY_ERROR", e.message, null)
                    }
                }
                "isBatteryOptimized" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(!pm.isIgnoringBatteryOptimizations(packageName))
                }
                "startSetupService" -> {
                    try {
                        SetupService.start(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "updateSetupNotification" -> {
                    val text = call.argument<String>("text")
                    val progress = call.argument<Int>("progress") ?: -1
                    if (text != null) {
                        SetupService.updateNotification(text, progress)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "text required", null)
                    }
                }
                "stopSetupService" -> {
                    try {
                        SetupService.stop(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "showUrlNotification" -> {
                    val url = call.argument<String>("url")
                    val title = call.argument<String>("title") ?: "URL Detected"
                    if (url != null) {
                        showUrlNotification(url, title)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "url required", null)
                    }
                }
                "copyToClipboard" -> {
                    val text = call.argument<String>("text")
                    if (text != null) {
                        val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("URL", text))
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "text required", null)
                    }
                }
                "requestScreenCapture" -> {
                    val durationMs = call.argument<Int>("durationMs")?.toLong() ?: 5000L
                    screenCaptureResult = result
                    screenCaptureDurationMs = durationMs
                    ScreenCaptureService.clearResult()
                    val projectionManager =
                        getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    startActivityForResult(
                        projectionManager.createScreenCaptureIntent(),
                        SCREEN_CAPTURE_REQUEST
                    )
                }
                "stopScreenCapture" -> {
                    try {
                        stopService(Intent(applicationContext, ScreenCaptureService::class.java))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "vibrate" -> {
                    val durationMs = call.argument<Int>("durationMs")?.toLong() ?: 200L
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val vibratorManager =
                                getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                            val vibrator = vibratorManager.defaultVibrator
                            vibrator.vibrate(
                                VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator.vibrate(
                                    VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator.vibrate(durationMs)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VIBRATE_ERROR", e.message, null)
                    }
                }
                "requestStoragePermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            if (!Environment.isExternalStorageManager()) {
                                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                startActivity(intent)
                            }
                        } else {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(
                                    Manifest.permission.READ_EXTERNAL_STORAGE,
                                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                                ),
                                STORAGE_PERMISSION_REQUEST
                            )
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.message, null)
                    }
                }
                "hasStoragePermission" -> {
                    val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Environment.isExternalStorageManager()
                    } else {
                        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
                    }
                    result.success(hasPermission)
                }
                "getExternalStoragePath" -> {
                    result.success(Environment.getExternalStorageDirectory().absolutePath)
                }
                "openTermux" -> {
                    try {
                        val intent = packageManager.getLaunchIntentForPackage("com.termux")
                            ?: Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.termux"))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("TERMUX_ERROR", e.message, null)
                    }
                }
                "readSensor" -> {
                    val sensorType = call.argument<String>("sensor") ?: "accelerometer"
                    Thread {
                        try {
                            val sensorManager =
                                getSystemService(Context.SENSOR_SERVICE) as SensorManager
                            val type = when (sensorType) {
                                "accelerometer" -> Sensor.TYPE_ACCELEROMETER
                                "gyroscope" -> Sensor.TYPE_GYROSCOPE
                                "magnetometer" -> Sensor.TYPE_MAGNETIC_FIELD
                                "barometer" -> Sensor.TYPE_PRESSURE
                                else -> Sensor.TYPE_ACCELEROMETER
                            }
                            val sensor = sensorManager.getDefaultSensor(type)
                            if (sensor == null) {
                                runOnUiThread {
                                    result.error("SENSOR_ERROR", "Sensor $sensorType not available", null)
                                }
                                return@Thread
                            }
                            var received = false
                            val listener = object : SensorEventListener {
                                override fun onSensorChanged(event: SensorEvent?) {
                                    if (received || event == null) return
                                    received = true
                                    sensorManager.unregisterListener(this)
                                    val data = hashMapOf<String, Any>(
                                        "sensor" to sensorType,
                                        "timestamp" to event.timestamp,
                                        "accuracy" to event.accuracy
                                    )
                                    when (sensorType) {
                                        "accelerometer", "gyroscope", "magnetometer" -> {
                                            data["x"] = event.values[0].toDouble()
                                            data["y"] = event.values[1].toDouble()
                                            data["z"] = event.values[2].toDouble()
                                        }
                                        "barometer" -> {
                                            data["pressure"] = event.values[0].toDouble()
                                        }
                                    }
                                    runOnUiThread { result.success(data) }
                                }
                                override fun onAccuracyChanged(s: Sensor?, accuracy: Int) {}
                            }
                            sensorManager.registerListener(
                                listener, sensor, SensorManager.SENSOR_DELAY_NORMAL
                            )
                            // Timeout after 3 seconds
                            Thread.sleep(3000)
                            if (!received) {
                                sensorManager.unregisterListener(listener)
                                runOnUiThread {
                                    result.error("SENSOR_ERROR", "Sensor read timed out", null)
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SENSOR_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "sendChatNotification" -> {
                    val title = call.argument<String>("title") ?: "OpenClaw"
                    val body = call.argument<String>("body") ?: ""
                    sendChatNotification(title, body)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        createUrlNotificationChannel()
        createChatNotificationChannel()
        requestNotificationPermission()
        requestStoragePermissionOnLaunch()

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    GatewayService.logSink = events
                }
                override fun onCancel(arguments: Any?) {
                    GatewayService.logSink = null
                }
            }
        )

        // Shake detection EventChannel for mascot animation
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.openclaw.android/shake").setStreamHandler(
            object : EventChannel.StreamHandler {
                private var sensorManager: android.hardware.SensorManager? = null
                private var listener: SensorEventListener? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val sm = getSystemService(Context.SENSOR_SERVICE) as android.hardware.SensorManager
                    sensorManager = sm
                    val accel = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return

                    listener = object : SensorEventListener {
                        private var lastShakeTime = 0L

                        override fun onSensorChanged(event: SensorEvent?) {
                            if (event == null) return
                            val x = event.values[0]; val y = event.values[1]; val z = event.values[2]
                            val magnitude = Math.sqrt((x * x + y * y + z * z).toDouble())
                            val now = System.currentTimeMillis()
                            if (magnitude > 25 && now - lastShakeTime > 2000) {
                                lastShakeTime = now
                                events?.success("shake")
                            }
                        }

                        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    }
                    sm.registerListener(listener, accel, android.hardware.SensorManager.SENSOR_DELAY_UI)
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let { sensorManager?.unregisterListener(it) }
                    listener = null
                    sensorManager = null
                }
            }
        )
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST
                )
            }
        }
    }

    private fun requestStoragePermissionOnLaunch() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (!Environment.isExternalStorageManager()) {
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    startActivity(intent)
                } catch (_: Exception) {}
            }
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE
                    ),
                    STORAGE_PERMISSION_REQUEST
                )
            }
        }
    }

    private fun createChatNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                GatewayService.CHAT_CHANNEL_ID,
                "Chat Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Agent response notifications"
                enableVibration(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun sendChatNotification(title: String, body: String) {
        try {
            val intent = Intent(this, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                this, 99, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, GatewayService.CHAT_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            // Truncate body for notification
            val preview = if (body.length > 200) body.substring(0, 200) + "…" else body

            builder.setContentTitle(title)
                .setContentText(preview)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setStyle(Notification.BigTextStyle().bigText(preview))

            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(GatewayService.CHAT_NOTIFICATION_ID, builder.build())
        } catch (_: Exception) {}
    }

    private fun createUrlNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                URL_CHANNEL_ID,
                "OpenClaw URLs",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for detected URLs"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private var urlNotificationId = 100

    private fun showUrlNotification(url: String, title: String) {
        val openIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        val openPending = PendingIntent.getActivity(
            this, urlNotificationId, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, URL_CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(url)
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setContentIntent(openPending)
                .setAutoCancel(true)
                .setStyle(Notification.BigTextStyle().bigText(url))
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle(title)
                .setContentText(url)
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setContentIntent(openPending)
                .setAutoCancel(true)
                .build()
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(urlNotificationId++, notification)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCREEN_CAPTURE_REQUEST) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val intent = Intent(applicationContext, ScreenCaptureService::class.java).apply {
                    putExtra("resultCode", resultCode)
                    putExtra("data", data)
                    putExtra("durationMs", screenCaptureDurationMs)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                // Poll for result
                Thread {
                    val startTime = System.currentTimeMillis()
                    val timeout = screenCaptureDurationMs + 5000L
                    while (ScreenCaptureService.resultPath == null &&
                        System.currentTimeMillis() - startTime < timeout
                    ) {
                        Thread.sleep(200)
                    }
                    val path = ScreenCaptureService.resultPath
                    runOnUiThread {
                        screenCaptureResult?.success(path)
                        screenCaptureResult = null
                    }
                }.start()
            } else {
                screenCaptureResult?.success(null)
                screenCaptureResult = null
            }
        }
    }

    companion object {
        const val URL_CHANNEL_ID = "openclaw_urls"
        const val NOTIFICATION_PERMISSION_REQUEST = 1001
        const val SCREEN_CAPTURE_REQUEST = 1002
        const val STORAGE_PERMISSION_REQUEST = 1003
    }
}
