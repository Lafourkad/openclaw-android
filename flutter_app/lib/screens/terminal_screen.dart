import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Used by Clipboard
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';
import '../app.dart';
import '../services/native_bridge.dart';
import '../widgets/terminal_toolbar.dart';

class TerminalScreen extends StatefulWidget {
  /// Optional command to run automatically when the shell starts.
  final String? initialCommand;
  const TerminalScreen({super.key, this.initialCommand});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  Pty? _pty;

  final ValueNotifier<bool> _ctrlNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _altNotifier = ValueNotifier(false);

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _terminalController = TerminalController();
    _startShell();
  }

  @override
  void dispose() {
    _pty?.kill();
    _terminalController.dispose();
    _ctrlNotifier.dispose();
    _altNotifier.dispose();
    super.dispose();
  }

  Future<void> _startShell() async {
    try {
      final filesDir = await NativeBridge.getFilesDir();
      final nativeLibDir = await NativeBridge.getNativeLibDir();

      final nodeDir = '$filesDir/node';
      final glibcDir = '$filesDir/glibc';
      final ldSo = '$nativeLibDir/libopenclaw-ld.so';

      // Build PATH: node/bin first so `node`, `npm`, `openclaw` are available
      // /data/local/tmp has real node/npm/openclaw wrappers (execve-able, written by GatewayService)
      final path = '/data/local/tmp:$nodeDir/bin:/system/bin:/system/xbin';

      // NOTE: Do NOT set LD_LIBRARY_PATH here — /system/bin/sh uses Android's bionic
      // linker which would find our glibc libc.so (a linker script, not ELF) and crash.
      // Instead we define shell functions below that invoke node/openclaw via ld.so.
      final env = {
        'HOME': filesDir,
        'TMPDIR': '$filesDir/tmp',
        'PATH': path,
        'NODE_PATH': '$nodeDir/lib/node_modules',
        'npm_config_git': '/system/bin/true',
        'UV_USE_IO_URING': '0',
        'CHOKIDAR_USEPOLLING': 'true',
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
        'LANG': 'en_US.UTF-8',
        // Exposed to shell functions below
        'OC_LD': ldSo,
        'OC_GLIBC': '$glibcDir/lib',
        'OC_NODE': '$nodeDir/bin/node',
        'OC_NPM': '$nodeDir/lib/node_modules/npm/bin/npm-cli.js',
        'OC_OPENCLAW': '$nodeDir/bin/openclaw',
        'OC_COMPAT': '$filesDir/patches/glibc-compat.js',
      };

      final pty = Pty.start(
        '/system/bin/sh',
        columns: _terminal.viewWidth,
        rows: _terminal.viewHeight,
        environment: env,
      );

      pty.output.cast<List<int>>().transform(const Utf8Decoder()).listen((data) {
        _terminal.write(data);
      });

      pty.exitCode.then((code) {
        if (mounted) {
          _terminal.write('\r\n[Process exited with code $code]\r\n');
          _terminal.write('[Tap restart to start a new session]\r\n');
        }
      });

      _terminal.onOutput = (data) {
        pty.write(const Utf8Encoder().convert(data));
      };

      _terminal.onResize = (w, h, pw, ph) {
        pty.resize(h, w);
      };

      // Run initial command if provided (e.g. 'openclaw onboard\r\n')
      final initialCmd = widget.initialCommand;

      // Fix libsignal stub if needed (npm installs a broken stub without src/curve.js)
      final libsignalTarget = '$nodeDir/lib/node_modules/openclaw/node_modules/libsignal';
      final libsignalTgz = '$filesDir/patches/libsignal.tgz';
      const nl = '\r\n';
      // libsignal.tgz is a self-contained bundle with all deps (curve25519-js, protobufjs, long)
      pty.write(const Utf8Encoder().convert(
        '[ -f "$libsignalTarget/src/curve.js" ] || '
        '(/system/bin/tar -xzf "$libsignalTgz" --strip-components=1 -C "$libsignalTarget/" 2>/dev/null '
        '&& echo "\\033[0;32mlibsignal + deps installed\\033[0m")$nl',
      ));

      // Define shell functions silently (stty -echo suppresses PTY input echo during init)
      pty.write(const Utf8Encoder().convert([
        'stty -echo$nl',
        'node() { LD_LIBRARY_PATH="\$OC_GLIBC" NODE_OPTIONS="--require \$OC_COMPAT" "\$OC_LD" --library-path "\$OC_GLIBC" "\$OC_NODE" "\$@"; }$nl',
        'npm() { node "\$OC_NPM" "\$@"; }$nl',
        'openclaw() { node "\$OC_OPENCLAW" "\$@"; }$nl',
        'stty echo$nl',
        // Welcome banner
        'echo "\\033[1;32m✓ OpenClaw Terminal\\033[0m — type openclaw, node or npm"$nl',
        if (initialCmd != null) initialCmd,
      ].join('')));

      if (mounted) {
        setState(() {
          _pty = pty;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _restart() {
    _pty?.kill();
    setState(() {
      _loading = true;
      _error = null;
    });
    _terminal.buffer.clear();
    _terminal.buffer.resetVerticalMargins();
    _startShell();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Terminal', style: TextStyle(fontFamily: 'monospace', fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New session',
            onPressed: _restart,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          TerminalToolbar(
            pty: _pty,
            ctrlNotifier: _ctrlNotifier,
            altNotifier: _altNotifier,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 16),
            Text('Starting shell...', style: TextStyle(color: Colors.white54, fontFamily: 'monospace')),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.accent, size: 48),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: () async {
        final selected = _terminalController.selection != null
            ? _terminal.buffer.getText(_terminalController.selection!)
            : null;
        if (selected != null && selected.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: selected));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
            );
          }
        } else {
          // Nothing selected — show paste option
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          final text = data?.text;
          if (text != null && text.isNotEmpty && mounted) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Paste'),
                content: Text(text.length > 100 ? '${text.substring(0, 100)}…' : text),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  TextButton(
                    onPressed: () {
                      _pty?.write(const Utf8Encoder().convert(text));
                      Navigator.pop(context);
                    },
                    child: const Text('Paste'),
                  ),
                ],
              ),
            );
          }
        }
      },
      child: TerminalView(
        _terminal,
        controller: _terminalController,
        autofocus: true,
        backgroundOpacity: 0,
        theme: const TerminalTheme(
          cursor: Color(0xFFDC2626),
          selection: Color(0x80DC2626),
          foreground: Color(0xFFE0E0E0),
          background: Color(0xFF0D0D0D),
          black: Color(0xFF000000),
          red: Color(0xFFDC2626),
          green: Color(0xFF22C55E),
          yellow: Color(0xFFF59E0B),
          blue: Color(0xFF3B82F6),
          magenta: Color(0xFFA855F7),
          cyan: Color(0xFF06B6D4),
          white: Color(0xFFE0E0E0),
          brightBlack: Color(0xFF6B7280),
          brightRed: Color(0xFFEF4444),
          brightGreen: Color(0xFF4ADE80),
          brightYellow: Color(0xFFFBBF24),
          brightBlue: Color(0xFF60A5FA),
          brightMagenta: Color(0xFFC084FC),
          brightCyan: Color(0xFF22D3EE),
          brightWhite: Color(0xFFFFFFFF),
          searchHitBackground: Color(0x80F59E0B),
          searchHitBackgroundCurrent: Color(0x80DC2626),
          searchHitForeground: Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}
