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
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
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
      // Inject token into the dashboard's localStorage and trigger connect
      await _controller.runJavaScript('''
        (function() {
          // Save token to localStorage so dashboard remembers it
          localStorage.setItem('openclaw_gateway_token', '$token');
          localStorage.setItem('gatewayToken', '$token');
          // Try to find the token input and fill it
          var inputs = document.querySelectorAll('input[type="text"], input[type="password"], input:not([type])');
          inputs.forEach(function(inp) {
            var label = inp.placeholder || inp.name || inp.id || '';
            if (label.toLowerCase().includes('token') || label.includes('GATEWAY')) {
              inp.value = '$token';
              inp.dispatchEvent(new Event('input', {bubbles: true}));
              inp.dispatchEvent(new Event('change', {bubbles: true}));
            }
          });
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
