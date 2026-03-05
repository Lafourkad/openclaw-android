import 'dart:convert';
import 'package:flutter/material.dart';
import '../../app.dart';
import '../../services/config_generator.dart';
import '../../services/native_bridge.dart';
import '../dashboard_screen.dart';

class SummaryStep extends StatefulWidget {
  final OnboardingConfig config;
  final VoidCallback onBack;

  const SummaryStep({super.key, required this.config, required this.onBack});

  @override
  State<SummaryStep> createState() => _SummaryStepState();
}

class _SummaryStepState extends State<SummaryStep> {
  final _agentNameController = TextEditingController();
  bool _launching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _agentNameController.text = widget.config.agentName;
  }

  @override
  void dispose() {
    _agentNameController.dispose();
    super.dispose();
  }

  Future<void> _launchGateway() async {
    setState(() {
      _launching = true;
      _error = null;
    });

    try {
      // Write config
      widget.config.agentName = _agentNameController.text.isNotEmpty
          ? _agentNameController.text
          : 'assistant';

      final configPath = await ConfigGenerator.writeConfig(widget.config);

      // Start gateway
      await NativeBridge.startGateway();

      // Wait a moment for gateway to boot
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _launching = false;
        _error = 'Failed to start: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = widget.config;
    final provider = config.provider!;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Almost Done!',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Review your setup and launch.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Agent name
        TextField(
          controller: _agentNameController,
          decoration: const InputDecoration(
            labelText: 'Agent Name',
            hintText: 'assistant',
            border: OutlineInputBorder(),
            helperText: 'Give your agent a name',
          ),
          onChanged: (val) => widget.config.agentName = val,
        ),

        const SizedBox(height: 24),

        // Summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configuration Summary',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                const Divider(),
                _summaryRow(theme, 'Provider', provider.name),
                _summaryRow(theme, 'Model',
                    config.selectedModelId.isNotEmpty
                        ? config.selectedModelId
                        : provider.models.first.id),
                _summaryRow(theme, 'API Key',
                    provider.needsApiKey
                        ? (config.apiKey.isNotEmpty ? '••••${config.apiKey.substring(config.apiKey.length - 4)}' : 'Not set')
                        : 'Not needed'),
                if (config.enableTelegram) ...[
                  const Divider(),
                  _summaryRow(theme, 'Telegram', '✅ Enabled'),
                  _summaryRow(theme, 'Bot Token',
                      config.telegramBotToken.isNotEmpty
                          ? '••••${config.telegramBotToken.substring(config.telegramBotToken.length - 6)}'
                          : 'Not set'),
                  if (config.telegramUserId.isNotEmpty)
                    _summaryRow(theme, 'Admin ID', config.telegramUserId),
                ],
                if (config.enableDiscord) ...[
                  const Divider(),
                  _summaryRow(theme, 'Discord', '✅ Enabled'),
                  _summaryRow(theme, 'Bot Token',
                      config.discordBotToken.isNotEmpty
                          ? '••••${config.discordBotToken.substring(config.discordBotToken.length - 6)}'
                          : 'Not set'),
                  if (config.discordUserId.isNotEmpty)
                    _summaryRow(theme, 'Admin ID', config.discordUserId),
                ],
              ],
            ),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
          ),
        ],

        const SizedBox(height: 32),

        // Navigation
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _launching ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _launching ? null : _launchGateway,
              icon: _launching
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.rocket_launch),
              label: Text(_launching ? 'Starting...' : 'Launch Gateway'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
