import 'dart:convert';
import 'dart:io';
import '../models/ai_provider.dart';
import 'native_bridge.dart';

/// Reads and writes AI provider configuration in openclaw.json.
class ProviderConfigService {
  static String? _filesDir;

  static Future<String> _getConfigPath() async {
    _filesDir ??= await NativeBridge.getFilesDir();
    return '$_filesDir/.openclaw/openclaw.json';
  }

  /// Read the current config and return a map with:
  /// - `activeModel`: the current primary model string (or null)
  /// - `providers`: Map<providerId, {apiKey, model}> for configured providers
  static Future<Map<String, dynamic>> readConfig() async {
    try {
      final path = await _getConfigPath();
      final file = File(path);
      if (!file.existsSync()) {
        return {'activeModel': null, 'providers': <String, dynamic>{}};
      }
      final content = file.readAsStringSync();
      if (content.isEmpty) {
        return {'activeModel': null, 'providers': <String, dynamic>{}};
      }
      final config = jsonDecode(content) as Map<String, dynamic>;

      // Extract active model
      String? activeModel;
      final agents = config['agents'] as Map<String, dynamic>?;
      if (agents != null) {
        final defaults = agents['defaults'] as Map<String, dynamic>?;
        if (defaults != null) {
          final model = defaults['model'] as Map<String, dynamic>?;
          if (model != null) {
            activeModel = model['primary'] as String?;
          }
        }
      }

      // Extract configured providers
      final providers = <String, dynamic>{};
      final modelsSection = config['models'] as Map<String, dynamic>?;
      if (modelsSection != null) {
        final providerEntries = modelsSection['providers'] as Map<String, dynamic>?;
        if (providerEntries != null) {
          for (final entry in providerEntries.entries) {
            providers[entry.key] = entry.value;
          }
        }
      }

      return {'activeModel': activeModel, 'providers': providers};
    } catch (_) {
      return {'activeModel': null, 'providers': <String, dynamic>{}};
    }
  }

  /// Save a provider's API key and set its model as the active model.
  static Future<void> saveProviderConfig({
    required AiProvider provider,
    required String apiKey,
    required String model,
  }) async {
    final providerJson = jsonEncode({
      'apiKey': apiKey,
      'baseUrl': provider.baseUrl,
    });
    final modelJson = jsonEncode(model);
    final providerIdJson = jsonEncode(provider.id);

    final script = '''
const fs = require("fs");
const p = process.env.HOME + "/.openclaw/openclaw.json";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
if (!c.models) c.models = {};
if (!c.models.providers) c.models.providers = {};
c.models.providers[$providerIdJson] = $providerJson;
if (!c.agents) c.agents = {};
if (!c.agents.defaults) c.agents.defaults = {};
if (!c.agents.defaults.model) c.agents.defaults.model = {};
c.agents.defaults.model.primary = $modelJson;
fs.mkdirSync(require("path").dirname(p), { recursive: true });
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';
    try {
      await NativeBridge.runNode(['-e', script], timeout: 15);
    } catch (_) {
      // Fallback: write config directly via dart:io
      await _saveConfigDirect(
        providerId: provider.id,
        apiKey: apiKey,
        baseUrl: provider.baseUrl,
        model: model,
      );
    }
  }

  /// Direct file-write fallback that doesn't depend on runNode.
  static Future<void> _saveConfigDirect({
    required String providerId,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final path = await _getConfigPath();
    Map<String, dynamic> config = {};
    try {
      final file = File(path);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.isNotEmpty) {
          config = jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (_) {}

    // Merge provider entry
    config['models'] ??= <String, dynamic>{};
    (config['models'] as Map<String, dynamic>)['providers'] ??= <String, dynamic>{};
    ((config['models'] as Map<String, dynamic>)['providers'] as Map<String, dynamic>)[providerId] = {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
    };

    // Set active model
    config['agents'] ??= <String, dynamic>{};
    (config['agents'] as Map<String, dynamic>)['defaults'] ??= <String, dynamic>{};
    ((config['agents'] as Map<String, dynamic>)['defaults'] as Map<String, dynamic>)['model'] ??= <String, dynamic>{};
    (((config['agents'] as Map<String, dynamic>)['defaults'] as Map<String, dynamic>)['model'] as Map<String, dynamic>)['primary'] = model;

    const encoder = JsonEncoder.withIndent('  ');
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encoder.convert(config));
  }

  /// Remove a provider's config entry and clear the active model if it
  /// belonged to this provider.
  static Future<void> removeProviderConfig({
    required AiProvider provider,
  }) async {
    final providerIdJson = jsonEncode(provider.id);
    final modelsJson = jsonEncode(provider.defaultModels);

    final script = '''
const fs = require("fs");
const p = process.env.HOME + "/.openclaw/openclaw.json";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
if (c.models && c.models.providers) {
  delete c.models.providers[$providerIdJson];
}
const known = $modelsJson;
if (c.agents && c.agents.defaults && c.agents.defaults.model) {
  const cur = c.agents.defaults.model.primary;
  if (cur && known.some(m => cur.includes(m))) {
    delete c.agents.defaults.model.primary;
  }
}
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';
    await NativeBridge.runNode(['-e', script], timeout: 15);
  }
}
