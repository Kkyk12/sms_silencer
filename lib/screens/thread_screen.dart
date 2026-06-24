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
  bool _loading = true;
  bool _sending = false;
  String? _name;

  String get _displayName =>
      (_name != null && _name!.trim().isNotEmpty) ? _name!.trim() : widget.address;

  @override
  void initState() {
    super.initState();
    _load();
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
    await NativeBridge.markRead(widget.address);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _name = name;
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await NativeBridge.sendSms(widget.address, text);
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

  static String _initial(String s) {
    final t = s.trim();
    return t.isEmpty ? '#' : t.substring(0, 1).toUpperCase();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: scheme.surfaceContainerHighest,
              child: Text(
                _initial(_displayName),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
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
              if (v == 'silence') _silenceSender();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'silence', child: Text('Silence sender')),
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
                              Text(
                                'Say hello below',
                                style:
                                    TextStyle(color: scheme.onSurfaceVariant),
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
                            final prev = i > 0 ? _messages[i - 1] : null;
                            final next = i < _messages.length - 1
                                ? _messages[i + 1]
                                : null;
                            final showDate = prev == null ||
                                !_sameDay(prev.date, m.date);
                            final groupedWithPrev = !showDate &&
                                prev != null &&
                                prev.outgoing == m.outgoing;
                            final isLastInGroup = next == null ||
                                next.outgoing != m.outgoing ||
                                !_sameDay(next.date, m.date);
                            return Column(
                              children: [
                                if (showDate)
                                  _DateSeparator(date: m.date),
                                GestureDetector(
                                  onLongPress: () => _deleteMessage(m),
                                  child: _Bubble(
                                    message: m,
                                    grouped: groupedWithPrev,
                                    showTime: isLastInGroup,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
          ),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});

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
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    this.grouped = false,
    this.showTime = true,
  });

  final ThreadMessage message;
  final bool grouped;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final out = message.outgoing;

    return Padding(
      padding: EdgeInsets.only(top: grouped ? 2 : 10),
      child: Column(
        crossAxisAlignment:
            out ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                bottomLeft: Radius.circular(out ? 20 : (grouped ? 20 : 5)),
                bottomRight: Radius.circular(out ? (grouped ? 20 : 5) : 20),
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
          if (showTime)
            Padding(
              padding: EdgeInsets.only(
                  top: 3, left: out ? 0 : 6, right: out ? 6 : 0),
              child: Text(
                DateFormat('h:mm a').format(message.date),
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
                          strokeWidth: 2, color: scheme.onSurfaceVariant),
                    ),
                  )
                : Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onSend,
                      child: const SizedBox(
                        width: 46,
                        height: 46,
                        child: Center(
                          child: Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
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
