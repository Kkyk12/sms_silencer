import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/thread_screen.dart';

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

    final all = state.conversations;
    final silencedCount = all.where((c) => c.silenced).length;
    final list = switch (_filter) {
      _Filter.all => all,
      _Filter.silenced => all.where((c) => c.silenced).toList(),
      _Filter.rings => all.where((c) => !c.silenced).toList(),
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
            onRefresh: () => context.read<AppState>().loadConversations(),
            child: (state.loadingConversations && all.isEmpty)
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          _CenteredPrompt(
                            icon: Icons.inbox_outlined,
                            title: 'Nothing here',
                            message: 'No conversations match this filter yet.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 76,
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                        itemBuilder: (_, i) => _ConversationTile(convo: list[i]),
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

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.convo});

  final Conversation convo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final silenced = convo.silenced;
    final unread = convo.unread > 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThreadScreen(address: convo.address),
          ),
        );
        if (context.mounted) context.read<AppState>().loadConversations();
      },
      leading: CircleAvatar(
        radius: 22,
        backgroundColor:
            silenced ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        child: Text(
          _initial(convo.address),
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
              convo.address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDate(convo.date),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: unread ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: unread ? FontWeight.w700 : FontWeight.normal,
                ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(
              silenced ? Icons.notifications_off : Icons.notifications_active,
              size: 14,
              color: silenced ? scheme.onSurfaceVariant : scheme.primary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                convo.lastBody.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (unread) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${convo.unread}',
                  style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
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
