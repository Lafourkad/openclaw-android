import 'package:flutter/material.dart';
import 'chat_screen.dart';

/// VoiceScreen — redirects to ChatScreen (unified chat interface).
/// Old HTTP SSE implementation removed; chat uses WebSocket pipeline.
class VoiceScreen extends StatelessWidget {
  const VoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatScreen();
  }
}
