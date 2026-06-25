import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class SilencedTab extends StatefulWidget {
  const SilencedTab({super.key});

  @override
  State<SilencedTab> createState() => _SilencedTabState();
}

class _SilencedTabState extends State<SilencedTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();

    final defaults = q.isEmpty
        ? state.defaults
        : state.defaults
              .where((e) => e.address.toLowerCase().contains(q))
              .toList();
    final custom = q.isEmpty
        ? state.custom
        : state.custom.where((a) => a.toLowerCase().contains(q)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        // Explainer
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(Icons.notifications_off, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'These senders are silenced — their texts are saved without '
                  'sound or vibration. Everyone else rings normally.\n\n'
                  'The built-in ones are silenced by default; turn a switch off '
                  'to let that sender ring.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search senders',
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '${state.activeSilencedCount} silenced  ·  '
            '${state.defaults.length} built-in  ·  '
            '${state.custom.length} added by you',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),

        // User-added entries
        if (custom.isNotEmpty) ...[
          const _SectionHeader('Added by you'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < custom.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -2),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: scheme.tertiaryContainer,
                      child: Icon(
                        Icons.person,
                        size: 16,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    title: Text(
                      custom[i],
                      style: const TextStyle(fontSize: 14),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => _confirmRemove(context, custom[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Built-in defaults with toggles
        if (defaults.isNotEmpty) ...[
          const _SectionHeader('Built-in (silenced by default)'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < defaults.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -4,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: scheme.surfaceContainerHighest,
                      child: Text(
                        defaults[i].address.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    title: Text(
                      defaults[i].address,
                      style: const TextStyle(fontSize: 14),
                    ),
                    trailing: SizedBox(
                      width: 40,
                      child: Transform.scale(
                        scale: 0.7,
                        child: Switch(
                          value: defaults[i].silenced,
                          onChanged: (v) => context
                              .read<AppState>()
                              .toggleDefault(defaults[i].address, v),
                        ),
                      ),
                    ),
                    onTap: () => context.read<AppState>().toggleDefault(
                      defaults[i].address,
                      !defaults[i].silenced,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        if (defaults.isEmpty && custom.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No senders match "$_query".',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context, String address) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove sender?'),
        content: Text('$address will ring normally from now on.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true && context.mounted) {
      await context.read<AppState>().removeCustom(address);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
