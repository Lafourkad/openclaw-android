import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../app.dart';
import '../services/native_bridge.dart';
import '../services/gateway_websocket.dart';
import 'dashboard_screen.dart';
import 'file_browser_screen.dart';
import 'packages_screen.dart';
import 'doctor_screen.dart';
import 'logs_screen.dart';
import 'backup_screen.dart';
import 'agents_screen.dart';
import 'settings/settings_main_screen.dart';
import '../widgets/mascot_animation.dart';
import '../widgets/mini_mascot.dart';

/// Chat with the OpenClaw agent via Gateway WebSocket (full agent pipeline).
/// SOUL.md, tools, memory, skills — all active through the controlUi protocol.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const _loadingQuotes = [
    '✂️ Sharpening the claws...',
    '🧠 Loading brain cells...',
    '🔧 Tightening bolts...',
    '📡 Establishing neural link...',
    '🌊 Rising from the deep...',
    '⚡ Warming up circuits...',
    '🗝️ Unlocking the vault...',
    '🎯 Calibrating responses...',
    '🚀 Fueling the engines...',
    '🧬 Assembling DNA...',
    '🔮 Consulting the oracle...',
    '🏗️ Building context...',
    '🎭 Putting on my face...',
    '📚 Speed-reading manuals...',
    '🦾 Flexing servos...',
    '🧪 Mixing the potions...',
    '☕ Brewing first coffee...',
    '🪐 Downloading the universe...',
    '🎪 Setting up the stage...',
    '🔬 Focusing the lens...',
  ];
  bool _appInForeground = true;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late String _loadingQuote;
  final List<_ChatMessage> _messages = [];

  bool _sending = false;
  bool _ready = false;
  String? _filesDir;
  int _port = 18789;
  String? _gatewayToken;
  String _agentName = 'OpenClaw';
  bool _showScrollFab = false;

  GatewayWebSocket? _ws;
  StreamSubscription<GatewayEvent>? _eventSub;
  StreamSubscription<bool>? _connSub;
  String? _currentRunId;
  bool _wsConnected = false;
  Timer? _quoteTimer;
  double _quoteOpacity = 1.0;
  late List<String> _shuffledQuotes;
  int _quoteIndex = 0;

  // Voice input/output
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _shuffledQuotes = _loadingQuotes.toList()..shuffle();
    _loadingQuote = _shuffledQuotes[0];
    _startQuoteRotation();
    _initSpeech();
    _inputController.addListener(() => setState(() {})); // Rebuild for mic/send icon switch
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _init();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) {
        setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
          // Auto-send if we got text
          if (_inputController.text.isNotEmpty) {
            _send();
          }
        }
      },
    );
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _inputController.text = result.recognizedWords;
            _inputController.selection = TextSelection.fromPosition(
              TextPosition(offset: _inputController.text.length),
            );
          });
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_US',
      );
    }
  }

  void _startQuoteRotation() {
    _quoteTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted || _ready) {
        _quoteTimer?.cancel();
        return;
      }
      // Fade out
      setState(() => _quoteOpacity = 0.0);
      // After fade out, change quote and fade in
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _quoteIndex = (_quoteIndex + 1) % _shuffledQuotes.length;
        setState(() {
          _loadingQuote = _shuffledQuotes[_quoteIndex];
          _quoteOpacity = 1.0;
        });
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackground = !_appInForeground;
    _appInForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      if (_ws != null && !_ws!.connected) {
        _ws!.connect();
      }
      // Reload history in case agent responded while we were in background
      if (wasBackground) {
        _refreshFromHistory();
      }
    }
  }

  /// Reload messages from gateway history (e.g. after returning from background)
  /// Only appends new messages — never clears existing ones
  Future<void> _refreshFromHistory() async {
    if (_ws == null || !_ws!.connected) return;
    try {
      final messages = await _ws!.chatHistory(limit: 100);
      if (messages.isEmpty || !mounted) return;

      // Build list of new messages from gateway
      final gatewayMessages = <_ChatMessage>[];
      for (final m in messages) {
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
        // Filter internal/system messages
        if (role == 'user' && text.contains('just installed this app')) continue;
        if (role == 'user' && text.contains('[system:hatch]')) continue;
        if (text == 'HEARTBEAT_OK' || text == 'NO_REPLY') continue;
        if (role == 'user' && text.contains('Heartbeat prompt:')) continue;
        if (role == 'user' || role == 'assistant') {
          gatewayMessages.add(_ChatMessage(
            text: text,
            isUser: role == 'user',
            time: DateTime.now(),
          ));
        }
      }

      // Only update if gateway has more messages than we have locally
      if (gatewayMessages.length > _messages.length) {
        final oldCount = _messages.length;
        setState(() {
          _messages.clear();
          _messages.addAll(gatewayMessages);
          _sending = false;
          _currentRunId = null;
        });
        _scrollToBottom();
        _saveHistory();

        // Notify about new messages
        if (_messages.length > oldCount && _messages.isNotEmpty && !_messages.last.isUser) {
          final text = _messages.last.text;
          if (text.isNotEmpty) {
            final preview = text.length > 100 ? '${text.substring(0, 100)}…' : text;
            NativeBridge.sendChatNotification(_agentName, preview);
          }
        }
      } else if (_sending) {
        // If we were waiting for a response, check if it arrived
        final lastGw = gatewayMessages.isNotEmpty ? gatewayMessages.last : null;
        if (lastGw != null && !lastGw.isUser && _messages.isNotEmpty && _messages.last.text.isEmpty) {
          setState(() {
            _messages.last.text = lastGw.text;
            _sending = false;
            _currentRunId = null;
          });
          _scrollToBottom();
          _saveHistory();
        }
      }
    } catch (_) {}
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (_showScrollFab == atBottom) {
      setState(() => _showScrollFab = !atBottom);
    }
  }

  Future<void> _init() async {
    _filesDir = await NativeBridge.getFilesDir();
    await _loadConfig();
    await _ensureGatewayRunning();
    _connectWebSocket();
  }

  Future<void> _ensureGatewayRunning() async {
    // Try a quick HTTP health check
    if (await _isBackendUp()) return;

    // Not up — start it
    try { await NativeBridge.startGateway(); } catch (_) {}

    // Poll until ready (max ~20s)
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
      final response = await request.close().timeout(const Duration(seconds: 3));
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
      if (mounted) {
        setState(() => _wsConnected = connected);
        if (connected && !_ready) {
          _onFirstConnect();
        }
      }
    });

    _eventSub = _ws!.events.listen(_onGatewayEvent);
    _ws!.connect();
  }

  Future<void> _onFirstConnect() async {
    setState(() => _ready = true);

    // Load history from gateway
    await _loadHistory();

    // The config file is the sole source of truth for agent name.
    // Do NOT use agentIdentity() — the gateway often returns "assistant"
    // which overwrites the user's chosen name.

    // Welcome message on first ever launch
    if (_messages.isEmpty) {
      await _sendWelcome();
    }
  }

  void _onGatewayEvent(GatewayEvent evt) {
    final payload = evt.payload;
    if (payload == null || payload is! Map) return;

    // Handle agent events (streaming text from assistant + thinking)
    if (evt.event == 'agent') {
      final stream = payload['stream'] as String?;
      final data = payload['data'];
      if (data is Map && _messages.isNotEmpty && !_messages.last.isUser) {
        final text = data['text'] as String?;
        if (stream == 'thinking' && text != null && text.isNotEmpty) {
          setState(() => _messages.last.thinking = text);
          _scrollToBottom();
        } else if (stream == 'assistant' && text != null && text.isNotEmpty) {
          // Filter internal messages
          if (text == 'HEARTBEAT_OK' || text == 'NO_REPLY') return;
          setState(() => _messages.last.text = text);
          _scrollToBottom();
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
      // Streaming is handled by the 'agent' event handler (token by token).
      // 'chat' delta arrives with full accumulated text — skip to avoid overwriting
      // smooth streaming with a sudden full-text replacement.
    } else if (state == 'final') {
      // On final, sync the definitive text from gateway (handles edge cases where
      // agent streaming missed tokens or arrived out of order)
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
            setState(() {
              _sending = false;
              _currentRunId = null;
              if (fullText.isNotEmpty && _messages.isNotEmpty && !_messages.last.isUser) {
                _messages.last.text = fullText;
              }
            });
            _saveHistory();
            return;
          }
        }
      }
      setState(() {
        _sending = false;
        _currentRunId = null;
      });
      _saveHistory();



      // Background notification
      if (!_appInForeground && _messages.isNotEmpty && !_messages.last.isUser) {
        final text = _messages.last.text;
        if (text.isNotEmpty) {
          final preview = text.length > 100 ? '${text.substring(0, 100)}…' : text;
          NativeBridge.sendChatNotification(_agentName, preview);
        }
      }
    } else if (state == 'aborted') {
      setState(() {
        _sending = false;
        _currentRunId = null;
        if (_messages.isNotEmpty && !_messages.last.isUser && _messages.last.text.isEmpty) {
          _messages.last.text = '(Aborted)';
          _messages.last.isError = true;
        }
      });
    } else if (state == 'error') {
      setState(() {
        _sending = false;
        _currentRunId = null;
        if (_messages.isNotEmpty && !_messages.last.isUser) {
          if (_messages.last.text.isEmpty) {
            _messages.last.text = '❌ Error from agent';
          }
          _messages.last.isError = true;
        }
      });
    }
  }

  Future<void> _loadConfig() async {
    try {
      final configFile = File('$_filesDir/.openclaw/openclaw.json');
      if (configFile.existsSync()) {
        final config = json.decode(configFile.readAsStringSync()) as Map<String, dynamic>;
        _gatewayToken = config['gateway']?['auth']?['token'] as String?;
        _port = config['gateway']?['port'] as int? ?? 18789;
        // Read agent name from first agent in list
        final agentsList = config['agents']?['list'] as List?;
        if (agentsList != null && agentsList.isNotEmpty) {
          final name = (agentsList[0] as Map?)?['name'] as String?;
          debugPrint('OpenClaw: agent name from config = "$name"');
          if (name != null && name.isNotEmpty && name != 'assistant') {
            _agentName = name;
          } else if (name != null && name.isNotEmpty) {
            // Even "assistant" is better than "OpenClaw"
            _agentName = name;
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
      final messages = await _ws!.chatHistory(limit: 100);
      if (messages.isNotEmpty && mounted) {
        setState(() {
          _messages.clear();
          for (final m in messages) {
            if (m is! Map) continue;
            final role = m['role'] as String? ?? '';
            final content = m['content'];
            String text = '';
            if (content is String) {
              text = content;
            } else if (content is List) {
              // Multi-part content — extract text parts
              text = content
                  .where((c) => c is Map && c['type'] == 'text')
                  .map((c) => c['text'] as String? ?? '')
                  .join('\n');
            }
            if (text.isEmpty) continue;
            // Hide internal/system messages from history
            if (role == 'user' && text.contains('just installed this app')) continue;
            if (role == 'user' && text.contains('[system:hatch]')) continue;
            if (text == 'HEARTBEAT_OK' || text == 'NO_REPLY') continue;
            if (role == 'user' && text.contains('Heartbeat prompt:')) continue;
            if (role == 'user' || role == 'assistant') {
              _messages.add(_ChatMessage(
                text: text,
                isUser: role == 'user',
                time: DateTime.now(), // Gateway doesn't provide timestamps in history
              ));
            }
          }
        });
        _scrollToBottom();
      }
    } catch (_) {
      // Fall back to local history
      _loadLocalHistory();
    }
  }

  void _loadLocalHistory() {
    try {
      final histFile = File('$_filesDir/.openclaw/chat_history.json');
      if (histFile.existsSync()) {
        final list = json.decode(histFile.readAsStringSync()) as List;
        setState(() {
          _messages.clear();
          for (final m in list) {
            _messages.add(_ChatMessage.fromJson(m as Map<String, dynamic>));
          }
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final histFile = File('$_filesDir/.openclaw/chat_history.json');
      final toSave = _messages.length > 200 ? _messages.sublist(_messages.length - 200) : _messages;
      histFile.writeAsStringSync(json.encode(toSave.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _sendWelcome() async {
    if (_ws == null || !_ws!.connected) return;

    // Add ONLY the assistant placeholder — the hatching prompt is invisible to the user
    final assistantMsg = _ChatMessage(text: '', isUser: false, time: DateTime.now());
    setState(() {
      _sending = true;
      _messages.add(assistantMsg);
    });

    try {
      _currentRunId = await _ws!.chatSend(
        '[system:hatch] You just hatched. This is your first conversation ever. Your name is $_agentName.\n'
        'Introduce yourself briefly, then ask your owner the standard onboarding questions one at a time:\n'
        '1. What\'s your name?\n'
        '2. What should I call you?\n'
        '3. What timezone are you in?\n'
        '4. Any preferences for how I should communicate? (language, tone, etc.)\n'
        'Start with a warm greeting and the first question. Keep it natural — don\'t list all questions at once.\n'
        'After you\'ve gathered the answers, write them to ~/.openclaw/workspace/USER.md.\n'
        'Also fill in ~/.openclaw/workspace/IDENTITY.md with your own identity (name, creature type, vibe, emoji).',
      );
      // Safety timeout — if no response in 60s, show fallback
      Future.delayed(const Duration(seconds: 60), () {
        if (_sending && mounted) {
          setState(() {
            if (assistantMsg.text.isEmpty) {
              assistantMsg.text = 'Hey! 👋 I\'m $_agentName. Ask me anything.';
            }
            _sending = false;
            _currentRunId = null;
          });
          _saveHistory();
        }
      });
    } catch (e) {
      setState(() {
        assistantMsg.text = 'Hey! 👋 I\'m $_agentName. Ask me anything.';
        _sending = false;
        _currentRunId = null;
      });
      _saveHistory();
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    _inputController.clear();

    final userMsg = _ChatMessage(text: text, isUser: true, time: DateTime.now());
    final assistantMsg = _ChatMessage(text: '', isUser: false, time: DateTime.now());
    setState(() {
      _messages.add(userMsg);
      _messages.add(assistantMsg);
      _sending = true;
    });
    _scrollToBottom();

    try {
      if (_ws == null || !_ws!.connected) {
        throw 'WebSocket not connected';
      }
      _currentRunId = await _ws!.chatSend(text);
      // Safety timeout — unblock after 120s if no response
      Future.delayed(const Duration(seconds: 120), () {
        if (_sending && mounted) {
          setState(() {
            if (assistantMsg.text.isEmpty) {
              assistantMsg.text = '⏱ Response timed out. Try again.';
              assistantMsg.isError = true;
            }
            _sending = false;
            _currentRunId = null;
          });
          _saveHistory();
        }
      });
    } catch (e) {
      setState(() {
        assistantMsg.text = '❌ Failed to send: $e';
        assistantMsg.isError = true;
        _sending = false;
        _currentRunId = null;
      });
      _saveHistory();
    }
  }

  Future<void> _regenerate() async {
    if (_sending) return;
    // Remove last assistant message
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (!_messages[i].isUser) {
        setState(() => _messages.removeAt(i));
        break;
      }
    }
    // Re-send last user message
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        final text = _messages[i].text;
        setState(() => _messages.removeAt(i));
        _inputController.text = text;
        await _send();
        return;
      }
    }
  }

  void _editMessage(int index) {
    if (index >= _messages.length || !_messages[index].isUser) return;
    final text = _messages[index].text;
    setState(() => _messages.removeRange(index, _messages.length));
    _inputController.text = text;
    _saveHistory();
  }

  void _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear chat?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _messages.clear());
      _saveHistory();
    }
  }

  void _abortRun() {
    if (_ws != null && _ws!.connected) {
      _ws!.chatAbort(_currentRunId);
    }
  }

  Widget _buildDrawer(bool isDark) {
    void nav(Widget screen) {
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    return Drawer(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceAlt : AppColors.accent.withOpacity(0.1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white24,
                    child: MiniMascot(size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text(_agentName,
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text('Powered by OpenClaw',
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('New Chat'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _messages.clear());
                _saveHistory();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              onTap: () => nav(const DashboardScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Agents'),
              onTap: () => nav(const AgentsScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Files'),
              onTap: () => nav(const FileBrowserScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('Packages'),
              onTap: () => nav(const PackagesScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.medical_services_outlined),
              title: const Text('Doctor'),
              onTap: () => nav(const DoctorScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Logs'),
              onTap: () => nav(const LogsScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Backup'),
              onTap: () => nav(const BackupScreen()),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () => nav(const SettingsMainScreen()),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- Date / grouping helpers ---

  bool _needsDateSeparator(int index) {
    if (index == 0) return true;
    final prev = _messages[index - 1].time;
    final curr = _messages[index].time;
    if (prev == null || curr == null) return false;
    return prev.day != curr.day || prev.month != curr.month || prev.year != curr.year;
  }

  bool _isGrouped(int index) {
    if (index == 0) return false;
    final prev = _messages[index - 1];
    final curr = _messages[index];
    if (prev.isUser != curr.isUser) return false;
    if (prev.time == null || curr.time == null) return false;
    return curr.time!.difference(prev.time!).inSeconds < 60;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String statusText;
    if (!_ready && !_wsConnected) {
      statusText = 'starting...';
    } else if (_sending) {
      statusText = 'typing...';
    } else if (!_wsConnected) {
      statusText = 'reconnecting...';
    } else {
      statusText = 'online';
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightSurface,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.accent,
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                child: MiniMascot(size: 24),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _agentName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    statusText,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (_sending)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _abortRun,
              tooltip: 'Stop',
            ),
          IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _clearChat),
        ],
      ),
      drawer: _buildDrawer(isDark),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: Stack(
              children: [
                _messages.isEmpty
                    ? !_ready
                        ? Stack(
                            children: [
                              const MascotAnimation(size: 110),
                              Positioned(
                                left: 0, right: 0,
                                bottom: 40,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 24, height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: isDark ? Colors.white24 : Colors.black12,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    AnimatedOpacity(
                                      opacity: _quoteOpacity,
                                      duration: const Duration(milliseconds: 300),
                                      child: Text(
                                        _loadingQuote,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark ? Colors.white38 : Colors.black38,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.black12,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Start a conversation',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final widgets = <Widget>[];
                          if (index == 0 || _needsDateSeparator(index)) {
                            widgets.add(_buildDateSeparator(_messages[index].time));
                          }
                          widgets.add(_buildMessage(_messages[index], index));
                          return Column(children: widgets);
                        },
                      ),

                // Scroll FAB
                if (_showScrollFab)
                  Positioned(
                    right: 16,
                    bottom: 8,
                    child: FloatingActionButton.small(
                      onPressed: _scrollToBottom,
                      backgroundColor: AppColors.accent,
                      child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attachment button
                  IconButton(
                    icon: Icon(Icons.attach_file, color: isDark ? Colors.white54 : Colors.black45),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File attachments coming soon')),
                      );
                    },
                  ),
                  // Input
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBorder : const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _inputController,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.newline,
                        maxLines: 6,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        enabled: _ready && !_sending,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Combo mic/send button
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _isListening
                          ? Colors.red
                          : (_sending || !_ready) ? Colors.grey : AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : IconButton(
                            onPressed: _ready ? () {
                              HapticFeedback.lightImpact();
                              if (_inputController.text.trim().isNotEmpty) {
                                _send();
                              } else {
                                _toggleListening();
                              }
                            } : null,
                            icon: Icon(
                              _isListening
                                  ? Icons.stop
                                  : _inputController.text.trim().isNotEmpty
                                      ? Icons.send
                                      : Icons.mic,
                              color: Colors.white,
                              size: 18,
                            ),
                            padding: EdgeInsets.zero,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(_ChatMessage msg, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = msg.isUser;
    final grouped = _isGrouped(index);
    final time = msg.time != null && !grouped
        ? '${msg.time!.hour.toString().padLeft(2, '0')}:${msg.time!.minute.toString().padLeft(2, '0')}'
        : '';

    // Base bubble colors
    Color baseBubbleColor = isUser
        ? (isDark ? AppColors.accent : AppColors.accent.withOpacity(0.15))
        : msg.isError
            ? (isDark ? const Color(0xFF3D2020) : const Color(0xFFFFE0E0))
            : (isDark ? AppColors.darkSurfaceAlt : Colors.white);

    // Subtle hue shift for user messages based on position in list
    if (isUser && _messages.length > 1) {
      final t = index / _messages.length.toDouble();
      // Shift hue slightly — older messages warmer, newer messages cooler
      final hsl = HSLColor.fromColor(baseBubbleColor);
      final hueShift = (t - 0.5) * 12; // ±6 degrees
      final lightnessShift = (1 - t) * 0.04; // slightly brighter at top
      baseBubbleColor = hsl
          .withHue((hsl.hue + hueShift) % 360)
          .withLightness((hsl.lightness + lightnessShift).clamp(0.0, 1.0))
          .toColor();
    }

    final bubbleColor = baseBubbleColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final timeColor = isDark ? Colors.white38 : Colors.black38;

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showMessageMenu(msg);
      },
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Agent avatar (assistant messages only, not grouped)
            if (!isUser && !grouped)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 4),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: isDark ? Colors.white12 : AppColors.accent.withOpacity(0.15),
                  child: const MiniMascot(size: 20),
                ),
              )
            else if (!isUser && grouped)
              const SizedBox(width: 34), // spacer to align with avatar above
            Flexible(
              child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: EdgeInsets.only(
            bottom: grouped ? 2 : 4,
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isUser ? 12 : 2),
              bottomRight: Radius.circular(isUser ? 2 : 12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thinking block (collapsible)
              if (!isUser && msg.thinking.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => msg.thinkingCollapsed = !msg.thinkingCollapsed),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              msg.thinkingCollapsed ? Icons.expand_more : Icons.expand_less,
                              size: 16,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Thinking…',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                        if (!msg.thinkingCollapsed) ...[
                          const SizedBox(height: 4),
                          Text(
                            msg.thinking,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black54,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (!isUser && msg.text.isEmpty && _sending)
                _TypingDots()
              else
                _buildFormattedText(msg.text, textColor),
              if (time.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: TextStyle(fontSize: 11, color: timeColor)),
                    if (isUser) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.done_all, size: 14, color: timeColor),
                    ],
                  ],
                ),
              ],
            ],
          ),
              ), // Container end
            ), // Flexible end
          ], // Row children end
        ), // Row end
      ), // Align end
    ); // GestureDetector end
  }

  Widget _buildFormattedText(String text, Color defaultColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MarkdownBody(
      data: text,
      selectable: true,
      onTapLink: (text, href, title) {
        if (href != null) launchUrl(Uri.parse(href));
      },
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: 14, color: defaultColor, height: 1.4),
        strong: TextStyle(fontSize: 14, color: defaultColor, fontWeight: FontWeight.bold),
        em: TextStyle(fontSize: 14, color: defaultColor, fontStyle: FontStyle.italic),
        code: TextStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          color: defaultColor,
          backgroundColor: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.07),
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        listBullet: TextStyle(fontSize: 14, color: defaultColor),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: defaultColor.withOpacity(0.3), width: 3)),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        blockquote: TextStyle(fontSize: 14, color: defaultColor.withOpacity(0.8), fontStyle: FontStyle.italic),
        h1: TextStyle(fontSize: 20, color: defaultColor, fontWeight: FontWeight.bold),
        h2: TextStyle(fontSize: 18, color: defaultColor, fontWeight: FontWeight.bold),
        h3: TextStyle(fontSize: 16, color: defaultColor, fontWeight: FontWeight.bold),
        a: TextStyle(fontSize: 14, color: Colors.blue.shade300, decoration: TextDecoration.underline),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: defaultColor.withOpacity(0.2))),
        ),
      ),
    );
  }

  Widget _buildDateSeparator(DateTime? time) {
    String label;
    if (time == null) {
      label = '';
    } else {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDate = DateTime(time.year, time.month, time.day);
      final diff = today.difference(msgDate).inDays;
      label = diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : '${time.day}/${time.month}/${time.year}';
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ),
    );
  }

  void _showMessageMenu(_ChatMessage msg) {
    final index = _messages.indexOf(msg);
    final isLastAssistant = !msg.isUser && index == _messages.length - 1;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                HapticFeedback.lightImpact();
                Clipboard.setData(ClipboardData(text: msg.text));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                );
              },
            ),
            if (msg.isUser)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit & resend'),
                onTap: () { Navigator.pop(ctx); _editMessage(index); },
              ),
            if (isLastAssistant)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Regenerate'),
                onTap: () { Navigator.pop(ctx); _regenerate(); },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                setState(() => _messages.remove(msg));
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _speech.stop();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _eventSub?.cancel();
    _connSub?.cancel();
    _ws?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _ChatMessage {
  String text;
  String thinking;
  bool thinkingCollapsed;
  final bool isUser;
  bool isError;
  final DateTime? time;

  _ChatMessage({
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

  factory _ChatMessage.fromJson(Map<String, dynamic> j) => _ChatMessage(
    text: j['text'] as String? ?? '',
    isUser: j['isUser'] as bool? ?? false,
    isError: j['isError'] as bool? ?? false,
    thinking: j['thinking'] as String? ?? '',
    time: j['time'] != null ? DateTime.tryParse(j['time'] as String) : null,
  );
}

/// Typing dots animation.
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = (t + i * 0.33) % 1.0;
            final opacity = (1 - (offset * 2 - 1).abs()).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(
                    color: Colors.white54,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
