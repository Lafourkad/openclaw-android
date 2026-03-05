import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/config_service.dart';

/// Raw JSON editor for openclaw.json — power user escape hatch.
class RawConfigScreen extends StatefulWidget {
  const RawConfigScreen({super.key});

  @override
  State<RawConfigScreen> createState() => _RawConfigScreenState();
}

class _RawConfigScreenState extends State<RawConfigScreen> {
  late ConfigService _config;
  late TextEditingController _controller;
  bool _hasChanges = false;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _config = context.read<ConfigService>();
    _controller = TextEditingController(text: _config.toJson());
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {
      _hasChanges = true;
      _parseError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raw JSON'),
        actions: [
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _controller.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
          ),
          TextButton.icon(
            onPressed: _hasChanges ? _save : null,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_parseError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.withOpacity(0.1),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _parseError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final valid = _config.fromJson(_controller.text);
    if (!valid) {
      setState(() => _parseError = _config.error ?? 'Invalid JSON');
      return;
    }

    final ok = await _config.saveAndRestart();
    if (mounted) {
      if (ok) {
        setState(() {
          _hasChanges = false;
          _parseError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved & restarting gateway...')),
        );
      } else {
        setState(() => _parseError = _config.error);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }
}
