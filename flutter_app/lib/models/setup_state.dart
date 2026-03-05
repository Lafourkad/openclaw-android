enum SetupStep {
  checkingStatus,
  downloadingGlibc,
  downloadingNode,
  installingOpenClaw,
  // Optional packages — installed after core
  installingPackages,
  complete,
  error,
}

class SetupState {
  final SetupStep step;
  final double progress;
  final String message;
  final String? error;

  /// Currently installing package name (during installingPackages step)
  final String? currentPackage;

  /// Total optional packages to install
  final int totalPackages;

  /// Current package index (1-based)
  final int currentPackageIndex;

  const SetupState({
    this.step = SetupStep.checkingStatus,
    this.progress = 0.0,
    this.message = '',
    this.error,
    this.currentPackage,
    this.totalPackages = 0,
    this.currentPackageIndex = 0,
  });

  SetupState copyWith({
    SetupStep? step,
    double? progress,
    String? message,
    String? error,
    String? currentPackage,
    int? totalPackages,
    int? currentPackageIndex,
  }) {
    return SetupState(
      step: step ?? this.step,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      error: error,
      currentPackage: currentPackage ?? this.currentPackage,
      totalPackages: totalPackages ?? this.totalPackages,
      currentPackageIndex: currentPackageIndex ?? this.currentPackageIndex,
    );
  }

  bool get isComplete => step == SetupStep.complete;
  bool get hasError => step == SetupStep.error;

  /// True when the core bootstrap is done (before optional packages)
  bool get isCoreComplete =>
      step == SetupStep.installingPackages ||
      step == SetupStep.complete ||
      (step == SetupStep.installingOpenClaw && progress >= 1.0);

  String get stepLabel {
    switch (step) {
      case SetupStep.checkingStatus:
        return 'Checking status...';
      case SetupStep.downloadingGlibc:
        return 'Downloading glibc runtime';
      case SetupStep.downloadingNode:
        return 'Installing Node.js';
      case SetupStep.installingOpenClaw:
        return 'Installing OpenClaw';
      case SetupStep.installingPackages:
        return currentPackage != null
            ? 'Installing $currentPackage'
            : 'Installing packages...';
      case SetupStep.complete:
        return 'Setup complete';
      case SetupStep.error:
        return 'Error';
    }
  }

  int get stepNumber {
    switch (step) {
      case SetupStep.checkingStatus:
        return 0;
      case SetupStep.downloadingGlibc:
        return 1;
      case SetupStep.downloadingNode:
        return 2;
      case SetupStep.installingOpenClaw:
        return 3;
      case SetupStep.installingPackages:
        return 4;
      case SetupStep.complete:
        return 5;
      case SetupStep.error:
        return -1;
    }
  }

  static const int totalSteps = 4;
}
