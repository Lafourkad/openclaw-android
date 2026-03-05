import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../services/config_generator.dart';

class ProviderStep extends StatefulWidget {
  final OnboardingConfig config;
  final VoidCallback onNext;

  const ProviderStep({super.key, required this.config, required this.onNext});

  @override
  State<ProviderStep> createState() => _ProviderStepState();
}

class _ProviderStepState extends State<ProviderStep> {
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _showApiKey = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController.text = widget.config.apiKey;
    _baseUrlController.text = widget.config.customBaseUrl;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final provider = widget.config.provider;
    if (provider == null) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);

      final baseUrl = _baseUrlController.text.isNotEmpty
          ? _baseUrlController.text
          : provider.baseUrl;
      final apiKey = _apiKeyController.text;

      Response response;

      if (provider.apiFormat == 'anthropic') {
        response = await dio.get(
          'https://api.anthropic.com/v1/models',
          options: Options(headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          }),
        );
      } else if (provider.apiFormat == 'google') {
        response = await dio.get(
          '$baseUrl/models?key=$apiKey',
        );
      } else {
        // OpenAI-compatible
        response = await dio.get(
          '$baseUrl/models',
          options: Options(headers: {
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          }),
        );
      }

      setState(() {
        _testing = false;
        _testSuccess = response.statusCode == 200;
        _testResult = _testSuccess ? 'Connection successful!' : 'Error: ${response.statusCode}';
      });
    } on DioException catch (e) {
      setState(() {
        _testing = false;
        _testSuccess = false;
        _testResult = 'Connection failed: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _testing = false;
        _testSuccess = false;
        _testResult = 'Error: $e';
      });
    }
  }

  bool get _canProceed {
    if (widget.config.provider == null) return false;
    if (widget.config.provider!.needsApiKey && _apiKeyController.text.isEmpty) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'AI Provider',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose which AI model will power your agent.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Provider cards
        for (final preset in ProviderPreset.all)
          _buildProviderCard(theme, preset),

        // API Key
        if (widget.config.provider != null) ...[
          const SizedBox(height: 24),
          if (widget.config.provider!.needsApiKey) ...[
            TextField(
              controller: _apiKeyController,
              obscureText: !_showApiKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'Enter your ${widget.config.provider!.name} API key',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showApiKey = !_showApiKey),
                    ),
                  ],
                ),
              ),
              onChanged: (val) {
                widget.config.apiKey = val;
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
          ],

          // Custom base URL (collapsed)
          ExpansionTile(
            title: const Text('Advanced'),
            children: [
              TextField(
                controller: _baseUrlController,
                decoration: InputDecoration(
                  labelText: 'Custom Base URL',
                  hintText: widget.config.provider!.baseUrl,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (val) => widget.config.customBaseUrl = val,
              ),
              const SizedBox(height: 12),
            ],
          ),

          // Model selection
          const SizedBox(height: 16),
          Text('Model', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: widget.config.selectedModelId.isNotEmpty
                ? widget.config.selectedModelId
                : widget.config.provider!.models.first.id,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: widget.config.provider!.models.map((m) {
              return DropdownMenuItem(value: m.id, child: Text(m.name));
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => widget.config.selectedModelId = val);
              }
            },
          ),

          // Test connection
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_find),
            label: Text(_testing ? 'Testing...' : 'Test Connection'),
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Text(
              _testResult!,
              style: TextStyle(
                color: _testSuccess ? Colors.green : theme.colorScheme.error,
              ),
            ),
          ],

          // Next
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canProceed ? widget.onNext : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProviderCard(ThemeData theme, ProviderPreset preset) {
    final selected = widget.config.provider?.id == preset.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            widget.config.provider = preset;
            widget.config.selectedModelId = preset.models.first.id;
            _testResult = null;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Radio<String>(
                value: preset.id,
                groupValue: widget.config.provider?.id,
                onChanged: (_) {
                  setState(() {
                    widget.config.provider = preset;
                    widget.config.selectedModelId = preset.models.first.id;
                    _testResult = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      preset.needsApiKey ? 'Requires API key' : 'No API key needed',
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
      ),
    );
  }
}
