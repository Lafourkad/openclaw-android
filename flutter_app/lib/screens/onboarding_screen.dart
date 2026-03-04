import 'package:flutter/material.dart';
import '../app.dart';
import 'dashboard_screen.dart';
import 'terminal_screen.dart';

/// Onboarding screen — shown after first-time setup.
/// Launches the built-in terminal pre-loaded with `openclaw onboard`.
class OnboardingScreen extends StatelessWidget {
  final bool isFirstRun;

  const OnboardingScreen({super.key, this.isFirstRun = false});

  void _openTerminal(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TerminalScreen(initialCommand: 'openclaw onboard\r\n'),
      ),
    );
  }

  void _goToDashboard(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: isFirstRun ? null : AppBar(title: const Text('Configure OpenClaw')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.terminal, size: 48, color: AppColors.accent),
                ),
                const SizedBox(height: 24),
                Text(
                  'Configure OpenClaw',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Run the interactive setup to configure\nyour API keys and channels.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500], height: 1.6),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _openTerminal(context),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Run openclaw onboard'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _goToDashboard(context),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Skip — Go to Dashboard'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
