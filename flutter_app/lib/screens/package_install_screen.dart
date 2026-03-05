import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../app.dart';
import '../constants.dart';
import '../models/optional_package.dart';
import '../services/native_bridge.dart';
import '../services/package_service.dart';
import '../services/bootstrap_service.dart';

/// Package install screen — downloads and installs an optional package natively.
class PackageInstallScreen extends StatefulWidget {
  final OptionalPackage package;
  final bool isUninstall;

  const PackageInstallScreen({
    super.key,
    required this.package,
    this.isUninstall = false,
  });

  @override
  State<PackageInstallScreen> createState() => _PackageInstallScreenState();
}

class _PackageInstallScreenState extends State<PackageInstallScreen> {
  String _statusMessage = '';
  double _progress = 0.0;
  bool _running = false;
  bool _done = false;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _statusMessage = widget.isUninstall
          ? 'Removing ${widget.package.name}...'
          : 'Starting install...';
    });

    if (widget.isUninstall) {
      await _uninstall();
    } else {
      await _install();
    }
  }

  Future<void> _install() async {
    try {
      final bootstrapService = BootstrapService();
      final filesDir = await NativeBridge.getFilesDir();

      await bootstrapService.installPackages(
        packages: [widget.package],
        onProgress: (state) {
          if (mounted) {
            setState(() {
              _progress = state.progress;
              _statusMessage = state.message;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _running = false;
          _done = true;
          _success = true;
          _statusMessage = '${widget.package.name} installed successfully!';
          _progress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _done = true;
          _success = false;
          _error = e.toString();
          _statusMessage = 'Installation failed';
        });
      }
    }
  }

  Future<void> _uninstall() async {
    try {
      setState(() => _statusMessage = 'Removing ${widget.package.name}...');
      final filesDir = await NativeBridge.getFilesDir();

      // Remove the done marker
      await PackageService.markUninstalled(widget.package);

      // Remove the binary/directory
      switch (widget.package.installMethod) {
        case PackageInstallMethod.tarGz:
          final dir = Directory('$filesDir/${widget.package.id}');
          if (dir.existsSync()) dir.deleteSync(recursive: true);
          break;
        case PackageInstallMethod.staticBinary:
          final bin = File('$filesDir/${widget.package.binaryDestPath ?? "bin/${widget.package.id}"}');
          if (bin.existsSync()) bin.deleteSync();
          // Also remove applet symlinks
          if (widget.package.installApplets) {
            final binDir = Directory('$filesDir/bin');
            if (binDir.existsSync()) {
              for (final f in binDir.listSync()) {
                if (f is Link) {
                  try {
                    if ((f as Link).targetSync().contains(widget.package.id)) {
                      f.deleteSync();
                    }
                  } catch (_) {}
                }
              }
            }
          }
          break;
        case PackageInstallMethod.termuxDeb:
        case PackageInstallMethod.termuxDebBundle:
          // Cannot cleanly uninstall from glibc dir; just remove marker
          break;
      }

      if (mounted) {
        setState(() {
          _running = false;
          _done = true;
          _success = true;
          _statusMessage = '${widget.package.name} removed.';
          _progress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _done = true;
          _success = false;
          _error = e.toString();
          _statusMessage = 'Removal failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = widget.isUninstall ? 'Uninstall' : 'Install';

    return Scaffold(
      appBar: AppBar(
        title: Text('$action ${widget.package.name}'),
        automaticallyImplyLeading: _done,
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: widget.package.color.withAlpha(25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(widget.package.icon, color: widget.package.color, size: 40),
            ),
            const SizedBox(height: 24),

            // Status
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),

            // Progress bar
            if (_running || (_done && _success)) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _running ? (_progress > 0 ? _progress : null) : 1.0,
                  minHeight: 6,
                  color: _done && _success
                      ? AppColors.statusGreen
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _done ? '' : '${(_progress * 100).round()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            // Error
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],

            // Done — success icon
            if (_done && _success) ...[
              const SizedBox(height: 16),
              const Icon(Icons.check_circle, color: AppColors.statusGreen, size: 48),
            ],

            const SizedBox(height: 32),

            // Back button
            if (_done)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_success),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
