import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class StatusTab extends StatelessWidget {
  const StatusTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Overall status header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: state.isReady ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              Icon(
                state.isReady ? Icons.verified_user : Icons.gpp_maybe,
                size: 44,
                color: state.isReady ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isReady ? 'Protection is on' : 'Protection is off',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: state.isReady
                                ? scheme.onPrimaryContainer
                                : scheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.isReady
                          ? '${state.activeSilencedCount} senders silenced. '
                              'Everyone else rings.'
                          : 'Complete the steps below to start filtering.',
                      style: TextStyle(
                        color: state.isReady
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text('Setup', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _StatusTile(
                ok: state.isDefaultSmsApp,
                title: 'Default SMS app',
                subtitle: 'Required to intercept and silence messages.',
                actionLabel: 'Set',
                onAction: state.isDefaultSmsApp
                    ? null
                    : () => context.read<AppState>().requestDefaultApp(),
              ),
              const Divider(height: 1),
              _StatusTile(
                ok: state.smsGranted,
                title: 'SMS permission',
                subtitle: 'Read incoming texts and your inbox.',
                actionLabel: 'Grant',
                onAction: state.smsGranted
                    ? null
                    : () => context.read<AppState>().requestPermissions(),
              ),
              const Divider(height: 1),
              _StatusTile(
                ok: state.notificationsGranted,
                title: 'Notifications',
                subtitle: 'Show alerts for messages that are allowed to ring.',
                actionLabel: 'Grant',
                onAction: state.notificationsGranted
                    ? null
                    : () => context.read<AppState>().requestPermissions(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text('How it works', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const _Step(
          number: '1',
          text: 'When a text arrives, SMS Guard checks who sent it.',
        ),
        const _Step(
          number: '2',
          text: 'If the sender is on your silenced list, the message is saved '
              'quietly — no sound, no vibration.',
        ),
        const _Step(
          number: '3',
          text: 'Everyone else rings normally with a sound notification.',
        ),
        const SizedBox(height: 24),
        Text(
          'SMS Guard must remain your default messaging app for filtering to '
          'work. You can switch back any time in Android settings.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.ok,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final bool ok;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        ok ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ok ? Colors.green : scheme.outline,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: ok
          ? null
          : (onAction != null
              ? FilledButton.tonal(onPressed: onAction, child: Text(actionLabel))
              : null),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              number,
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text),
            ),
          ),
        ],
      ),
    );
  }
}
