import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
import '../models.dart';
import '../screens/thread_screen.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
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

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Personal, Work…'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.trim().isNotEmpty && mounted) {
      await context.read<AppState>().createFolder(name.trim());
    }
  }

  Future<void> _confirmDeleteFolder(Folder f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${f.name}"?'),
        content: const Text(
          'Conversations stay on your phone; only the folder is removed.',
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
      await context.read<AppState>().deleteFolder(f.id);
    }
  }

  Future<void> _addSelectedToFolder() async {
    final state = context.read<AppState>();
    final folders = state.folders;
    String? folderId;

    if (folders.isEmpty) {
      await _createFolder();
      if (!mounted) return;
      final updated = context.read<AppState>().folders;
      if (updated.isEmpty) return;
      folderId = updated.last.id;
    } else {
      folderId = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  'Add to folder',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              ...folders.map(
                (f) => ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.name),
                  onTap: () => Navigator.pop(ctx, f.id),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('New folder…'),
                onTap: () => Navigator.pop(ctx, '__new__'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

      if (folderId == '__new__') {
        if (!mounted) return;
        await _createFolder();
        if (!mounted) return;
        final updated = context.read<AppState>().folders;
        if (updated.isEmpty) return;
        folderId = updated.last.id;
      }
    }

    if (folderId != null && mounted) {
      await context
          .read<AppState>()
          .addConversationsToFolder(folderId, _selected.toList());
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

    final List<Conversation> list;
    final activeFolderId = state.activeFolderId;
    if (activeFolderId != null) {
      final folder = state.folders.where((f) => f.id == activeFolderId).firstOrNull;
      if (folder != null) {
        final addrSet = folder.addresses.toSet();
        list = all.where((c) => addrSet.contains(c.address)).toList();
      } else {
        list = all;
      }
    } else {
      list = switch (state.msgFilter) {
        MsgFilter.all => all,
        MsgFilter.silenced => all.where((c) => c.silenced).toList(),
        MsgFilter.rings => all.where((c) => !c.silenced).toList(),
      };
    }

    return Column(
      children: [
        if (_selecting) _selectionBar(scheme, list),
        _FolderTabBar(
          folders: state.folders,
          conversations: all,
          activeFolderId: state.activeFolderId,
          onSelect: (id) => state.setActiveFolder(id),
          onLongPressFolder: _confirmDeleteFolder,
          onCreateFolder: _createFolder,
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
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Add to folder',
            onPressed: _addSelectedToFolder,
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

// ── Folder tab bar ─────────────────────────────────────────────────────────────

class _FolderTabBar extends StatelessWidget {
  const _FolderTabBar({
    required this.folders,
    required this.conversations,
    required this.activeFolderId,
    required this.onSelect,
    required this.onLongPressFolder,
    required this.onCreateFolder,
  });

  final List<Folder> folders;
  final List<Conversation> conversations;
  final String? activeFolderId;
  final void Function(String? id) onSelect;
  final void Function(Folder f) onLongPressFolder;
  final VoidCallback onCreateFolder;

  int _unread(Folder f) {
    final addrs = f.addresses.toSet();
    return conversations
        .where((c) => addrs.contains(c.address))
        .fold(0, (s, c) => s + c.unread);
  }

  static String _fmtCount(int n) {
    if (n == 0) return '';
    if (n < 10) return '$n';
    return '${(n ~/ 10) * 10}+';
  }

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        children: [
          _Chip(
            label: 'All',
            active: activeFolderId == null,
            scheme: scheme,
            onTap: () => onSelect(null),
          ),
          ...folders.map(
            (f) => _Chip(
              label: f.name,
              unreadLabel: _fmtCount(_unread(f)),
              active: activeFolderId == f.id,
              scheme: scheme,
              onTap: () => onSelect(f.id),
              onLongPress: () => onLongPressFolder(f),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: onCreateFolder,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: scheme.outlineVariant, width: 1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 15, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'New',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.scheme,
    required this.onTap,
    this.unreadLabel = '',
    this.onLongPress,
  });

  final String label;
  final String unreadLabel;
  final bool active;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            border: Border.all(
              color: active ? AppColors.primary : scheme.outlineVariant,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    color: active ? Colors.white : scheme.onSurfaceVariant,
                  ),
                ),
                if (unreadLabel.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Text(
                    unreadLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? Colors.white.withValues(alpha: 0.8)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Conversation tile ──────────────────────────────────────────────────────────

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
                    backgroundColor: scheme.surfaceContainerHighest,
                    child: Text(
                      _initial(convo.displayName),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
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
                            color: scheme.onSurfaceVariant,
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
                          color: scheme.onSurfaceVariant,
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
                            color: unread
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
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
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${convo.unread}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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
