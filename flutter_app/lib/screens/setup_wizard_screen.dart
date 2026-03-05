import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../constants.dart';
import '../models/setup_state.dart';
import '../models/optional_package.dart';
import '../providers/setup_provider.dart';
import '../services/package_service.dart';
import '../widgets/progress_step.dart';
import 'onboarding_screen.dart';

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  bool _started = false;

  /// Phase: 'core' = running core setup, 'select' = package selection,
  /// 'packages' = installing packages, 'done' = all complete
  String _phase = 'core';

  /// Selected packages (toggled by user)
  final Map<String, bool> _selectedPackages = {};

  @override
  void initState() {
    super.initState();
    // Default: all packages with defaultEnabled=true are selected
    for (final pkg in OptionalPackage.all) {
      _selectedPackages[pkg.id] = pkg.defaultEnabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Consumer<SetupProvider>(
          builder: (context, provider, _) {
            final state = provider.state;

            // When core completes, show package selection
            if (state.isCoreComplete &&
                _phase == 'core' &&
                state.step != SetupStep.installingPackages) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _phase = 'select');
              });
            }

            // When packages complete
            if (state.isComplete && _phase == 'packages') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _phase = 'done');
              });
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  Image.asset('assets/ic_launcher.png', width: 64, height: 64),
                  const SizedBox(height: 16),
                  Text(
                    _phase == 'select'
                        ? 'Optional Packages'
                        : 'Setup OpenClaw',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getSubtitle(state),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _phase == 'select'
                        ? _buildPackageSelection(theme, isDark)
                        : _buildSteps(state, theme, isDark),
                  ),
                  if (state.hasError) ...[
                    _buildErrorBox(state, theme),
                    const SizedBox(height: 16),
                  ],
                  _buildBottomButton(state, provider, theme),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'by ${AppConstants.authorName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _getSubtitle(SetupState state) {
    switch (_phase) {
      case 'select':
        return 'Choose which development tools to install. You can change this later in Settings.';
      case 'core':
        if (!_started) {
          return 'This will download glibc, Node.js, and OpenClaw into a self-contained environment.';
        }
        return 'Setting up the core environment...';
      case 'packages':
        return 'Installing selected packages...';
      case 'done':
        return 'Everything is ready!';
      default:
        return '';
    }
  }

  Widget _buildSteps(SetupState state, ThemeData theme, bool isDark) {
    if (_phase == 'done' || (_phase != 'packages' && state.isComplete)) {
      return _buildCompletionView(theme);
    }

    // Core complete — show all steps as done
    if (state.isCoreComplete && _phase == 'core') {
      return ListView(
        children: [
          for (final (num, label) in [
            (1, 'Download glibc runtime'),
            (2, 'Install Node.js'),
            (3, 'Install OpenClaw'),
          ])
            ProgressStep(
              stepNumber: num,
              label: label,
              isActive: false,
              isComplete: true,
            ),
          const ProgressStep(
            stepNumber: 4,
            label: 'Core setup complete!',
            isComplete: true,
          ),
        ],
      );
    }

    final steps = <(int, String, SetupStep)>[
      (1, 'Download glibc runtime', SetupStep.downloadingGlibc),
      (2, 'Install Node.js', SetupStep.downloadingNode),
      (3, 'Install OpenClaw', SetupStep.installingOpenClaw),
    ];

    if (_phase == 'packages') {
      steps.add((4, state.currentPackage != null
          ? 'Installing ${state.currentPackage} (${state.currentPackageIndex}/${state.totalPackages})'
          : 'Installing packages...',
          SetupStep.installingPackages));
    }

    return ListView(
      children: [
        for (final (num, label, step) in steps)
          ProgressStep(
            stepNumber: num,
            label: state.step == step ? state.message : label,
            isActive: state.step == step,
            isComplete: state.stepNumber > step.index + 1 || state.isComplete,
            hasError: state.hasError && state.step == step,
            progress: state.step == step ? state.progress : null,
          ),
      ],
    );
  }

  Widget _buildPackageSelection(ThemeData theme, bool isDark) {
    final iconBg = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFF3F4F6);
    int totalSizeMb = 0;
    for (final pkg in OptionalPackage.all) {
      if (_selectedPackages[pkg.id] == true) {
        // Parse "~75 MB" → 75
        final match = RegExp(r'(\d+)').firstMatch(pkg.estimatedSize);
        if (match != null) totalSizeMb += int.parse(match.group(1)!);
      }
    }

    return ListView(
      children: [
        for (final pkg in OptionalPackage.all)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: CheckboxListTile(
              value: _selectedPackages[pkg.id] ?? false,
              onChanged: (val) {
                setState(() => _selectedPackages[pkg.id] = val ?? false);
              },
              secondary: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(pkg.icon, color: pkg.color, size: 22),
              ),
              title: Text(pkg.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${pkg.description}\n${pkg.estimatedSize}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              isThreeLine: true,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Total estimated download: ~$totalSizeMb MB',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCompletionView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: AppColors.statusGreen, size: 80),
          const SizedBox(height: 16),
          Text(
            'Setup Complete!',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your OpenClaw environment is ready.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(SetupState state, ThemeData theme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 160),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  state.error ?? 'Unknown error',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton(
      SetupState state, SetupProvider provider, ThemeData theme) {
    switch (_phase) {
      case 'core':
        if (state.isComplete || state.isCoreComplete) {
          return const SizedBox.shrink(); // Will transition to 'select'
        }
        if (!_started || state.hasError) {
          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: provider.isRunning
                      ? null
                      : () {
                          setState(() => _started = true);
                          provider.runCoreOnly();
                        },
                  icon: const Icon(Icons.download),
                  label: Text(_started ? 'Retry Setup' : 'Begin Setup'),
                ),
              ),
              if (!_started) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Requires ~100 MB of storage and an internet connection',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          );
        }
        return const SizedBox.shrink(); // Running

      case 'select':
        final anySelected =
            _selectedPackages.values.any((v) => v);
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  setState(() => _phase = 'packages');
                  final selected = OptionalPackage.all
                      .where((p) => _selectedPackages[p.id] == true)
                      .toList();
                  provider.installSelectedPackages(selected);
                },
                icon: const Icon(Icons.install_desktop),
                label: Text(anySelected
                    ? 'Install Selected'
                    : 'Skip & Continue'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _phase = 'done');
                provider.skipPackages();
              },
              child: const Text('Skip all — install later'),
            ),
          ],
        );

      case 'packages':
        if (state.hasError) {
          return SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _goToOnboarding(context),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue Anyway'),
            ),
          );
        }
        return const SizedBox.shrink(); // Running

      case 'done':
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _goToOnboarding(context),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Configure API Keys'),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  void _goToOnboarding(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const OnboardingScreen(isFirstRun: true),
      ),
    );
  }
}
