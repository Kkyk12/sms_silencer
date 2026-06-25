import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'app_theme.dart';
import 'models.dart';
import 'native_bridge.dart';
import 'screens/new_message_screen.dart';
import 'screens/scheduled_messages_screen.dart';
import 'screens/thread_screen.dart';
import 'tabs/messages_tab.dart';
import 'tabs/silenced_tab.dart';
import 'tabs/status_tab.dart';

void main() {
  runApp(const SmsGuardApp());
}

const Color _seed = AppColors.primary;

class SmsGuardApp extends StatelessWidget {
  const SmsGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, state, _) => MaterialApp(
          title: 'SMS Guard',
          debugShowCheckedModeBanner: false,
          themeMode: state.themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: const HomeShell(),
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    ).copyWith(primary: AppColors.primary);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          color: scheme.onSurface,
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.primary.withValues(alpha: 0.14),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      // iOS-style swipe-from-left-edge to go back, on Android too.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  static const _titles = ['Messages', 'Silenced', 'Status'];

  StreamSubscription<Map<String, dynamic>>? _smsSub;
  OverlayEntry? _banner;
  bool _defaultBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Read the launch address first — before any dialogs that could steal focus
      // or cause some devices to clear intent extras on the next resume.
      final addr = await NativeBridge.getInitialAddress();

      final st = context.read<AppState>();
      await st.ensureStartupPermissions();

      if (addr != null && addr.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ThreadScreen(address: addr)),
        );
        return; // skip the default-app prompt when opened from the dialer
      }

      if (mounted) await st.autoPromptDefaultIfNeeded();
    });
    _smsSub = NativeBridge.smsEvents.listen(_onSmsArrived);
  }

  @override
  void dispose() {
    _smsSub?.cancel();
    _banner?.remove();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().refreshOnResume();
      // Some phones take a moment to update the default SMS app registry.
      // Retry a few times so the red banner disappears promptly.
      for (final ms in [600, 1500, 3500]) {
        Future.delayed(Duration(milliseconds: ms), () {
          if (mounted) context.read<AppState>().refreshStatus();
        });
      }
    }
  }

  void _onSmsArrived(Map<String, dynamic> data) {
    // onNewIntent from phone dialer sends this to open a specific thread
    if (data['type'] == 'openThread') {
      final address = data['address'] as String? ?? '';
      if (address.isNotEmpty && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ThreadScreen(address: address)),
        );
        context.read<AppState>().loadConversations();
      }
      return;
    }

    final address = data['sender'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final state = context.read<AppState>();
    final convo = state.conversations
        .where((c) => c.address == address)
        .firstOrNull;
    final displayName = convo?.displayName ?? address;
    state.loadConversations();
    _showBanner(displayName: displayName, address: address, body: body);
  }

  void _showBanner({
    required String displayName,
    required String address,
    required String body,
  }) {
    _banner?.remove();
    _banner = null;
    final entry = OverlayEntry(
      builder: (_) => _SmsBanner(
        displayName: displayName,
        body: body,
        onTap: () {
          _banner?.remove();
          _banner = null;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ThreadScreen(address: address)),
          );
        },
        onDismiss: () {
          _banner?.remove();
          _banner = null;
        },
      ),
    );
    Overlay.of(context).insert(entry);
    _banner = entry;
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Silence a sender'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add a phone number or sender name. Messages from it will be '
              'saved silently.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. +251912345678 or "MyBank"',
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Silence'),
          ),
        ],
      ),
    );
    if (value != null && value.trim().isNotEmpty && mounted) {
      await context.read<AppState>().addCustom(value);
    }
  }

  Future<void> _openNewMessage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewMessageScreen()),
    );
    if (mounted) context.read<AppState>().loadConversations();
  }

  // kept for reference — replaced by _openNewMessage
  Future<void> _showNewMessageDialog() async {
    final controller = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Recipient',
            hintText: 'e.g. +251912345678',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Next'),
          ),
        ],
      ),
    );
    if (number != null && number.trim().isNotEmpty && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ThreadScreen(address: number.trim()),
        ),
      );
      if (mounted) context.read<AppState>().loadConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        leading: _index > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _index = 0),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: SvgPicture.asset(
              'assets/icons/magnifying-glass.svg',
              width: 22,
              height: 22,
              colorFilter:
                  ColorFilter.mode(scheme.onSurface, BlendMode.srcIn),
            ),
            onPressed: () => showSearch(
              context: context,
              delegate: _ConvoSearchDelegate(state.conversations),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'rings':
                  context.read<AppState>().setMsgFilter(MsgFilter.rings);
                case 'silenced':
                  context.read<AppState>().setMsgFilter(MsgFilter.silenced);
                case 'all':
                  context.read<AppState>().setMsgFilter(MsgFilter.all);
                case 'silenced_tab':
                  setState(() => _index = 1);
                case 'status':
                  setState(() => _index = 2);
                case 'scheduled':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ScheduledMessagesScreen()),
                  );
              }
            },
            itemBuilder: (_) {
              final f = state.msgFilter;
              return [
                PopupMenuItem<String>(
                  value: 'rings',
                  child: Row(children: [
                    const Expanded(child: Text('Rings only')),
                    if (f == MsgFilter.rings) const Icon(Icons.check, size: 18),
                  ]),
                ),
                PopupMenuItem<String>(
                  value: 'silenced',
                  child: Row(children: [
                    const Expanded(child: Text('Silenced')),
                    if (f == MsgFilter.silenced) const Icon(Icons.check, size: 18),
                  ]),
                ),
                PopupMenuItem<String>(
                  value: 'all',
                  child: Row(children: [
                    const Expanded(child: Text('All messages')),
                    if (f == MsgFilter.all) const Icon(Icons.check, size: 18),
                  ]),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'scheduled',
                  child: Row(children: [
                    Icon(Icons.schedule_outlined, size: 20),
                    SizedBox(width: 14),
                    Text('Scheduled messages'),
                  ]),
                ),
                const PopupMenuItem<String>(
                  value: 'silenced_tab',
                  child: Text('Silenced senders'),
                ),
                const PopupMenuItem<String>(
                  value: 'status',
                  child: Text('Status'),
                ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.statusChecked &&
              !state.isDefaultSmsApp &&
              !_defaultBannerDismissed)
            _DefaultAppBanner(
              onDismiss: () => setState(() => _defaultBannerDismissed = true),
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [MessagesTab(), SilencedTab(), StatusTab()],
            ),
          ),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              onPressed: _openNewMessage,
              tooltip: 'New message',
              backgroundColor: scheme.surfaceContainerHighest,
              child: Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant),
            )
          : _index == 1
              ? FloatingActionButton.small(
                  onPressed: _showAddDialog,
                  tooltip: 'Add sender',
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: Icon(Icons.add, color: scheme.onSurfaceVariant),
                )
              : null,
    );
  }

}

// ── In-app SMS banner ──────────────────────────────────────────────────────────

class _SmsBanner extends StatefulWidget {
  const _SmsBanner({
    required this.displayName,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  final String displayName;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_SmsBanner> createState() => _SmsBannerState();
}

class _SmsBannerState extends State<_SmsBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween(begin: const Offset(0, -1), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  static String _initial(String s) {
    final t = s.trim();
    return t.isEmpty ? '#' : t.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.of(context).viewPadding.top;

    return Positioned(
      top: top + 10,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: () {
            _timer?.cancel();
            widget.onTap();
          },
          onVerticalDragUpdate: (d) {
            if ((d.primaryDelta ?? 0) < -6) _dismiss();
          },
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            color: scheme.surfaceContainerHigh,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.14),
                    child: Text(
                      _initial(widget.displayName),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.body,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _dismiss,
                    child: Icon(Icons.close,
                        size: 18, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────

/// Searches conversations by contact name, number, or last message text.
class _ConvoSearchDelegate extends SearchDelegate<void> {
  _ConvoSearchDelegate(this.conversations)
      : super(searchFieldLabel: 'Search messages');

  final List<Conversation> conversations;

  List<Conversation> _filtered() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return conversations;
    return conversations.where((c) {
      return c.displayName.toLowerCase().contains(q) ||
          c.address.toLowerCase().contains(q) ||
          c.lastBody.toLowerCase().contains(q);
    }).toList();
  }

  static String _initial(String s) {
    final t = s.trim();
    return t.isEmpty ? '#' : t.substring(0, 1).toUpperCase();
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = _filtered();
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No conversations found',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final c = results[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.surfaceContainerHighest,
            child: Text(
              _initial(c.displayName),
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          title: Text(
            c.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            c.lastBody.replaceAll('\n', ' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            DateFormat('MMM d').format(c.date),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          onTap: () {
            final addr = c.address;
            close(context, null);
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ThreadScreen(address: addr)),
            );
          },
        );
      },
    );
  }
}

/// Persistent reminder shown until the app is set as the default SMS app.
class _DefaultAppBanner extends StatelessWidget {
  const _DefaultAppBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => context.read<AppState>().requestDefaultApp(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: scheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Filtering is off. Tap to set SMS Guard as your '
                        'default messaging app.',
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Clear, high-contrast dismiss button.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: scheme.onErrorContainer,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: scheme.errorContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
