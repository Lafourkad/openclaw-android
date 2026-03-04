import 'dart:io';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../models/setup_state.dart';
import 'native_bridge.dart';

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

  Future<void> runFullSetup({
    required void Function(SetupState) onProgress,
  }) async {
    try {
      // Start foreground service to keep app alive during setup
      try {
        await NativeBridge.startSetupService();
      } catch (_) {}

      final filesDir = await NativeBridge.getFilesDir();

      // Step 0: Cleanup partial extractions from previous failed attempts,
      // then setup directories + copy glibc-compat.js from assets
      onProgress(const SetupState(
        step: SetupStep.checkingStatus,
        progress: 0.0,
        message: 'Setting up directories...',
      ));
      _updateSetupNotification('Setting up directories...', progress: 2);
      // Clean up stale partial state so re-extraction starts fresh
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
            final notifProgress = 5 + (progress * 15).round();
            _updateSetupNotification(
                'Downloading glibc: $mb / $totalMb MB',
                progress: notifProgress);
            onProgress(SetupState(
              step: SetupStep.downloadingGlibc,
              progress: progress,
              message: 'Downloading glibc: $mb MB / $totalMb MB',
            ));
          }
        },
      );

      // Extract glibc deb (25-35%)
      _updateSetupNotification('Extracting glibc runtime...', progress: 22);
      onProgress(const SetupState(
        step: SetupStep.downloadingGlibc,
        progress: 1.0,
        message: 'Extracting glibc runtime...',
      ));
      await NativeBridge.extractGlibcDeb(glibcDebPath);
      // Patch glibc to use our resolv.conf path (hardcoded Termux path → our filesDir)
      await NativeBridge.patchGlibcPaths();

      // Step 1b: Download + extract gcc-libs (libstdc++.so.6, libgcc_s.so.1)
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
            final notifProgress = 35 + (progress * 30).round();
            _updateSetupNotification(
                'Downloading Node.js: $mb / $totalMb MB',
                progress: notifProgress);
            onProgress(SetupState(
              step: SetupStep.downloadingNode,
              progress: progress,
              message: 'Downloading Node.js: $mb MB / $totalMb MB',
            ));
          }
        },
      );

      // Extract Node.js (70-75%)
      _updateSetupNotification('Extracting Node.js...', progress: 68);
      onProgress(const SetupState(
        step: SetupStep.downloadingNode,
        progress: 1.0,
        message: 'Extracting Node.js...',
      ));
      await NativeBridge.extractNodeTarball(nodeTarPath);
      // Patch @npmcli/git: which.js (git stub) + clone.js (stub for git-URL deps)
      await NativeBridge.patchNpmGit();
      // Write package.json in filesDir with npm overrides: libsignal git URL → local tarball
      await NativeBridge.writeNpmOverrides();

      // Step 3: Install OpenClaw (75-98%)
      _updateSetupNotification('Installing OpenClaw...', progress: 75);
      onProgress(const SetupState(
        step: SetupStep.installingOpenClaw,
        progress: 0.0,
        message: 'Installing OpenClaw (this may take a few minutes)...',
      ));

      final npmCli =
          '$filesDir/node/lib/node_modules/npm/bin/npm-cli.js';
      // Use runNodeBootstrap — no NODE_OPTIONS, glibc-compat.js copied after
      // Try up to 3 times — heap corruption (exit 134) is non-deterministic on some devices
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

      _updateSetupNotification('Verifying OpenClaw...', progress: 95);
      onProgress(const SetupState(
        step: SetupStep.installingOpenClaw,
        progress: 0.9,
        message: 'Verifying OpenClaw...',
      ));

      // Verify node runs (bootstrap env)
      await NativeBridge.runNodeBootstrap(['--version']);

      // Activate sharp prebuilt binary (downloads @img/sharp-linux-arm64, no compilation)
      // sharp's install script checks for system libvips; if absent, uses bundled prebuilt.
      _updateSetupNotification('Activating native modules...', progress: 97);
      onProgress(const SetupState(
        step: SetupStep.installingOpenClaw,
        progress: 0.95,
        message: 'Activating native modules (sharp)...',
      ));
      try {
        final npmCli = '$filesDir/node/lib/node_modules/npm/bin/npm-cli.js';
        await NativeBridge.runNodeBootstrap([
          npmCli, 'rebuild',
          '--prefix', '$filesDir/node',
          'sharp',
          '--loglevel=error',
        ]);
      } catch (_) {
        // Non-fatal — gateway works without sharp (image processing only)
      }

      onProgress(const SetupState(
        step: SetupStep.installingOpenClaw,
        progress: 1.0,
        message: 'OpenClaw installed',
      ));

      // Step 4: Download + install Python 3.13 (82-92%)
      _updateSetupNotification('Downloading Python ${AppConstants.pythonVersion}...', progress: 82);
      onProgress(const SetupState(
        step: SetupStep.installingPython,
        progress: 0.0,
        message: 'Downloading Python ${AppConstants.pythonVersion}...',
      ));

      final pythonTarPath = '$filesDir/tmp/python.tar.gz';
      await _dio.download(
        AppConstants.pythonUrl,
        pythonTarPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            _updateSetupNotification('Downloading Python: $mb / $totalMb MB', progress: 82 + (progress * 5).round());
            onProgress(SetupState(
              step: SetupStep.installingPython,
              progress: progress * 0.6,
              message: 'Downloading Python: $mb MB / $totalMb MB',
            ));
          }
        },
      );

      _updateSetupNotification('Extracting Python...', progress: 88);
      onProgress(const SetupState(
        step: SetupStep.installingPython,
        progress: 0.7,
        message: 'Extracting Python...',
      ));
      await NativeBridge.extractPythonTarball(pythonTarPath);

      onProgress(const SetupState(
        step: SetupStep.installingPython,
        progress: 1.0,
        message: 'Python installed',
      ));

      // Step 5: Download + install Go (92-99%)
      _updateSetupNotification('Downloading Go ${AppConstants.goVersion}...', progress: 92);
      onProgress(const SetupState(
        step: SetupStep.installingGo,
        progress: 0.0,
        message: 'Downloading Go ${AppConstants.goVersion}...',
      ));

      final goTarPath = '$filesDir/tmp/go.tar.gz';
      await _dio.download(
        AppConstants.goUrl,
        goTarPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            _updateSetupNotification('Downloading Go: $mb / $totalMb MB', progress: 92 + (progress * 5).round());
            onProgress(SetupState(
              step: SetupStep.installingGo,
              progress: progress * 0.6,
              message: 'Downloading Go: $mb MB / $totalMb MB',
            ));
          }
        },
      );

      _updateSetupNotification('Extracting Go...', progress: 97);
      onProgress(const SetupState(
        step: SetupStep.installingGo,
        progress: 0.7,
        message: 'Extracting Go...',
      ));
      await NativeBridge.extractGoTarball(goTarPath);

      onProgress(const SetupState(
        step: SetupStep.installingGo,
        progress: 1.0,
        message: 'Go installed',
      ));

      // Mark bootstrap complete
      await NativeBridge.markBootstrapDone();

      _updateSetupNotification('Setup complete!', progress: 100);
      _stopSetupService();
      onProgress(const SetupState(
        step: SetupStep.complete,
        progress: 1.0,
        message: 'Setup complete! Ready to start the gateway.',
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
}
