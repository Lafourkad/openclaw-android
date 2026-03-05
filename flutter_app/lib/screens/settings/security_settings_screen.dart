import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/config_service.dart';
import '../../widgets/config_widgets.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  late ConfigService _config;

  @override
  void initState() {
    super.initState();
    _config = context.read<ConfigService>();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _config,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Security & Access'),
          actions: [_saveButton()],
        ),
        body: ListView(
          children: [
            const ConfigSectionHeader('Elevated Tools', icon: Icons.admin_panel_settings),
            _infoCard('Elevated tools allow dangerous operations like exec, '
                'gateway restart, and config changes. Only authorized users '
                'should have access.'),
            ConfigSwitch(
              config: _config,
              path: 'tools.elevated.enabled',
              title: 'Enable elevated tools',
              subtitle: 'Allow exec, gateway, config changes',
              defaultValue: true,
            ),
            ConfigStringList(
              config: _config,
              path: 'tools.elevated.allowFrom.telegram',
              title: 'Telegram elevated users',
              addHint: 'Telegram user ID',
            ),
            ConfigStringList(
              config: _config,
              path: 'tools.elevated.allowFrom.discord',
              title: 'Discord elevated users',
              addHint: 'Discord user ID',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Exec Security', icon: Icons.terminal),
            ConfigDropdown(
              config: _config,
              path: 'tools.exec.security',
              title: 'Exec security mode',
              subtitle: 'Controls what the agent can execute',
              options: const [
                ConfigOption('full', 'Full (unrestricted)'),
                ConfigOption('allowlist', 'Allowlist (specific commands)'),
                ConfigOption('deny', 'Deny (no exec)'),
              ],
              defaultValue: 'full',
            ),
            ConfigDropdown(
              config: _config,
              path: 'tools.exec.ask',
              title: 'Ask before exec',
              subtitle: 'Prompt user before running commands',
              options: const [
                ConfigOption('off', 'Off (auto-approve)'),
                ConfigOption('on-miss', 'On miss (ask if not in allowlist)'),
                ConfigOption('always', 'Always ask'),
              ],
              defaultValue: 'off',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Sandbox', icon: Icons.shield),
            ConfigDropdown(
              config: _config,
              path: 'agents.defaults.sandbox.mode',
              title: 'Default sandbox mode',
              subtitle: 'Isolate agent execution environment',
              options: const [
                ConfigOption('off', 'Off (no sandbox)'),
                ConfigOption('docker', 'Docker'),
                ConfigOption('nsjail', 'nsjail'),
              ],
              defaultValue: 'off',
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        color: Colors.amber.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.amber, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saveButton() {
    return TextButton.icon(
      onPressed: () async {
        final ok = await _config.saveAndRestart();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? 'Saved & restarting...' : 'Save failed')),
          );
        }
      },
      icon: const Icon(Icons.save),
      label: const Text('Save'),
    );
  }
}
