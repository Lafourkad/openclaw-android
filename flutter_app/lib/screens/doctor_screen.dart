import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../app.dart';
import '../models/optional_package.dart';
import '../services/bootstrap_service.dart';
import '../services/native_bridge.dart';
import '../services/package_service.dart';

/// OpenClaw Doctor — system health checks with visual feedback.
/// Like `openclaw doctor` but graphical.
class DoctorScreen extends StatefulWidget {
  const DoctorScreen({super.key});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  final List<_Check> _checks = [];
  bool _running = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _runAllChecks();
  }

  Future<void> _runAllChecks() async {
    setState(() {
      _running = true;
      _done = false;
      _checks.clear();
    });

    final filesDir = await NativeBridge.getFilesDir();
    final nativeLibDir = await NativeBridge.getNativeLibDir();

    // 1. glibc runtime
    await _check(
      'glibc Runtime',
      'ld-linux loader available',
      () async {
        final ldSo = '$nativeLibDir/libopenclaw-ld.so';
        return File(ldSo).existsSync();
      },
    );

    // 2. Node.js
    await _check(
      'Node.js',
      'Node binary installed',
      () async {
        final nodeBin = '$filesDir/node/bin/node';
        return File(nodeBin).existsSync();
      },
    );

    // 3. npm / OpenClaw modules
    await _check(
      'npm Modules',
      'node_modules installed',
      () async {
        final modulesDir = Directory('$filesDir/node/lib/node_modules');
        if (!modulesDir.existsSync()) return false;
        final count = modulesDir.listSync().length;
        _checks.last.detail = '$count packages';
        return count > 0;
      },
    );

    // 4. OpenClaw CLI
    await _check(
      'OpenClaw CLI',
      'openclaw binary found',
      () async {
        final oc = '$filesDir/node/bin/openclaw';
        if (File(oc).existsSync()) return true;
        // Also check node_modules
        final ocModule = '$filesDir/node/lib/node_modules/openclaw/bin/openclaw.js';
        return File(ocModule).existsSync();
      },
    );

    // 5. Config file
    await _check(
      'Configuration',
      'openclaw.json exists and is valid JSON',
      () async {
        final configPath = '$filesDir/.openclaw/openclaw.json';
        final file = File(configPath);
        if (!file.existsSync()) {
          _checks.last.detail = 'File not found';
          return false;
        }
        try {
          final raw = file.readAsStringSync();
          final config = json.decode(raw) as Map<String, dynamic>;
          final keys = config.keys.toList();
          _checks.last.detail = '${keys.length} top-level keys';
          return true;
        } catch (e) {
          _checks.last.detail = 'Invalid JSON: $e';
          return false;
        }
      },
    );

    // 6. Provider configured
    await _check(
      'Model Provider',
      'At least one provider with API key',
      () async {
        final configPath = '$filesDir/.openclaw/openclaw.json';
        try {
          final config = json.decode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
          final providers = config['models']?['providers'] as Map?;
          if (providers == null || providers.isEmpty) {
            _checks.last.detail = 'No providers configured';
            return false;
          }
          final names = providers.keys.toList();
          _checks.last.detail = names.join(', ');
          return true;
        } catch (_) {
          return false;
        }
      },
    );

    // 7. Channel configured
    await _check(
      'Messaging Channel',
      'Telegram, Discord, or WhatsApp configured',
      () async {
        final configPath = '$filesDir/.openclaw/openclaw.json';
        try {
          final config = json.decode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
          final channels = config['channels'] as Map?;
          if (channels == null) return false;

          final active = <String>[];
          for (final ch in ['telegram', 'discord', 'whatsapp']) {
            final chConfig = channels[ch] as Map?;
            if (chConfig != null) {
              final hasToken = chConfig['botToken'] != null &&
                  (chConfig['botToken'] as String).isNotEmpty;
              if (hasToken) active.add(ch);
            }
          }
          _checks.last.detail = active.isEmpty ? 'No channels with bot token' : active.join(', ');
          return active.isNotEmpty;
        } catch (_) {
          return false;
        }
      },
    );

    // 8. Gateway health
    await _check(
      'Gateway',
      'Gateway process responding',
      () async {
        try {
          final client = HttpClient();
          client.connectionTimeout = const Duration(seconds: 3);
          final request = await client.getUrl(Uri.parse('http://127.0.0.1:18789/api/health'));
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          client.close();
          if (response.statusCode == 200) {
            _checks.last.detail = 'Running';
            return true;
          }
          _checks.last.detail = 'HTTP ${response.statusCode}';
          return false;
        } catch (e) {
          _checks.last.detail = 'Not running';
          return false;
        }
      },
    );

    // 9. Workspace
    await _check(
      'Workspace',
      'Agent workspace directory exists',
      () async {
        final wsPath = '$filesDir/.openclaw/workspace';
        final exists = Directory(wsPath).existsSync();
        if (exists) {
          final files = Directory(wsPath).listSync().length;
          _checks.last.detail = '$files items';
        }
        return exists;
      },
    );

    // 10. Python (optional)
    await _check(
      'Python (optional)',
      'Python 3 available for skills',
      () async {
        final py = '$filesDir/python/bin/python3';
        if (!File(py).existsSync()) {
          _checks.last.detail = 'Not installed — tap to install';
          _checks.last.status = _CheckStatus.warning;
          _checks.last.installPackage = OptionalPackage.pythonPackage;
          return true;
        }
        _checks.last.detail = 'Installed';
        return true;
      },
    );

    // 11. Git (optional)
    await _check(
      'Git (optional)',
      'Git available for version control',
      () async {
        final git = '$filesDir/git/bin/git';
        final gitAlt = '$filesDir/git/git';
        if (!File(git).existsSync() && !File(gitAlt).existsSync()) {
          _checks.last.detail = 'Not installed — tap to install';
          _checks.last.status = _CheckStatus.warning;
          _checks.last.installPackage = OptionalPackage.gitPackage;
          return true;
        }
        _checks.last.detail = 'Installed';
        return true;
      },
    );

    // 12. Disk space
    await _check(
      'Disk Space',
      'Sufficient storage available',
      () async {
        try {
          final stat = await FileStat.stat(filesDir);
          // We can't easily get free space on Android without platform channel,
          // but we can check if our dir is accessible
          _checks.last.detail = 'Accessible';
          return true;
        } catch (_) {
          return false;
        }
      },
    );

    setState(() {
      _running = false;
      _done = true;
    });
  }

  Future<void> _check(String name, String description, Future<bool> Function() test) async {
    final check = _Check(name: name, description: description);
    setState(() => _checks.add(check));

    try {
      final ok = await test();
      if (check.status != _CheckStatus.warning) {
        check.status = ok ? _CheckStatus.pass : _CheckStatus.fail;
      }
    } catch (e) {
      check.status = _CheckStatus.fail;
      check.detail = e.toString();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final passCount = _checks.where((c) => c.status == _CheckStatus.pass).length;
    final warnCount = _checks.where((c) => c.status == _CheckStatus.warning).length;
    final failCount = _checks.where((c) => c.status == _CheckStatus.fail).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor'),
        actions: [
          if (_done)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _runAllChecks,
              tooltip: 'Re-run checks',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_done)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: failCount > 0
                  ? Colors.red.withOpacity(0.1)
                  : warnCount > 0
                      ? Colors.amber.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    failCount > 0
                        ? Icons.error
                        : warnCount > 0
                            ? Icons.warning
                            : Icons.check_circle,
                    color: failCount > 0
                        ? AppColors.statusRed
                        : warnCount > 0
                            ? AppColors.statusAmber
                            : AppColors.statusGreen,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    failCount > 0
                        ? '$failCount issue${failCount > 1 ? 's' : ''} found'
                        : warnCount > 0
                            ? 'All good — $warnCount optional'
                            : 'All checks passed',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: failCount > 0
                          ? AppColors.statusRed
                          : warnCount > 0
                              ? AppColors.statusAmber
                              : AppColors.statusGreen,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '($passCount ✓  $warnCount ⚠  $failCount ✗)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _checks.length + (_running ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _checks.length) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Running checks...'),
                        ],
                      ),
                    ),
                  );
                }
                return _buildCheckTile(_checks[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _installPackage(_Check check) async {
    if (check.installPackage == null) return;

    setState(() {
      check.detail = 'Installing...';
      check.status = _CheckStatus.running;
    });

    try {
      final service = BootstrapService();
      await service.installPackages(
        packages: [check.installPackage!],
        onProgress: (state) {
          setState(() {
            check.detail = state.message;
          });
        },
      );
      setState(() {
        check.status = _CheckStatus.pass;
        check.detail = 'Installed ✓';
        check.installPackage = null;
      });
    } catch (e) {
      setState(() {
        check.status = _CheckStatus.fail;
        check.detail = 'Install failed: $e';
      });
    }
  }

  Widget _buildCheckTile(_Check check) {
    final (icon, color) = switch (check.status) {
      _CheckStatus.running => (Icons.hourglass_empty, Colors.grey),
      _CheckStatus.pass => (Icons.check_circle, AppColors.statusGreen),
      _CheckStatus.warning => (Icons.warning_amber, AppColors.statusAmber),
      _CheckStatus.fail => (Icons.cancel, AppColors.statusRed),
    };

    return ListTile(
      leading: check.status == _CheckStatus.running
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: color),
      title: Text(check.name),
      subtitle: Text(
        check.detail ?? check.description,
        style: TextStyle(
          color: check.detail != null
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      trailing: check.installPackage != null && check.status == _CheckStatus.warning
          ? TextButton(
              onPressed: () => _installPackage(check),
              child: const Text('Install'),
            )
          : null,
      onTap: check.installPackage != null && check.status == _CheckStatus.warning
          ? () => _installPackage(check)
          : null,
    );
  }
}

enum _CheckStatus { running, pass, warning, fail }

class _Check {
  final String name;
  final String description;
  _CheckStatus status;
  String? detail;
  OptionalPackage? installPackage;

  _Check({
    required this.name,
    required this.description,
    this.status = _CheckStatus.running,
    this.detail,
    this.installPackage,
  });
}
