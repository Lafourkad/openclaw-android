import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'native_bridge.dart';

/// AI provider presets
class ProviderPreset {
  final String id;
  final String name;
  final String baseUrl;
  final String apiFormat;
  final bool needsApiKey;
  final List<ModelPreset> models;

  const ProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiFormat = 'openai-completions',
    this.needsApiKey = true,
    required this.models,
  });

  static const anthropic = ProviderPreset(
    id: 'anthropic',
    name: 'Anthropic (Claude)',
    baseUrl: 'https://api.anthropic.com',
    apiFormat: 'anthropic',
    models: [
      ModelPreset(id: 'claude-sonnet-4-20250514', name: 'Claude Sonnet 4', reasoning: true),
      ModelPreset(id: 'claude-haiku-3-20250414', name: 'Claude Haiku 3.5', reasoning: false),
    ],
  );

  static const openai = ProviderPreset(
    id: 'openai',
    name: 'OpenAI (GPT)',
    baseUrl: 'https://api.openai.com/v1',
    models: [
      ModelPreset(id: 'gpt-4o', name: 'GPT-4o', reasoning: false),
      ModelPreset(id: 'gpt-4o-mini', name: 'GPT-4o Mini', reasoning: false),
      ModelPreset(id: 'o3-mini', name: 'o3-mini', reasoning: true),
    ],
  );

  static const google = ProviderPreset(
    id: 'google',
    name: 'Google (Gemini)',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    apiFormat: 'google',
    models: [
      ModelPreset(id: 'gemini-2.5-flash', name: 'Gemini 2.5 Flash', reasoning: true),
      ModelPreset(id: 'gemini-2.5-pro', name: 'Gemini 2.5 Pro', reasoning: true),
    ],
  );

  static const zai = ProviderPreset(
    id: 'zai',
    name: 'ZAI (GLM — Free)',
    baseUrl: 'https://api.z.ai/api/coding/paas/v4',
    models: [
      ModelPreset(id: 'glm-5', name: 'GLM-5', reasoning: true),
      ModelPreset(id: 'glm-4.7', name: 'GLM-4.7', reasoning: true),
      ModelPreset(id: 'glm-4.7-flash', name: 'GLM-4.7 Flash', reasoning: true),
    ],
  );

  static const ollama = ProviderPreset(
    id: 'ollama',
    name: 'Ollama (Local)',
    baseUrl: 'http://localhost:11434',
    needsApiKey: false,
    models: [
      ModelPreset(id: 'qwen3:14b', name: 'Qwen 3 14B', reasoning: true),
      ModelPreset(id: 'llama3.1:8b', name: 'Llama 3.1 8B', reasoning: false),
    ],
  );

  static const all = [anthropic, openai, google, zai, ollama];
}

class ModelPreset {
  final String id;
  final String name;
  final bool reasoning;

  const ModelPreset({
    required this.id,
    required this.name,
    this.reasoning = false,
  });
}

/// Channel type
enum ChannelType { telegram, discord }

/// Holds user input from the wizard
class OnboardingConfig {
  // Provider
  ProviderPreset? provider;
  String apiKey = '';
  String customBaseUrl = '';
  String selectedModelId = '';

  // Channels
  bool enableTelegram = false;
  String telegramBotToken = '';
  String telegramUserId = '';

  bool enableDiscord = false;
  String discordBotToken = '';
  String discordApplicationId = '';
  String discordUserId = '';

  // Agent
  String agentName = 'assistant';
}

class ConfigGenerator {
  /// Generate a complete openclaw.json from wizard inputs.
  static Map<String, dynamic> generate(OnboardingConfig config) {
    final provider = config.provider!;
    final modelId = config.selectedModelId.isNotEmpty
        ? config.selectedModelId
        : provider.models.first.id;
    final providerModelRef = '${provider.id}/$modelId';

    final result = <String, dynamic>{
      'meta': {
        'lastTouchedVersion': '2026.3.2',
        'lastTouchedAt': DateTime.now().toUtc().toIso8601String(),
      },
    };

    // Auth
    if (provider.needsApiKey && config.apiKey.isNotEmpty) {
      result['auth'] = {
        'profiles': {
          '${provider.id}:default': {
            'provider': provider.id,
            'mode': 'api_key',
          },
        },
      };
    }

    // Models
    final baseUrl = config.customBaseUrl.isNotEmpty
        ? config.customBaseUrl
        : provider.baseUrl;

    final modelsConfig = <String, dynamic>{};
    for (final m in provider.models) {
      modelsConfig[m.id] = {
        'name': m.name,
        if (m.reasoning) 'reasoning': true,
        'input': ['text'],
        'contextWindow': 128000,
        'maxTokens': 32768,
      };
    }

    result['models'] = {
      'mode': 'merge',
      'providers': {
        provider.id: {
          'baseUrl': baseUrl,
          'api': provider.apiFormat,
          if (provider.needsApiKey && config.apiKey.isNotEmpty)
            'apiKey': config.apiKey,
          'models': modelsConfig.entries.map((e) {
            final m = Map<String, dynamic>.from(e.value as Map);
            m['id'] = e.key;
            return m;
          }).toList(),
        },
      },
    };

    // Agents
    result['agents'] = {
      'defaults': {
        'model': {'primary': providerModelRef},
        'compaction': {'mode': 'safeguard'},
        'blockStreamingDefault': 'off',
        'maxConcurrent': 4,
      },
      'list': [
        {
          'id': config.agentName,
          'name': config.agentName,
        },
      ],
    };

    // Bindings
    final bindings = <Map<String, dynamic>>[];
    if (config.enableTelegram) {
      bindings.add({
        'agentId': config.agentName,
        'match': {'channel': 'telegram'},
      });
    }
    if (config.enableDiscord) {
      bindings.add({
        'agentId': config.agentName,
        'match': {'channel': 'discord'},
      });
    }
    if (bindings.isEmpty) {
      // Default: bind to all
      bindings.add({'agentId': config.agentName});
    }
    result['bindings'] = bindings;

    // Tools
    final toolsConfig = <String, dynamic>{
      'exec': {
        'security': 'full',
        'ask': 'off',
      },
    };

    // Elevated permissions for the owner
    final elevatedAllowFrom = <String, dynamic>{};
    if (config.enableTelegram && config.telegramUserId.isNotEmpty) {
      elevatedAllowFrom['telegram'] = [
        int.tryParse(config.telegramUserId) ?? config.telegramUserId,
      ];
    }
    if (config.enableDiscord && config.discordUserId.isNotEmpty) {
      elevatedAllowFrom['discord'] = [config.discordUserId];
    }
    if (elevatedAllowFrom.isNotEmpty) {
      toolsConfig['elevated'] = {
        'enabled': true,
        'allowFrom': elevatedAllowFrom,
      };
    }
    result['tools'] = toolsConfig;

    // Channels
    final channels = <String, dynamic>{};

    if (config.enableTelegram && config.telegramBotToken.isNotEmpty) {
      final tgConfig = <String, dynamic>{
        'enabled': true,
        'botToken': config.telegramBotToken,
      };
      if (config.telegramUserId.isNotEmpty) {
        tgConfig['dmPolicy'] = 'allowlist';
        tgConfig['allowFrom'] = [
          int.tryParse(config.telegramUserId) ?? config.telegramUserId,
        ];
      } else {
        tgConfig['dmPolicy'] = 'pairing';
      }
      channels['telegram'] = tgConfig;
    }

    if (config.enableDiscord && config.discordBotToken.isNotEmpty) {
      final discordConfig = <String, dynamic>{
        'enabled': true,
        'botToken': config.discordBotToken,
      };
      if (config.discordUserId.isNotEmpty) {
        discordConfig['dm'] = {
          'policy': 'allowlist',
          'allowFrom': [config.discordUserId],
        };
      }
      discordConfig['groupPolicy'] = 'allowlist';
      discordConfig['groupAllowFrom'] = <String>[];
      channels['discord'] = discordConfig;
    }

    if (channels.isNotEmpty) {
      result['channels'] = channels;
    }

    // Messages
    result['messages'] = {
      'ackReactionScope': 'group-mentions',
    };

    // Session
    result['session'] = {
      'dmScope': 'per-channel-peer',
    };

    // Gateway
    result['gateway'] = {
      'port': 18789,
    };

    return result;
  }

  /// Write the config to disk and return the path.
  static Future<String> writeConfig(OnboardingConfig config) async {
    final filesDir = await NativeBridge.getFilesDir();
    final configDir = Directory('$filesDir/.openclaw');
    if (!configDir.existsSync()) configDir.createSync(recursive: true);

    final configPath = '${configDir.path}/openclaw.json';
    final json = generate(config);
    final encoder = const JsonEncoder.withIndent('  ');
    File(configPath).writeAsStringSync(encoder.convert(json));

    return configPath;
  }
}
