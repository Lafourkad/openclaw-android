import 'package:flutter/material.dart';
import '../models/optional_package.dart';
import '../services/native_bridge.dart';

/// Package install screen — installs/uninstalls an optional package via Termux.
class PackageInstallScreen extends StatelessWidget {
  final OptionalPackage package;
  final bool isUninstall;

  const PackageInstallScreen({
    super.key,
    required this.package,
    this.isUninstall = false,
  });

  @override
  Widget build(BuildContext context) {
    final cmd = isUninstall
        ? 'apt remove ${package.id}'
        : 'apt install ${package.id}';

    return Scaffold(
      appBar: AppBar(
        title: Text(isUninstall ? 'Uninstall ${package.name}' : 'Install ${package.name}'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.terminal, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Terminal not available in this build.',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                'Use Termux to run:\n\n$cmd',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], height: 1.6),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => NativeBridge.openTermux(),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Termux'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
