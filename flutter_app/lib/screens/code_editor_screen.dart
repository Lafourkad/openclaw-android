import 'dart:io';
import 'package:flutter/material.dart';
import '../app.dart';

/// Simple code/text editor with save functionality.
class CodeEditorScreen extends StatefulWidget {
  final String filePath;
  const CodeEditorScreen({super.key, required this.filePath});

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late TextEditingController _controller;
  bool _hasChanges = false;
  bool _loading = true;
  String? _error;
  int _lineCount = 0;

  String get _fileName => widget.filePath.split('/').last;
  String get _ext => _fileName.contains('.') ? _fileName.split('.').last.toLowerCase() : '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final file = File(widget.filePath);
      if (!file.existsSync()) {
        setState(() { _error = 'File not found'; _loading = false; });
        return;
      }

      final stat = file.statSync();
      if (stat.size > 2 * 1024 * 1024) {
        setState(() { _error = 'File too large (${(stat.size / 1024 / 1024).toStringAsFixed(1)} MB)'; _loading = false; });
        return;
      }

      final content = file.readAsStringSync();
      _controller.text = content;
      _lineCount = content.split('\n').length;
      _controller.addListener(_onChanged);

      setState(() => _loading = false);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
    _lineCount = _controller.text.split('\n').length;
  }

  Future<void> _save() async {
    try {
      File(widget.filePath).writeAsStringSync(_controller.text);
      setState(() => _hasChanges = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved ✓'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save before leaving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'discard'), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (result == 'save') {
      await _save();
      return true;
    }
    return result == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final canLeave = await _onWillPop();
          if (canLeave && mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Flexible(
                child: Text(
                  _fileName,
                  style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_hasChanges)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('●', style: TextStyle(color: AppColors.statusAmber, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: _hasChanges ? _save : null,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.5,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ),
                      // Status bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        child: Row(
                          children: [
                            Text(
                              _ext.toUpperCase(),
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Text(
                              '$_lineCount lines',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _hasChanges ? 'Modified' : 'Saved',
                              style: TextStyle(
                                fontSize: 11,
                                color: _hasChanges ? AppColors.statusAmber : AppColors.statusGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }
}
