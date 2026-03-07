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
      if (token.isEmpty) return;
      // Fill the Gateway Token field and click Connect
      await _controller.runJavaScript('''
        (function() {
          // Find and fill the token input
          var inputs = document.querySelectorAll('input');
          var tokenInput = null;
          inputs.forEach(function(inp) {
            var v = (inp.value || inp.placeholder || inp.name || inp.id || '').toLowerCase();
            if (v.includes('token') || v.includes('openclaw')) tokenInput = inp;
          });
          if (tokenInput) {
            var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
            nativeInputValueSetter.call(tokenInput, '$token');
            tokenInput.dispatchEvent(new Event('input', {bubbles: true}));
            tokenInput.dispatchEvent(new Event('change', {bubbles: true}));
          }
          // Click the Connect button after a short delay
          setTimeout(function() {
            var btns = document.querySelectorAll('button');
            btns.forEach(function(btn) {
              if (btn.textContent.trim().toLowerCase() === 'connect') {
                btn.click();
              }
            });
          }, 500);
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
