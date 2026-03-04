import 'package:flutter/material.dart';
import 'terminal_screen.dart';

/// Configure screen — opens the integrated terminal with openclaw configure.
class ConfigureScreen extends StatelessWidget {
  const ConfigureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configure')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gateway Configuration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Use the terminal to configure OpenClaw settings.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            _tile(
              context,
              icon: Icons.settings,
              title: 'openclaw configure',
              subtitle: 'Interactive setup wizard',
              command: 'openclaw configure\r',
            ),
            _tile(
              context,
              icon: Icons.vpn_key,
              title: 'openclaw onboard',
              subtitle: 'Configure API keys and channels',
              command: 'openclaw onboard\r',
            ),
            _tile(
              context,
              icon: Icons.terminal,
              title: 'Terminal',
              subtitle: 'Full shell access',
              command: null,
            ),


          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String? command,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TerminalScreen(initialCommand: command),
          ),
        ),
      ),
    );
  }
}
