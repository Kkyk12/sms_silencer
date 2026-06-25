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
            color: state.isReady
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              Icon(
                state.isReady ? Icons.verified_user : Icons.gpp_maybe,
                size: 44,
                color: state.isReady
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.read<AppState>().sendTestNotification(),
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Send test notification'),
          ),
        ),

        if (!state.isDefaultSmsApp) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Phone won't let you set it as default?",
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Some phones (e.g. Samsung) block apps installed outside the '
                  'Play Store from becoming the default SMS app. To allow it:\n'
                  '1. Open app settings below\n'
                  '2. Tap ⋮ (top-right) → "Allow restricted settings"\n'
                  '3. Come back and tap "Set" again',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.read<AppState>().openSystemAppSettings(),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open app settings'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
          ],
          selected: {state.themeMode},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              context.read<AppState>().setThemeMode(s.first),
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
          text:
              'If the sender is on your silenced list, the message is saved '
              'quietly — no sound, no vibration.',
        ),
        const _Step(
          number: '3',
          text: 'Everyone else rings normally with a sound notification.',
        ),
        const SizedBox(height: 24),

        Text('Your privacy', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: const [
              _PrivacyPoint(
                icon: Icons.lock_outline,
                title: 'Everything stays on your phone',
                body:
                    'The app has no Internet access (check Android’s app '
                    'permissions to confirm), so your messages and contacts '
                    'can’t be sent anywhere. No servers, accounts, ads or '
                    'analytics.',
              ),
              Divider(height: 1),
              _PrivacyPoint(
                icon: Icons.visibility_outlined,
                title: 'Read only to filter',
                body:
                    'Texts are read for one reason: to decide whether each '
                    'one should ring or stay silent, and to show them in this app.',
              ),
              Divider(height: 1),
              _PrivacyPoint(
                icon: Icons.center_focus_strong_outlined,
                title: 'One job, done well',
                body:
                    'SMS Guard silences the senders you choose — nothing '
                    'more. Your silence list is stored only on this device.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'SMS Guard must remain your default messaging app for filtering to '
          'work. You can switch back any time in Android settings.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
                ? FilledButton.tonal(
                    onPressed: onAction,
                    child: Text(actionLabel),
                  )
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

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
