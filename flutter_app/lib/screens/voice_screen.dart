import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app.dart';
import '../constants.dart';
import '../services/native_bridge.dart';
import '../services/preferences_service.dart';

class _Message {
  final String text;
  final bool isUser;
  final bool isStreaming;
  const _Message({required this.text, required this.isUser, this.isStreaming = false});
  _Message copyWith({String? text, bool? isStreaming}) =>
      _Message(text: text ?? this.text, isUser: isUser, isStreaming: isStreaming ?? this.isStreaming);
}

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with TickerProviderStateMixin {
  final List<_Message> _messages = [];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _isListening = false;
  bool _isTtsEnabled = true;
  bool _isSending = false;
  bool _systemPromptSent = false;

  late AnimationController _dotsAnim;

  @override
  void initState() {
    super.initState();
    _dotsAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _dotsAnim.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;
    _ctrl.clear();

    // Slash commands
    if (trimmed.startsWith('/model ')) {
      final model = trimmed.substring(7).trim();
      setState(() => _messages.add(_Message(text: 'Model → $model', isUser: false)));
      _scrollToBottom();
      return;
    }
    if (trimmed == '/clear') {
      setState(() { _messages.clear(); _systemPromptSent = false; });
      return;
    }

    setState(() {
      _messages.add(_Message(text: trimmed, isUser: true));
      _isSending = true;
    });
    _scrollToBottom();

    await _streamResponse(trimmed);
    setState(() => _isSending = false);
  }

  Future<void> _streamResponse(String userText) async {
    final prefs = PreferencesService();
    await prefs.load();

    final token = prefs.gatewayToken;
    final systemPrompt = _systemPromptSent ? null : prefs.systemPrompt;
    _systemPromptSent = true;

    // Add streaming placeholder
    setState(() => _messages.add(const _Message(text: '', isUser: false, isStreaming: true)));
    _scrollToBottom();

    final idx = _messages.length - 1;
    final buffer = StringBuffer();

    try {
      final uri = Uri.parse('${AppConstants.gatewayUrl}/api/chat/stream');
      final body = jsonEncode({
        'message': userText,
        if (systemPrompt != null && systemPrompt.isNotEmpty) 'systemPrompt': systemPrompt,
      });

      final request = http.Request('POST', uri);
      request.headers['Content-Type'] = 'application/json';
      if (token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
      request.body = body;

      final response = await request.send().timeout(const Duration(seconds: 30));

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data);
            final delta = json['choices']?[0]?['delta']?['content']
                ?? json['delta']?['text']
                ?? json['text']
                ?? '';
            if (delta is String && delta.isNotEmpty) {
              buffer.write(delta);
              setState(() {
                _messages[idx] = _messages[idx].copyWith(
                  text: buffer.toString(),
                  isStreaming: true,
                );
              });
              _scrollToBottom();
            }
          } catch (_) {}
        }
      }

      final finalText = buffer.toString();
      setState(() {
        _messages[idx] = _Message(text: finalText.isEmpty ? '…' : finalText, isUser: false);
      });

      if (_isTtsEnabled && finalText.isNotEmpty) {
        await NativeBridge.speak(finalText);
      }
    } catch (e) {
      setState(() {
        _messages[idx] = _Message(text: 'Error: $e', isUser: false);
      });
    }
    _scrollToBottom();
  }

  Future<void> _toggleMic() async {
    if (_isListening) {
      await NativeBridge.stopListening();
      setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    try {
      final result = await NativeBridge.startListening();
      if (result != null && result.isNotEmpty) {
        await _send(result);
      }
    } catch (_) {}
    setState(() => _isListening = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Assistant'),
        actions: [
          IconButton(
            icon: Icon(_isTtsEnabled ? Icons.volume_up : Icons.volume_off),
            tooltip: 'Toggle TTS',
            onPressed: () => setState(() => _isTtsEnabled = !_isTtsEnabled),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () => setState(() { _messages.clear(); _systemPromptSent = false; }),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('Tap the mic or type a message',
                            style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _buildBubble(_messages[i], isDark),
                  ),
          ),
          _buildInput(isDark),
        ],
      ),
    );
  }

  Widget _buildBubble(_Message msg, bool isDark) {
    final isUser = msg.isUser;
    final bg = isUser
        ? AppColors.accent
        : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF3F4F6));
    final fg = isUser ? Colors.white : (isDark ? Colors.white : Colors.black87);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: msg.isStreaming && msg.text.isEmpty
            ? _buildDots(fg)
            : Text(msg.text, style: TextStyle(color: fg, height: 1.4)),
      ),
    );
  }

  Widget _buildDots(Color color) {
    return AnimatedBuilder(
      animation: _dotsAnim,
      builder: (_, __) {
        final t = _dotsAnim.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final opacity = ((t * 3 - i) % 1.0).clamp(0.2, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildInput(bool isDark) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
        ),
        child: Row(
          children: [
            // Mic button
            GestureDetector(
              onTap: _toggleMic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _isListening ? AppColors.accent : AppColors.accent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  color: _isListening ? Colors.white : AppColors.accent,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: 'Message…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF3F4F6),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isSending ? null : () => _send(_ctrl.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _isSending ? Colors.grey[400] : AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
