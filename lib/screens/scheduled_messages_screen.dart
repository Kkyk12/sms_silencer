import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../native_bridge.dart';
import 'thread_screen.dart';

class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({
    super.key,
    this.address,
    this.displayName,
  });

  /// When null, shows scheduled messages for ALL conversations.
  final String? address;
  final String? displayName;

  @override
  State<ScheduledMessagesScreen> createState() =>
      _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen> {
  List<ScheduledMessage> _scheduled = [];
  bool _loading = true;

  bool get _allMode => widget.address == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final msgs =
        await NativeBridge.getScheduledMessages(widget.address ?? '');
    msgs.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    if (mounted) setState(() { _scheduled = msgs; _loading = false; });
  }

  /// Best-effort display name for an address (used in all-conversations mode).
  String _nameFor(String address) {
    final convo = context
        .read<AppState>()
        .conversations
        .where((c) => c.address == address)
        .firstOrNull;
    return convo?.displayName ?? address;
  }

  Future<void> _cancel(ScheduledMessage m) async {
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
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel message'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await NativeBridge.cancelScheduledMessage(m.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Scheduled',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              _allMode ? 'All conversations' : (widget.displayName ?? ''),
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _scheduled.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_outlined,
                          size: 56, color: scheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text(
                        'No scheduled messages',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Messages you schedule will appear here',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _scheduled.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 72,
                      color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  itemBuilder: (_, i) {
                    final m = _scheduled[i];
                    final when = DateFormat('EEE, MMM d • HH:mm')
                        .format(m.scheduledTime);
                    final recipient = _allMode ? _nameFor(m.address) : null;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 6),
                      onTap: _allMode
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ThreadScreen(address: m.address),
                                ),
                              ).then((_) => _load())
                          : null,
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: scheme.secondaryContainer,
                        child: Icon(Icons.schedule_outlined,
                            size: 18, color: scheme.onSecondaryContainer),
                      ),
                      title: Text(
                        m.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          recipient == null ? when : '$recipient  •  $when',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: scheme.onSurfaceVariant),
                        tooltip: 'Cancel',
                        onPressed: () => _cancel(m),
                      ),
                    );
                  },
                ),
    );
  }
}
