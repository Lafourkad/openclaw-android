import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app.dart';
import '../services/native_bridge.dart';
import '../services/gateway_websocket.dart';

/// Full-pipeline chat with the OpenClaw agent via WebSocket.
/// Uses the same protocol as the web Control UI dashboard.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];

  GatewayWebSocket? _ws;
  StreamSubscription? _eventSub;
  StreamSubscription? _connSub;

  bool _wsConnected = false;
  bool _sending = false;
  String _streamBuffer = '';
  String? _currentRunId;
  String? _agentName;
  String? _filesDir;
  int _port = 18789;
  String? _gatewayToken;
  String _sessionKey = 'agent:main:main';
  bool _showScrollFab = false;

  // Tool calls tracking
  final List<String> _activeTools = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
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
    _connectWebSocket();
  }

  Future<void> _loadConfig() async {
    try {
      final configFile = File('$_filesDir/.openclaw/openclaw.json');
      if (configFile.existsSync()) {
        final config = json.decode(configFile.readAsStringSync()) as Map<String, dynamic>;
        _gatewayToken = config['gateway']?['auth']?['token'] as String?;
        _port = config['gateway']?['port'] as int? ?? 18789;

        // Auto-generate token if missing
        if (_gatewayToken == null || _gatewayToken!.isEmpty) {
          _ensureToken(config, configFile);
        }
      }
    } catch (_) {}
  }

  void _ensureToken(Map<String, dynamic> config, File configFile) {
    config.putIfAbsent('gateway', () => <String, dynamic>{});
    final gw = config['gateway'] as Map<String, dynamic>;
    gw['auth'] = {
      'mode': 'token',
      'token': 'openclaw-local-${DateTime.now().millisecondsSinceEpoch}',
    };
    _gatewayToken = gw['auth']['token'] as String;
    configFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(config));
  }

  void _connectWebSocket() {
    _ws?.dispose();

    _ws = GatewayWebSocket(
      host: '127.0.0.1',
      port: _port,
      token: _gatewayToken,
      sessionKey: _sessionKey,
    );

    _connSub = _ws!.connectionState.listen((connected) {
      setState(() => _wsConnected = connected);
    });

    _eventSub = _ws!.events.listen(_onGatewayEvent);

    _ws!.connect();
  }

  void _onGatewayEvent(GatewayEvent event) {
    switch (event.event) {
      case 'hello':
        // Connected — load history + agent identity
        _loadChatHistory();
        _loadAgentIdentity();
        break;

      case 'chat':
        _handleChatEvent(event.payload);
        break;

      case 'agent':
        _handleAgentEvent(event.payload);
        break;
    }
  }

  Future<void> _loadChatHistory() async {
    try {
      final messages = await _ws!.chatHistory(limit: 200);
      setState(() {
        _messages.clear();
        for (final m in messages) {
          if (m is! Map) continue;
          final msg = _parseGatewayMessage(m as Map<String, dynamic>);
          if (msg != null) _messages.add(msg);
        }
      });
      _scrollToBottom();
    } catch (_) {}
  }

  Future<void> _loadAgentIdentity() async {
    try {
      final identity = await _ws!.agentIdentity();
      if (identity != null && mounted) {
        setState(() {
          _agentName = identity['name'] as String? ?? 'OpenClaw';
        });
      }
    } catch (_) {}
  }

  /// Parse a gateway message into our display format.
  _ChatMessage? _parseGatewayMessage(Map<String, dynamic> msg) {
    final role = (msg['role'] as String? ?? '').toLowerCase();
    if (role != 'user' && role != 'assistant') return null;

    // Extract text from content array or text field
    String text = '';
    final content = msg['content'];
    if (content is String) {
      text = content;
    } else if (content is List) {
      final textParts = <String>[];
      for (final part in content) {
        if (part is Map) {
          if (part['type'] == 'text' && part['text'] is String) {
            textParts.add(part['text'] as String);
          } else if (part['type'] == 'tool_use') {
            textParts.add('🔧 ${part['name'] ?? 'tool'}');
          } else if (part['type'] == 'tool_result') {
            // Skip tool results in display
          }
        }
      }
      text = textParts.join('\n');
    }

    // Skip NO_REPLY messages
    if (text.trim() == 'NO_REPLY') return null;
    if (text.isEmpty) return null;

    final ts = msg['timestamp'];
    DateTime? time;
    if (ts is int) {
      time = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      time = DateTime.tryParse(ts);
    }

    return _ChatMessage(
      text: text,
      isUser: role == 'user',
      time: time ?? DateTime.now(),
    );
  }

  void _handleChatEvent(dynamic payload) {
    if (payload is! Map) return;
    final p = payload as Map<String, dynamic>;

    // Only handle events for our session
    if (p['sessionKey'] != _sessionKey) return;

    final state = p['state'] as String?;

    switch (state) {
      case 'delta':
        _handleDelta(p);
        break;
      case 'final':
        _handleFinal(p);
        break;
      case 'aborted':
        _handleAborted(p);
        break;
      case 'error':
        _handleError(p);
        break;
    }
  }

  void _handleDelta(Map<String, dynamic> p) {
    final msg = p['message'];
    if (msg == null) return;

    String? text;
    if (msg is Map) {
      final content = msg['content'];
      if (content is String) {
        text = content;
      } else if (content is List) {
        final parts = content.whereType<Map>()
            .where((c) => c['type'] == 'text')
            .map((c) => c['text'] as String? ?? '')
            .join();
        text = parts;
      }
      // Also try 'text' field
      text ??= msg['text'] as String?;
    }

    if (text != null && text.isNotEmpty && text.trim() != 'NO_REPLY') {
      if (text.length >= _streamBuffer.length) {
        _streamBuffer = text;
        setState(() {
          // Update the last assistant message (streaming placeholder)
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            _messages.last.text = _streamBuffer;
          }
        });
        _scrollToBottom();
      }
    }
  }

  void _handleFinal(Map<String, dynamic> p) {
    final msg = p['message'];
    final parsed = msg is Map<String, dynamic> ? _parseGatewayMessage(msg) : null;

    setState(() {
      // Remove streaming placeholder
      if (_messages.isNotEmpty && !_messages.last.isUser && _sending) {
        _messages.removeLast();
      }

      if (parsed != null) {
        _messages.add(parsed);
      } else if (_streamBuffer.trim().isNotEmpty && _streamBuffer.trim() != 'NO_REPLY') {
        _messages.add(_ChatMessage(
          text: _streamBuffer,
          isUser: false,
          time: DateTime.now(),
        ));
      }

      _sending = false;
      _currentRunId = null;
      _streamBuffer = '';
      _activeTools.clear();
    });
    _scrollToBottom();
  }

  void _handleAborted(Map<String, dynamic> p) {
    setState(() {
      if (_messages.isNotEmpty && !_messages.last.isUser && _sending) {
        if (_streamBuffer.trim().isNotEmpty) {
          _messages.last.text = _streamBuffer + '\n\n⚠️ (aborted)';
        } else {
          _messages.removeLast();
        }
      }
      _sending = false;
      _currentRunId = null;
      _streamBuffer = '';
      _activeTools.clear();
    });
  }

  void _handleError(Map<String, dynamic> p) {
    final errorMsg = p['errorMessage'] as String? ?? 'Unknown error';
    setState(() {
      if (_messages.isNotEmpty && !_messages.last.isUser && _sending) {
        _messages.last.text = '❌ $errorMsg';
        _messages.last.isError = true;
      }
      _sending = false;
      _currentRunId = null;
      _streamBuffer = '';
      _activeTools.clear();
    });
  }

  void _handleAgentEvent(dynamic payload) {
    if (payload is! Map) return;
    // Track tool usage for display
    final toolName = payload['tool'] as String?;
    final status = payload['status'] as String?;

    if (toolName != null) {
      setState(() {
        if (status == 'started') {
          _activeTools.add(toolName);
        } else {
          _activeTools.remove(toolName);
        }
      });
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending || !_wsConnected) return;

    _inputController.clear();

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true, time: DateTime.now()));
      _sending = true;
      _streamBuffer = '';
      // Add streaming placeholder
      _messages.add(_ChatMessage(text: '', isUser: false, time: DateTime.now()));
    });
    _scrollToBottom();

    try {
      _currentRunId = await _ws!.chatSend(text);
    } catch (e) {
      setState(() {
        if (_messages.isNotEmpty && !_messages.last.isUser) {
          _messages.last.text = '❌ $e';
          _messages.last.isError = true;
        }
        _sending = false;
      });
    }
  }

  Future<void> _abort() async {
    if (!_sending) return;
    try {
      await _ws!.chatAbort(_currentRunId);
    } catch (_) {}
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
    // Find last user message and resend
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
  }

  void _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text('This clears local display only. Server history remains.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _messages.clear());
    }
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

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E1621) : const Color(0xFFE8DFD5),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF17212B) : AppColors.accent,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              child: Text('🦞', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _agentName ?? 'OpenClaw',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                _buildSubtitle(isDark),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _clearChat),
        ],
      ),
      body: Column(
        children: [
          // Connection banner
          if (!_wsConnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade800,
              child: Row(
                children: [
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Connecting to gateway...', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: _connectWebSocket,
                    child: const Text('Retry', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),

          // Messages
          Expanded(
            child: Stack(
              children: [
                _messages.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.black12,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _wsConnected ? 'Start a conversation' : 'Waiting for connection...',
                            style: const TextStyle(fontSize: 13),
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
                      backgroundColor: isDark ? const Color(0xFF2B5278) : AppColors.accent,
                      child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // Tool calls banner
          if (_activeTools.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: isDark ? const Color(0xFF1A2736) : const Color(0xFFF5F0E8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🔧 Using ${_activeTools.last}...',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF17212B) : Colors.white,
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
                        color: isDark ? const Color(0xFF242F3D) : const Color(0xFFF0F0F0),
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
                        enabled: _wsConnected,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Send / Stop button
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _sending
                          ? Colors.red.shade700
                          : (!_wsConnected ? Colors.grey : AppColors.accent),
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? IconButton(
                            onPressed: _abort,
                            icon: const Icon(Icons.stop, color: Colors.white, size: 20),
                            padding: EdgeInsets.zero,
                          )
                        : IconButton(
                            onPressed: _wsConnected ? _send : null,
                            icon: const Icon(Icons.send, color: Colors.white, size: 18),
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

  Widget _buildSubtitle(bool isDark) {
    if (_sending && _activeTools.isNotEmpty) {
      return Text(
        'using ${_activeTools.last}...',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      );
    }
    if (_sending) {
      return const Text(
        'typing...',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      );
    }
    return Text(
      _wsConnected ? 'online' : 'connecting...',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: _wsConnected ? Colors.greenAccent : Colors.white60,
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

    final bubbleColor = isUser
        ? (isDark ? const Color(0xFF2B5278) : const Color(0xFFEFFFDE))
        : msg.isError
            ? (isDark ? const Color(0xFF3D2020) : const Color(0xFFFFE0E0))
            : (isDark ? const Color(0xFF182533) : Colors.white);

    final textColor = isDark ? Colors.white : Colors.black87;
    final timeColor = isDark ? Colors.white38 : Colors.black38;

    return GestureDetector(
      onLongPress: () => _showMessageMenu(msg),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          margin: EdgeInsets.only(
            bottom: grouped ? 2 : 4,
            left: isUser ? 48 : 0,
            right: isUser ? 0 : 48,
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
        ),
      ),
    );
  }

  Widget _buildFormattedText(String text, Color defaultColor) {
    if (text.contains('```')) {
      final parts = <Widget>[];
      final segments = text.split('```');

      for (int i = 0; i < segments.length; i++) {
        if (i % 2 == 0) {
          if (segments[i].trim().isNotEmpty) {
            parts.add(SelectableText.rich(
              _parseInlineMarkdown(segments[i].trim(), defaultColor),
            ));
          }
        } else {
          var code = segments[i];
          if (code.startsWith('\n')) code = code.substring(1);
          final firstNewline = code.indexOf('\n');
          if (firstNewline > 0 && firstNewline < 20 && !code.substring(0, firstNewline).contains(' ')) {
            code = code.substring(firstNewline + 1);
          }

          parts.add(Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                SelectableText(
                  code.trim(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: defaultColor,
                    height: 1.4,
                  ),
                ),
                Positioned(
                  top: 0, right: 0,
                  child: GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code.trim()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Icon(Icons.copy, size: 14, color: defaultColor.withOpacity(0.5)),
                  ),
                ),
              ],
            ),
          ));
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: parts,
      );
    }

    return SelectableText.rich(_parseInlineMarkdown(text, defaultColor));
  }

  TextSpan _parseInlineMarkdown(String text, Color defaultColor) {
    final spans = <InlineSpan>[];
    final baseStyle = TextStyle(fontSize: 14, color: defaultColor, height: 1.4);
    final regex = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`([^`]+)`');

    int lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: baseStyle));
      }
      if (match.group(1) != null) {
        spans.add(TextSpan(text: match.group(1), style: baseStyle.copyWith(fontWeight: FontWeight.bold)));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(text: match.group(2), style: baseStyle.copyWith(fontStyle: FontStyle.italic)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(
          text: match.group(3),
          style: baseStyle.copyWith(fontFamily: 'monospace', fontSize: 13, backgroundColor: defaultColor.withOpacity(0.1)),
        ));
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }
    return TextSpan(children: spans.isEmpty ? [TextSpan(text: text, style: baseStyle)] : spans);
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
    _scrollController.removeListener(_onScroll);
    _inputController.dispose();
    _scrollController.dispose();
    _eventSub?.cancel();
    _connSub?.cancel();
    _ws?.dispose();
    super.dispose();
  }
}

class _ChatMessage {
  String text;
  final bool isUser;
  bool isError;
  final DateTime? time;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.time,
  });
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
