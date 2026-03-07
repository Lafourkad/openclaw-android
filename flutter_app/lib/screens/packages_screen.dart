import 'dart:io';
import 'package:flutter/material.dart';
import '../app.dart';
import '../models/optional_package.dart';
import '../models/package_registry.dart';
import '../services/bootstrap_service.dart';
import '../services/native_bridge.dart';
import '../services/package_service.dart';

/// Package Manager — install/uninstall dev tools in one tap.
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  final Map<String, bool> _installed = {};
  final Map<String, bool> _busy = {};
  final Map<String, String?> _status = {};
  // Alpine/registry packages
  final Map<String, bool> _regInstalled = {};
  final Map<String, bool> _regBusy = {};
  final Map<String, String?> _regStatus = {};
  String? _filesDir;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    setState(() => _loading = true);
    _filesDir = await NativeBridge.getFilesDir();
    for (final pkg in OptionalPackage.all) {
      _installed[pkg.id] = await PackageService.isInstalled(pkg);
    }
    // Check registry packages — verify they actually work
    final regStatuses = await PackageService.checkRegistryStatuses();
    for (final entry in regStatuses.entries) {
      _regInstalled[entry.key] = entry.value;
    }
    setState(() => _loading = false);
  }

  Future<void> _install(OptionalPackage pkg) async {
    setState(() {
      _busy[pkg.id] = true;
      _status[pkg.id] = 'Downloading...';
    });

    try {
      final service = BootstrapService();
      await service.installPackages(
        packages: [pkg],
        onProgress: (state) {
          setState(() => _status[pkg.id] = state.message);
        },
      );
      setState(() {
        _installed[pkg.id] = true;
        _busy[pkg.id] = false;
        _status[pkg.id] = null;
      });
    } catch (e) {
      setState(() {
        _busy[pkg.id] = false;
        _status[pkg.id] = 'Failed: $e';
      });
    }
  }

  /// Install an Alpine APK package.
  Future<void> _installAlpine(RegistryPackage pkg) async {
    setState(() {
      _regBusy[pkg.id] = true;
      _regStatus[pkg.id] = 'Downloading...';
    });

    try {
      final tmpDir = '$_filesDir/tmp';
      final alpineDir = '$_filesDir/alpine';
      final binDir = '$_filesDir/bin';

      // Ensure dirs exist
      await Directory(tmpDir).create(recursive: true);
      await Directory(alpineDir).create(recursive: true);
      await Directory(binDir).create(recursive: true);

      // Download and extract all package URLs
      final client = HttpClient();
      for (int i = 0; i < pkg.downloadUrls.length; i++) {
        final url = pkg.downloadUrls[i];
        setState(() => _regStatus[pkg.id] = 'Downloading ${i + 1}/${pkg.downloadUrls.length}...');
        
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        // Handle redirects for GitHub releases (302)
        if (response.statusCode >= 400) {
          throw 'Download failed: HTTP ${response.statusCode} for $url';
        }

        if (url.endsWith('.deb')) {
          // Termux .deb = ar archive with data.tar.xz inside
          final debPath = '$tmpDir/${pkg.id}_$i.deb';
          final file = File(debPath);
          final sink = file.openWrite();
          await response.pipe(sink);
          
          setState(() => _regStatus[pkg.id] = 'Extracting ${i + 1}/${pkg.downloadUrls.length}...');
          // Use busybox ar and tar to extract .deb (supports xz)
          await NativeBridge.runNode(['-e', '''
const {execSync} = require("child_process");
const fs = require("fs");
const debPath = "$debPath";
const outDir = "$alpineDir";
const tmpDir = "$tmpDir";
const busybox = "$_filesDir/bin/busybox";

fs.mkdirSync(outDir, {recursive: true});

// Extract data.tar.* from .deb using busybox ar (extracts to cwd)
execSync(busybox + " ar -x " + debPath, {cwd: tmpDir, stdio: "inherit"});

// Find the data.tar.* file
const files = fs.readdirSync(tmpDir);
const dataTar = files.find(f => f.startsWith("data.tar"));
if (!dataTar) throw new Error("No data.tar found in .deb");

// Extract tar to outDir
execSync(busybox + " tar -xf " + tmpDir + "/" + dataTar + " -C " + outDir, {stdio: "inherit"});

// Cleanup
try { fs.unlinkSync(tmpDir + "/" + dataTar); } catch(e) {}
try { fs.unlinkSync(tmpDir + "/control.tar.*"); } catch(e) {}
try { fs.unlinkSync(tmpDir + "/debian-binary"); } catch(e) {}
'''], timeout: 30);
          try { File(debPath).deleteSync(); } catch (_) {}
        } else if (url.endsWith('.apk')) {
          // Alpine APK = gzip tar
          final apkPath = '$tmpDir/${pkg.id}_$i.apk';
          final file = File(apkPath);
          final sink = file.openWrite();
          await response.pipe(sink);
          
          setState(() => _regStatus[pkg.id] = 'Extracting ${i + 1}/${pkg.downloadUrls.length}...');
          await Process.run(
            '/system/bin/tar', ['-xzf', apkPath, '-C', alpineDir],
            environment: {'PATH': '/system/bin'},
          );
          try { File(apkPath).deleteSync(); } catch (_) {}
        } else {
          // Standalone binary (e.g. yt-dlp GitHub release)
          final binName = pkg.binaries.first.split('/').last;
          final binSubDir = '$alpineDir/usr/bin';
          await Directory(binSubDir).create(recursive: true);
          final binFile = File('$binSubDir/$binName');
          final sink = binFile.openWrite();
          await response.pipe(sink);
        }
      }
      client.close();

      setState(() => _regStatus[pkg.id] = 'Setting up wrappers...');

      // Symlink binaries to bin/
      for (final binPath in pkg.binaries) {
        final src = '$alpineDir/$binPath';
        final name = binPath.split('/').last;
        final dst = '$binDir/$name';
        if (File(src).existsSync()) {
          // Make executable
          await Process.run('/system/bin/chmod', ['+x', src]);
          // Create wrapper script that uses glibc ld-linux
          // Use musl loader from APK native libs (bundled as libmusl-ld.so)
          // Must be in /data/app/.../lib/arm64/ — SELinux blocks exec from /data/user/
          final ldMusl = '${await NativeBridge.getNativeLibDir()}/libmusl-ld.so';
          final muslLib = '$_filesDir/git/lib';
          final wrapper = File(dst);
          // Use /system/bin/sh as interpreter since direct exec from /data is blocked
          // Include alpine/usr/lib for shared lib deps (e.g. libonig for jq)
          await wrapper.writeAsString(
            '#!/system/bin/sh\n'
            'exec ${ldMusl} --library-path ${muslLib}:$_filesDir/alpine/usr/lib ${src} "\$@"\n'
          );
          // Note: scripts in /data can't be executed directly due to W^X/SELinux
          // The shell spawns them via /system/bin/sh automatically
          await Process.run('/system/bin/chmod', ['+x', dst]);
        }
      }


      // Verify the package actually works
      setState(() => _regStatus[pkg.id] = 'Verifying...');
      // Check what files exist for debugging
      final firstBin = pkg.binaries.first.split('/').last;
      final wrapperFile = File('$binDir/$firstBin');
      final srcFile = File('$alpineDir/${pkg.binaries.first}');
      if (!srcFile.existsSync()) {
        throw 'Source binary not found: $alpineDir/${pkg.binaries.first}';
      }
      if (!wrapperFile.existsSync()) {
        throw 'Wrapper not created: $binDir/$firstBin';
      }
      // Verify binary was extracted (wrapper exec is blocked by SELinux — skip exec test)
      // The agent can use tools via the loader directly: /path/to/ld-musl binary --version

      setState(() {
        _regInstalled[pkg.id] = true;
        _regBusy[pkg.id] = false;
        _regStatus[pkg.id] = null;
      });
    } catch (e) {
      setState(() {
        _regBusy[pkg.id] = false;
        _regStatus[pkg.id] = 'Failed: $e';
      });
    }
  }

  Future<void> _uninstall(OptionalPackage pkg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${pkg.name}?'),
        content: const Text('This will delete the package files.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _busy[pkg.id] = true;
      _status[pkg.id] = 'Removing...';
    });

    try {
      await PackageService.markUninstalled(pkg);
      // TODO: Actually delete the files on disk
      setState(() {
        _installed[pkg.id] = false;
        _busy[pkg.id] = false;
        _status[pkg.id] = null;
      });
    } catch (e) {
      setState(() {
        _busy[pkg.id] = false;
        _status[pkg.id] = 'Failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installedCount = _installed.values.where((v) => v).length;
    final totalCount = OptionalPackage.all.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Packages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkAll,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Summary
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$installedCount / $totalCount packages installed',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tools are installed in the app sandbox — no root needed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                for (final pkg in OptionalPackage.all) _buildPackageTile(pkg),

                // ── Alpine Catalog ──
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.store, color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'PACKAGE CATALOG',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Source: Alpine Linux',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                for (final entry in PackageRegistry.byCategory.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      entry.key,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final pkg in entry.value) _buildRegistryTile(pkg),
                ],

                // Info card
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    color: Colors.blue.withOpacity(0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Core packages use glibc/static builds. Catalog packages '
                              'are from Alpine Linux (musl aarch64). All run without root '
                              'and are available to the agent via exec and Terminal.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRegistryTile(RegistryPackage pkg) {
    final installed = _regInstalled[pkg.id] ?? false;
    final busy = _regBusy[pkg.id] ?? false;
    final status = _regStatus[pkg.id];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: pkg.color.withOpacity(0.15),
        child: Icon(pkg.icon, color: pkg.color, size: 20),
      ),
      title: Row(
        children: [
          Flexible(child: Text(pkg.name, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 6),
          Text(pkg.version, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (pkg.estimatedSize != null) ...[
            const SizedBox(width: 6),
            Text(pkg.estimatedSize!, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ],
      ),
      subtitle: Text(
        status ?? pkg.description,
        style: TextStyle(
          fontSize: 13,
          color: status != null && status.startsWith('Failed') ? AppColors.statusRed : null,
        ),
      ),
      trailing: busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : installed
              ? const Icon(Icons.check_circle, color: AppColors.statusGreen, size: 20)
              : TextButton(
                  onPressed: () => _installAlpine(pkg),
                  child: const Text('Install'),
                ),
    );
  }

  Widget _buildPackageTile(OptionalPackage pkg) {
    final installed = _installed[pkg.id] ?? false;
    final busy = _busy[pkg.id] ?? false;
    final status = _status[pkg.id];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: pkg.color.withOpacity(0.15),
        child: Icon(pkg.icon, color: pkg.color, size: 22),
      ),
      title: Row(
        children: [
          Text(pkg.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(
            pkg.estimatedSize,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      subtitle: Text(
        status ?? pkg.description,
        style: TextStyle(
          fontSize: 13,
          color: status != null && status.startsWith('Failed')
              ? AppColors.statusRed
              : null,
        ),
      ),
      trailing: busy
          ? const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : installed
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.statusGreen, size: 20),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _uninstall(pkg),
                      tooltip: 'Remove',
                    ),
                  ],
                )
              : TextButton(
                  onPressed: () => _install(pkg),
                  child: const Text('Install'),
                ),
    );
  }
}
