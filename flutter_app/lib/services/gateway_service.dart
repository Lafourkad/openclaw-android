import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models/gateway_state.dart';
import 'native_bridge.dart';
import 'preferences_service.dart';

class GatewayService {
  Timer? _healthTimer;
  StreamSubscription? _logSubscription;
  final _stateController = StreamController<GatewayState>.broadcast();
  GatewayState _state = const GatewayState();
  static final _tokenUrlRegex = RegExp(r'https?://(?:localhost|127\.0\.0\.1):18789/#token=[0-9a-zA-Z_\-]+');
  static final _boxDrawing = RegExp(r'[│┤├┬┴┼╮╯╰╭─╌╴╶┌┐└┘◇◆]+');

  /// Strip ANSI, box-drawing chars, and whitespace to reconstruct URLs
  /// split by terminal line wrapping or TUI borders.
  static String _cleanForUrl(String text) {
    return text
        .replaceAll(AppConstants.ansiEscape, '')
        .replaceAll(_boxDrawing, '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  Stream<GatewayState> get stateStream => _stateController.stream;
  GatewayState get state => _state;

  void _updateState(GatewayState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  /// Check if the gateway is already running (e.g. after app restart)
  /// and sync the UI state accordingly.  If not running but auto-start
  /// is enabled, start it automatically.
  Future<void> init() async {
    final prefs = PreferencesService();
    await prefs.init();
    final savedUrl = prefs.dashboardUrl;

    // Ensure directories exist on app open.
    try { await NativeBridge.setupDirs(); } catch (_) {}

    // Check if gateway is reachable via HTTP first (most reliable)
    final httpHealthy = await checkHealth();
    final processRunning = await NativeBridge.isGatewayRunning();

    if (httpHealthy || processRunning) {
      await _writeNodeAllowConfig();
      _updateState(_state.copyWith(
        status: httpHealthy ? GatewayStatus.running : GatewayStatus.starting,
        dashboardUrl: savedUrl,
        logs: [..._state.logs, '[INFO] Gateway ${httpHealthy ? "is running" : "process detected, reconnecting"}...'],
      ));

      _subscribeLogs();
      _startHealthCheck();
    } else if (prefs.autoStartGateway) {
      _updateState(_state.copyWith(
        logs: [..._state.logs, '[INFO] Auto-starting gateway...'],
      ));
      await start();
    }
  }

  void _subscribeLogs() {
    _logSubscription?.cancel();
    _logSubscription = NativeBridge.gatewayLogStream.listen((log) {
      final logs = [..._state.logs, log];
      if (logs.length > 500) {
        logs.removeRange(0, logs.length - 500);
      }
      String? dashboardUrl;
      final cleanLog = _cleanForUrl(log);
      final urlMatch = _tokenUrlRegex.firstMatch(cleanLog);
      if (urlMatch != null) {
        dashboardUrl = urlMatch.group(0);
        final prefs = PreferencesService();
        prefs.init().then((_) => prefs.dashboardUrl = dashboardUrl);
      }
      _updateState(_state.copyWith(logs: logs, dashboardUrl: dashboardUrl));
    });
  }

  /// Patch the openclaw config to clear denyCommands and set allowCommands
  /// for all node capabilities.
  Future<void> _autoSaveGatewayToken() async {
    // Wait a bit for the gateway to write its config
    await Future.delayed(const Duration(seconds: 5));
    try {
      final token = await NativeBridge.readGatewayToken();
      if (token.isNotEmpty) {
        final prefs = PreferencesService();
        await prefs.init();
        // Always overwrite — token changes on every fresh install
        prefs.nodeGatewayToken = token;
        _updateState(_state.copyWith(
          logs: [..._state.logs, '[INFO] Gateway token updated'],
        ));
      }

      // Debug: dump config keys to logcat
      await NativeBridge.debugConfigKeys();

      // Read dashboard URL with Control UI token from config
      final dashboardUrl = await NativeBridge.readDashboardUrl();
      if (dashboardUrl.isNotEmpty) {
        final prefs = PreferencesService();
        await prefs.init();
        prefs.dashboardUrl = dashboardUrl;
        _updateState(_state.copyWith(dashboardUrl: dashboardUrl));
      }
    } catch (_) {}
  }

  Future<void> _writeNodeAllowConfig() async {
    const allowCommands = [
      'camera.snap', 'camera.clip', 'camera.list',
      'canvas.navigate', 'canvas.eval', 'canvas.snapshot',
      'flash.on', 'flash.off', 'flash.toggle', 'flash.status',
      'location.get',
      'screen.record',
      'sensor.read', 'sensor.list',
      'haptic.vibrate',
    ];
    final allowJson = jsonEncode(allowCommands);
    final script = '''
const fs = require("fs");
const p = process.env.HOME + "/.openclaw/openclaw.json";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
if (!c.gateway) c.gateway = {};
if (!c.gateway.nodes) c.gateway.nodes = {};
c.gateway.nodes.denyCommands = [];
c.gateway.nodes.allowCommands = $allowJson;
// Set gateway.mode=local if not already set
if (!c.gateway.mode) c.gateway.mode = "local";
// Migrate legacy agent.* → agents.defaults.*
if (c.agent) { if (!c.agents) c.agents = {}; if (!c.agents.defaults) c.agents.defaults = {}; Object.assign(c.agents.defaults, c.agent); delete c.agent; }
// Detect available providers
const zaiCfg = c.models && c.models.providers && c.models.providers.zai;
const hasZai = zaiCfg && zaiCfg.apiKey;
const groqCfg = c.models && c.models.providers && c.models.providers.groq;
const hasGroq = groqCfg && groqCfg.apiKey;
// Set default model if not set
if (!c.agents) c.agents = {};
if (!c.agents.defaults) c.agents.defaults = {};
if (!c.agents.defaults.model) {
  if (hasZai) c.agents.defaults.model = "zai/glm-4.7";
  else if (hasGroq) c.agents.defaults.model = "groq/llama-3.3-70b-versatile";
}
fs.writeFileSync(p, JSON.stringify(c, null, 2));
// Write auth-profiles.json for the main agent so it can authenticate API calls
const agentDir = process.env.HOME + "/.openclaw/agents/main/agent";
fs.mkdirSync(agentDir, { recursive: true });
const authFile = agentDir + "/auth-profiles.json";
let auth = {};
try { auth = JSON.parse(fs.readFileSync(authFile, "utf8")); } catch {}
if (hasZai && !auth["zai:default"]) {
  auth["zai:default"] = { provider: "zai", mode: "api_key", apiKey: zaiCfg.apiKey };
}
if (hasGroq && !auth["groq:default"]) {
  auth["groq:default"] = { provider: "groq", mode: "api_key", apiKey: groqCfg.apiKey };
}
// Also check env vars as fallback
const envZai = process.env.ZAI_API_KEY;
const envGroq = process.env.GROQ_API_KEY;
if (envZai && !auth["zai:default"]) auth["zai:default"] = { provider: "zai", mode: "api_key", apiKey: envZai };
if (envGroq && !auth["groq:default"]) auth["groq:default"] = { provider: "groq", mode: "api_key", apiKey: envGroq };
fs.writeFileSync(authFile, JSON.stringify(auth, null, 2));
''';
    try {
      await NativeBridge.runNode(['-e', script], timeout: 15);
    } catch (_) {
      // Non-fatal: gateway may still work with default policy
    }
  }

  Future<void> start() async {
    final prefs = PreferencesService();
    await prefs.init();
    final savedUrl = prefs.dashboardUrl;

    _updateState(_state.copyWith(
      status: GatewayStatus.starting,
      clearError: true,
      logs: [..._state.logs, '[INFO] Starting gateway...'],
      dashboardUrl: savedUrl,
    ));

    try {
      // Ensure directories exist — Android may have cleared them.
      try { await NativeBridge.setupDirs(); } catch (_) {}
      await _writeNodeAllowConfig();
      await NativeBridge.startGateway();
      _subscribeLogs();
      _startHealthCheck();
      // After gateway starts, read the auto-generated token and save to prefs
      // so the Voice screen can connect without manual token entry
      _autoSaveGatewayToken();
    } catch (e) {
      _updateState(_state.copyWith(
        status: GatewayStatus.error,
        errorMessage: 'Failed to start: $e',
        logs: [..._state.logs, '[ERROR] Failed to start: $e'],
      ));
    }
  }

  Future<void> stop() async {
    _healthTimer?.cancel();
    _logSubscription?.cancel();

    try {
      await NativeBridge.stopGateway();
      _updateState(GatewayState(
        status: GatewayStatus.stopped,
        logs: [..._state.logs, '[INFO] Gateway stopped'],
      ));
    } catch (e) {
      _updateState(_state.copyWith(
        status: GatewayStatus.error,
        errorMessage: 'Failed to stop: $e',
      ));
    }
  }

  void _startHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.healthCheckIntervalMs),
      (_) => _checkHealth(),
    );
  }

  Future<void> _checkHealth() async {
    try {
      final response = await http
          .head(Uri.parse(AppConstants.gatewayUrl))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode < 500 && _state.status != GatewayStatus.running) {
        _updateState(_state.copyWith(
          status: GatewayStatus.running,
          startedAt: DateTime.now(),
          logs: [..._state.logs, '[INFO] Gateway is healthy'],
        ));
      }
    } catch (_) {
      final isRunning = await NativeBridge.isGatewayRunning();
      if (!isRunning && _state.status != GatewayStatus.stopped) {
        _updateState(_state.copyWith(
          status: GatewayStatus.stopped,
          logs: [..._state.logs, '[WARN] Gateway process not running'],
        ));
        _healthTimer?.cancel();
      }
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http
          .head(Uri.parse(AppConstants.gatewayUrl))
          .timeout(const Duration(seconds: 3));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _healthTimer?.cancel();
    _logSubscription?.cancel();
    _stateController.close();
  }
}
