import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../app.dart';
import '../services/native_bridge.dart';

/// Auto-update screen — update OpenClaw without terminal.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  String? _currentVersion;
  String? _latestVersion;
  bool _checking = false;
  bool _updating = false;
  String _updateLog = '';

  @override
  void initState() {
    super.initState();
    _checkVersion();
  }

  Future<void> _checkVersion() async {
    setState(() => _checking = true);

    try {
      final filesDir = await NativeBridge.getFilesDir();
      // Get current version from package.json
      final pkgJson = File('$filesDir/node/lib/node_modules/openclaw/package.json');
      if (pkgJson.existsSync()) {
        final pkg = json.decode(pkgJson.readAsStringSync());
        _currentVersion = pkg['version'] as String?;
      }

      // Check npm registry for latest
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse('https://registry.npmjs.org/openclaw/latest'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = json.decode(body);
        _latestVersion = data['version'] as String?;
      }
    } catch (e) {
      _latestVersion = 'Error: $e';
    }

    setState(() => _checking = false);
  }

  bool get _updateAvailable {
    if (_currentVersion == null || _latestVersion == null) return false;
    if (_latestVersion!.startsWith('Error')) return false;
    return _currentVersion != _latestVersion;
  }

  Future<void> _runUpdate() async {
    setState(() {
      _updating = true;
      _updateLog = 'Starting update...\n';
    });

    try {
      final filesDir = await NativeBridge.getFilesDir();
      final nativeLibDir = await NativeBridge.getNativeLibDir();
      final glibcDir = '$filesDir/glibc/lib';
      final ldSo = '$nativeLibDir/libopenclaw-ld.so';
      final nodeBin = '$filesDir/node/bin/node';
      final npmCli = '$filesDir/node/lib/node_modules/npm/bin/npm-cli.js';
      final compatJs = '$filesDir/patches/glibc-compat.js';

      final result = await Process.run(
        ldSo,
        [
          '--library-path', glibcDir,
          nodeBin,
          '--require', compatJs,
          npmCli,
          'install', '-g', 'openclaw@latest',
        ],
        environment: {
          'HOME': filesDir,
          'PATH': '$filesDir/node/bin:/system/bin',
          'NODE_PATH': '$filesDir/node/lib/node_modules',
          'LD_LIBRARY_PATH': glibcDir,
          'UV_USE_IO_URING': '0',
          'npm_config_git': '/system/bin/true',
          'TERM': 'dumb',
          'NO_COLOR': '1',
        },
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(minutes: 5));

      _updateLog += result.stdout.toString();
      if (result.stderr.toString().isNotEmpty) {
        _updateLog += '\n${result.stderr}';
      }

      if (result.exitCode == 0) {
        _updateLog += '\n✓ Update complete! Restart the gateway to use the new version.';
        _checkVersion(); // Refresh versions
      } else {
        _updateLog += '\n✗ Update failed (exit code ${result.exitCode})';
      }
    } catch (e) {
      _updateLog += '\n✗ Error: $e';
    }

    setState(() => _updating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Update')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Version info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Installed', style: TextStyle(fontWeight: FontWeight.w600)),
                      _checking
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_currentVersion ?? 'Unknown',
                              style: const TextStyle(fontFamily: 'monospace')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Latest', style: TextStyle(fontWeight: FontWeight.w600)),
                      _checking
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_latestVersion ?? 'Unknown',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: _updateAvailable ? AppColors.statusAmber : AppColors.statusGreen,
                              )),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_updateAvailable)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _updating ? null : _runUpdate,
                        icon: _updating
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.system_update),
                        label: Text(_updating ? 'Updating...' : 'Update to $_latestVersion'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    )
                  else if (!_checking)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle, color: AppColors.statusGreen, size: 18),
                        const SizedBox(width: 8),
                        const Text('Up to date'),
                      ],
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checking ? null : _checkVersion,
            tooltip: 'Check again',
          ),

          if (_updateLog.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Update Log', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _updateLog,
                style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12,
                  color: Colors.greenAccent, height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
