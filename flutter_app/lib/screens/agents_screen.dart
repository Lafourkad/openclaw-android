import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../services/config_service.dart';
import '../services/native_bridge.dart';

/// Multi-agent management — add, edit, remove agents.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  List<Map<String, dynamic>> _agents = [];
  bool _loading = true;
  Map<String, dynamic> _config = {};
  String? _configPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final filesDir = await NativeBridge.getFilesDir();
    _configPath = '$filesDir/.openclaw/openclaw.json';
    final file = File(_configPath!);
    if (file.existsSync()) {
      _config = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final list = _config['agents']?['list'];
      if (list is List) {
        _agents = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_configPath == null) return;
    _config['agents'] ??= <String, dynamic>{};
    (_config['agents'] as Map<String, dynamic>)['list'] = _agents;
    File(_configPath!).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_config),
    );
  }

  void _addAgent() {
    _showAgentEditor(null);
  }

  void _editAgent(int index) {
    _showAgentEditor(index);
  }

  void _deleteAgent(int index) async {
    final agent = _agents[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${agent['name'] ?? agent['id']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _agents.removeAt(index));
    await _save();
  }

  void _showAgentEditor(int? index) {
    final isNew = index == null;
    final agent = isNew ? <String, dynamic>{} : Map<String, dynamic>.from(_agents[index!]);

    final idCtrl = TextEditingController(text: agent['id']?.toString() ?? '');
    final nameCtrl = TextEditingController(text: agent['name']?.toString() ?? '');
    final modelCtrl = TextEditingController(text: agent['model']?.toString() ?? '');
    final emojiCtrl = TextEditingController(text: agent['identity']?['emoji']?.toString() ?? '');
    final workspaceCtrl = TextEditingController(text: agent['workspace']?.toString() ?? '');
    bool isDefault = agent['default'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isNew ? 'Add Agent' : 'Edit Agent',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(labelText: 'Agent ID *', border: OutlineInputBorder(), isDense: true),
                enabled: isNew,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(labelText: 'Model', hintText: 'e.g. anthropic/claude-sonnet-4-6', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emojiCtrl,
                decoration: const InputDecoration(labelText: 'Emoji', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: workspaceCtrl,
                decoration: const InputDecoration(labelText: 'Workspace Path', border: OutlineInputBorder(), isDense: true),
              ),
              SwitchListTile(
                title: const Text('Default Agent'),
                value: isDefault,
                onChanged: (v) => setSheetState(() => isDefault = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (idCtrl.text.trim().isEmpty) return;

                    final newAgent = <String, dynamic>{
                      'id': idCtrl.text.trim(),
                    };
                    if (nameCtrl.text.isNotEmpty) newAgent['name'] = nameCtrl.text;
                    if (modelCtrl.text.isNotEmpty) newAgent['model'] = modelCtrl.text;
                    if (workspaceCtrl.text.isNotEmpty) newAgent['workspace'] = workspaceCtrl.text;
                    if (isDefault) newAgent['default'] = true;
                    if (emojiCtrl.text.isNotEmpty) {
                      newAgent['identity'] = {'emoji': emojiCtrl.text};
                    }

                    setState(() {
                      if (isNew) {
                        _agents.add(newAgent);
                      } else {
                        _agents[index!] = newAgent;
                      }
                    });
                    _save();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isNew ? 'Add' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _save();
              try { await NativeBridge.restartGateway(); } catch (_) {}
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved & restarting...')),
                );
              }
            },
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAgent,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _agents.isEmpty
              ? const Center(child: Text('No agents configured.\nTap + to add one.', textAlign: TextAlign.center))
              : ListView.builder(
                  itemCount: _agents.length,
                  itemBuilder: (context, index) => _buildAgentTile(index),
                ),
    );
  }

  Widget _buildAgentTile(int index) {
    final agent = _agents[index];
    final id = agent['id'] ?? 'unknown';
    final name = agent['name'] ?? id;
    final model = agent['model']?.toString() ?? 'default';
    final isDefault = agent['default'] == true;
    final emoji = agent['identity']?['emoji'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.accent.withOpacity(0.15),
          child: Text(emoji ?? '🤖', style: const TextStyle(fontSize: 20)),
        ),
        title: Row(
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (isDefault) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.statusGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('default', style: TextStyle(fontSize: 10, color: AppColors.statusGreen)),
              ),
            ],
          ],
        ),
        subtitle: Text('$id • $model', style: const TextStyle(fontSize: 12)),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') _editAgent(index);
            if (v == 'delete') _deleteAgent(index);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}
