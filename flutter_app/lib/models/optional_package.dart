import 'package:flutter/material.dart';

/// Installation method for optional packages.
enum PackageInstallMethod {
  /// Download a tar.gz and extract via NativeBridge (Python, Go)
  tarGz,
  /// Download a Termux glibc .deb and extract via extractGlibcDeb (Make)
  termuxDeb,
  /// Download a single static binary (Busybox)
  staticBinary,
  /// Download multiple Termux glibc .debs and extract all (Git)
  termuxDebBundle,
}

/// Metadata for an optional development tool that can be installed
/// inside the glibc native environment.
class OptionalPackage {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final String estimatedSize;
  final bool defaultEnabled;

  /// Installation method
  final PackageInstallMethod installMethod;

  /// Download URL (single file) or list of URLs (bundle)
  final String? downloadUrl;
  final List<String>? downloadUrls;

  /// Path to check if installed (relative to filesDir)
  final String checkPath;

  /// Marker file (relative to filesDir) written on completion
  final String doneMarker;

  /// NativeBridge extract method name
  final String? extractMethod;

  /// For static binaries: where to place them (relative to filesDir)
  final String? binaryDestPath;

  /// Applets to symlink (busybox)
  final bool installApplets;

  const OptionalPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.estimatedSize,
    required this.checkPath,
    required this.doneMarker,
    this.defaultEnabled = true,
    this.installMethod = PackageInstallMethod.tarGz,
    this.downloadUrl,
    this.downloadUrls,
    this.extractMethod,
    this.binaryDestPath,
    this.installApplets = false,
  });

  // ──────────────────────────────────────────────
  // Package definitions
  // ──────────────────────────────────────────────

  static const pythonPackage = OptionalPackage(
    id: 'python',
    name: 'Python 3.13',
    description: 'Python interpreter — scripts, scraping, ML, data processing',
    icon: Icons.code,
    color: Colors.blue,
    estimatedSize: '~75 MB',
    defaultEnabled: true,
    installMethod: PackageInstallMethod.tarGz,
    downloadUrl: null, // Set from AppConstants at runtime
    extractMethod: 'extractPythonTarball',
    checkPath: 'python/bin/python3',
    doneMarker: '.python-done',
  );

  static const goPackage = OptionalPackage(
    id: 'go',
    name: 'Go 1.26',
    description: 'Go compiler and tools — fast compiled programs',
    icon: Icons.integration_instructions,
    color: Colors.cyan,
    estimatedSize: '~70 MB',
    defaultEnabled: true,
    installMethod: PackageInstallMethod.tarGz,
    downloadUrl: null, // Set from AppConstants at runtime
    extractMethod: 'extractGoTarball',
    checkPath: 'go/bin/go',
    doneMarker: '.go-done',
  );

  static const busyboxPackage = OptionalPackage(
    id: 'busybox',
    name: 'Busybox',
    description: '300+ Unix commands in one binary — ls, grep, sed, awk, find, tar...',
    icon: Icons.terminal,
    color: Colors.orange,
    estimatedSize: '~2 MB',
    defaultEnabled: true,
    installMethod: PackageInstallMethod.staticBinary,
    downloadUrl: null, // Set from AppConstants at runtime
    binaryDestPath: 'bin/busybox',
    installApplets: true,
    checkPath: 'bin/busybox',
    doneMarker: '.busybox-done',
  );

  static const gitPackage = OptionalPackage(
    id: 'git',
    name: 'Git',
    description: 'Version control — clone repos, manage code, install skills',
    icon: Icons.merge_type,
    color: Colors.deepOrange,
    estimatedSize: '~45 MB',
    defaultEnabled: true,
    installMethod: PackageInstallMethod.termuxDeb,
    downloadUrl: null, // Set from AppConstants at runtime
    checkPath: 'glibc/bin/git',
    doneMarker: '.git-done',
  );

  static const makePackage = OptionalPackage(
    id: 'make',
    name: 'Make',
    description: 'Build automation tool — compile native npm modules',
    icon: Icons.build,
    color: Colors.green,
    estimatedSize: '~1 MB',
    defaultEnabled: true,
    installMethod: PackageInstallMethod.termuxDeb,
    downloadUrl:
        'https://packages-cf.termux.dev/apt/termux-glibc/pool/stable/m/make-glibc/make-glibc_4.4.1_aarch64.deb',
    checkPath: 'glibc/bin/make',
    doneMarker: '.make-done',
  );

  /// All available optional packages, in recommended install order.
  static const all = [
    pythonPackage,
    goPackage,
    busyboxPackage,
    gitPackage,
    makePackage,
  ];
}
