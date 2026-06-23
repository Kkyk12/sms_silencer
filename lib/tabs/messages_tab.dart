import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';

enum _Filter { all, silenced, rings }

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    if (!state.smsGranted) {
      return _CenteredPrompt(
        icon: Icons.lock_outline,
        title: 'SMS permission needed',
        message: 'Grant SMS access so SMS Guard can read your inbox.',
        actionLabel: 'Grant permission',
        onAction: () => context.read<AppState>().requestPermissions(),
      );
    }

    final all = state.messages;
    final silencedCount = all.where((m) => m.silenced).length;
    final list = switch (_filter) {
      _Filter.all => all,
      _Filter.silenced => all.where((m) => m.silenced).toList(),
      _Filter.rings => all.where((m) => !m.silenced).toList(),
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(
            spacing: 8,
            children: [
              _chip('All', all.length, _Filter.all),
              _chip('Silenced', silencedCount, _Filter.silenced),
              _chip('Rings', all.length - silencedCount, _Filter.rings),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => context.read<AppState>().loadMessages(),
            child: (state.loadingMessages && all.isEmpty)
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          _CenteredPrompt(
                            icon: Icons.inbox_outlined,
                            title: 'Nothing here',
                            message: 'No messages match this filter yet.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                        itemBuilder: (_, i) => _MessageTile(message: list[i]),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, int count, _Filter f) {
    return ChoiceChip(
      label: Text('$label · $count'),
      selected: _filter == f,
      onSelected: (_) => setState(() => _filter = f),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final SmsMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final silenced = message.silenced;
    final accent = silenced ? scheme.onSurfaceVariant : scheme.primary;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor:
            silenced ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        child: Text(
          _initial(message.address),
          style: TextStyle(
            color: silenced ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              message.address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (message.date.millisecondsSinceEpoch > 0)
            Text(_formatDate(message.date),
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      isThreeLine: true,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(message.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                silenced ? Icons.notifications_off : Icons.notifications_active,
                size: 14,
                color: accent,
              ),
              const SizedBox(width: 4),
              Text(
                silenced ? 'Silenced' : 'Rings',
                style: TextStyle(
                    color: accent, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _initial(String s) {
    final t = s.trim();
    return t.isEmpty ? '#' : t.substring(0, 1).toUpperCase();
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final sameDay =
        now.year == date.year && now.month == date.month && now.day == date.day;
    return sameDay
        ? DateFormat('h:mm a').format(date)
        : DateFormat('MMM d').format(date);
  }
}

class _CenteredPrompt extends StatelessWidget {
  const _CenteredPrompt({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
