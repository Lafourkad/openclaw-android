import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/config_service.dart';
import '../../widgets/config_widgets.dart';

class AdvancedSettingsScreen extends StatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  State<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
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
          title: const Text('Advanced'),
          actions: [_saveButton()],
        ),
        body: ListView(
          children: [
            const ConfigSectionHeader('Context Pruning', icon: Icons.auto_delete),
            ConfigDropdown(
              config: _config,
              path: 'agents.defaults.contextPruning.mode',
              title: 'Pruning mode',
              subtitle: 'How old context is removed',
              options: const [
                ConfigOption('cache-ttl', 'Cache TTL'),
                ConfigOption('sliding-window', 'Sliding window'),
                ConfigOption('off', 'Off'),
              ],
              defaultValue: 'cache-ttl',
            ),
            ConfigTextField(
              config: _config,
              path: 'agents.defaults.contextPruning.ttl',
              label: 'TTL',
              hint: 'e.g. 1h, 30m',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Memory', icon: Icons.psychology),
            ConfigDropdown(
              config: _config,
              path: 'agents.defaults.memorySearch.provider',
              title: 'Memory search provider',
              options: const [
                ConfigOption('local', 'Local'),
                ConfigOption('none', 'None'),
              ],
              defaultValue: 'local',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Session', icon: Icons.forum),
            ConfigDropdown(
              config: _config,
              path: 'session.dmScope',
              title: 'DM session scope',
              subtitle: 'How DM sessions are isolated',
              options: const [
                ConfigOption('per-channel-peer', 'Per channel + peer'),
                ConfigOption('per-peer', 'Per peer (shared across channels)'),
              ],
              defaultValue: 'per-channel-peer',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Commands', icon: Icons.terminal),
            ConfigDropdown(
              config: _config,
              path: 'commands.native',
              title: 'Native commands',
              subtitle: '/status, /restart, /model etc.',
              options: const [
                ConfigOption('auto', 'Auto'),
                ConfigOption('on', 'On'),
                ConfigOption('off', 'Off'),
              ],
              defaultValue: 'auto',
            ),
            ConfigSwitch(
              config: _config,
              path: 'commands.restart',
              title: 'Allow /restart command',
              defaultValue: true,
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Reactions', icon: Icons.emoji_emotions),
            ConfigDropdown(
              config: _config,
              path: 'messages.ackReactionScope',
              title: 'Ack reaction scope',
              subtitle: 'When to send acknowledgement reactions',
              options: const [
                ConfigOption('group-mentions', 'Group mentions only'),
                ConfigOption('all', 'All messages'),
                ConfigOption('off', 'Off'),
              ],
              defaultValue: 'group-mentions',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Skills', icon: Icons.extension),
            ConfigDropdown(
              config: _config,
              path: 'skills.install.nodeManager',
              title: 'Node package manager',
              options: const [
                ConfigOption('npm', 'npm'),
                ConfigOption('pnpm', 'pnpm'),
                ConfigOption('yarn', 'yarn'),
              ],
              defaultValue: 'npm',
            ),

            const SizedBox(height: 32),
          ],
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
