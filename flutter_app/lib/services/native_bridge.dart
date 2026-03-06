import 'package:flutter/services.dart';
import '../constants.dart';

class NativeBridge {
  static const _channel = MethodChannel(AppConstants.channelName);
  static const _eventChannel = EventChannel(AppConstants.eventChannelName);

  static Future<String> getArch() async {
    return await _channel.invokeMethod('getArch');
  }

  static Future<String> getFilesDir() async {
    return await _channel.invokeMethod('getFilesDir');
  }

  static Future<String> getNativeLibDir() async {
    return await _channel.invokeMethod('getNativeLibDir');
  }

  static Future<bool> isBootstrapComplete() async {
    return await _channel.invokeMethod('isBootstrapComplete');
  }

  static Future<Map<String, dynamic>> getBootstrapStatus() async {
    final result = await _channel.invokeMethod('getBootstrapStatus');
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> setupDirs() async {
    return await _channel.invokeMethod('setupDirs');
  }

  static Future<bool> extractGlibcDeb(String debPath) async {
    return await _channel.invokeMethod('extractGlibcDeb', {'tarPath': debPath});
  }

  static Future<bool> extractNodeTarball(String tarPath) async {
    return await _channel.invokeMethod('extractNodeTarball', {'tarPath': tarPath});
  }

  static Future<void> patchGlibcPaths() async {
    await _channel.invokeMethod('patchGlibcPaths');
  }

  static Future<void> patchNpmGit() async {
    await _channel.invokeMethod('patchNpmGit');
  }

  static Future<void> writeNpmOverrides() async {
    await _channel.invokeMethod('writeNpmOverrides');
  }

  static Future<String?> copyNpmLogToExternal() async {
    return await _channel.invokeMethod<String>('copyNpmLogToExternal');
  }

  static Future<void> copyGlibcCompat() async {
    await _channel.invokeMethod('copyGlibcCompat');
  }

  static Future<bool> isPythonInstalled() async {
    return await _channel.invokeMethod('isPythonInstalled');
  }

  static Future<bool> isGoInstalled() async {
    return await _channel.invokeMethod('isGoInstalled');
  }

  static Future<bool> extractPythonTarball(String tarPath) async {
    return await _channel.invokeMethod('extractPythonTarball', {'tarPath': tarPath});
  }

  static Future<bool> extractGoTarball(String tarPath) async {
    return await _channel.invokeMethod('extractGoTarball', {'tarPath': tarPath});
  }

  static Future<bool> extractGitBundle(String tarPath) async {
    return await _channel.invokeMethod('extractGitBundle', {'tarPath': tarPath});
  }

  static Future<void> markBootstrapDone() async {
    await _channel.invokeMethod('markBootstrapDone');
  }

  // ── Optional package installation ──────────────────────────

  /// Install a static binary (e.g. busybox) into filesDir
  static Future<bool> installStaticBinary(
    String binaryPath,
    String destRelPath, {
    bool installApplets = false,
  }) async {
    return await _channel.invokeMethod('installStaticBinary', {
      'binaryPath': binaryPath,
      'destRelPath': destRelPath,
      'installApplets': installApplets,
    });
  }

  /// Install a Termux glibc .deb into the glibc directory
  static Future<bool> installTermuxDeb(String debPath) async {
    return await _channel.invokeMethod('installTermuxDeb', {'debPath': debPath});
  }

  /// Write a done-marker for an optional package
  static Future<void> markPackageDone(String markerId) async {
    await _channel.invokeMethod('markPackageDone', {'markerId': markerId});
  }

  /// Check if a package is installed (by checkPath + doneMarker)
  static Future<bool> isPackageInstalled(
    String checkPath,
    String doneMarker,
  ) async {
    return await _channel.invokeMethod('isPackageInstalled', {
      'checkPath': checkPath,
      'doneMarker': doneMarker,
    });
  }

  /// Reinstall wrapper scripts (after new packages are installed)
  static Future<void> installWrappers() async {
    await _channel.invokeMethod('installWrappers');
  }

  static Future<String> runNode(List<String> args, {int timeout = 900}) async {
    return await _channel.invokeMethod('runNode', {'args': args, 'timeout': timeout});
  }

  /// Like runNode but without NODE_OPTIONS — use during bootstrap before
  /// glibc-compat.js is in place.
  static Future<String> runNodeBootstrap(List<String> args, {int timeout = 1800}) async {
    return await _channel.invokeMethod('runNodeBootstrap', {'args': args, 'timeout': timeout});
  }

  static Future<bool> startGateway() async {
    return await _channel.invokeMethod('startGateway');
  }

  static Future<bool> stopGateway() async {
    return await _channel.invokeMethod('stopGateway');
  }

  static Future<bool> getAutoStart() async {
    return await _channel.invokeMethod('getAutoStart') ?? false;
  }

  static Future<void> setAutoStart(bool enabled) async {
    await _channel.invokeMethod('setAutoStart', {'enabled': enabled});
  }

  static Future<bool> restartGateway() async {
    await stopGateway();
    await Future.delayed(const Duration(seconds: 1));
    return await startGateway();
  }

  /// Send a chat notification (for when app is in background).
  static Future<void> sendChatNotification(String title, String body) async {
    await _channel.invokeMethod('sendChatNotification', {
      'title': title,
      'body': body,
    });
  }

  static Future<bool> isGatewayRunning() async {
    return await _channel.invokeMethod('isGatewayRunning');
  }

  static Future<bool> startTerminalService() async {
    return await _channel.invokeMethod('startTerminalService');
  }

  static Future<bool> stopTerminalService() async {
    return await _channel.invokeMethod('stopTerminalService');
  }

  static Future<bool> isTerminalServiceRunning() async {
    return await _channel.invokeMethod('isTerminalServiceRunning');
  }

  static Future<bool> startNodeService() async {
    return await _channel.invokeMethod('startNodeService');
  }

  static Future<bool> stopNodeService() async {
    return await _channel.invokeMethod('stopNodeService');
  }

  static Future<bool> isNodeServiceRunning() async {
    return await _channel.invokeMethod('isNodeServiceRunning');
  }

  static Future<bool> updateNodeNotification(String text) async {
    return await _channel.invokeMethod('updateNodeNotification', {'text': text});
  }

  static Future<bool> requestBatteryOptimization() async {
    return await _channel.invokeMethod('requestBatteryOptimization');
  }

  static Future<bool> isBatteryOptimized() async {
    return await _channel.invokeMethod('isBatteryOptimized');
  }

  static Future<bool> startSetupService() async {
    return await _channel.invokeMethod('startSetupService');
  }

  static Future<bool> updateSetupNotification(String text, {int progress = -1}) async {
    return await _channel.invokeMethod('updateSetupNotification', {'text': text, 'progress': progress});
  }

  static Future<bool> stopSetupService() async {
    return await _channel.invokeMethod('stopSetupService');
  }

  static Future<bool> showUrlNotification(String url, {String title = 'URL Detected'}) async {
    return await _channel.invokeMethod('showUrlNotification', {'url': url, 'title': title});
  }

  static Stream<String> get gatewayLogStream {
    return _eventChannel.receiveBroadcastStream().map((event) => event.toString());
  }

  static Future<String?> requestScreenCapture(int durationMs) async {
    return await _channel.invokeMethod('requestScreenCapture', {'durationMs': durationMs});
  }

  static Future<bool> stopScreenCapture() async {
    return await _channel.invokeMethod('stopScreenCapture');
  }

  static Future<bool> requestStoragePermission() async {
    return await _channel.invokeMethod('requestStoragePermission');
  }

  static Future<bool> hasStoragePermission() async {
    return await _channel.invokeMethod('hasStoragePermission');
  }

  static Future<String> getExternalStoragePath() async {
    return await _channel.invokeMethod('getExternalStoragePath');
  }

  static Future<bool> openTermux() async {
    return await _channel.invokeMethod('openTermux');
  }

  // SSH Service
  static Future<bool> startSshd({int port = 8022}) async {
    return await _channel.invokeMethod('startSshd', {'port': port});
  }

  static Future<bool> stopSshd() async {
    return await _channel.invokeMethod('stopSshd');
  }

  static Future<bool> isSshdRunning() async {
    return await _channel.invokeMethod('isSshdRunning');
  }

  static Future<int> getSshdPort() async {
    return await _channel.invokeMethod('getSshdPort');
  }

  static Future<List<String>> getDeviceIps() async {
    final result = await _channel.invokeMethod('getDeviceIps');
    return List<String>.from(result);
  }

  /// Import openclaw-migrate.json from sdcard root → filesDir/.openclaw/openclaw.json
  static Future<void> importMigrateConfig() async {
    await _channel.invokeMethod('importMigrateConfig');
  }

  /// Read the gateway auth token from openclaw.json (generated on first start)
  static Future<String> readGatewayToken() async {
    return await _channel.invokeMethod<String>('readGatewayToken') ?? '';
  }
}
