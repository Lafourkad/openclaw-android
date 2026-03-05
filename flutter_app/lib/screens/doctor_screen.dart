import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import '../app.dart';
import '../models/optional_package.dart';
import '../services/bootstrap_service.dart';
import '../services/native_bridge.dart';

/// OpenClaw Doctor — wraps `openclaw doctor` with graphical UI.
/// Shows parsed diagnostic results + Fix button.
class DoctorScreen extends StatefulWidget {
  const DoctorScreen({super.key});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  bool _running = false;
  bool _fixing = false;
  String _rawOutput = '';
  List<_DiagSection> _sections = [];
  bool _hasFixableIssues = false;
  String? _error;

  // System checks (pre-doctor)
  final List<_SystemCheck> _systemChecks = [];

  @override
  void initState() {
    super.initState();
    _runDoctor();
  }

  Future<void> _runDoctor() async {
    setState(() {
      _running = true;
      _error = null;
      _rawOutput = '';
      _sections = [];
      _systemChecks.clear();
      _hasFixableIssues = false;
    });

    // Phase 1: Quick system checks
    await _runSystemChecks();

    // Phase 2: Run openclaw doctor
    try {
      final filesDir = await NativeBridge.getFilesDir();
      final nativeLibDir = await NativeBridge.getNativeLibDir();
      final glibcDir = '$filesDir/glibc/lib';
      final ldSo = '$nativeLibDir/libopenclaw-ld.so';
      final nodeBin = '$filesDir/node/bin/node';
      final openclawBin = '$filesDir/node/bin/openclaw';
      final compatJs = '$filesDir/patches/glibc-compat.js';

      final result = await Process.run(
        ldSo,
        [
          '--library-path', glibcDir,
          nodeBin,
          '--require', compatJs,
          openclawBin,
          'doctor',
          '--non-interactive',
        ],
        environment: {
          'HOME': filesDir,
          'PATH': '$filesDir/node/bin:/system/bin',
          'NODE_PATH': '$filesDir/node/lib/node_modules',
          'LD_LIBRARY_PATH': glibcDir,
          'UV_USE_IO_URING': '0',
          'CHOKIDAR_USEPOLLING': 'true',
          'TERM': 'dumb',
          'NO_COLOR': '1',
        },
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 30));

      _rawOutput = result.stdout.toString() + result.stderr.toString();
      _sections = _parseOutput(_rawOutput);
      _hasFixableIssues = _rawOutput.contains('--fix');
    } catch (e) {
      _error = 'Failed to run doctor: $e';
    }

    setState(() => _running = false);
  }

  Future<void> _runFix() async {
    setState(() => _fixing = true);

    try {
      final filesDir = await NativeBridge.getFilesDir();
      final nativeLibDir = await NativeBridge.getNativeLibDir();
      final glibcDir = '$filesDir/glibc/lib';
      final ldSo = '$nativeLibDir/libopenclaw-ld.so';
      final nodeBin = '$filesDir/node/bin/node';
      final openclawBin = '$filesDir/node/bin/openclaw';
      final compatJs = '$filesDir/patches/glibc-compat.js';

      final result = await Process.run(
        ldSo,
        [
          '--library-path', glibcDir,
          nodeBin,
          '--require', compatJs,
          openclawBin,
          'doctor',
          '--fix',
          '--non-interactive',
        ],
        environment: {
          'HOME': filesDir,
          'PATH': '$filesDir/node/bin:/system/bin',
          'NODE_PATH': '$filesDir/node/lib/node_modules',
          'LD_LIBRARY_PATH': glibcDir,
          'UV_USE_IO_URING': '0',
          'CHOKIDAR_USEPOLLING': 'true',
          'TERM': 'dumb',
          'NO_COLOR': '1',
        },
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 30));

      _rawOutput = result.stdout.toString() + result.stderr.toString();
      _sections = _parseOutput(_rawOutput);
      _hasFixableIssues = false; // Assume fixed

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Doctor fix applied ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fix failed: $e')),
        );
      }
    }

    setState(() => _fixing = false);
  }

  Future<void> _runSystemChecks() async {
    final filesDir = await NativeBridge.getFilesDir();
    final nativeLibDir = await NativeBridge.getNativeLibDir();

    _addCheck('glibc Runtime', File('$nativeLibDir/libopenclaw-ld.so').existsSync());
    _addCheck('Node.js', File('$filesDir/node/bin/node').existsSync());
    _addCheck('OpenClaw CLI', File('$filesDir/node/bin/openclaw').existsSync() ||
        File('$filesDir/node/lib/node_modules/openclaw/bin/openclaw.js').existsSync());

    final configFile = File('$filesDir/.openclaw/openclaw.json');
    bool configValid = false;
    if (configFile.existsSync()) {
      try {
        json.decode(configFile.readAsStringSync());
        configValid = true;
      } catch (_) {}
    }
    _addCheck('Config file', configValid);

    _addCheck('Workspace', Directory('$filesDir/.openclaw/workspace').existsSync());

    // Optional
    _addOptionalCheck('Python', File('$filesDir/python/bin/python3').existsSync(),
        OptionalPackage.pythonPackage);
    _addOptionalCheck('Git', File('$filesDir/git/bin/git').existsSync() ||
        File('$filesDir/git/git').existsSync(),
        OptionalPackage.gitPackage);

    setState(() {});
  }

  void _addCheck(String name, bool ok) {
    _systemChecks.add(_SystemCheck(name: name, ok: ok));
  }

  void _addOptionalCheck(String name, bool ok, OptionalPackage pkg) {
    _systemChecks.add(_SystemCheck(name: name, ok: ok, optional: true, package: ok ? null : pkg));
  }

  Future<void> _installPackage(_SystemCheck check) async {
    if (check.package == null) return;
    setState(() => check.installing = true);

    try {
      final service = BootstrapService();
      await service.installPackages(
        packages: [check.package!],
        onProgress: (state) {
          setState(() => check.installStatus = state.message);
        },
      );
      setState(() {
        check.ok = true;
        check.installing = false;
        check.package = null;
        check.installStatus = null;
      });
    } catch (e) {
      setState(() {
        check.installing = false;
        check.installStatus = 'Failed: $e';
      });
    }
  }

  List<_DiagSection> _parseOutput(String raw) {
    final sections = <_DiagSection>[];
    // Strip ANSI codes
    final clean = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');

    // Parse boxed sections: ◇  Title ──...╮ ... ├──...╯
    final sectionRegex = RegExp(r'◇\s+(.+?)\s*[─]+[╮┐]\n([\s\S]*?)(?=[├└])', multiLine: true);
    for (final match in sectionRegex.allMatches(clean)) {
      final title = match.group(1)?.trim() ?? 'Unknown';
      final body = match.group(2)
          ?.split('\n')
          .map((l) => l.replaceAll(RegExp(r'^│\s*'), '').replaceAll(RegExp(r'\s*│$'), '').trim())
          .where((l) => l.isNotEmpty)
          .join('\n') ?? '';
      if (body.isNotEmpty) {
        final isWarning = body.contains('--fix') || body.contains('missing') || body.contains('legacy');
        sections.add(_DiagSection(title: title, body: body, isWarning: isWarning));
      }
    }

    // Also capture plain lines (Telegram: ok, Agents:, etc.)
    final plainLines = <String>[];
    for (final line in clean.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('◇') || trimmed.startsWith('│') ||
          trimmed.startsWith('├') || trimmed.startsWith('└') ||
          trimmed.startsWith('┌') || trimmed.contains('──')) continue;
      if (trimmed.contains('▄') || trimmed.contains('▀') || trimmed.contains('█')) continue;
      if (trimmed.contains('🦞') || trimmed.contains('OPENCLAW')) continue;
      if (trimmed.startsWith('[bridge/')) continue;
      plainLines.add(trimmed);
    }
    if (plainLines.isNotEmpty) {
      sections.add(_DiagSection(
        title: 'Status',
        body: plainLines.join('\n'),
        isWarning: false,
      ));
    }

    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failCount = _systemChecks.where((c) => !c.ok && !c.optional).length;
    final allOk = failCount == 0 && !_hasFixableIssues;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor'),
        actions: [
          if (!_running)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _runDoctor,
              tooltip: 'Re-run',
            ),
        ],
      ),
      body: _running
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Running diagnostics...'),
                ],
              ),
            )
          : ListView(
              children: [
                // Summary banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: _error != null
                      ? Colors.red.withOpacity(0.1)
                      : allOk
                          ? Colors.green.withOpacity(0.1)
                          : Colors.amber.withOpacity(0.1),
                  child: Row(
                    children: [
                      Icon(
                        _error != null
                            ? Icons.error
                            : allOk
                                ? Icons.check_circle
                                : Icons.warning_amber,
                        color: _error != null
                            ? AppColors.statusRed
                            : allOk
                                ? AppColors.statusGreen
                                : AppColors.statusAmber,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error ?? (allOk ? 'All checks passed' : 'Issues found'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _error != null
                                ? AppColors.statusRed
                                : allOk
                                    ? AppColors.statusGreen
                                    : AppColors.statusAmber,
                          ),
                        ),
                      ),
                      if (_hasFixableIssues)
                        ElevatedButton.icon(
                          onPressed: _fixing ? null : _runFix,
                          icon: _fixing
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.build, size: 18),
                          label: Text(_fixing ? 'Fixing...' : 'Fix'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),

                // System checks
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'SYSTEM',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                for (final check in _systemChecks) _buildSystemCheckTile(check),

                // Doctor output sections
                if (_sections.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(
                      'DIAGNOSTICS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  for (final section in _sections) _buildDiagCard(section),
                ],

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildSystemCheckTile(_SystemCheck check) {
    return ListTile(
      leading: check.installing
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
              check.ok
                  ? Icons.check_circle
                  : check.optional
                      ? Icons.warning_amber
                      : Icons.cancel,
              color: check.ok
                  ? AppColors.statusGreen
                  : check.optional
                      ? AppColors.statusAmber
                      : AppColors.statusRed,
            ),
      title: Text(check.name),
      subtitle: check.installStatus != null
          ? Text(check.installStatus!, style: const TextStyle(fontSize: 13))
          : Text(
              check.ok
                  ? 'OK'
                  : check.optional
                      ? 'Not installed'
                      : 'Missing',
              style: const TextStyle(fontSize: 13),
            ),
      trailing: check.package != null && !check.installing
          ? TextButton(
              onPressed: () => _installPackage(check),
              child: const Text('Install'),
            )
          : null,
    );
  }

  Widget _buildDiagCard(_DiagSection section) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  section.isWarning ? Icons.warning_amber : Icons.info_outline,
                  size: 18,
                  color: section.isWarning ? AppColors.statusAmber : AppColors.statusGreen,
                ),
                const SizedBox(width: 8),
                Text(
                  section.title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              section.body,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemCheck {
  final String name;
  bool ok;
  final bool optional;
  OptionalPackage? package;
  bool installing;
  String? installStatus;

  _SystemCheck({
    required this.name,
    required this.ok,
    this.optional = false,
    this.package,
    this.installing = false,
    this.installStatus,
  });
}

class _DiagSection {
  final String title;
  final String body;
  final bool isWarning;

  _DiagSection({required this.title, required this.body, required this.isWarning});
}
