import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/config_service.dart';
import 'provider_settings_screen.dart';
import 'agent_settings_screen.dart';
import 'channels_settings_screen.dart';
import 'security_settings_screen.dart';
import 'tools_settings_screen.dart';
import 'gateway_settings_screen.dart';
import 'advanced_settings_screen.dart';
import 'raw_config_screen.dart';

/// Main settings screen — hub for all OpenClaw configuration sections.
class SettingsMainScreen extends StatefulWidget {
  const SettingsMainScreen({super.key});

  @override
  State<SettingsMainScreen> createState() => _SettingsMainScreenState();
}

class _SettingsMainScreenState extends State<SettingsMainScreen> {
  @override
  void initState() {
    super.initState();
    // Load config when entering settings
    context.read<ConfigService>().load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<ConfigService>();

    if (config.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _SectionTile(
            icon: Icons.cloud,
            color: Colors.blue,
            title: 'Provider & Models',
            subtitle: 'API keys, model selection, base URLs',
            onTap: () => _push(context, const ProviderSettingsScreen()),
          ),
          _SectionTile(
            icon: Icons.smart_toy,
            color: Colors.purple,
            title: 'Agents',
            subtitle: 'Agent name, model, workspace, personality',
            onTap: () => _push(context, const AgentSettingsScreen()),
          ),
          _SectionTile(
            icon: Icons.chat,
            color: Colors.green,
            title: 'Channels',
            subtitle: 'Telegram, Discord, WhatsApp configuration',
            onTap: () => _push(context, const ChannelsSettingsScreen()),
          ),
          _SectionTile(
            icon: Icons.security,
            color: Colors.orange,
            title: 'Security & Access',
            subtitle: 'Who can talk to your bot, DM policy, groups',
            onTap: () => _push(context, const SecuritySettingsScreen()),
          ),
          _SectionTile(
            icon: Icons.build,
            color: Colors.teal,
            title: 'Tools & Permissions',
            subtitle: 'Exec, elevated, browser, sandbox',
            onTap: () => _push(context, const ToolsSettingsScreen()),
          ),
          _SectionTile(
            icon: Icons.dns,
            color: Colors.indigo,
            title: 'Gateway',
            subtitle: 'Port, authentication, network, Tailscale',
            onTap: () => _push(context, const GatewaySettingsScreen()),
          ),
          _SectionTile(
            icon: Icons.tune,
            color: Colors.grey,
            title: 'Advanced',
            subtitle: 'Streaming, heartbeat, compaction, context',
            onTap: () => _push(context, const AdvancedSettingsScreen()),
          ),
          const Divider(),
          _SectionTile(
            icon: Icons.code,
            color: Colors.blueGrey,
            title: 'Raw JSON',
            subtitle: 'View and edit openclaw.json directly',
            onTap: () => _push(context, const RawConfigScreen()),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SectionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      )),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      )),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
