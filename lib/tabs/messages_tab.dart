import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
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
  final Set<String> _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(Conversation c) {
    setState(() {
      if (!_selected.remove(c.address)) _selected.add(c.address);
    });
  }

  Future<void> _open(Conversation c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ThreadScreen(address: c.address)),
    );
    if (mounted) context.read<AppState>().loadConversations();
  }

  Future<void> _silenceSelected() async {
    final addresses = _selected.toList();
    await context.read<AppState>().silenceMany(addresses);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _deleteSelected() async {
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $n conversation${n == 1 ? '' : 's'}?'),
        content: const Text(
          'This permanently removes the messages from your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppState>().deleteConversations(_selected.toList());
      if (mounted) setState(_selected.clear);
    }
  }

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
        _selecting ? _selectionBar(scheme, list) : _filterChips(all, silencedCount),
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
                          indent: 84,
                          endIndent: 16,
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          return _ConversationTile(
                            convo: c,
                            selecting: _selecting,
                            selected: _selected.contains(c.address),
                            onTap: () => _selecting ? _toggle(c) : _open(c),
                            onLongPress: () => _toggle(c),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  Widget _filterChips(List<Conversation> all, int silencedCount) {
    Widget chip(String label, int count, _Filter f) => ChoiceChip(
          label: Text('$label · $count'),
          selected: _filter == f,
          onSelected: (_) => setState(() => _filter = f),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Wrap(
        spacing: 8,
        children: [
          chip('All', all.length, _Filter.all),
          chip('Silenced', silencedCount, _Filter.silenced),
          chip('Rings', all.length - silencedCount, _Filter.rings),
        ],
      ),
    );
  }

  Widget _selectionBar(ColorScheme scheme, List<Conversation> list) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () => setState(_selected.clear),
          ),
          Text(
            '${_selected.length} selected',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Select all',
            onPressed: () => setState(
              () => _selected.addAll(list.map((c) => c.address)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_off_outlined),
            tooltip: 'Silence',
            onPressed: _silenceSelected,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: _deleteSelected,
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.convo,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Conversation convo;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final silenced = convo.silenced;
    final unread = convo.unread > 0;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected ? AppColors.primary.withValues(alpha: 0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: silenced
                        ? scheme.surfaceContainerHighest
                        : AppColors.primary.withValues(alpha: 0.12),
                    child: Text(
                      _initial(convo.displayName),
                      style: TextStyle(
                        color: silenced ? scheme.onSurfaceVariant : AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 2),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.check,
                            size: 13, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          convo.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: scheme.onSurface,
                            fontWeight:
                                unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(convo.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: unread ? AppColors.primary : scheme.onSurfaceVariant,
                          fontWeight:
                              unread ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (silenced) ...[
                        Icon(Icons.notifications_off,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          convo.lastBody.replaceAll('\n', ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
                            fontWeight:
                                unread ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${convo.unread}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
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
