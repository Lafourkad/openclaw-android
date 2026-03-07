import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/native_bridge.dart';
import '../services/gateway_websocket.dart';

// ---------------------------------------------------------------------------
// ChatMessage — public, so ChatScreen can read it
// ---------------------------------------------------------------------------

class ChatMessage {
  String text;
  String thinking;
  bool thinkingCollapsed;
  final bool isUser;
  bool isError;
  final DateTime? time;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.thinking = '',
    this.thinkingCollapsed = true,
    this.isError = false,
    this.time,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'isError': isError,
        if (thinking.isNotEmpty) 'thinking': thinking,
        'time': time?.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        text: j['text'] as String? ?? '',
        isUser: j['isUser'] as bool? ?? false,
        isError: j['isError'] as bool? ?? false,
        thinking: j['thinking'] as String? ?? '',
        time: j['time'] != null ? DateTime.tryParse(j['time'] as String) : null,
      );
}

// ---------------------------------------------------------------------------
// ChatController — all WS logic, message state, history, runId tracking
// ---------------------------------------------------------------------------

class ChatController extends ChangeNotifier {
  // --- State ---
  final List<ChatMessage> messages = [];
  bool sending = false;
  bool ready = false;
  bool wsConnected = false;
  String agentName = 'OpenClaw';

  // --- Private ---
  String? _filesDir;
  int _port = 18789;
  String? _gatewayToken;
  String? _currentRunId;
  bool _appInForeground = true;

  GatewayWebSocket? _ws;
  StreamSubscription<GatewayEvent>? _eventSub;
  StreamSubscription<bool>? _connSub;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Call once at init time. Fetches filesDir, loads config, starts WS.
  Future<void> init() async {
    _filesDir = await NativeBridge.getFilesDir();
    await _loadConfig();
    await _ensureGatewayRunning();
    _connectWebSocket();
  }

  /// Call when the app comes back to foreground.
  void onAppResumed(bool wasBackground) {
    _appInForeground = true;
    if (_ws != null && !_ws!.connected) {
      _ws!.connect();
    }
    if (wasBackground) {
      _refreshFromHistory();
    }
  }

  void onAppPaused() {
    _appInForeground = false;
  }

  /// Reconnect WebSocket (e.g. after gateway restart).
  void reconnect() {
    if (_ws != null) {
      _ws!.connect();
    } else {
      _connectWebSocket();
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _connSub?.cancel();
    _ws?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Public actions
  // ---------------------------------------------------------------------------

  Future<void> sendMessage(String text, {bool isHidden = false}) async {
    if (text.isEmpty || sending) return;

    final userMsg = ChatMessage(text: text, isUser: true, time: DateTime.now());
    final assistantMsg = ChatMessage(text: '', isUser: false, time: DateTime.now());
    messages.add(userMsg);
    messages.add(assistantMsg);
    sending = true;
    notifyListeners();

    try {
      if (_ws == null || !_ws!.connected) {
        throw 'WebSocket not connected';
      }
      _currentRunId = await _ws!.chatSend(text, isHidden: isHidden);
      // Safety timeout — unblock after 120s if no response
      Future.delayed(const Duration(seconds: 120), () {
        if (sending) {
          if (assistantMsg.text.isEmpty) {
            assistantMsg.text = '⏱ Response timed out. Try again.';
            assistantMsg.isError = true;
          }
          sending = false;
          _currentRunId = null;
          _saveHistory();
          notifyListeners();
        }
      });
    } catch (e) {
      assistantMsg.text = '❌ Failed to send: $e';
      assistantMsg.isError = true;
      sending = false;
      _currentRunId = null;
      _saveHistory();
      notifyListeners();
    }
  }

  void abortRun() {
    if (_ws != null && _ws!.connected) {
      _ws!.chatAbort(_currentRunId);
    }
  }

  Future<void> clearHistory() async {
    messages.clear();
    notifyListeners();
    await _saveHistory();
  }

  void deleteMessage(ChatMessage msg) {
    messages.remove(msg);
    notifyListeners();
  }

  /// Remove messages from [index] onward (for edit & resend).
  List<ChatMessage> spliceFrom(int index) {
    final removed = messages.sublist(index);
    messages.removeRange(index, messages.length);
    notifyListeners();
    _saveHistory();
    return removed;
  }

  Future<void> regenerate() async {
    if (sending) return;
    // Remove last assistant message
    for (int i = messages.length - 1; i >= 0; i--) {
      if (!messages[i].isUser) {
        messages.removeAt(i);
        break;
      }
    }
    // Get last user message text and remove it too
    String? text;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) {
        text = messages[i].text;
        messages.removeAt(i);
        break;
      }
    }
    notifyListeners();
    if (text != null) {
      await sendMessage(text);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — gateway setup
  // ---------------------------------------------------------------------------

  Future<void> _ensureGatewayRunning() async {
    if (await _isBackendUp()) return;
    try {
      await NativeBridge.startGateway();
    } catch (_) {}
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await _isBackendUp()) return;
    }
  }

  Future<bool> _isBackendUp() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$_port/v1/chat/completions'),
      );
      request.headers.set('Content-Type', 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      await response.drain();
      client.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _connectWebSocket() {
    _ws = GatewayWebSocket(
      host: '127.0.0.1',
      port: _port,
      token: _gatewayToken,
      sessionKey: 'agent:main:main',
    );

    _connSub = _ws!.connectionState.listen((connected) {
      wsConnected = connected;
      notifyListeners();
      if (connected && !ready) {
        _onFirstConnect();
      }
    });

    _eventSub = _ws!.events.listen(_onGatewayEvent);
    _ws!.connect();
  }

  Future<void> _onFirstConnect() async {
    ready = true;
    notifyListeners();
    await _loadHistory();
    if (messages.isEmpty) {
      await _sendWelcome();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — event handling
  // ---------------------------------------------------------------------------

  void _onGatewayEvent(GatewayEvent evt) {
    final payload = evt.payload;
    if (payload == null || payload is! Map) return;

    // --- agent events (streaming text + thinking) ---
    if (evt.event == 'agent') {
      final stream = payload['stream'] as String?;
      final data = payload['data'];
      if (data is Map && messages.isNotEmpty && !messages.last.isUser) {
        final text = data['text'] as String?;
        if (stream == 'thinking' && text != null && text.isNotEmpty) {
          messages.last.thinking = text;
          notifyListeners();
        } else if (stream == 'assistant' && text != null && text.isNotEmpty) {
          // Filter internal messages
          if (text.startsWith('HEARTBEAT') || text == 'NO_REPLY') return;
          messages.last.text = text;
          notifyListeners();
        }
      }
      return;
    }

    if (evt.event != 'chat') return;

    final state = payload['state'] as String?;
    final runId = payload['runId'] as String?;

    // Only handle events for our current run
    if (_currentRunId != null && runId != null && runId != _currentRunId) return;

    if (state == 'delta') {
      // Streaming handled by 'agent' event — skip to avoid overwriting
    } else if (state == 'final') {
      final messageData = payload['message'];
      if (messageData is Map) {
        final content = messageData['content'];
        if (content is List && content.isNotEmpty) {
          final textEntry = content.firstWhere(
            (c) => c is Map && c['type'] == 'text',
            orElse: () => null,
          );
          if (textEntry != null) {
            final fullText = textEntry['text'] as String? ?? '';
            sending = false;
            _currentRunId = null;
            if (fullText.isNotEmpty && messages.isNotEmpty && !messages.last.isUser) {
              messages.last.text = fullText;
            }
            _saveHistory();
            notifyListeners();
            _maybeNotify();
            return;
          }
        }
      }
      sending = false;
      _currentRunId = null;
      _saveHistory();
      notifyListeners();
      _maybeNotify();
    } else if (state == 'aborted') {
      sending = false;
      _currentRunId = null;
      if (messages.isNotEmpty && !messages.last.isUser && messages.last.text.isEmpty) {
        messages.last.text = '(Aborted)';
        messages.last.isError = true;
      }
      notifyListeners();
    } else if (state == 'error') {
      sending = false;
      _currentRunId = null;
      if (messages.isNotEmpty && !messages.last.isUser) {
        if (messages.last.text.isEmpty) {
          messages.last.text = '❌ Error from agent';
        }
        messages.last.isError = true;
      }
      notifyListeners();
    }
  }

  void _maybeNotify() {
    if (!_appInForeground && messages.isNotEmpty && !messages.last.isUser) {
      final text = messages.last.text;
      if (text.isNotEmpty) {
        final preview = text.length > 100 ? '${text.substring(0, 100)}…' : text;
        NativeBridge.sendChatNotification(agentName, preview);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — config & history
  // ---------------------------------------------------------------------------

  Future<void> _loadConfig() async {
    try {
      final configFile = File('$_filesDir/.openclaw/openclaw.json');
      if (configFile.existsSync()) {
        final config =
            json.decode(configFile.readAsStringSync()) as Map<String, dynamic>;
        _gatewayToken = config['gateway']?['auth']?['token'] as String?;
        _port = config['gateway']?['port'] as int? ?? 18789;
        final agentsList = config['agents']?['list'] as List?;
        if (agentsList != null && agentsList.isNotEmpty) {
          final name = (agentsList[0] as Map?)?['name'] as String?;
          debugPrint('OpenClaw: agent name from config = "$name"');
          if (name != null && name.isNotEmpty) {
            agentName = name;
          }
        } else {
          debugPrint('OpenClaw: no agents list in config!');
        }
      }
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    if (_ws == null || !_ws!.connected) return;
    try {
      final msgs = await _ws!.chatHistory(limit: 100);
      if (msgs.isNotEmpty) {
        messages.clear();
        for (final m in msgs) {
          if (m is! Map) continue;
          final role = m['role'] as String? ?? '';
          final content = m['content'];
          String text = '';
          if (content is String) {
            text = content;
          } else if (content is List) {
            text = content
                .where((c) => c is Map && c['type'] == 'text')
                .map((c) => c['text'] as String? ?? '')
                .join('\n');
          }
          if (text.isEmpty) continue;
          if (role == 'user' && text.contains('just installed this app')) continue;
          if (role == 'user' && text.contains('[system:hatch]')) continue;
          if (text.startsWith('HEARTBEAT') || text == 'NO_REPLY') continue;
          if (role == 'user' && text.contains('Heartbeat prompt:')) continue;
          if (role == 'user' || role == 'assistant') {
            messages.add(ChatMessage(
              text: text,
              isUser: role == 'user',
              time: DateTime.now(),
            ));
          }
        }
        notifyListeners();
      }
    } catch (_) {
      _loadLocalHistory();
    }
  }

  void _loadLocalHistory() {
    try {
      final histFile = File('$_filesDir/.openclaw/chat_history.json');
      if (histFile.existsSync()) {
        final list = json.decode(histFile.readAsStringSync()) as List;
        messages.clear();
        for (final m in list) {
          messages.add(ChatMessage.fromJson(m as Map<String, dynamic>));
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final histFile = File('$_filesDir/.openclaw/chat_history.json');
      final toSave = messages.length > 200
          ? messages.sublist(messages.length - 200)
          : messages;
      histFile.writeAsStringSync(
          json.encode(toSave.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  /// Reload messages from gateway history (e.g. after returning from background).
  /// Only updates if gateway has more messages than we have locally.
  Future<void> _refreshFromHistory() async {
    if (_ws == null || !_ws!.connected) return;
    try {
      final msgs = await _ws!.chatHistory(limit: 100);
      if (msgs.isEmpty) return;

      final gatewayMessages = <ChatMessage>[];
      for (final m in msgs) {
        if (m is! Map) continue;
        final role = m['role'] as String? ?? '';
        final content = m['content'];
        String text = '';
        if (content is String) {
          text = content;
        } else if (content is List) {
          text = content
              .where((c) => c is Map && c['type'] == 'text')
              .map((c) => c['text'] as String? ?? '')
              .join('\n');
        }
        if (text.isEmpty) continue;
        if (role == 'user' && text.contains('just installed this app')) continue;
        if (role == 'user' && text.contains('[system:hatch]')) continue;
        if (text.startsWith('HEARTBEAT') || text == 'NO_REPLY') continue;
        if (role == 'user' && text.contains('Heartbeat prompt:')) continue;
        if (role == 'user' || role == 'assistant') {
          gatewayMessages.add(ChatMessage(
            text: text,
            isUser: role == 'user',
            time: DateTime.now(),
          ));
        }
      }

      if (gatewayMessages.length > messages.length) {
        final oldCount = messages.length;
        messages.clear();
        messages.addAll(gatewayMessages);
        sending = false;
        _currentRunId = null;
        notifyListeners();
        _saveHistory();

        if (messages.length > oldCount && messages.isNotEmpty && !messages.last.isUser) {
          final text = messages.last.text;
          if (text.isNotEmpty) {
            final preview = text.length > 100 ? '${text.substring(0, 100)}…' : text;
            NativeBridge.sendChatNotification(agentName, preview);
          }
        }
      } else if (sending) {
        final lastGw = gatewayMessages.isNotEmpty ? gatewayMessages.last : null;
        if (lastGw != null &&
            !lastGw.isUser &&
            messages.isNotEmpty &&
            messages.last.text.isEmpty) {
          messages.last.text = lastGw.text;
          sending = false;
          _currentRunId = null;
          notifyListeners();
          _saveHistory();
        }
      }
    } catch (_) {}
  }

  Future<void> _sendWelcome() async {
    if (_ws == null || !_ws!.connected) return;

    final assistantMsg = ChatMessage(text: '', isUser: false, time: DateTime.now());
    messages.add(assistantMsg);
    sending = true;
    notifyListeners();

    try {
      _currentRunId = await _ws!.chatSend(
        '[system:hatch] You just hatched. This is your first conversation ever. Your name is $agentName.\n'
        'Introduce yourself briefly, then ask your owner the standard onboarding questions one at a time:\n'
        '1. What\'s your name?\n'
        '2. What should I call you?\n'
        '3. What timezone are you in?\n'
        '4. Any preferences for how I should communicate? (language, tone, etc.)\n'
        'Start with a warm greeting and the first question. Keep it natural — don\'t list all questions at once.\n'
        'After you\'ve gathered the answers, write them to ~/.openclaw/workspace/USER.md.\n'
        'Also fill in ~/.openclaw/workspace/IDENTITY.md with your own identity (name, creature type, vibe, emoji).',
      );
      // Safety timeout
      Future.delayed(const Duration(seconds: 60), () {
        if (sending) {
          if (assistantMsg.text.isEmpty) {
            assistantMsg.text = 'Hey! 👋 I\'m $agentName. Ask me anything.';
          }
          sending = false;
          _currentRunId = null;
          _saveHistory();
          notifyListeners();
        }
      });
    } catch (e) {
      assistantMsg.text = 'Hey! 👋 I\'m $agentName. Ask me anything.';
      sending = false;
      _currentRunId = null;
      _saveHistory();
      notifyListeners();
    }
  }
}
