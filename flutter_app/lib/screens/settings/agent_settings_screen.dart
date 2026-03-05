import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/config_service.dart';
import '../../widgets/config_widgets.dart';

class AgentSettingsScreen extends StatefulWidget {
  const AgentSettingsScreen({super.key});

  @override
  State<AgentSettingsScreen> createState() => _AgentSettingsScreenState();
}

class _AgentSettingsScreenState extends State<AgentSettingsScreen> {
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
        final agents = _getAgents();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Agents'),
            actions: [_saveButton()],
          ),
          body: ListView(
            children: [
              const ConfigSectionHeader('Agent Defaults', icon: Icons.settings),
              ConfigTextField(
                config: _config,
                path: 'agents.defaults.workspace',
                label: 'Default workspace path',
              ),
              ConfigNumberField(
                config: _config,
                path: 'agents.defaults.maxConcurrent',
                label: 'Max concurrent requests',
              ),
              ConfigNumberField(
                config: _config,
                path: 'agents.defaults.contextTokens',
                label: 'Context window (tokens)',
              ),
              ConfigDropdown(
                config: _config,
                path: 'agents.defaults.compaction.mode',
                title: 'Compaction mode',
                options: const [
                  ConfigOption('safeguard', 'Safeguard (recommended)'),
                  ConfigOption('aggressive', 'Aggressive'),
                  ConfigOption('off', 'Off'),
                ],
                defaultValue: 'safeguard',
              ),
              ConfigTextField(
                config: _config,
                path: 'agents.defaults.heartbeat.every',
                label: 'Heartbeat interval',
                hint: 'e.g. 1h, 30m, off',
              ),

              const ConfigSectionHeader('Subagents', icon: Icons.group),
              ConfigNumberField(
                config: _config,
                path: 'agents.defaults.subagents.maxConcurrent',
                label: 'Max concurrent subagents',
              ),
              ConfigTextField(
                config: _config,
                path: 'agents.defaults.subagents.model',
                label: 'Subagent model',
                hint: 'e.g. ollama/qwen3:14b',
              ),

              const ConfigSectionHeader('Agent List', icon: Icons.smart_toy),
              for (int i = 0; i < agents.length; i++) _agentCard(i, agents[i]),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _getAgents() {
    final list = _config.get('agents.list');
    if (list is List) {
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Widget _agentCard(int index, Map<String, dynamic> agent) {
    final id = agent['id'] ?? 'agent-$index';
    final name = agent['name'] ?? id;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.smart_toy_outlined),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('ID: $id'),
        children: [
          ConfigTextField(
            config: _config,
            path: 'agents.list[$index].id',
            label: 'Agent ID',
          ),
          ConfigTextField(
            config: _config,
            path: 'agents.list[$index].name',
            label: 'Display name',
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
            SnackBar(content: Text(ok ? 'Saved & restarting...' : 'Save failed')),
          );
        }
      },
      icon: const Icon(Icons.save),
      label: const Text('Save'),
    );
  }
}
