import 'dart:io';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../models/setup_state.dart';
import '../models/optional_package.dart';
import 'native_bridge.dart';
import 'package_service.dart';

class BootstrapService {
  final Dio _dio = Dio();

  void _updateSetupNotification(String text, {int progress = -1}) {
    try {
      NativeBridge.updateSetupNotification(text, progress: progress);
    } catch (_) {}
  }

  void _stopSetupService() {
    try {
      NativeBridge.stopSetupService();
    } catch (_) {}
  }

  Future<SetupState> checkStatus() async {
    try {
      final complete = await NativeBridge.isBootstrapComplete();
      if (complete) {
        return const SetupState(
          step: SetupStep.complete,
          progress: 1.0,
          message: 'Setup complete',
        );
      }
      return const SetupState(
        step: SetupStep.checkingStatus,
        progress: 0.0,
        message: 'Setup required',
      );
    } catch (e) {
      return SetupState(
        step: SetupStep.error,
        error: 'Failed to check status: $e',
      );
    }
  }

  /// Run the core bootstrap (glibc + Node + OpenClaw).
  /// Optional packages are installed separately via [installPackages].
  Future<void> runCoreSetup({
    required void Function(SetupState) onProgress,
  }) async {
    try {
      try { await NativeBridge.startSetupService(); } catch (_) {}

      final filesDir = await NativeBridge.getFilesDir();

      // Step 0: Cleanup + setup directories
      onProgress(const SetupState(
        step: SetupStep.checkingStatus,
        progress: 0.0,
        message: 'Setting up directories...',
      ));
      _updateSetupNotification('Setting up directories...', progress: 2);
      try {
        final glibcDir = Directory('$filesDir/glibc');
        if (glibcDir.existsSync()) glibcDir.deleteSync(recursive: true);
        final nodeDir = Directory('$filesDir/node');
        if (nodeDir.existsSync()) nodeDir.deleteSync(recursive: true);
        File('$filesDir/.bootstrap-done').deleteSync();
      } catch (_) {}
      try { await NativeBridge.setupDirs(); } catch (_) {}
      try { await NativeBridge.copyGlibcCompat(); } catch (_) {}

      // Step 1: Download glibc deb (0-25%)
      final glibcDebPath = '$filesDir/tmp/glibc.deb';
      _updateSetupNotification('Downloading glibc runtime...', progress: 5);
      onProgress(const SetupState(
        step: SetupStep.downloadingGlibc,
        progress: 0.0,
        message: 'Downloading glibc runtime...',
      ));

      await _dio.download(
        AppConstants.glibcDebUrl,
        glibcDebPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            _updateSetupNotification('Downloading glibc: $mb / $totalMb MB',
                progress: 5 + (progress * 15).round());
            onProgress(SetupState(
              step: SetupStep.downloadingGlibc,
              progress: progress,
              message: 'Downloading glibc: $mb MB / $totalMb MB',
            ));
          }
        },
      );

      _updateSetupNotification('Extracting glibc runtime...', progress: 22);
      onProgress(const SetupState(
        step: SetupStep.downloadingGlibc,
        progress: 1.0,
        message: 'Extracting glibc runtime...',
      ));
      await NativeBridge.extractGlibcDeb(glibcDebPath);
      await NativeBridge.patchGlibcPaths();

      // Step 1b: GCC runtime libs
      final gccLibsPath = '$filesDir/tmp/gcc-libs.deb';
      _updateSetupNotification('Downloading GCC runtime...', progress: 28);
      onProgress(const SetupState(
        step: SetupStep.downloadingGlibc,
        progress: 0.5,
        message: 'Downloading GCC runtime libs...',
      ));
      await _dio.download(AppConstants.gccLibsDebUrl, gccLibsPath);
      await NativeBridge.extractGlibcDeb(gccLibsPath);
      try { File(gccLibsPath).deleteSync(); } catch (_) {}

      // Step 2: Download Node.js (35-70%)
      final nodeTarUrl = AppConstants.getNodeTarballUrl('aarch64');
      final nodeTarPath = '$filesDir/tmp/nodejs.tar.xz';

      _updateSetupNotification(
          'Downloading Node.js ${AppConstants.nodeVersion}...',
          progress: 35);
      onProgress(const SetupState(
        step: SetupStep.downloadingNode,
        progress: 0.0,
        message: 'Downloading Node.js ${AppConstants.nodeVersion}...',
      ));

      await _dio.download(
        nodeTarUrl,
        nodeTarPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            _updateSetupNotification('Downloading Node.js: $mb / $totalMb MB',
                progress: 35 + (progress * 30).round());
            onProgress(SetupState(
              step: SetupStep.downloadingNode,
              progress: progress,
              message: 'Downloading Node.js: $mb MB / $totalMb MB',
            ));
          }
        },
      );

      _updateSetupNotification('Extracting Node.js...', progress: 68);
      onProgress(const SetupState(
        step: SetupStep.downloadingNode,
        progress: 1.0,
        message: 'Extracting Node.js...',
      ));
      await NativeBridge.extractNodeTarball(nodeTarPath);
      await NativeBridge.patchNpmGit();
      await NativeBridge.writeNpmOverrides();

      // Step 3: Install OpenClaw (75-95%)
      _updateSetupNotification('Installing OpenClaw...', progress: 75);
      onProgress(const SetupState(
        step: SetupStep.installingOpenClaw,
        progress: 0.0,
        message: 'Installing OpenClaw (this may take a few minutes)...',
      ));

      final npmCli = '$filesDir/node/lib/node_modules/npm/bin/npm-cli.js';
      Exception? lastNpmErr;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          if (attempt > 1) {
            _updateSetupNotification('Retrying npm install (attempt $attempt/3)...', progress: 75);
            onProgress(SetupState(
              step: SetupStep.installingOpenClaw,
              progress: 0.0,
              message: 'Retrying install (attempt $attempt/3)...',
            ));
            await Future.delayed(const Duration(seconds: 3));
          }
          await NativeBridge.runNodeBootstrap(
            [npmCli, 'install', '-g', 'openclaw', '--ignore-scripts'],
            timeout: 1800,
          );
          lastNpmErr = null;
          break;
        } catch (e) {
          lastNpmErr = Exception(e.toString());
        }
      }
      if (lastNpmErr != null) {
        try { await NativeBridge.copyNpmLogToExternal(); } catch (_) {}
        throw Exception('npm install failed after 3 attempts: $lastNpmErr');
      }

      _updateSetupNotification('Verifying OpenClaw...', progress: 92);
      onProgress(const SetupState(
        step: SetupStep.installingOpenClaw,
        progress: 0.9,
        message: 'Verifying OpenClaw...',
      ));
      await NativeBridge.runNodeBootstrap(['--version']);

      // Activate sharp prebuilt
      _updateSetupNotification('Activating native modules...', progress: 95);
      onProgress(const SetupState(
        step: SetupStep.installingOpenClaw,
        progress: 0.95,
        message: 'Activating native modules (sharp)...',
      ));
      try {
        await NativeBridge.runNodeBootstrap([
          npmCli, 'rebuild',
          '--prefix', '$filesDir/node',
          'sharp',
          '--loglevel=error',
        ]);
      } catch (_) {}

      // Mark core bootstrap done
      await NativeBridge.markBootstrapDone();

      onProgress(const SetupState(
        step: SetupStep.installingOpenClaw,
        progress: 1.0,
        message: 'Core setup complete',
      ));

    } on DioException catch (e) {
      _stopSetupService();
      onProgress(SetupState(
        step: SetupStep.error,
        error: 'Download failed: ${e.message}. Check your internet connection.',
      ));
    } catch (e) {
      _stopSetupService();
      onProgress(SetupState(
        step: SetupStep.error,
        error: 'Setup failed: $e',
      ));
    }
  }

  /// Install selected optional packages.
  Future<void> installPackages({
    required List<OptionalPackage> packages,
    required void Function(SetupState) onProgress,
  }) async {
    final filesDir = await NativeBridge.getFilesDir();
    final total = packages.length;

    for (int i = 0; i < packages.length; i++) {
      final pkg = packages[i];
      final idx = i + 1;

      // Skip if already installed
      final installed = await PackageService.isInstalled(pkg);
      if (installed) continue;

      onProgress(SetupState(
        step: SetupStep.installingPackages,
        progress: i / total,
        message: 'Installing ${pkg.name}...',
        currentPackage: pkg.name,
        totalPackages: total,
        currentPackageIndex: idx,
      ));
      _updateSetupNotification(
        'Installing ${pkg.name} ($idx/$total)...',
        progress: 80 + ((i / total) * 18).round(),
      );

      try {
        await _installSinglePackage(pkg, filesDir, (progress, message) {
          onProgress(SetupState(
            step: SetupStep.installingPackages,
            progress: (i + progress) / total,
            message: message,
            currentPackage: pkg.name,
            totalPackages: total,
            currentPackageIndex: idx,
          ));
        });

        await NativeBridge.markPackageDone(pkg.doneMarker);
      } catch (e) {
        // Non-fatal — continue with other packages
        onProgress(SetupState(
          step: SetupStep.installingPackages,
          progress: (i + 1) / total,
          message: '${pkg.name} failed: $e — continuing...',
          currentPackage: pkg.name,
          totalPackages: total,
          currentPackageIndex: idx,
        ));
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Reinstall wrappers to pick up new binaries
    try { await NativeBridge.installWrappers(); } catch (_) {}

    _updateSetupNotification('Setup complete!', progress: 100);
    _stopSetupService();

    onProgress(const SetupState(
      step: SetupStep.complete,
      progress: 1.0,
      message: 'Setup complete! Ready to start the gateway.',
    ));
  }

  /// Install a single optional package.
  Future<void> _installSinglePackage(
    OptionalPackage pkg,
    String filesDir,
    void Function(double progress, String message) onProgress,
  ) async {
    final tmpDir = '$filesDir/tmp';
    final downloadUrl = _getDownloadUrl(pkg);

    switch (pkg.installMethod) {
      case PackageInstallMethod.tarGz:
        final tarPath = '$tmpDir/${pkg.id}.tar.gz';
        onProgress(0.0, 'Downloading ${pkg.name}...');

        await _dio.download(
          downloadUrl,
          tarPath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = received / total * 0.6;
              final mb = (received / 1024 / 1024).toStringAsFixed(1);
              onProgress(progress, 'Downloading ${pkg.name}: $mb MB');
            }
          },
        );

        onProgress(0.7, 'Extracting ${pkg.name}...');
        if (pkg.extractMethod == 'extractPythonTarball') {
          await NativeBridge.extractPythonTarball(tarPath);
        } else if (pkg.extractMethod == 'extractGoTarball') {
          await NativeBridge.extractGoTarball(tarPath);
        } else if (pkg.extractMethod == 'extractGitBundle') {
          await NativeBridge.extractGitBundle(tarPath);
        }
        break;

      case PackageInstallMethod.termuxDeb:
        final debPath = '$tmpDir/${pkg.id}.deb';
        onProgress(0.0, 'Downloading ${pkg.name}...');

        await _dio.download(
          downloadUrl,
          debPath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = received / total * 0.6;
              onProgress(progress, 'Downloading ${pkg.name}...');
            }
          },
        );

        onProgress(0.7, 'Installing ${pkg.name}...');
        await NativeBridge.installTermuxDeb(debPath);
        break;

      case PackageInstallMethod.staticBinary:
        final binPath = '$tmpDir/${pkg.id}_binary';
        onProgress(0.0, 'Downloading ${pkg.name}...');

        await _dio.download(
          downloadUrl,
          binPath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final progress = received / total * 0.6;
              onProgress(progress, 'Downloading ${pkg.name}...');
            }
          },
        );

        onProgress(0.7, 'Installing ${pkg.name}...');
        await NativeBridge.installStaticBinary(
          binPath,
          pkg.binaryDestPath ?? 'bin/${pkg.id}',
          installApplets: pkg.installApplets,
        );
        try { File(binPath).deleteSync(); } catch (_) {}
        break;

      case PackageInstallMethod.termuxDebBundle:
        // Download all URLs and extract each
        final urls = pkg.downloadUrls ?? [downloadUrl];
        for (int j = 0; j < urls.length; j++) {
          final debPath = '$tmpDir/${pkg.id}_$j.deb';
          final urlProgress = j / urls.length;
          onProgress(urlProgress * 0.6, 'Downloading ${pkg.name} (${j + 1}/${urls.length})...');

          await _dio.download(urls[j], debPath);
          await NativeBridge.installTermuxDeb(debPath);
        }
        break;
    }

    onProgress(1.0, '${pkg.name} installed');
  }

  /// Resolve the download URL for a package (some use AppConstants).
  String _getDownloadUrl(OptionalPackage pkg) {
    if (pkg.downloadUrl != null) return pkg.downloadUrl!;

    switch (pkg.id) {
      case 'python':
        return AppConstants.pythonUrl;
      case 'go':
        return AppConstants.goUrl;
      case 'busybox':
        return AppConstants.busyboxUrl;
      case 'git':
        return AppConstants.gitBundleUrl;
      case 'make':
        return AppConstants.makeDebUrl;
      default:
        throw Exception('No download URL for package ${pkg.id}');
    }
  }

  // ── Legacy compatibility ──────────────────────────────────

  /// Full setup (core + all default packages). Called by SetupProvider.
  Future<void> runFullSetup({
    required void Function(SetupState) onProgress,
  }) async {
    await runCoreSetup(onProgress: onProgress);

    // If core failed, don't install packages
    // (the onProgress callback will have set error state)
    // Check if core completed by looking at the marker
    final filesDir = await NativeBridge.getFilesDir();
    if (!File('$filesDir/.bootstrap-done').existsSync()) return;

    // Install all default-enabled packages
    final defaultPackages = OptionalPackage.all
        .where((p) => p.defaultEnabled)
        .toList();

    await installPackages(
      packages: defaultPackages,
      onProgress: onProgress,
    );
  }
}
