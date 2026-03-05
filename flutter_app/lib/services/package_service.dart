import 'dart:io';
import '../models/optional_package.dart';
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
}
