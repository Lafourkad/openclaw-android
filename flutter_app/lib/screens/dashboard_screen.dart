import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/gateway_provider.dart';
import '../providers/node_provider.dart';
import '../widgets/gateway_controls.dart';
import '../widgets/status_card.dart';
import 'node_screen.dart';
import 'agents_screen.dart';
import 'backup_screen.dart';
import 'doctor_screen.dart';
import 'file_browser_screen.dart';
import 'packages_screen.dart';
import 'update_screen.dart';
import 'web_dashboard_screen.dart';
import 'logs_screen.dart';
import 'settings/settings_main_screen.dart';


class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsMainScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const GatewayControls(),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'MANAGE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            StatusCard(
              title: 'Agents',
              subtitle: 'Add, edit, remove agents',
              icon: Icons.smart_toy,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AgentsScreen()),
              ),
            ),
            StatusCard(
              title: 'Files',
              subtitle: 'Browse workspace & edit files',
              icon: Icons.folder,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FileBrowserScreen()),
              ),
            ),
            StatusCard(
              title: 'Packages',
              subtitle: 'Install tools — Python, Git, jq, ffmpeg...',
              icon: Icons.inventory_2,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PackagesScreen()),
              ),
            ),

            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'DIAGNOSTICS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            StatusCard(
              title: 'Doctor',
              subtitle: 'System health & diagnostics',
              icon: Icons.health_and_safety,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DoctorScreen()),
              ),
            ),
            StatusCard(
              title: 'Logs',
              subtitle: 'View output and errors',
              icon: Icons.article_outlined,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LogsScreen()),
              ),
            ),

            Consumer<GatewayProvider>(
              builder: (context, provider, _) {
                if (!provider.state.isRunning) return const SizedBox.shrink();
                return StatusCard(
                  title: 'Web Dashboard',
                  subtitle: 'Open in browser',
                  icon: Icons.language,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WebDashboardScreen(
                        url: provider.state.dashboardUrl,
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'MAINTENANCE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            StatusCard(
              title: 'Backup & Restore',
              subtitle: 'Export or import your setup',
              icon: Icons.backup,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupScreen()),
              ),
            ),
            StatusCard(
              title: 'Update',
              subtitle: 'Check for OpenClaw updates',
              icon: Icons.system_update,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UpdateScreen()),
              ),
            ),

            Consumer<NodeProvider>(
              builder: (context, nodeProvider, _) {
                final nodeState = nodeProvider.state;
                return StatusCard(
                  title: 'Node',
                  subtitle: nodeState.isPaired
                      ? 'Connected to gateway'
                      : nodeState.isDisabled
                          ? 'Device capabilities for AI'
                          : nodeState.statusText,
                  icon: Icons.devices,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NodeScreen()),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Text(
                    'OpenClaw v${AppConstants.version}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'by ${AppConstants.authorName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
