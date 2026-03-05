import 'package:flutter/foundation.dart';
import '../models/setup_state.dart';
import '../models/optional_package.dart';
import '../services/bootstrap_service.dart';

class SetupProvider extends ChangeNotifier {
  final BootstrapService _bootstrapService = BootstrapService();
  SetupState _state = const SetupState();
  bool _isRunning = false;

  SetupState get state => _state;
  bool get isRunning => _isRunning;

  Future<bool> checkIfSetupNeeded() async {
    _state = await _bootstrapService.checkStatus();
    notifyListeners();
    return !_state.isComplete;
  }

  /// Run only core bootstrap (glibc + Node + OpenClaw).
  Future<void> runCoreOnly() async {
    if (_isRunning) return;
    _isRunning = true;
    notifyListeners();

    await _bootstrapService.runCoreSetup(
      onProgress: (state) {
        _state = state;
        notifyListeners();
      },
    );

    _isRunning = false;
    notifyListeners();
  }

  /// Install selected optional packages.
  Future<void> installSelectedPackages(List<OptionalPackage> packages) async {
    if (_isRunning) return;
    _isRunning = true;
    notifyListeners();

    await _bootstrapService.installPackages(
      packages: packages,
      onProgress: (state) {
        _state = state;
        notifyListeners();
      },
    );

    _isRunning = false;
    notifyListeners();
  }

  /// Skip packages and mark setup as complete.
  void skipPackages() {
    _state = const SetupState(
      step: SetupStep.complete,
      progress: 1.0,
      message: 'Setup complete',
    );
    notifyListeners();
  }

  /// Full setup (core + all default packages).
  /// Legacy — called from automated flows.
  Future<void> runSetup() async {
    if (_isRunning) return;
    _isRunning = true;
    notifyListeners();

    await _bootstrapService.runFullSetup(
      onProgress: (state) {
        _state = state;
        notifyListeners();
      },
    );

    _isRunning = false;
    notifyListeners();
  }

  void reset() {
    _state = const SetupState();
    _isRunning = false;
    notifyListeners();
  }
}
