import 'dart:io';
import '../models/optional_package.dart';
import '../models/package_registry.dart';
import 'native_bridge.dart';

/// Checks installation status of optional packages by looking for
/// their binaries and done-markers in the glibc-native layout.
class PackageService {
  static String? _filesDir;

  static Future<String> _getFilesDir() async {
    if (_filesDir != null) return _filesDir!;
    _filesDir = await NativeBridge.getFilesDir();
    return _filesDir!;
  }

  /// Check if a single package is installed.
  static Future<bool> isInstalled(OptionalPackage package) async {
    final filesDir = await _getFilesDir();
    final markerExists = File('$filesDir/${package.doneMarker}').existsSync();
    final binaryExists = File('$filesDir/${package.checkPath}').existsSync();
    return markerExists && binaryExists;
  }

  /// Check installation status for all optional packages.
  /// Returns a map of package id → installed boolean.
  static Future<Map<String, bool>> checkAllStatuses() async {
    final filesDir = await _getFilesDir();
    final statuses = <String, bool>{};
    for (final pkg in OptionalPackage.all) {
      final markerExists = File('$filesDir/${pkg.doneMarker}').existsSync();
      final binaryExists = File('$filesDir/${pkg.checkPath}').existsSync();
      statuses[pkg.id] = markerExists && binaryExists;
    }
    return statuses;
  }

  /// Mark a package as installed by writing its done-marker.
  static Future<void> markInstalled(OptionalPackage package) async {
    final filesDir = await _getFilesDir();
    File('$filesDir/${package.doneMarker}').writeAsStringSync('ok');
  }

  /// Remove a package's done-marker (for uninstall).
  static Future<void> markUninstalled(OptionalPackage package) async {
    final filesDir = await _getFilesDir();
    final marker = File('$filesDir/${package.doneMarker}');
    if (marker.existsSync()) marker.deleteSync();
  }

  /// Check if a registry package (Alpine APK) is actually working.
  /// Runs the first binary with --version/--help and checks exit code.
  static Future<bool> isRegistryPackageInstalled(RegistryPackage pkg) async {
    final filesDir = await _getFilesDir();
    final binDir = '$filesDir/bin';

    for (final binPath in pkg.binaries) {
      final name = binPath.split('/').last;
      final wrapperPath = '$binDir/$name';

      // Check wrapper exists
      if (!File(wrapperPath).existsSync()) return false;

      // Check the actual binary it points to exists
      final alpinePath = '$filesDir/alpine/$binPath';
      if (!File(alpinePath).existsSync()) return false;
    }

    // Run the first binary to verify it actually works
    final firstBin = pkg.binaries.first.split('/').last;
    final wrapperPath = '$binDir/$firstBin';
    try {
      final result = await Process.run(
        wrapperPath,
        ['--version'],
        environment: {'PATH': '$binDir:/system/bin'},
      ).timeout(const Duration(seconds: 5));
      // Some tools return 0, some return 1/2 for --version but still produce output
      return result.exitCode == 0 || 
             result.stdout.toString().isNotEmpty ||
             result.stderr.toString().isNotEmpty;
    } catch (_) {
      // Binary exists but can't execute — probably missing libs
      return false;
    }
  }

  /// Check all registry packages, returns map of id → working boolean.
  static Future<Map<String, bool>> checkRegistryStatuses() async {
    final statuses = <String, bool>{};
    for (final pkg in PackageRegistry.catalog) {
      statuses[pkg.id] = await isRegistryPackageInstalled(pkg);
    }
    return statuses;
  }
}
