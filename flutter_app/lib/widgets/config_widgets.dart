import 'package:flutter/material.dart';
import '../services/config_service.dart';

/// Toggle switch tied to a config path.
class ConfigSwitch extends StatelessWidget {
  final ConfigService config;
  final String path;
  final String title;
  final String? subtitle;
  final bool defaultValue;

  const ConfigSwitch({
    super.key,
    required this.config,
    required this.path,
    required this.title,
    this.subtitle,
    this.defaultValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: config.getBool(path, defaultValue),
      onChanged: (v) => config.set(path, v),
    );
  }
}

/// Text field tied to a config path.
class ConfigTextField extends StatelessWidget {
  final ConfigService config;
  final String path;
  final String label;
  final String? hint;
  final bool obscure;
  final int maxLines;
  final TextInputType? keyboardType;

  const ConfigTextField({
    super.key,
    required this.config,
    required this.path,
    required this.label,
    this.hint,
    this.obscure = false,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        initialValue: config.getString(path),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        obscureText: obscure,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: (v) => config.set(path, v.isEmpty ? null : v),
      ),
    );
  }
}

/// Dropdown tied to a config path with enum values.
class ConfigDropdown extends StatelessWidget {
  final ConfigService config;
  final String path;
  final String title;
  final String? subtitle;
  final List<ConfigOption> options;
  final String defaultValue;

  const ConfigDropdown({
    super.key,
    required this.config,
    required this.path,
    required this.title,
    this.subtitle,
    required this.options,
    this.defaultValue = '',
  });

  @override
  Widget build(BuildContext context) {
    final current = config.getString(path, defaultValue);
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: DropdownButton<String>(
        value: options.any((o) => o.value == current) ? current : defaultValue,
        underline: const SizedBox(),
        items: options.map((o) => DropdownMenuItem(
          value: o.value,
          child: Text(o.label),
        )).toList(),
        onChanged: (v) {
          if (v != null) config.set(path, v);
        },
      ),
    );
  }
}

class ConfigOption {
  final String value;
  final String label;
  const ConfigOption(this.value, this.label);
}

/// Number field tied to a config path.
class ConfigNumberField extends StatelessWidget {
  final ConfigService config;
  final String path;
  final String label;
  final String? hint;
  final int? min;
  final int? max;

  const ConfigNumberField({
    super.key,
    required this.config,
    required this.path,
    required this.label,
    this.hint,
    this.min,
    this.max,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        initialValue: config.getInt(path).toString(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        keyboardType: TextInputType.number,
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) config.set(path, n);
        },
      ),
    );
  }
}

/// Editable list of strings (e.g. allowFrom IDs).
class ConfigStringList extends StatefulWidget {
  final ConfigService config;
  final String path;
  final String title;
  final String addHint;

  const ConfigStringList({
    super.key,
    required this.config,
    required this.path,
    required this.title,
    this.addHint = 'Add item',
  });

  @override
  State<ConfigStringList> createState() => _ConfigStringListState();
}

class _ConfigStringListState extends State<ConfigStringList> {
  final _controller = TextEditingController();

  List<dynamic> get _items => widget.config.getList(widget.path);

  void _add() {
    final val = _controller.text.trim();
    if (val.isEmpty) return;
    final list = List<dynamic>.from(_items);
    // Try to parse as int (for user IDs)
    final asInt = int.tryParse(val);
    list.add(asInt ?? val);
    widget.config.set(widget.path, list);
    _controller.clear();
    setState(() {});
  }

  void _remove(int index) {
    final list = List<dynamic>.from(_items);
    list.removeAt(index);
    widget.config.set(widget.path, list);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (int i = 0; i < items.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(items[i].toString(),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _remove(i),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: widget.addHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _add,
                icon: const Icon(Icons.add_circle),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Section header for settings screens.
class ConfigSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;

  const ConfigSectionHeader(this.title, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
