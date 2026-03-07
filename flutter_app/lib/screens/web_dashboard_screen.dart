import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../constants.dart';
import '../services/native_bridge.dart';
import '../services/preferences_service.dart';

class WebDashboardScreen extends StatefulWidget {
  final String? url;

  const WebDashboardScreen({super.key, this.url});

  @override
  State<WebDashboardScreen> createState() => _WebDashboardScreenState();
}

class _WebDashboardScreenState extends State<WebDashboardScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) async {
            if (mounted) setState(() => _loading = true);
            // Inject WebSocket patch as early as possible
            await _injectToken();
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => _loading = false);
            // Re-inject in case page reloaded after patch
            await _injectToken();
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = 'Failed to load dashboard: ${error.description}';
              });
            }
          },
        ),
      );
    _loadUrl();
  }

  Future<void> _injectToken() async {
    try {
      final token = await NativeBridge.readGatewayToken();
      // Monkey-patch WebSocket so every connect frame includes:
      // - clientId: 'openclaw-control-ui' (required for dangerouslyDisableDeviceAuth bypass)
      // - token: <gateway token> (for sharedAuthOk)
      final tokenJs = token.isNotEmpty ? '"$token"' : 'null';
      await _controller.runJavaScript('''
        (function() {
          var _WS = window.WebSocket;
          if (_WS.__patched) return;
          function PatchedWS(url, protocols) {
            var ws = protocols ? new _WS(url, protocols) : new _WS(url);
            var _send = ws.send.bind(ws);
            ws.send = function(data) {
              try {
                var msg = JSON.parse(data);
                if (msg && msg.method === 'connect') {
                  if (!msg.params) msg.params = {};
                  msg.params.clientId = 'openclaw-control-ui';
                  msg.params.clientVersion = '1.0.0';
                  msg.params.clientMode = 'ui';
                  var tok = $tokenJs || (window.location.hash.match(/#token=([^&]+)/)||[])[1];
                  if (tok) msg.params.token = tok;
                  data = JSON.stringify(msg);
                }
              } catch(e) {}
              return _send(data);
            };
            return ws;
          }
          PatchedWS.__patched = true;
          PatchedWS.prototype = _WS.prototype;
          PatchedWS.CONNECTING = _WS.CONNECTING;
          PatchedWS.OPEN = _WS.OPEN;
          PatchedWS.CLOSING = _WS.CLOSING;
          PatchedWS.CLOSED = _WS.CLOSED;
          window.WebSocket = PatchedWS;
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _loadUrl() async {
    var url = widget.url;
    if (url == null || url.isEmpty) {
      // Fallback: load saved token URL from preferences
      final prefs = PreferencesService();
      await prefs.init();
      url = prefs.dashboardUrl;
    }
    _controller.loadRequest(Uri.parse(url ?? AppConstants.gatewayUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _error = null;
                _loading = true;
              });
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_off,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        _controller.reload();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_loading)
            const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
