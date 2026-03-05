import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/config_service.dart';
import '../../services/native_bridge.dart';
import '../../widgets/config_widgets.dart';

class GatewaySettingsScreen extends StatefulWidget {
  const GatewaySettingsScreen({super.key});

  @override
  State<GatewaySettingsScreen> createState() => _GatewaySettingsScreenState();
}

class _GatewaySettingsScreenState extends State<GatewaySettingsScreen> {
  late ConfigService _config;
  bool _autoStart = false;

  @override
  void initState() {
    super.initState();
    _config = context.read<ConfigService>();
    _loadAutoStart();
  }

  Future<void> _loadAutoStart() async {
    final enabled = await NativeBridge.getAutoStart();
    if (mounted) setState(() => _autoStart = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _config,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Gateway'),
          actions: [_saveButton()],
        ),
        body: ListView(
          children: [
            const ConfigSectionHeader('Startup', icon: Icons.power_settings_new),
            SwitchListTile(
              title: const Text('Auto-start on boot'),
              subtitle: const Text('Start gateway when device boots'),
              value: _autoStart,
              onChanged: (v) async {
                await NativeBridge.setAutoStart(v);
                setState(() => _autoStart = v);
              },
            ),

            const ConfigSectionHeader('Network', icon: Icons.dns),
            ConfigNumberField(
              config: _config,
              path: 'gateway.port',
              label: 'Port',
              hint: '18789',
            ),
            ConfigDropdown(
              config: _config,
              path: 'gateway.bind',
              title: 'Bind address',
              subtitle: 'Network interface to listen on',
              options: const [
                ConfigOption('loopback', 'Loopback (localhost only)'),
                ConfigOption('all', 'All interfaces (0.0.0.0)'),
              ],
              defaultValue: 'loopback',
            ),
            ConfigDropdown(
              config: _config,
              path: 'gateway.mode',
              title: 'Gateway mode',
              options: const [
                ConfigOption('local', 'Local'),
                ConfigOption('remote', 'Remote'),
              ],
              defaultValue: 'local',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Authentication', icon: Icons.lock),
            ConfigDropdown(
              config: _config,
              path: 'gateway.auth.mode',
              title: 'Auth mode',
              subtitle: 'How clients authenticate to the gateway',
              options: const [
                ConfigOption('token', 'Token'),
                ConfigOption('none', 'None (open)'),
              ],
              defaultValue: 'token',
            ),
            ConfigTextField(
              config: _config,
              path: 'gateway.auth.token',
              label: 'Auth token',
              obscure: true,
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Tailscale', icon: Icons.vpn_key),
            ConfigDropdown(
              config: _config,
              path: 'gateway.tailscale.mode',
              title: 'Tailscale mode',
              options: const [
                ConfigOption('off', 'Off'),
                ConfigOption('serve', 'Serve'),
                ConfigOption('funnel', 'Funnel (public)'),
              ],
              defaultValue: 'off',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('HTTP API', icon: Icons.api),
            ConfigSwitch(
              config: _config,
              path: 'gateway.http.endpoints.chatCompletions.enabled',
              title: 'Chat Completions API',
              subtitle: 'OpenAI-compatible HTTP endpoint',
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
