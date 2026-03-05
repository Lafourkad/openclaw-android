import 'package:flutter/material.dart';
import '../app.dart';
import '../models/optional_package.dart';
import '../services/bootstrap_service.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    setState(() => _loading = true);
    for (final pkg in OptionalPackage.all) {
      _installed[pkg.id] = await PackageService.isInstalled(pkg);
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
                              'Packages are static/musl binaries that run without root. '
                              'They\'re available to the agent via exec and in the Terminal.',
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
