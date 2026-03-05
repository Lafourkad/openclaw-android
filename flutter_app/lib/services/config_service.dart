import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'native_bridge.dart';

/// Service to read/write openclaw.json config and restart the gateway.
/// Central point for all config mutations from the settings UI.
class ConfigService extends ChangeNotifier {
  Map<String, dynamic> _config = {};
  String? _configPath;
  bool _loading = false;
  String? _error;

  Map<String, dynamic> get config => _config;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasConfig => _config.isNotEmpty;

  /// Load the config from the device filesystem.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final filesDir = await NativeBridge.getFilesDir();
      _configPath = '$filesDir/.openclaw/openclaw.json';
      final file = File(_configPath!);

      if (file.existsSync()) {
        final raw = file.readAsStringSync();
        _config = json.decode(raw) as Map<String, dynamic>;
      } else {
        _config = {};
        _error = 'Config file not found';
      }
    } catch (e) {
      _error = 'Failed to load config: $e';
      _config = {};
    }

    _loading = false;
    notifyListeners();
  }

  /// Get a value at a dot-separated path (e.g. "channels.telegram.botToken").
  dynamic get(String path) {
    final parts = path.split('.');
    dynamic current = _config;
    for (final part in parts) {
      if (current is Map<String, dynamic>) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Get a string value with a default.
  String getString(String path, [String defaultValue = '']) {
    final v = get(path);
    return v?.toString() ?? defaultValue;
  }

  /// Get a bool value with a default.
  bool getBool(String path, [bool defaultValue = false]) {
    final v = get(path);
    if (v is bool) return v;
    if (v is String) return v == 'true';
    return defaultValue;
  }

  /// Get an int value with a default.
  int getInt(String path, [int defaultValue = 0]) {
    final v = get(path);
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? defaultValue;
    return defaultValue;
  }

  /// Get a list value.
  List<dynamic> getList(String path) {
    final v = get(path);
    if (v is List) return v;
    return [];
  }

  /// Set a value at a dot-separated path. Creates intermediate maps as needed.
  void set(String path, dynamic value) {
    final parts = path.split('.');
    Map<String, dynamic> current = _config;

    for (int i = 0; i < parts.length - 1; i++) {
      if (current[parts[i]] is! Map) {
        current[parts[i]] = <String, dynamic>{};
      }
      current = current[parts[i]] as Map<String, dynamic>;
    }

    current[parts.last] = value;
    notifyListeners();
  }

  /// Remove a value at a dot-separated path.
  void remove(String path) {
    final parts = path.split('.');
    Map<String, dynamic>? current = _config;

    for (int i = 0; i < parts.length - 1; i++) {
      if (current?[parts[i]] is Map) {
        current = current![parts[i]] as Map<String, dynamic>;
      } else {
        return; // Path doesn't exist
      }
    }

    current?.remove(parts.last);
    notifyListeners();
  }

  /// Save config to disk and restart the gateway.
  Future<bool> saveAndRestart() async {
    if (_configPath == null) return false;

    try {
      final file = File(_configPath!);
      final encoder = const JsonEncoder.withIndent('  ');
      file.writeAsStringSync(encoder.convert(_config));

      // Restart the gateway to pick up changes
      try {
        await NativeBridge.restartGateway();
      } catch (_) {
        // Gateway restart is best-effort
      }

      return true;
    } catch (e) {
      _error = 'Failed to save: $e';
      notifyListeners();
      return false;
    }
  }

  /// Save config to disk without restarting.
  Future<bool> save() async {
    if (_configPath == null) return false;

    try {
      final file = File(_configPath!);
      final encoder = const JsonEncoder.withIndent('  ');
      file.writeAsStringSync(encoder.convert(_config));
      return true;
    } catch (e) {
      _error = 'Failed to save: $e';
      notifyListeners();
      return false;
    }
  }

  /// Get the raw JSON string.
  String toJson() {
    return const JsonEncoder.withIndent('  ').convert(_config);
  }

  /// Replace the entire config from raw JSON.
  bool fromJson(String rawJson) {
    try {
      _config = json.decode(rawJson) as Map<String, dynamic>;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Invalid JSON: $e';
      notifyListeners();
      return false;
    }
  }
}
