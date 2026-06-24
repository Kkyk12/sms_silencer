import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../app_theme.dart';
import '../models.dart';
import 'thread_screen.dart';

/// Full-screen "compose new message" — search existing contacts / type a number.
class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open(String address) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ThreadScreen(address: address)),
    );
  }

  static String _initial(String s) {
    final t = s.trim();
    return t.isEmpty ? '#' : t.substring(0, 1).toUpperCase();
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final sameDay = now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;
    return sameDay
        ? DateFormat('h:mm a').format(date)
        : DateFormat('MMM d').format(date);
  }

  bool get _looksLikeNumber =>
      _query.isNotEmpty &&
      RegExp(r'^[\d\s\+\-\(\)]+$').hasMatch(_query);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final all = state.conversations;

    final filtered = _query.isEmpty
        ? all
        : all.where((c) {
            final q = _query.toLowerCase();
            return c.displayName.toLowerCase().contains(q) ||
                c.address.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('New message')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Search / number input ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.go,
              onChanged: (v) => setState(() => _query = v.trim()),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _open(v.trim());
              },
              decoration: InputDecoration(
                hintText: 'Search name or type a number…',
                prefixIcon:
                    Icon(Icons.search, color: scheme.onSurfaceVariant),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // ── "Open chat with this number" shortcut ──────────────────────
          if (_looksLikeNumber)
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.dialpad,
                    color: AppColors.primary, size: 20),
              ),
              title: Text(
                _query,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Open chat with this number'),
              onTap: () => _open(_query),
            ),

          // ── Section header ─────────────────────────────────────────────
          if (filtered.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                _query.isEmpty ? 'Recent conversations' : 'Results',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
              ),
            ),

          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off,
                            size: 48, color: scheme.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          'No conversations found',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 76,
                      endIndent: 16,
                      color:
                          scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      return _ConvoTile(
                        convo: c,
                        scheme: scheme,
                        onTap: () => _open(c.address),
                        initial: _initial(c.displayName),
                        dateLabel: _formatDate(c.date),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConvoTile extends StatelessWidget {
  const _ConvoTile({
    required this.convo,
    required this.scheme,
    required this.onTap,
    required this.initial,
    required this.dateLabel,
  });

  final Conversation convo;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final String initial;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: scheme.surfaceContainerHighest,
              child: Text(
                initial,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    convo.lastBody.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
