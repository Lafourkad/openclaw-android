import 'dart:io';
import 'package:flutter/material.dart';
import '../app.dart';
import '../services/native_bridge.dart';

/// Backup & Restore — export/import config + workspace.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _backing = false;
  bool _restoring = false;
  String? _lastBackupPath;
  String _status = '';
  List<FileSystemEntity> _backups = [];
  String? _filesDir;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _filesDir = await NativeBridge.getFilesDir();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    if (_filesDir == null) return;
    final backupDir = Directory('$_filesDir/backups');
    if (!backupDir.existsSync()) {
      setState(() => _backups = []);
      return;
    }
    final entries = backupDir.listSync()
      ..sort((a, b) => b.path.compareTo(a.path)); // newest first
    setState(() => _backups = entries);
  }

  Future<void> _createBackup() async {
    setState(() { _backing = true; _status = 'Creating backup...'; });

    try {
      final now = DateTime.now();
      final timestamp = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}-${now.minute.toString().padLeft(2,'0')}';
      final backupDir = Directory('$_filesDir/backups');
      if (!backupDir.existsSync()) backupDir.createSync(recursive: true);

      final backupPath = '$_filesDir/backups/openclaw-backup-$timestamp.tar.gz';
      final openclawDir = '$_filesDir/.openclaw';

      setState(() => _status = 'Compressing workspace + config...');

      final result = await Process.run(
        '/system/bin/tar',
        ['-czf', backupPath, '-C', _filesDir!, '.openclaw'],
        environment: {'PATH': '/system/bin:$_filesDir/bin'},
      ).timeout(const Duration(minutes: 5));

      if (result.exitCode == 0) {
        final file = File(backupPath);
        final size = file.statSync().size;
        final sizeStr = size < 1024 * 1024
            ? '${(size / 1024).toStringAsFixed(0)} KB'
            : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';

        setState(() {
          _lastBackupPath = backupPath;
          _status = 'Backup created: $sizeStr';
        });
        _loadBackups();
      } else {
        setState(() => _status = 'Backup failed: ${result.stderr}');
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }

    setState(() => _backing = false);
  }

  Future<void> _restore(String backupPath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This will overwrite your current config and workspace. '
          'The gateway will be stopped first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() { _restoring = true; _status = 'Stopping gateway...'; });

    try {
      try { await NativeBridge.stopGateway(); } catch (_) {}

      setState(() => _status = 'Restoring from backup...');

      final result = await Process.run(
        '/system/bin/tar',
        ['-xzf', backupPath, '-C', _filesDir!],
        environment: {'PATH': '/system/bin'},
      ).timeout(const Duration(minutes: 5));

      if (result.exitCode == 0) {
        setState(() => _status = 'Restored! Restart the gateway.');
      } else {
        setState(() => _status = 'Restore failed: ${result.stderr}');
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }

    setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Create backup
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Create Backup', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    'Backs up your entire .openclaw directory: config, workspace, '
                    'agent state, skills, and memory files.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _backing ? null : _createBackup,
                      icon: _backing
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.backup),
                      label: Text(_backing ? 'Backing up...' : 'Create Backup'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _status.contains('Error') || _status.contains('failed')
                        ? Icons.error : Icons.info_outline,
                    size: 18,
                    color: _status.contains('Error') || _status.contains('failed')
                        ? AppColors.statusRed : AppColors.statusGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Existing backups
          Text('Saved Backups', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          if (_backups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No backups yet', style: TextStyle(color: Colors.grey)),
            ),

          for (final backup in _backups) _buildBackupTile(backup),
        ],
      ),
    );
  }

  Widget _buildBackupTile(FileSystemEntity entity) {
    final name = entity.path.split('/').last;
    String sizeStr = '';
    try {
      final size = File(entity.path).statSync().size;
      sizeStr = size < 1024 * 1024
          ? '${(size / 1024).toStringAsFixed(0)} KB'
          : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {}

    return ListTile(
      leading: const Icon(Icons.archive, color: Colors.blue),
      title: Text(name, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
      subtitle: Text(sizeStr),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _restoring ? null : () => _restore(entity.path),
            child: const Text('Restore'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () async {
              try {
                File(entity.path).deleteSync();
                _loadBackups();
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}
