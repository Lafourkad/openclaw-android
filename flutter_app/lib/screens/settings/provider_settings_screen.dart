import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/config_service.dart';
import '../../widgets/config_widgets.dart';

class ProviderSettingsScreen extends StatefulWidget {
  const ProviderSettingsScreen({super.key});

  @override
  State<ProviderSettingsScreen> createState() => _ProviderSettingsScreenState();
}

class _ProviderSettingsScreenState extends State<ProviderSettingsScreen> {
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
      builder: (context, _) {
        final providers = _getProviders();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Provider & Models'),
            actions: [_saveButton()],
          ),
          body: ListView(
            children: [
              const ConfigSectionHeader('Model Providers', icon: Icons.cloud),
              if (providers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No providers configured.'),
                ),
              for (final p in providers) _providerCard(p),
              const SizedBox(height: 16),

              const ConfigSectionHeader('Default Model', icon: Icons.star),
              ConfigTextField(
                config: _config,
                path: 'agents.defaults.model.primary',
                label: 'Primary model',
                hint: 'e.g. anthropic/claude-sonnet-4-6',
              ),
              ConfigTextField(
                config: _config,
                path: 'agents.defaults.imageModel.primary',
                label: 'Image model',
                hint: 'e.g. zai/glm-4.6v',
              ),
            ],
          ),
        );
      },
    );
  }

  List<String> _getProviders() {
    final providers = _config.get('models.providers');
    if (providers is Map) return providers.keys.cast<String>().toList();
    return [];
  }

  Widget _providerCard(String providerId) {
    final prefix = 'models.providers.$providerId';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text(providerId, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_config.getString('$prefix.baseUrl', 'No URL')),
        children: [
          ConfigTextField(config: _config, path: '$prefix.baseUrl', label: 'Base URL'),
          ConfigTextField(config: _config, path: '$prefix.apiKey', label: 'API Key', obscure: true),
          ConfigDropdown(
            config: _config,
            path: '$prefix.api',
            title: 'API Format',
            options: const [
              ConfigOption('', 'Auto'),
              ConfigOption('openai-completions', 'OpenAI'),
              ConfigOption('anthropic', 'Anthropic'),
              ConfigOption('google', 'Google'),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _saveButton() {
    return TextButton.icon(
      onPressed: () async {
        final ok = await _config.saveAndRestart();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? 'Saved & restarting gateway...' : 'Save failed')),
          );
        }
      },
      icon: const Icon(Icons.save),
      label: const Text('Save'),
    );
  }
}
