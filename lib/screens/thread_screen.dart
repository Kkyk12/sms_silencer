import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
import '../models.dart';
import '../native_bridge.dart';
import 'scheduled_messages_screen.dart';

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
  final Set<int> _selectedIds = {};
  int _defaultSubId = -1;
  int _selectedSubId = -1; // tracks which SIM will be used for the next send
  bool _loading = true;
  bool _sending = false;
  String? _name;
  Uint8List? _contactPhoto;
  AppState? _appState; // held for use in dispose()

  bool get _selecting => _selectedIds.isNotEmpty;

  String get _displayName =>
      (_name != null && _name!.trim().isNotEmpty) ? _name!.trim() : widget.address;

  static String _initial(String s) {
    final t = s.trim();
    return t.isEmpty ? '#' : t.substring(0, 1).toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appState = context.read<AppState>();
      final draft = _appState!.getDraft(widget.address);
      if (draft.isNotEmpty) {
        _input.text = draft;
        _input.selection =
            TextSelection.fromPosition(TextPosition(offset: draft.length));
      }
    });
    _load();
    _loadSims();
  }

  Future<void> _loadSims() async {
    final results = await Future.wait([
      NativeBridge.getSims(),
      NativeBridge.getDefaultSmsSubId(),
    ]);
    if (mounted) setState(() {
      _sims = results[0] as List<SimInfo>;
      _defaultSubId = results[1] as int;
      if (_selectedSubId == -1) _selectedSubId = _defaultSubId;
    });
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

  /// Short label for the SIM that will be used on the next send tap.
  String? get _currentSimLabel {
    if (_sims.isEmpty) return null;
    for (final s in _sims) {
      if (s.subId == _selectedSubId) return s.shortLabel;
    }
    if (_sims.length == 1) return _sims.first.shortLabel;
    return _sims.first.shortLabel;
  }

  @override
  void dispose() {
    // Persist whatever is in the text field as a draft (empty = clears draft)
    _appState?.saveDraft(widget.address, _input.text.trim());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      NativeBridge.getThread(widget.address),
      NativeBridge.getContactName(widget.address),
      NativeBridge.getScheduledMessages(widget.address),
      NativeBridge.markRead(widget.address),
    ]);
    if (!mounted) return;
    final photo = context.read<AppState>().contactPhotos[widget.address];
    setState(() {
      _messages = results[0] as List<ThreadMessage>;
      _name = results[1] as String?;
      _scheduled = results[2] as List<ScheduledMessage>;
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

  void _toast(String message, {IconData? icon, bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final bg = error ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = error ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message, style: TextStyle(color: fg))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: bg,
        duration: Duration(seconds: error ? 3 : 2),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ));
  }

  Future<void> _send({int? subId}) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final effectiveSubId = subId ?? _selectedSubId;
    final ok = await NativeBridge.sendSms(widget.address, text,
        subId: effectiveSubId);
    if (!mounted) return;
    if (ok) {
      _input.clear();
      _appState?.saveDraft(widget.address, ''); // clear draft on send
      await _load();
    } else {
      _toast('Couldn\'t send the message.',
          icon: Icons.error_outline_rounded, error: true);
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

  void _toggleMessageSelect(ThreadMessage m) {
    setState(() {
      if (!_selectedIds.remove(m.id)) _selectedIds.add(m.id);
    });
  }

  Future<void> _deleteSelected() async {
    final ids = List<int>.from(_selectedIds);
    setState(() => _selectedIds.clear());
    for (final id in ids) {
      await NativeBridge.deleteMessage(id);
    }
    await _load();
  }

  void _silenceSender() {
    context.read<AppState>().addCustom(widget.address);
    _toast('$_displayName will be silenced.', icon: Icons.volume_off_rounded);
  }

  Future<void> _togglePin() async {
    await context.read<AppState>().togglePin(widget.address);
    if (!mounted) return;
    final pinned = context.read<AppState>().isPinned(widget.address);
    _toast(
      pinned ? '$_displayName pinned.' : '$_displayName unpinned.',
      icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
    );
    setState(() {});
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
        _toast('$_displayName unblocked.', icon: Icons.lock_open_rounded);
      }
    }
  }

  void _markRead() {
    context.read<AppState>().markRead(widget.address);
    _toast('Marked as read.', icon: Icons.mark_email_read_outlined);
  }

  void _openScheduled() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduledMessagesScreen(
          address: widget.address,
          displayName: _displayName,
        ),
      ),
    ).then((_) => _load());
  }

  /// Schedule the current composer text to be sent at a chosen time.
  Future<void> _scheduleMessage() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _toast('Type a message first.',
          icon: Icons.edit_outlined, error: true);
      return;
    }
    final scheduled = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SchedulePickerSheet(),
    );
    if (scheduled == null || !mounted) return;
    if (scheduled.isBefore(DateTime.now())) {
      _toast('Please pick a future time.',
          icon: Icons.schedule_outlined, error: true);
      return;
    }
    await NativeBridge.scheduleMessage(
        widget.address, text, scheduled.millisecondsSinceEpoch);
    _input.clear();
    await _load();
    if (mounted) {
      _toast(
        'Scheduled for ${DateFormat('MMM d, h:mm a').format(scheduled)}.',
        icon: Icons.check_circle_outline_rounded,
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
                    backgroundColor: s.subId == _selectedSubId
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.14),
                    child: Text('${s.slot + 1}',
                        style: TextStyle(
                            color: s.subId == _selectedSubId
                                ? Colors.white
                                : AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                  title: Text(s.label),
                  subtitle: Text(s.shortLabel,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  trailing: s.subId == _selectedSubId
                      ? const Icon(Icons.check, color: AppColors.primary, size: 18)
                      : null,
                  onTap: () {
                    // Only switch the active SIM — do NOT send yet.
                    setState(() => _selectedSubId = s.subId);
                    Navigator.pop(ctx);
                  },
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
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedIds.clear()),
              ),
              title: Text('${_selectedIds.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select all',
                  onPressed: () => setState(
                    () => _selectedIds.addAll(_messages.map((m) => m.id)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: _deleteSelected,
                ),
              ],
            )
          : AppBar(
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  onSelected: (v) {
                    switch (v) {
                      case 'silence': _silenceSender();
                      case 'pin': _togglePin();
                      case 'block': _toggleBlock();
                      case 'read': _markRead();
                      case 'scheduled': _openScheduled();
                    }
                  },
                  itemBuilder: (ctx) {
                    Widget item(IconData ic, String label) => Row(children: [
                          Icon(ic, size: 20),
                          const SizedBox(width: 14),
                          Text(label),
                        ]);
                    return <PopupMenuEntry<String>>[
                      PopupMenuItem(
                        value: 'silence',
                        child: item(Icons.notifications_off_outlined,
                            'Silence sender'),
                      ),
                      PopupMenuItem(
                        value: 'pin',
                        child: item(pinned ? Icons.push_pin : Icons.push_pin_outlined,
                            pinned ? 'Unpin' : 'Pin'),
                      ),
                      PopupMenuItem(
                        value: 'block',
                        child: item(blocked ? Icons.block : Icons.block_outlined,
                            blocked ? 'Unblock' : 'Block'),
                      ),
                      PopupMenuItem(
                        value: 'read',
                        child: item(Icons.mark_email_read_outlined, 'Mark as read'),
                      ),
                      PopupMenuItem(
                        value: 'scheduled',
                        child: item(Icons.schedule_outlined, 'Scheduled'),
                      ),
                    ];
                  },
                ),
              ],
            ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 250 && !_selecting) {
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
                                  size: 56, color: scheme.outlineVariant),
                              const SizedBox(height: 12),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('Say hello below',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant)),
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
                            final prev = i > 0 ? _messages[i - 1] : null;
                            final showDate = prev == null ||
                                !_sameDay(prev.date, m.date);
                            final grouped = !showDate &&
                                prev != null &&
                                prev.outgoing == m.outgoing;
                            final selected = _selectedIds.contains(m.id);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDate) _DateChip(date: m.date),
                                GestureDetector(
                                  onLongPress: () => _toggleMessageSelect(m),
                                  onTap: _selecting
                                      ? () => _toggleMessageSelect(m)
                                      : null,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    color: selected
                                        ? scheme.primary.withValues(alpha: 0.12)
                                        : Colors.transparent,
                                    child: Align(
                                      alignment: m.outgoing
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: _Bubble(
                                        message: m,
                                        tightTop: grouped,
                                        simTag: _simTag(m),
                                        selected: selected,
                                      ),
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
            currentSimLabel: _currentSimLabel,
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
  const _Bubble({
    required this.message,
    this.tightTop = false,
    this.simTag,
    this.selected = false,
  });

  final ThreadMessage message;
  final bool tightTop;
  final String? simTag;
  final bool selected;

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
    this.currentSimLabel,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback? onLongPressSend;
  /// Short SIM label shown below the send button (e.g. "SIM1"). Null = hidden.
  final String? currentSimLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      hintStyle: TextStyle(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.55)),
                      filled: false,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                            color: scheme.outlineVariant, width: 1.2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                            color: scheme.outlineVariant
                                .withValues(alpha: 0.6),
                            width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                            color: scheme.outlineVariant.withValues(alpha: 0.6),
                            width: 1.2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
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
            // SIM label sits below the Row so it never shifts the send button up
            if (currentSimLabel != null && !sending)
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 46,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      currentSimLabel!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                        letterSpacing: 0.3,
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

// ── Drum-wheel schedule picker ────────────────────────────────────────────────

class _SchedulePickerSheet extends StatefulWidget {
  const _SchedulePickerSheet();
  @override
  State<_SchedulePickerSheet> createState() => _SchedulePickerSheetState();
}

class _SchedulePickerSheetState extends State<_SchedulePickerSheet> {
  static const _itemH = 54.0;
  static const _visibleRows = 5; // rows visible at once
  static const _wheelH = _itemH * _visibleRows;

  late final List<DateTime> _days;
  late final FixedExtentScrollController _dayCtrl;
  late final FixedExtentScrollController _hrCtrl;
  late final FixedExtentScrollController _minCtrl;

  int _dayIdx = 0;
  int _hr = 0;
  int _min = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _days = List.generate(365, (i) => today.add(Duration(days: i)));
    // Default: now + 1 hour
    final init = now.add(const Duration(hours: 1));
    _dayIdx = 0;
    _hr = init.hour;
    _min = init.minute;
    _dayCtrl = FixedExtentScrollController(initialItem: _dayIdx);
    _hrCtrl = FixedExtentScrollController(initialItem: _hr);
    _minCtrl = FixedExtentScrollController(initialItem: _min);
  }

  @override
  void dispose() {
    _dayCtrl.dispose();
    _hrCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  DateTime get _combined {
    final d = _days[_dayIdx];
    return DateTime(d.year, d.month, d.day, _hr, _min);
  }

  String _dayLabel(DateTime d) {
    if (d == _days[0]) return 'Today';
    if (_days.length > 1 && d == _days[1]) return 'Tomorrow';
    return DateFormat('EEE, MMM d').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFuture = _combined.isAfter(DateTime.now());

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: scheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Schedule message',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),

        // ── Three-column drum picker ─────────────────────────────────────────
        SizedBox(
          height: _wheelH,
          child: Stack(
            children: [
              // Drums
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Day (wider)
                  Expanded(
                    flex: 54,
                    child: _Drum(
                      controller: _dayCtrl,
                      count: _days.length,
                      itemExtent: _itemH,
                      onChanged: (i) => setState(() => _dayIdx = i),
                      child: (i) => Text(
                        _dayLabel(_days[i]),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w400),
                      ),
                    ),
                  ),
                  // Hour
                  Expanded(
                    flex: 23,
                    child: _Drum(
                      controller: _hrCtrl,
                      count: 24,
                      itemExtent: _itemH,
                      onChanged: (i) => setState(() => _hr = i),
                      child: (i) => Text(
                        '$i'.padLeft(2, '0'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w400),
                      ),
                    ),
                  ),
                  // Minute
                  Expanded(
                    flex: 23,
                    child: _Drum(
                      controller: _minCtrl,
                      count: 60,
                      itemExtent: _itemH,
                      onChanged: (i) => setState(() => _min = i),
                      child: (i) => Text(
                        '$i'.padLeft(2, '0'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w400),
                      ),
                    ),
                  ),
                ],
              ),

              // Top fade
              IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: _itemH * 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.surface,
                          scheme.surface.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom fade
              IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: _itemH * 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          scheme.surface,
                          scheme.surface.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Selection band (two lines around center row)
              IgnorePointer(
                child: Center(
                  child: Container(
                    height: _itemH,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: scheme.outline, width: 1.5),
                        bottom: BorderSide(color: scheme.outline, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Confirm button
        Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32)),
              ),
              onPressed: isFuture ? () => Navigator.pop(context, _combined) : null,
              child: Text(
                isFuture
                    ? 'Schedule for ${DateFormat('MMM d').format(_combined)}'
                      ' at ${DateFormat('HH:mm').format(_combined)}'
                    : 'Pick a future time',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Single scrollable drum column used inside _SchedulePickerSheet.
class _Drum extends StatelessWidget {
  const _Drum({
    required this.controller,
    required this.count,
    required this.itemExtent,
    required this.onChanged,
    required this.child,
  });

  final FixedExtentScrollController controller;
  final int count;
  final double itemExtent;
  final ValueChanged<int> onChanged;
  final Widget Function(int) child;

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: itemExtent,
      diameterRatio: 8,
      perspective: 0.001,
      physics: const FixedExtentScrollPhysics(),
      overAndUnderCenterOpacity: 0.35,
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (_, i) => Center(child: child(i)),
      ),
    );
  }
}
