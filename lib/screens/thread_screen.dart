import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
import '../models.dart';
import '../native_bridge.dart';

class ThreadScreen extends StatefulWidget {
  const ThreadScreen({super.key, required this.address});

  final String address;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ThreadMessage> _messages = [];
  List<SimInfo> _sims = [];
  List<ScheduledMessage> _scheduled = [];
  bool _loading = true;
  bool _sending = false;
  String? _name;
  Uint8List? _contactPhoto;

  String get _displayName =>
      (_name != null && _name!.trim().isNotEmpty) ? _name!.trim() : widget.address;

  static String _initial(String s) {
    final t = s.trim();
    return t.isEmpty ? '#' : t.substring(0, 1).toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadSims();
  }

  Future<void> _loadSims() async {
    final sims = await NativeBridge.getSims();
    if (mounted) setState(() => _sims = sims);
  }

  /// SIM tag ("SIM1"/"SIM2") for a message, or null when there's only one SIM
  /// or the message's SIM can't be matched to a current card.
  String? _simTag(ThreadMessage m) {
    if (_sims.length < 2 || m.subId < 0) return null;
    for (final s in _sims) {
      if (s.subId == m.subId) return s.shortLabel;
    }
    return null;
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final msgs = await NativeBridge.getThread(widget.address);
    final name = await NativeBridge.getContactName(widget.address);
    final scheduled =
        await NativeBridge.getScheduledMessages(widget.address);
    await NativeBridge.markRead(widget.address);
    if (!mounted) return;
    // Load contact photo from cache or fetch
    final state = context.read<AppState>();
    Uint8List? photo = state.contactPhotos[widget.address];
    setState(() {
      _messages = msgs;
      _scheduled = scheduled;
      _name = name;
      _contactPhoto = photo;
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send({int subId = -1}) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await NativeBridge.sendSms(widget.address, text, subId: subId);
    if (!mounted) return;
    if (ok) {
      _input.clear();
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t send the message.')),
      );
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _deleteMessage(ThreadMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(m.body, maxLines: 4, overflow: TextOverflow.ellipsis),
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
    if (ok == true) {
      await NativeBridge.deleteMessage(m.id);
      await _load();
    }
  }

  void _silenceSender() {
    context.read<AppState>().addCustom(widget.address);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$_displayName will be silenced.')),
    );
  }

  void _togglePin() {
    context.read<AppState>().togglePin(widget.address);
    final pinned = context.read<AppState>().isPinned(widget.address);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(pinned
              ? '$_displayName pinned.'
              : '$_displayName unpinned.')),
    );
    setState(() {}); // rebuild to update menu icon
  }

  Future<void> _toggleBlock() async {
    final state = context.read<AppState>();
    final blocked = state.isBlocked(widget.address);
    if (!blocked) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Block $_displayName?'),
          content: const Text(
            'New messages from this number will be silently dropped. '
            'You can unblock from this menu.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        await state.addBlocked(widget.address);
        if (mounted) setState(() {});
      }
    } else {
      await state.removeBlocked(widget.address);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_displayName unblocked.')),
        );
      }
    }
  }

  /// Show a bottom sheet with saved quick-reply templates.
  Future<void> _showTemplates() async {
    final state = context.read<AppState>();
    if (state.templates.isEmpty) {
      await _editTemplates();
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Quick replies',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _editTemplates();
                      },
                      child: const Text('Edit'),
                    ),
                  ],
                ),
              ),
              ...state.templates.map(
                (t) => ListTile(
                  title: Text(t, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(ctx);
                    _input.text = t;
                    _input.selection = TextSelection.fromPosition(
                        TextPosition(offset: t.length));
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Edit the template list.
  Future<void> _editTemplates() async {
    final state = context.read<AppState>();
    final templates = List<String>.from(state.templates);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _TemplateEditor(templates: templates),
    );
    if (result != null && mounted) {
      await state.saveTemplates(result);
    }
  }

  /// Schedule the current composer text to be sent at a chosen time.
  Future<void> _scheduleMessage() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a message first.')),
      );
      return;
    }
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final scheduled = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a future time.')),
      );
      return;
    }
    await NativeBridge.scheduleMessage(
        widget.address, text, scheduled.millisecondsSinceEpoch);
    _input.clear();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Scheduled for ${DateFormat('MMM d, h:mm a').format(scheduled)}.'),
        ),
      );
    }
  }

  /// Long-press send: show combined options for scheduling and SIM selection.
  Future<void> _showSendOptions() async {
    if (_input.text.trim().isEmpty) return;
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
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
                'Send options',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.send_rounded),
              title: const Text('Send now'),
              onTap: () { Navigator.pop(ctx); _send(); },
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Schedule send'),
              onTap: () { Navigator.pop(ctx); _scheduleMessage(); },
            ),
            if (_sims.length >= 2) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Send with SIM',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
              ..._sims.map(
                (s) => ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                    child: Text('${s.slot + 1}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                  title: Text(s.label),
                  subtitle: Text(s.shortLabel,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  onTap: () { Navigator.pop(ctx); _send(subId: s.subId); },
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelScheduled(ScheduledMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel scheduled message?'),
        content: Text(m.body, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await NativeBridge.cancelScheduledMessage(m.id);
      await _load();
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final pinned = state.isPinned(widget.address);
    final blocked = state.isBlocked(widget.address);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: scheme.surfaceContainerHighest,
              backgroundImage: _contactPhoto != null
                  ? MemoryImage(_contactPhoto!)
                  : null,
              child: _contactPhoto == null
                  ? Text(
                      _initial(_displayName),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _displayName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_name != null && _name!.trim().isNotEmpty)
                    Text(
                      widget.address,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'silence':
                  _silenceSender();
                case 'pin':
                  _togglePin();
                case 'block':
                  _toggleBlock();
                case 'templates':
                  _editTemplates();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'silence', child: Text('Silence sender')),
              PopupMenuItem(
                  value: 'pin',
                  child: Text(pinned ? 'Unpin conversation' : 'Pin conversation')),
              PopupMenuItem(
                  value: 'block',
                  child: Text(blocked ? 'Unblock number' : 'Block number')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'templates', child: Text('Edit quick replies')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 250) {
                  Navigator.of(context).maybePop();
                }
              },
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                  size: 56,
                                  color: scheme.outlineVariant),
                              const SizedBox(height: 12),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Say hello below',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 16),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) {
                            final m = _messages[i];
                            final prev =
                                i > 0 ? _messages[i - 1] : null;
                            final showDate = prev == null ||
                                !_sameDay(prev.date, m.date);
                            // reduce gap when same sender follows same sender
                            final grouped = !showDate &&
                                prev != null &&
                                prev.outgoing == m.outgoing;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDate)
                                  _DateChip(date: m.date),
                                Align(
                                  alignment: m.outgoing
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: GestureDetector(
                                    onLongPress: () =>
                                        _deleteMessage(m),
                                    child: _Bubble(
                                      message: m,
                                      tightTop: grouped,
                                      simTag: _simTag(m),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
          ),
          if (_scheduled.isNotEmpty)
            _ScheduledSection(
                scheduled: _scheduled, onCancel: _cancelScheduled),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
            onLongPressSend: _showSendOptions,
            onTemplate: _showTemplates,
          ),
        ],
      ),
    );
  }
}

// ── Date separator ─────────────────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  const _DateChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final String label;
    if (d == today) {
      label = 'Today';
    } else if (d == today.subtract(const Duration(days: 1))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('EEE, MMM d').format(date);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chat bubble ────────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.tightTop = false, this.simTag});

  final ThreadMessage message;
  // true when previous message was from the same side — less vertical space
  final bool tightTop;
  // "SIM1"/"SIM2" shown beside the time; null to hide.
  final String? simTag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final out = message.outgoing;

    return Padding(
      padding: EdgeInsets.only(top: tightTop ? 3 : 12),
      child: Column(
        crossAxisAlignment:
            out ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: out
                  ? AppColors.sentBubble
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                // small "tail" corner on the sender's side
                bottomLeft: Radius.circular(out ? 20 : 5),
                bottomRight: Radius.circular(out ? 5 : 20),
              ),
            ),
            child: Text(
              message.body,
              style: TextStyle(
                color: out ? Colors.white : scheme.onSurface,
                height: 1.4,
                fontSize: 15,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
                top: 3, left: out ? 0 : 6, right: out ? 6 : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('h:mm a').format(message.date),
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                if (simTag != null) ...[
                  const SizedBox(width: 5),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    simTag!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Composer ───────────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.onLongPressSend,
    this.onTemplate,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback? onLongPressSend;
  final VoidCallback? onTemplate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Quick reply template button
            IconButton(
              icon: Icon(Icons.format_quote_outlined,
                  color: scheme.onSurfaceVariant),
              tooltip: 'Quick replies',
              onPressed: onTemplate,
              padding: const EdgeInsets.all(10),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Message…',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                    border: InputBorder.none,
                    filled: false,
                    isCollapsed: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            sending
                ? SizedBox(
                    width: 46,
                    height: 46,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onSend,
                      onLongPress: onLongPressSend,
                      child: const SizedBox(
                        width: 46,
                        height: 46,
                        child: Center(
                          child: Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Scheduled messages section ─────────────────────────────────────────────────

class _ScheduledSection extends StatelessWidget {
  const _ScheduledSection(
      {required this.scheduled, required this.onCancel});

  final List<ScheduledMessage> scheduled;
  final void Function(ScheduledMessage) onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Icon(Icons.schedule_outlined,
                    size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Scheduled',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ...scheduled.map(
            (m) => InkWell(
              onTap: () => onCancel(m),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('MMM d, h:mm a').format(m.scheduledTime),
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.close, size: 16, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ── Template editor dialog ─────────────────────────────────────────────────────

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({required this.templates});

  final List<String> templates;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final List<String> _items;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.templates);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _items.add(text));
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quick replies'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_items.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_items[i],
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () =>
                          setState(() => _items.removeAt(i)),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Add a quick reply…',
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _add,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _items),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
