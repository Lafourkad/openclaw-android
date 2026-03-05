import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app.dart';
import '../services/native_bridge.dart';

/// Telegram-quality chat with the OpenClaw agent.
/// Multi-turn context, streaming, markdown, persistence.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;
  String? _gatewayToken;
  String? _filesDir;
  String _streamBuffer = '';
  int _port = 18789;
  bool _showScrollFab = false;
  int? _editingIndex; // Index of message being edited

  bool _endpointChecked = false;

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
    await _loadToken();
    await _loadHistory();
    // Don't auto-restart on init — only enable if first send fails with 404
  }

  Future<void> _loadToken() async {
    try {
      final configFile = File('$_filesDir/.openclaw/openclaw.json');
      if (configFile.existsSync()) {
        final config = json.decode(configFile.readAsStringSync()) as Map<String, dynamic>;
        _gatewayToken = config['gateway']?['auth']?['token'] as String?;
        _port = config['gateway']?['port'] as int? ?? 18789;
      }
    } catch (_) {}
  }

  /// Auto-enable chatCompletions + set token if missing.
  Future<void> _ensureEndpointEnabled() async {
    try {
      final configFile = File('$_filesDir/.openclaw/openclaw.json');
      if (!configFile.existsSync()) return;

      final config = json.decode(configFile.readAsStringSync()) as Map<String, dynamic>;
      bool changed = false;

      // Ensure gateway.http.endpoints.chatCompletions.enabled
      config.putIfAbsent('gateway', () => <String, dynamic>{});
      final gw = config['gateway'] as Map<String, dynamic>;
      gw.putIfAbsent('http', () => <String, dynamic>{});
      final http = gw['http'] as Map<String, dynamic>;
      http.putIfAbsent('endpoints', () => <String, dynamic>{});
      final endpoints = http['endpoints'] as Map<String, dynamic>;

      if (endpoints['chatCompletions']?['enabled'] != true) {
        endpoints['chatCompletions'] = {'enabled': true};
        changed = true;
      }

      // Ensure gateway auth token
      if (gw['auth']?['token'] == null) {
        gw['auth'] = {'mode': 'token', 'token': 'openclaw-local-${DateTime.now().millisecondsSinceEpoch}'};
        _gatewayToken = gw['auth']['token'] as String;
        changed = true;
      }

      if (changed) {
        configFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(config));
        // Restart gateway to pick up changes
        try { await NativeBridge.restartGateway(); } catch (_) {}
        // Wait for restart
        await Future.delayed(const Duration(seconds: 3));
        await _loadToken();
      }
    } catch (_) {}
  }

  /// Load persisted chat history.
  Future<void> _loadHistory() async {
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

  /// Persist chat history.
  Future<void> _saveHistory() async {
    try {
      final histFile = File('$_filesDir/.openclaw/chat_history.json');
      // Keep last 200 messages
      final toSave = _messages.length > 200 ? _messages.sublist(_messages.length - 200) : _messages;
      histFile.writeAsStringSync(json.encode(toSave.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  /// Build conversation context for multi-turn.
  List<Map<String, String>> _buildContext() {
    // Send last 20 messages as context
    final recent = _messages.length > 20 ? _messages.sublist(_messages.length - 20) : _messages;
    return recent
        .where((m) => !m.isError)
        .map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    _inputController.clear();
    final userMsg = _ChatMessage(text: text, isUser: true, time: DateTime.now());
    setState(() {
      _messages.add(userMsg);
      _sending = true;
      _streamBuffer = '';
    });
    _scrollToBottom();

    // Add placeholder for streaming response
    final assistantMsg = _ChatMessage(text: '', isUser: false, time: DateTime.now());
    setState(() => _messages.add(assistantMsg));

    try {
      final context = _buildContext();
      // Remove the empty assistant placeholder from context
      if (context.isNotEmpty && context.last['content']?.isEmpty == true) {
        context.removeLast();
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$_port/v1/chat/completions'),
      );

      request.headers.set('Content-Type', 'application/json');
      if (_gatewayToken != null) {
        request.headers.set('Authorization', 'Bearer $_gatewayToken');
      }

      final body = json.encode({
        'model': 'default',
        'messages': context,
        'stream': true,
      });
      request.add(utf8.encode(body));

      final response = await request.close().timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        // Stream SSE responses
        await for (final chunk in response.transform(utf8.decoder)) {
          for (final line in chunk.split('\n')) {
            if (!line.startsWith('data: ')) continue;
            final data = line.substring(6).trim();
            if (data == '[DONE]') break;

            try {
              final obj = json.decode(data) as Map<String, dynamic>;
              final delta = obj['choices']?[0]?['delta']?['content'] as String?;
              if (delta != null) {
                _streamBuffer += delta;
                setState(() => assistantMsg.text = _streamBuffer);
                _scrollToBottom();
              }
            } catch (_) {}
          }
        }

        // If stream was empty, try non-streaming fallback
        if (_streamBuffer.isEmpty) {
          setState(() => assistantMsg.text = '(Empty response)');
        }

        client.close();
      } else if (response.statusCode == 404 && !_endpointChecked) {
        final body = await response.transform(utf8.decoder).join();
        client.close();
        _endpointChecked = true;
        setState(() {
          assistantMsg.text = 'Chat API not enabled. Enabling and restarting gateway...\n'
              'Try again in ~5 seconds.';
          assistantMsg.isError = true;
        });
        await _ensureEndpointEnabled();
      } else if (response.statusCode == 404) {
        final body = await response.transform(utf8.decoder).join();
        client.close();
        setState(() {
          assistantMsg.text = 'Chat API endpoint not found (404).\n'
              'Check Settings → Gateway → HTTP API → Chat Completions.';
          assistantMsg.isError = true;
        });
      } else {
        final body = await response.transform(utf8.decoder).join();
        client.close();
        setState(() {
          assistantMsg.text = 'Error ${response.statusCode}: $body';
          assistantMsg.isError = true;
        });
      }
    } catch (e) {
      setState(() {
        assistantMsg.text = 'Connection failed: $e\n\nPort: $_port | Token: ${_gatewayToken != null ? "set" : "missing"}';
        assistantMsg.isError = true;
      });
    }

    setState(() => _sending = false);
    _saveHistory();
    _scrollToBottom();
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

  /// Regenerate last assistant response.
  Future<void> _regenerate() async {
    if (_sending) return;
    // Find last assistant message and remove it
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

  /// Edit a user message and resend (removes all messages after it).
  void _editMessage(int index) {
    if (index >= _messages.length || !_messages[index].isUser) return;
    final text = _messages[index].text;
    // Remove this message and everything after
    setState(() {
      _messages.removeRange(index, _messages.length);
    });
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
                const Text('OpenClaw', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(
                  _sending ? 'typing...' : 'online',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                ),
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

                          // Date separator
                          if (index == 0 || _needsDateSeparator(index)) {
                            widgets.add(_buildDateSeparator(_messages[index].time));
                          }

                          widgets.add(_buildMessage(_messages[index], index));
                          return Column(children: widgets);
                        },
                      ),

                // Scroll-to-bottom FAB
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
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Send button
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _sending ? Colors.grey : AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : IconButton(
                            onPressed: _send,
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

  Widget _buildMessage(_ChatMessage msg, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = msg.isUser;
    final grouped = _isGrouped(index);
    final time = msg.time != null && !grouped
        ? '${msg.time!.hour.toString().padLeft(2, '0')}:${msg.time!.minute.toString().padLeft(2, '0')}'
        : '';

    // Telegram-style colors
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
              // Streaming indicator
              if (!isUser && msg.text.isEmpty && _sending)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TypingDots(),
                  ],
                )
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

  /// Render text with basic markdown: **bold**, `code`, ```code blocks```
  Widget _buildFormattedText(String text, Color defaultColor) {
    // Check for code blocks
    if (text.contains('```')) {
      final parts = <Widget>[];
      final segments = text.split('```');

      for (int i = 0; i < segments.length; i++) {
        if (i % 2 == 0) {
          // Normal text
          if (segments[i].isNotEmpty) {
            parts.add(SelectableText(
              segments[i].trim(),
              style: TextStyle(fontSize: 14, color: defaultColor, height: 1.4),
            ));
          }
        } else {
          // Code block
          var code = segments[i];
          // Remove language hint on first line
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
            child: SelectableText(
              code.trim(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: defaultColor,
                height: 1.4,
              ),
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

    // Inline formatting: **bold**, *italic*, `code`
    return SelectableText.rich(
      _parseInlineMarkdown(text, defaultColor),
    );
  }

  TextSpan _parseInlineMarkdown(String text, Color defaultColor) {
    final spans = <InlineSpan>[];
    final baseStyle = TextStyle(fontSize: 14, color: defaultColor, height: 1.4);

    // Pattern: **bold**, *italic*, `code`
    final regex = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`([^`]+)`');

    int lastEnd = 0;
    for (final match in regex.allMatches(text)) {
      // Text before match
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start), style: baseStyle));
      }

      if (match.group(1) != null) {
        // **bold**
        spans.add(TextSpan(
          text: match.group(1),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(2) != null) {
        // *italic*
        spans.add(TextSpan(
          text: match.group(2),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(3) != null) {
        // `code`
        spans.add(TextSpan(
          text: match.group(3),
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            fontSize: 13,
            backgroundColor: defaultColor.withOpacity(0.1),
          ),
        ));
      }

      lastEnd = match.end;
    }

    // Remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }

    return TextSpan(children: spans.isEmpty ? [TextSpan(text: text, style: baseStyle)] : spans);
  }

  bool _needsDateSeparator(int index) {
    if (index == 0) return true;
    final prev = _messages[index - 1].time;
    final curr = _messages[index].time;
    if (prev == null || curr == null) return false;
    return prev.day != curr.day || prev.month != curr.month || prev.year != curr.year;
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

      if (diff == 0) {
        label = 'Today';
      } else if (diff == 1) {
        label = 'Yesterday';
      } else {
        label = '${time.day}/${time.month}/${time.year}';
      }
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ),
    );
  }

  /// Check if this message should be grouped (hide time if same sender within 1 min).
  bool _isGrouped(int index) {
    if (index == 0) return false;
    final prev = _messages[index - 1];
    final curr = _messages[index];
    if (prev.isUser != curr.isUser) return false;
    if (prev.time == null || curr.time == null) return false;
    return curr.time!.difference(prev.time!).inSeconds < 60;
  }

  void _showMessageMenu(_ChatMessage msg) {
    final index = _messages.indexOf(msg);
    final isLastAssistant = !msg.isUser &&
        index == _messages.length - 1;

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
                onTap: () {
                  Navigator.pop(ctx);
                  _editMessage(index);
                },
              ),
            if (isLastAssistant)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Regenerate'),
                onTap: () {
                  Navigator.pop(ctx);
                  _regenerate();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                setState(() => _messages.remove(msg));
                _saveHistory();
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

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'isError': isError,
    'time': time?.toIso8601String(),
  };

  factory _ChatMessage.fromJson(Map<String, dynamic> j) => _ChatMessage(
    text: j['text'] as String? ?? '',
    isUser: j['isUser'] as bool? ?? false,
    isError: j['isError'] as bool? ?? false,
    time: j['time'] != null ? DateTime.tryParse(j['time'] as String) : null,
  );
}

/// Telegram-style typing dots animation.
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
                  decoration: BoxDecoration(
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
