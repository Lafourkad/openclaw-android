import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/config_generator.dart';

class ChannelStep extends StatefulWidget {
  final OnboardingConfig config;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const ChannelStep({
    super.key,
    required this.config,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<ChannelStep> createState() => _ChannelStepState();
}

class _ChannelStepState extends State<ChannelStep> {
  final _tgTokenController = TextEditingController();
  final _tgUserIdController = TextEditingController();
  final _dcTokenController = TextEditingController();
  final _dcAppIdController = TextEditingController();
  final _dcUserIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tgTokenController.text = widget.config.telegramBotToken;
    _tgUserIdController.text = widget.config.telegramUserId;
    _dcTokenController.text = widget.config.discordBotToken;
    _dcAppIdController.text = widget.config.discordApplicationId;
    _dcUserIdController.text = widget.config.discordUserId;
  }

  @override
  void dispose() {
    _tgTokenController.dispose();
    _tgUserIdController.dispose();
    _dcTokenController.dispose();
    _dcAppIdController.dispose();
    _dcUserIdController.dispose();
    super.dispose();
  }

  bool get _canProceed {
    if (!widget.config.enableTelegram && !widget.config.enableDiscord) {
      return false;
    }
    if (widget.config.enableTelegram && widget.config.telegramBotToken.isEmpty) {
      return false;
    }
    if (widget.config.enableDiscord && widget.config.discordBotToken.isEmpty) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Messaging Channel',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Connect your agent to a messaging platform.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Telegram
        _buildChannelSection(
          theme: theme,
          title: 'Telegram',
          icon: Icons.telegram,
          color: const Color(0xFF0088CC),
          enabled: widget.config.enableTelegram,
          onToggle: (val) => setState(() => widget.config.enableTelegram = val),
          helpText: 'Create a bot via @BotFather on Telegram to get a token.',
          children: [
            TextField(
              controller: _tgTokenController,
              decoration: const InputDecoration(
                labelText: 'Bot Token',
                hintText: '123456789:ABCdefGHIjklMNOpqrsTUVwxyz',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => widget.config.telegramBotToken = val),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tgUserIdController,
              decoration: const InputDecoration(
                labelText: 'Your Telegram User ID (optional)',
                hintText: 'e.g. 5786868666',
                border: OutlineInputBorder(),
                helperText: 'For admin permissions. Get it from @userinfobot',
              ),
              keyboardType: TextInputType.number,
              onChanged: (val) => widget.config.telegramUserId = val,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Discord
        _buildChannelSection(
          theme: theme,
          title: 'Discord',
          icon: Icons.discord,
          color: const Color(0xFF5865F2),
          enabled: widget.config.enableDiscord,
          onToggle: (val) => setState(() => widget.config.enableDiscord = val),
          helpText: 'Create a bot at discord.com/developers/applications.',
          children: [
            TextField(
              controller: _dcTokenController,
              decoration: const InputDecoration(
                labelText: 'Bot Token',
                hintText: 'MTQ3MzM2NTUx...',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => widget.config.discordBotToken = val),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dcAppIdController,
              decoration: const InputDecoration(
                labelText: 'Application ID (optional)',
                hintText: 'e.g. 1473365512787460096',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => widget.config.discordApplicationId = val,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dcUserIdController,
              decoration: const InputDecoration(
                labelText: 'Your Discord User ID (optional)',
                hintText: 'e.g. 334524117174976513',
                border: OutlineInputBorder(),
                helperText: 'For DM permissions. Enable Developer Mode to copy.',
              ),
              onChanged: (val) => widget.config.discordUserId = val,
            ),
          ],
        ),

        const SizedBox(height: 32),

        // Navigation
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _canProceed ? widget.onNext : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChannelSection({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Color color,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required String helpText,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
                const Spacer(),
                Switch(value: enabled, onChanged: onToggle),
              ],
            ),
            if (enabled) ...[
              const SizedBox(height: 8),
              Text(
                helpText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}
