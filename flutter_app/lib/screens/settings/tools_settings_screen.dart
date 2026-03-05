import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/config_service.dart';
import '../../widgets/config_widgets.dart';

class ToolsSettingsScreen extends StatefulWidget {
  const ToolsSettingsScreen({super.key});

  @override
  State<ToolsSettingsScreen> createState() => _ToolsSettingsScreenState();
}

class _ToolsSettingsScreenState extends State<ToolsSettingsScreen> {
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
          title: const Text('Tools & Permissions'),
          actions: [_saveButton()],
        ),
        body: ListView(
          children: [
            const ConfigSectionHeader('Messaging', icon: Icons.message),
            ConfigSwitch(
              config: _config,
              path: 'tools.message.allowCrossContextSend',
              title: 'Cross-context messaging',
              subtitle: 'Allow sending messages across channels',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Agent-to-Agent', icon: Icons.swap_horiz),
            ConfigSwitch(
              config: _config,
              path: 'tools.agentToAgent.enabled',
              title: 'Agent-to-agent communication',
              subtitle: 'Allow agents to message each other',
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Browser', icon: Icons.web),
            ConfigSwitch(
              config: _config,
              path: 'browser.enabled',
              title: 'Enable browser control',
              subtitle: 'Allow agent to browse the web',
            ),
            ConfigSwitch(
              config: _config,
              path: 'browser.headless',
              title: 'Headless mode',
              subtitle: 'Run browser without visible window',
              defaultValue: true,
            ),

            const Divider(height: 32),

            const ConfigSectionHeader('Text-to-Speech', icon: Icons.record_voice_over),
            ConfigDropdown(
              config: _config,
              path: 'messages.tts.auto',
              title: 'Auto TTS',
              subtitle: 'Automatically read replies aloud',
              options: const [
                ConfigOption('off', 'Off'),
                ConfigOption('on', 'On'),
              ],
              defaultValue: 'off',
            ),
            ConfigDropdown(
              config: _config,
              path: 'messages.tts.provider',
              title: 'TTS Provider',
              options: const [
                ConfigOption('edge', 'Edge (free)'),
                ConfigOption('elevenlabs', 'ElevenLabs'),
                ConfigOption('openai', 'OpenAI'),
              ],
              defaultValue: 'edge',
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
