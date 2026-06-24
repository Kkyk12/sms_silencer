import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Once the UI is up, proactively ask to be the default SMS app.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        await context.read<AppState>().autoPromptDefaultIfNeeded();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().refreshOnResume();
    }
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

  Widget _navIcon(String asset, Color color) => SvgPicture.asset(
        'assets/icons/$asset',
        width: 26,
        height: 26,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final inactive = scheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: Column(
        children: [
          if (!state.isDefaultSmsApp) const _DefaultAppBanner(),
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
              onPressed: _showNewMessageDialog,
              tooltip: 'New message',
              child: SvgPicture.asset(
                'assets/icons/pencil-simple.svg',
                width: 24,
                height: 24,
                colorFilter:
                    const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            )
          : _index == 1
              ? FloatingActionButton.small(
                  onPressed: _showAddDialog,
                  tooltip: 'Add sender',
                  child: const Icon(Icons.add),
                )
              : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: _navIcon('chat-teardrop-text.svg', inactive),
            selectedIcon: _navIcon('chat-teardrop-text.svg', AppColors.primary),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: _navIcon('bell-slash.svg', inactive),
            selectedIcon: _navIcon('bell-slash.svg', AppColors.primary),
            label: 'Silenced',
          ),
          NavigationDestination(
            icon: _navIcon('shield.svg', inactive),
            selectedIcon: _navIcon('shield.svg', AppColors.primary),
            label: 'Status',
          ),
        ],
      ),
    );
  }
}

/// Persistent reminder shown until the app is set as the default SMS app.
class _DefaultAppBanner extends StatelessWidget {
  const _DefaultAppBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: () => context.read<AppState>().requestDefaultApp(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Filtering is off. Tap to set SMS Guard as your default '
                  'messaging app.',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onErrorContainer),
            ],
          ),
        ),
      ),
    );
  }
}
