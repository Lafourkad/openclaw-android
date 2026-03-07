import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../controllers/chat_controller.dart';
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
/// UI-only. All logic lives in [ChatController].
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
  bool _showScrollFab = false;

  Timer? _quoteTimer;
  double _quoteOpacity = 1.0;
  late List<String> _shuffledQuotes;
  int _quoteIndex = 0;

  // Voice input
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  // The controller lives here so it's scoped to this screen's lifecycle.
  late final ChatController _controller;

  @override
  void initState() {
    super.initState();
    _shuffledQuotes = _loadingQuotes.toList()..shuffle();
    _loadingQuote = _shuffledQuotes[0];
    _startQuoteRotation();
    _initSpeech();
    _inputController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);

    _controller = ChatController();
    _controller.addListener(_onControllerChanged);
    _controller.init();
  }

  void _onControllerChanged() {
    // Auto-scroll when new messages arrive or controller state changes
    if (_controller.messages.isNotEmpty) {
      _scrollToBottom();
    }
    // Cancel quote rotation once ready
    if (_controller.ready) {
      _quoteTimer?.cancel();
    }
  }

  // ---------------------------------------------------------------------------
  // Speech
  // ---------------------------------------------------------------------------

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) {
        setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
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

  // ---------------------------------------------------------------------------
  // Quote rotation (shown while loading)
  // ---------------------------------------------------------------------------

  void _startQuoteRotation() {
    _quoteTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted || _controller.ready) {
        _quoteTimer?.cancel();
        return;
      }
      setState(() => _quoteOpacity = 0.0);
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

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackground = !_appInForeground;
    _appInForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _controller.onAppResumed(wasBackground);
    } else {
      _controller.onAppPaused();
    }
  }

  // ---------------------------------------------------------------------------
  // Scroll
  // ---------------------------------------------------------------------------

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (_showScrollFab == atBottom) {
      setState(() => _showScrollFab = !atBottom);
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

  // ---------------------------------------------------------------------------
  // Chat actions (thin wrappers — delegate to controller)
  // ---------------------------------------------------------------------------

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _controller.sending) return;
    _inputController.clear();
    await _controller.sendMessage(text);
  }

  void _editMessage(int index) {
    if (index >= _controller.messages.length ||
        !_controller.messages[index].isUser) return;
    final text = _controller.messages[index].text;
    _controller.spliceFrom(index);
    _inputController.text = text;
  }

  void _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear chat?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirm == true) {
      await _controller.clearHistory();
    }
  }

  // ---------------------------------------------------------------------------
  // File attachment
  // ---------------------------------------------------------------------------

  Future<void> _pickAndSendFile(BuildContext context, dynamic ctrl) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.single.path!);
    final name = result.files.single.name;
    final ext = name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);

    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);
    final mime = isImage ? 'image/$ext' : 'application/octet-stream';

    // Send as a message with embedded base64 attachment
    final msg = isImage
        ? '[image:$name]\ndata:$mime;base64,$b64'
        : '[file:$name]\ndata:$mime;base64,$b64';

    ctrl.sendMessage(msg);
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _speech.stop();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Provide controller so all descendant widgets can access it.
    return ChangeNotifierProvider<ChatController>.value(
      value: _controller,
      child: Consumer<ChatController>(
        builder: (context, ctrl, _) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          String statusText;
          if (!ctrl.ready && !ctrl.wsConnected) {
            statusText = 'starting...';
          } else if (ctrl.sending) {
            statusText = 'typing...';
          } else if (!ctrl.wsConnected) {
            statusText = 'reconnecting...';
          } else {
            statusText = 'online';
          }

          return Scaffold(
            backgroundColor:
                isDark ? AppColors.darkBg : AppColors.lightSurface,
            appBar: AppBar(
              backgroundColor:
                  isDark ? AppColors.darkSurface : AppColors.accent,
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
                          ctrl.agentName,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          statusText,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                if (ctrl.sending)
                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    onPressed: ctrl.abortRun,
                    tooltip: 'Stop',
                  ),
                IconButton(
                    icon: const Icon(Icons.delete_sweep),
                    onPressed: _clearChat),
              ],
            ),
            drawer: _buildDrawer(isDark, ctrl.agentName),
            body: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      ctrl.messages.isEmpty
                          ? !ctrl.ready
                              ? Stack(
                                  children: [
                                    const MascotAnimation(size: 110),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 40,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: isDark
                                                  ? Colors.white24
                                                  : Colors.black12,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          AnimatedOpacity(
                                            opacity: _quoteOpacity,
                                            duration: const Duration(
                                                milliseconds: 300),
                                            child: Text(
                                              _loadingQuote,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: isDark
                                                    ? Colors.white38
                                                    : Colors.black38,
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.black12,
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              itemCount: ctrl.messages.length,
                              itemBuilder: (context, index) {
                                final widgets = <Widget>[];
                                if (index == 0 ||
                                    _needsDateSeparator(ctrl, index)) {
                                  widgets.add(_buildDateSeparator(
                                      ctrl.messages[index].time));
                                }
                                widgets.add(
                                    _buildMessage(ctrl, ctrl.messages[index], index));
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
                            child: const Icon(Icons.keyboard_arrow_down,
                                color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),

                // Input bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    border: Border(
                        top: BorderSide(
                            color: isDark ? Colors.white10 : Colors.black12)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Attachment button
                        IconButton(
                          icon: Icon(Icons.attach_file,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.black45),
                          onPressed: ctrl.sending ? null : () => _pickAndSendFile(context, ctrl),
                        ),
                        // Input field
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: TextField(
                              controller: _inputController,
                              decoration: const InputDecoration(
                                hintText: 'Message',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                isDense: true,
                              ),
                              textInputAction: TextInputAction.newline,
                              maxLines: 6,
                              minLines: 1,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              enabled: ctrl.ready && !ctrl.sending,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Combo mic/send button
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _isListening
                                ? Colors.red
                                : (ctrl.sending || !ctrl.ready)
                                    ? Colors.grey
                                    : AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: ctrl.sending
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : IconButton(
                                  onPressed: ctrl.ready
                                      ? () {
                                          HapticFeedback.lightImpact();
                                          if (_inputController.text
                                              .trim()
                                              .isNotEmpty) {
                                            _send();
                                          } else {
                                            _toggleListening();
                                          }
                                        }
                                      : null,
                                  icon: Icon(
                                    _isListening
                                        ? Icons.stop
                                        : _inputController.text
                                                .trim()
                                                .isNotEmpty
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
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Drawer
  // ---------------------------------------------------------------------------

  Widget _buildDrawer(bool isDark, String agentName) {
    void nav(Widget screen) {
      Navigator.pop(context);
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen));
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
                color: isDark
                    ? AppColors.darkSurfaceAlt
                    : AppColors.accent.withOpacity(0.1),
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
                  Text(
                    agentName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    'Powered by OpenClaw',
                    style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('New Chat'),
              onTap: () {
                Navigator.pop(context);
                _controller.clearHistory();
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

  // ---------------------------------------------------------------------------
  // Message list helpers
  // ---------------------------------------------------------------------------

  bool _needsDateSeparator(ChatController ctrl, int index) {
    if (index == 0) return true;
    final prev = ctrl.messages[index - 1].time;
    final curr = ctrl.messages[index].time;
    if (prev == null || curr == null) return false;
    return prev.day != curr.day ||
        prev.month != curr.month ||
        prev.year != curr.year;
  }

  bool _isGrouped(ChatController ctrl, int index) {
    if (index == 0) return false;
    final prev = ctrl.messages[index - 1];
    final curr = ctrl.messages[index];
    if (prev.isUser != curr.isUser) return false;
    if (prev.time == null || curr.time == null) return false;
    return curr.time!.difference(prev.time!).inSeconds < 60;
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
      label = diff == 0
          ? 'Today'
          : diff == 1
              ? 'Yesterday'
              : '${time.day}/${time.month}/${time.year}';
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style:
                const TextStyle(fontSize: 12, color: Colors.white70)),
      ),
    );
  }

  Widget _buildMessage(ChatController ctrl, ChatMessage msg, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = msg.isUser;
    final grouped = _isGrouped(ctrl, index);
    final time = msg.time != null && !grouped
        ? '${msg.time!.hour.toString().padLeft(2, '0')}:'
            '${msg.time!.minute.toString().padLeft(2, '0')}'
        : '';

    // Base bubble color
    Color baseBubbleColor = isUser
        ? (isDark ? AppColors.accent : AppColors.accent.withOpacity(0.15))
        : msg.isError
            ? (isDark
                ? const Color(0xFF3D2020)
                : const Color(0xFFFFE0E0))
            : (isDark ? AppColors.darkSurfaceAlt : Colors.white);

    // Subtle hue shift for user messages
    if (isUser && ctrl.messages.length > 1) {
      final t = index / ctrl.messages.length.toDouble();
      final hsl = HSLColor.fromColor(baseBubbleColor);
      final hueShift = (t - 0.5) * 12;
      final lightnessShift = (1 - t) * 0.04;
      baseBubbleColor = hsl
          .withHue((hsl.hue + hueShift) % 360)
          .withLightness(
              (hsl.lightness + lightnessShift).clamp(0.0, 1.0))
          .toColor();
    }

    final bubbleColor = baseBubbleColor;
    final textColor = isDark ? Colors.white : Colors.black87;
    final timeColor = isDark ? Colors.white38 : Colors.black38;

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showMessageMenu(ctrl, msg);
      },
      child: Align(
        alignment:
            isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Agent avatar (non-grouped assistant only)
            if (!isUser && !grouped)
              Padding(
                padding:
                    const EdgeInsets.only(right: 6, bottom: 4),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: isDark
                      ? Colors.white12
                      : AppColors.accent.withOpacity(0.15),
                  child: const MiniMascot(size: 20),
                ),
              )
            else if (!isUser && grouped)
              const SizedBox(width: 34),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width * 0.75,
                ),
                margin: EdgeInsets.only(bottom: grouped ? 2 : 4),
                padding:
                    const EdgeInsets.fromLTRB(12, 8, 12, 6),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft:
                        Radius.circular(isUser ? 12 : 2),
                    bottomRight:
                        Radius.circular(isUser ? 2 : 12),
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
                        onTap: () => setState(
                            () => msg.thinkingCollapsed =
                                !msg.thinkingCollapsed),
                        child: Container(
                          margin:
                              const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.black
                                    .withOpacity(0.04),
                            borderRadius:
                                BorderRadius.circular(6),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.black12,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    msg.thinkingCollapsed
                                        ? Icons.expand_more
                                        : Icons.expand_less,
                                    size: 16,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Thinking…',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle:
                                          FontStyle.italic,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
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
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                    fontStyle:
                                        FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                    // Message content
                    if (!isUser &&
                        msg.text.isEmpty &&
                        ctrl.sending)
                      _TypingDots()
                    else
                      _buildFormattedText(msg.text, textColor),

                    // Timestamp
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(time,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: timeColor)),
                          if (isUser) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.done_all,
                                size: 14, color: timeColor),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        strong: TextStyle(
            fontSize: 14,
            color: defaultColor,
            fontWeight: FontWeight.bold),
        em: TextStyle(
            fontSize: 14,
            color: defaultColor,
            fontStyle: FontStyle.italic),
        code: TextStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          color: defaultColor,
          backgroundColor: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.07),
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        listBullet:
            TextStyle(fontSize: 14, color: defaultColor),
        blockquoteDecoration: BoxDecoration(
          border: Border(
              left: BorderSide(
                  color: defaultColor.withOpacity(0.3),
                  width: 3)),
        ),
        blockquotePadding: const EdgeInsets.only(
            left: 12, top: 4, bottom: 4),
        blockquote: TextStyle(
            fontSize: 14,
            color: defaultColor.withOpacity(0.8),
            fontStyle: FontStyle.italic),
        h1: TextStyle(
            fontSize: 20,
            color: defaultColor,
            fontWeight: FontWeight.bold),
        h2: TextStyle(
            fontSize: 18,
            color: defaultColor,
            fontWeight: FontWeight.bold),
        h3: TextStyle(
            fontSize: 16,
            color: defaultColor,
            fontWeight: FontWeight.bold),
        a: TextStyle(
            fontSize: 14,
            color: Colors.blue.shade300,
            decoration: TextDecoration.underline),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: defaultColor.withOpacity(0.2))),
        ),
      ),
    );
  }

  void _showMessageMenu(ChatController ctrl, ChatMessage msg) {
    final index = ctrl.messages.indexOf(msg);
    final isLastAssistant =
        !msg.isUser && index == ctrl.messages.length - 1;

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
                  const SnackBar(
                      content: Text('Copied'),
                      duration: Duration(seconds: 1)),
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
                  ctrl.regenerate();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                ctrl.deleteMessage(msg);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Typing dots animation
// ---------------------------------------------------------------------------

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
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
            final opacity =
                (1 - (offset * 2 - 1).abs()).clamp(0.3, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 7,
                  height: 7,
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
