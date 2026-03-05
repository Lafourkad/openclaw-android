import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/config_service.dart';
import '../../widgets/config_widgets.dart';

class ChannelsSettingsScreen extends StatefulWidget {
  const ChannelsSettingsScreen({super.key});

  @override
  State<ChannelsSettingsScreen> createState() => _ChannelsSettingsScreenState();
}

class _ChannelsSettingsScreenState extends State<ChannelsSettingsScreen> {
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
          title: const Text('Channels'),
          actions: [_saveButton()],
        ),
        body: ListView(
          children: [
            // === TELEGRAM ===
            const ConfigSectionHeader('Telegram', icon: Icons.send),
            ConfigSwitch(
              config: _config,
              path: 'channels.telegram.enabled',
              title: 'Enable Telegram',
              defaultValue: false,
            ),
            ConfigTextField(
              config: _config,
              path: 'channels.telegram.botToken',
              label: 'Bot Token',
              hint: 'From @BotFather',
              obscure: true,
            ),
            ConfigDropdown(
              config: _config,
              path: 'channels.telegram.dmPolicy',
              title: 'DM Policy',
              subtitle: 'Who can message your bot in DMs',
              options: const [
                ConfigOption('pairing', 'Pairing (code-based)'),
                ConfigOption('allowlist', 'Allowlist (specific users)'),
                ConfigOption('open', 'Open (anyone)'),
              ],
              defaultValue: 'pairing',
            ),
            ConfigStringList(
              config: _config,
              path: 'channels.telegram.allowFrom',
              title: 'Allowed User IDs',
              addHint: 'Telegram user ID',
            ),
            ConfigDropdown(
              config: _config,
              path: 'channels.telegram.groupPolicy',
              title: 'Group Policy',
              subtitle: 'How the bot behaves in groups',
              options: const [
                ConfigOption('allowlist', 'Allowlist (specific groups)'),
                ConfigOption('open', 'Open (all groups)'),
                ConfigOption('off', 'Disabled'),
              ],
              defaultValue: 'allowlist',
            ),
            ConfigStringList(
              config: _config,
              path: 'channels.telegram.groupAllowFrom',
              title: 'Allowed Group IDs',
              addHint: 'Group chat ID',
            ),
            ConfigDropdown(
              config: _config,
              path: 'channels.telegram.streaming',
              title: 'Streaming',
              subtitle: 'Live preview while generating',
              options: const [
                ConfigOption('off', 'Off'),
                ConfigOption('partial', 'Partial (draft preview)'),
              ],
              defaultValue: 'off',
            ),

            const Divider(height: 32),

            // === DISCORD ===
            const ConfigSectionHeader('Discord', icon: Icons.forum),
            ConfigSwitch(
              config: _config,
              path: 'channels.discord.enabled',
              title: 'Enable Discord',
              defaultValue: false,
            ),
            ConfigTextField(
              config: _config,
              path: 'channels.discord.botToken',
              label: 'Bot Token',
              hint: 'From Discord Developer Portal',
              obscure: true,
            ),
            ConfigDropdown(
              config: _config,
              path: 'channels.discord.groupPolicy',
              title: 'Group Policy',
              options: const [
                ConfigOption('allowlist', 'Allowlist'),
                ConfigOption('open', 'Open'),
                ConfigOption('off', 'Disabled'),
              ],
              defaultValue: 'allowlist',
            ),
            ConfigDropdown(
              config: _config,
              path: 'channels.discord.streaming',
              title: 'Streaming',
              options: const [
                ConfigOption('off', 'Off'),
                ConfigOption('partial', 'Partial'),
              ],
              defaultValue: 'off',
            ),

            const Divider(height: 32),

            // === WHATSAPP ===
            const ConfigSectionHeader('WhatsApp', icon: Icons.chat_bubble),
            ConfigSwitch(
              config: _config,
              path: 'channels.whatsapp.enabled',
              title: 'Enable WhatsApp',
              defaultValue: false,
            ),
            ConfigDropdown(
              config: _config,
              path: 'channels.whatsapp.dmPolicy',
              title: 'DM Policy',
              options: const [
                ConfigOption('allowlist', 'Allowlist'),
                ConfigOption('pairing', 'Pairing'),
                ConfigOption('open', 'Open'),
              ],
              defaultValue: 'allowlist',
            ),
            ConfigStringList(
              config: _config,
              path: 'channels.whatsapp.allowFrom',
              title: 'Allowed Phone Numbers',
              addHint: '+34123456789',
            ),
            ConfigSwitch(
              config: _config,
              path: 'channels.whatsapp.selfChatMode',
              title: 'Self-chat mode',
              subtitle: 'Use your own WhatsApp number to chat',
            ),
            ConfigNumberField(
              config: _config,
              path: 'channels.whatsapp.debounceMs',
              label: 'Debounce (ms)',
              hint: 'Delay before processing (0 = instant)',
            ),
            ConfigNumberField(
              config: _config,
              path: 'channels.whatsapp.mediaMaxMb',
              label: 'Max media size (MB)',
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
