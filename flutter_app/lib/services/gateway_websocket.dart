import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// WebSocket JSON-RPC client for the OpenClaw gateway.
/// Uses the same protocol as the web Control UI dashboard.
class GatewayWebSocket {
  // operator role + valid token = device identity not required
  static const String clientId = 'openclaw-android';
  static const String clientVersion = '2.0.0';
  static const String clientMode = 'ui';

  final String host;
  final int port;
  final String? token;
  final String sessionKey;

  WebSocket? _ws;
  bool _closed = false;
  bool _connected = false;
  bool _everConnected = false;
  int _backoffMs = 1500;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  final Map<String, Completer<dynamic>> _pending = {};
  final _eventController = StreamController<GatewayEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// Stream of all gateway events (chat deltas, agent events, etc.)
  Stream<GatewayEvent> get events => _eventController.stream;

  /// Stream of connection state changes.
  Stream<bool> get connectionState => _connectionController.stream;

  bool get connected => _connected;

  GatewayWebSocket({
    this.host = '127.0.0.1',
    this.port = 18789,
    this.token,
    this.sessionKey = 'agent:main:main',
  });

  /// Connect to the gateway WebSocket.
  Future<void> connect() async {
    _closed = false;
    await _doConnect();
  }

  /// Disconnect and stop reconnecting.
  void disconnect() {
    _closed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _disconnectDebounce?.cancel();
    _ws?.close();
    _ws = null;
    _setConnected(false);
    _flushPending('disconnected');
  }

  /// Send a JSON-RPC request and await the response.
  /// [_bypassConnCheck] is used only for the initial 'connect' handshake.
  Future<dynamic> request(String method, [Map<String, dynamic>? params, bool _bypassConnCheck = false]) {
    if (_ws == null) return Future.error('no websocket');
    if (!_bypassConnCheck && !_connected) {
      return Future.error('not connected');
    }

    final id = _uuid();
    final completer = Completer<dynamic>();
    _pending[id] = completer;

    final msg = json.encode({
      'type': 'req',
      'id': id,
      'method': method,
      'params': params ?? {},
    });

    _ws!.add(msg);

    // Timeout after 120s
    Future.delayed(const Duration(seconds: 120), () {
      if (_pending.containsKey(id)) {
        _pending.remove(id)?.completeError('request timeout: $method');
      }
    });

    return completer.future;
  }

  // --- Chat convenience methods ---

  /// Send a chat message through the full agent pipeline.
  /// If [isHidden] is true, the message won't appear in history (system-level injection).
  Future<String?> chatSend(String message, {bool isHidden = false}) async {
    final idempotencyKey = _uuid();
    final params = <String, dynamic>{
      'sessionKey': sessionKey,
      'message': message,
      'deliver': false,
      'idempotencyKey': idempotencyKey,
    };
    if (isHidden) {
      params['hidden'] = true;
    }
    await request('chat.send', params);
    return idempotencyKey;
  }

  /// Load chat history from the gateway.
  Future<List<dynamic>> chatHistory({int limit = 200}) async {
    final result = await request('chat.history', {
      'sessionKey': sessionKey,
      'limit': limit,
    });
    if (result is Map && result['messages'] is List) {
      return result['messages'] as List;
    }
    return [];
  }

  /// Abort the current chat run.
  Future<void> chatAbort([String? runId]) async {
    final params = <String, dynamic>{'sessionKey': sessionKey};
    if (runId != null) params['runId'] = runId;
    await request('chat.abort', params);
  }

  /// Get agent identity (name, avatar).
  Future<Map<String, dynamic>?> agentIdentity() async {
    try {
      final result = await request('agent.identity.get', {
        'sessionKey': sessionKey,
      });
      return result is Map<String, dynamic> ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// Get available sessions.
  Future<List<dynamic>> sessionsList({int activeMinutes = 120}) async {
    final result = await request('sessions.list', {
      'activeMinutes': activeMinutes,
    });
    if (result is Map && result['sessions'] is List) {
      return result['sessions'] as List;
    }
    return [];
  }

  // --- Private ---

  Future<void> _doConnect() async {
    if (_closed) return;

    // Close any existing connection before reconnecting
    try { _ws?.close(); } catch (_) {}
    _ws = null;

    try {
      _ws = await WebSocket.connect(
        'ws://$host:$port',
        headers: {'Origin': 'http://$host:$port'},
      );
      _ws!.listen(
        _onMessage,
        onDone: () => _onClose('connection closed'),
        onError: (e) => _onClose('ws error: $e'),
      );

      // Start keepalive timer — send a JSON tick request to keep the connection alive
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_ws != null && _connected) {
          try {
            // Send a lightweight JSON-RPC request as keepalive
            request('status', {}).catchError((_) {});
          } catch (_) {}
        }
      });

      // Wait for connect.challenge event, then send connect
      // The gateway sends a challenge nonce first
    } catch (e) {
      _onClose('connect failed: $e');
    }
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;

    Map<String, dynamic> msg;
    try {
      msg = json.decode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;

    if (type == 'event') {
      final event = msg['event'] as String?;

      // Handle connect challenge
      if (event == 'connect.challenge') {
        final nonce = msg['payload']?['nonce'] as String? ?? '';
        _sendConnect(nonce);
        return;
      }

      // Emit to listeners
      _eventController.add(GatewayEvent(
        event: event ?? 'unknown',
        payload: msg['payload'],
        seq: msg['seq'] as int?,
      ));
      return;
    }

    if (type == 'res') {
      final id = msg['id'] as String?;
      if (id == null) return;
      final completer = _pending.remove(id);
      if (completer == null) return;

      if (msg['ok'] == true) {
        completer.complete(msg['payload']);
      } else {
        final error = msg['error'];
        final errorMsg = error is Map ? (error['message'] ?? 'request failed') : 'request failed';
        completer.completeError(errorMsg);
      }
      return;
    }
  }

  void _sendConnect(String nonce) {
    final connectParams = <String, dynamic>{
      'minProtocol': 3,
      'maxProtocol': 3,
      'client': {
        'id': clientId,
        'version': clientVersion,
        'platform': 'android-arm64',
        'mode': clientMode,
      },
      'role': 'operator',
      'scopes': ['operator.admin'],
      'caps': [],
      // No device field — operator + valid token skips device identity check
    };

    if (token != null && token!.isNotEmpty) {
      connectParams['auth'] = {'token': token};
    }

    request('connect', connectParams, true).then((result) {
      _backoffMs = 1500;
      _everConnected = true;
      _disconnectDebounce?.cancel();
      _setConnected(true);

      // Emit hello event so UI can react
      _eventController.add(GatewayEvent(
        event: 'hello',
        payload: result is Map<String, dynamic> ? result : {},
      ));
    }).catchError((e) {
      _ws?.close();
      _ws = null;
      _setConnected(false);
      _scheduleReconnect();
    });
  }

  Timer? _disconnectDebounce;

  void _onClose(String reason) {
    _ws = null;
    _pingTimer?.cancel();
    _connected = false;
    _flushPending(reason);

    // Debounce the UI notification — if we reconnect within 2s, UI won't flicker
    _disconnectDebounce?.cancel();
    _disconnectDebounce = Timer(const Duration(seconds: 2), () {
      if (!_connected) {
        _connectionController.add(false);
      }
    });
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _backoffMs), () {
      _backoffMs = min(_backoffMs * 2, 15000);
      _doConnect();
    });
  }

  void _setConnected(bool value) {
    if (_connected != value) {
      _connected = value;
      _connectionController.add(value);
    }
  }

  void _flushPending(String reason) {
    for (final c in _pending.values) {
      c.completeError(reason);
    }
    _pending.clear();
  }

  String _uuid() {
    final r = Random();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _connectionController.close();
  }
}

/// A gateway event (chat delta, agent action, presence, etc.)
class GatewayEvent {
  final String event;
  final dynamic payload;
  final int? seq;

  GatewayEvent({required this.event, this.payload, this.seq});

  @override
  String toString() => 'GatewayEvent($event, seq=$seq)';
}
