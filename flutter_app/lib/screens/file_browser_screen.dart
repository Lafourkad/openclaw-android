import 'dart:io';
import 'package:flutter/material.dart';
import '../app.dart';
import '../services/native_bridge.dart';
import 'code_editor_screen.dart';

/// File browser — navigate workspace, open files in editor.
class FileBrowserScreen extends StatefulWidget {
  final String? initialPath;
  const FileBrowserScreen({super.key, this.initialPath});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  String _currentPath = '';
  List<FileSystemEntity> _entries = [];
  bool _loading = true;
  String? _error;
  bool _showHidden = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.initialPath != null) {
      _currentPath = widget.initialPath!;
    } else {
      final filesDir = await NativeBridge.getFilesDir();
      _currentPath = '$filesDir/.openclaw/workspace';
    }
    _loadDir();
  }

  Future<void> _loadDir() async {
    setState(() { _loading = true; _error = null; });

    try {
      final dir = Directory(_currentPath);
      if (!dir.existsSync()) {
        setState(() { _error = 'Directory not found'; _loading = false; });
        return;
      }

      final entries = dir.listSync()
        ..sort((a, b) {
          // Dirs first, then files, alphabetical
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.split('/').last.toLowerCase()
              .compareTo(b.path.split('/').last.toLowerCase());
        });

      setState(() {
        _entries = _showHidden
            ? entries
            : entries.where((e) => !e.path.split('/').last.startsWith('.')).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _navigate(String path) {
    setState(() => _currentPath = path);
    _loadDir();
  }

  void _goUp() {
    final parent = Directory(_currentPath).parent.path;
    _navigate(parent);
  }

  String get _displayPath {
    // Shorten for display
    final parts = _currentPath.split('/');
    if (parts.length > 4) {
      return '.../${parts.sublist(parts.length - 3).join('/')}';
    }
    return _currentPath;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_displayPath, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
        actions: [
          IconButton(
            icon: Icon(_showHidden ? Icons.visibility : Icons.visibility_off, size: 20),
            onPressed: () {
              setState(() => _showHidden = !_showHidden);
              _loadDir();
            },
            tooltip: _showHidden ? 'Hide dotfiles' : 'Show dotfiles',
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder, size: 20),
            onPressed: _createFolder,
            tooltip: 'New folder',
          ),
          IconButton(
            icon: const Icon(Icons.note_add, size: 20),
            onPressed: _createFile,
            tooltip: 'New file',
          ),
        ],
      ),
      body: Column(
        children: [
          // Navigation bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 20),
                  onPressed: _goUp,
                  tooltip: 'Parent directory',
                ),
                IconButton(
                  icon: const Icon(Icons.home, size: 20),
                  onPressed: () async {
                    final filesDir = await NativeBridge.getFilesDir();
                    _navigate('$filesDir/.openclaw/workspace');
                  },
                  tooltip: 'Workspace root',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadDir,
                ),
                const Spacer(),
                Text(
                  '${_entries.length} items',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // File list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : _entries.isEmpty
                        ? const Center(child: Text('Empty directory'))
                        : ListView.builder(
                            itemCount: _entries.length,
                            itemBuilder: (context, index) => _buildEntry(_entries[index]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(FileSystemEntity entity) {
    final name = entity.path.split('/').last;
    final isDir = entity is Directory;
    final isFile = entity is File;

    IconData icon;
    Color color;

    if (isDir) {
      icon = Icons.folder;
      color = Colors.amber;
    } else {
      final ext = name.split('.').last.toLowerCase();
      switch (ext) {
        case 'dart': icon = Icons.code; color = Colors.blue;
        case 'js' || 'ts' || 'mjs': icon = Icons.javascript; color = Colors.yellow;
        case 'json': icon = Icons.data_object; color = Colors.orange;
        case 'md': icon = Icons.description; color = Colors.grey;
        case 'py': icon = Icons.code; color = Colors.green;
        case 'sh' || 'bash': icon = Icons.terminal; color = Colors.teal;
        case 'yaml' || 'yml': icon = Icons.settings; color = Colors.purple;
        case 'txt' || 'log': icon = Icons.article; color = Colors.blueGrey;
        case 'png' || 'jpg' || 'jpeg' || 'gif' || 'webp':
          icon = Icons.image; color = Colors.pink;
        case 'tar' || 'gz' || 'zip' || 'tgz':
          icon = Icons.folder_zip; color = Colors.brown;
        default: icon = Icons.insert_drive_file; color = Colors.grey;
      }
    }

    String? subtitle;
    if (isFile) {
      try {
        final stat = (entity as File).statSync();
        final size = stat.size;
        subtitle = size < 1024
            ? '$size B'
            : size < 1024 * 1024
                ? '${(size / 1024).toStringAsFixed(1)} KB'
                : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      } catch (_) {}
    }

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
      trailing: isDir ? const Icon(Icons.chevron_right, size: 18) : null,
      onTap: () {
        if (isDir) {
          _navigate(entity.path);
        } else if (isFile) {
          _openFile(entity.path, name);
        }
      },
      onLongPress: () => _showContextMenu(entity),
    );
  }

  void _openFile(String path, String name) {
    // Check if it's a text file we can edit
    final ext = name.split('.').last.toLowerCase();
    const textExts = {'dart', 'js', 'ts', 'mjs', 'json', 'md', 'py', 'sh', 'bash',
      'yaml', 'yml', 'txt', 'log', 'toml', 'cfg', 'ini', 'env', 'html', 'css',
      'xml', 'svg', 'kt', 'java', 'c', 'h', 'cpp', 'rs', 'go', 'rb', 'lua',
      'sql', 'csv', 'conf', 'properties', 'gitignore', 'dockerignore',
      'makefile', 'dockerfile'};

    final isText = textExts.contains(ext) ||
        name == 'Makefile' || name == 'Dockerfile' ||
        name.startsWith('.') && !name.contains('.tar') && !name.contains('.gz');

    if (isText) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CodeEditorScreen(filePath: path)),
      ).then((_) => _loadDir()); // Refresh on return
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot edit binary file: $name')),
      );
    }
  }

  void _showContextMenu(FileSystemEntity entity) {
    final name = entity.path.split('/').last;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(name),
              subtitle: Text(entity.path, style: const TextStyle(fontSize: 11)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('Delete $name?'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  try {
                    if (entity is Directory) {
                      entity.deleteSync(recursive: true);
                    } else {
                      entity.deleteSync();
                    }
                    _loadDir();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Delete failed: $e')),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFolder() async {
    final name = await _showNameDialog('New Folder');
    if (name == null || name.isEmpty) return;
    try {
      Directory('$_currentPath/$name').createSync();
      _loadDir();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _createFile() async {
    final name = await _showNameDialog('New File');
    if (name == null || name.isEmpty) return;
    try {
      File('$_currentPath/$name').writeAsStringSync('');
      _loadDir();
      // Open in editor
      _openFile('$_currentPath/$name', name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<String?> _showNameDialog(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
