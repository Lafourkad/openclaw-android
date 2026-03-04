import 'native_bridge.dart';

/// Manages SSH server via a native foreground service.
class SshService {
  /// Check if OpenSSH is installed (not applicable in glibc mode).
  static Future<bool> isInstalled() async {
    return false;
  }

  /// Check if sshd foreground service is running.
  static Future<bool> isSshdRunning() async {
    try {
      return await NativeBridge.isSshdRunning();
    } catch (_) {
      return false;
    }
  }

  /// Start sshd in a persistent proot process via foreground service.
  static Future<void> startSshd({int port = 8022}) async {
    await NativeBridge.startSshd(port: port);
  }

  /// Stop the sshd foreground service.
  static Future<void> stopSshd() async {
    await NativeBridge.stopSshd();
  }

  /// Set the root password (not supported in glibc mode).
  static Future<void> setPassword(String password) async {
    throw UnsupportedError('setPassword is not supported in glibc mode');
  }

  /// Get device IP addresses from Android NetworkInterface (not proot).
  static Future<List<String>> getIpAddresses() async {
    try {
      return await NativeBridge.getDeviceIps();
    } catch (_) {
      return [];
    }
  }

  /// Get the port sshd is running on.
  static Future<int> getPort() async {
    try {
      return await NativeBridge.getSshdPort();
    } catch (_) {
      return 8022;
    }
  }
}
