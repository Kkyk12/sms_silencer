import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'native_bridge.dart';

/// App-wide state: default-app status, runtime permissions, the silence list,
/// and the conversation list.
class AppState extends ChangeNotifier {
  bool isDefaultSmsApp = false;
  bool smsGranted = false;
  bool notificationsGranted = false;
  bool contactsGranted = false;

  List<SilenceEntry> defaults = <SilenceEntry>[];
  List<String> custom = <String>[];
  List<Conversation> conversations = <Conversation>[];
  bool loadingConversations = false;
  bool _askedDefaultThisSession = false;
  ThemeMode themeMode = ThemeMode.system;

  bool get isReady => isDefaultSmsApp && smsGranted;
  int get mutedDefaultsCount => defaults.where((e) => e.silenced).length;
  int get activeSilencedCount => mutedDefaultsCount + custom.length;

  Future<void> init() async {
    await loadThemeMode();
    await refreshStatus();
    await loadSilenceList();
    await loadConversations();
  }

  Future<void> loadThemeMode() async {
    themeMode = _parseThemeMode(await NativeBridge.getThemeMode());
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await NativeBridge.setThemeMode(_themeModeName(mode));
  }

  static ThemeMode _parseThemeMode(String s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _themeModeName(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  Future<void> refreshOnResume() async {
    await refreshStatus();
    await loadConversations();
  }

  Future<void> refreshStatus() async {
    isDefaultSmsApp = await NativeBridge.isDefaultSmsApp();
    smsGranted = await Permission.sms.isGranted;
    notificationsGranted = await Permission.notification.isGranted;
    contactsGranted = await Permission.contacts.isGranted;
    notifyListeners();
  }

  Future<void> requestPermissions() async {
    await <Permission>[
      Permission.sms,
      Permission.notification,
      Permission.contacts,
    ].request();
    await refreshStatus();
    await loadConversations();
  }

  Future<void> requestDefaultApp() async {
    await NativeBridge.requestDefaultSmsApp();
  }

  /// Proactively ask to become the default SMS app on launch — once per
  /// session, only if not already default.
  Future<void> autoPromptDefaultIfNeeded() async {
    if (_askedDefaultThisSession) return;
    await refreshStatus();
    if (!isDefaultSmsApp) {
      _askedDefaultThisSession = true;
      await requestDefaultApp();
    }
  }

  /// Open this app's system settings page (to "Allow restricted settings").
  Future<void> openSystemAppSettings() async {
    await openAppSettings();
  }

  Future<void> loadSilenceList() async {
    final list = await NativeBridge.getSilenceList();
    defaults = list.defaults;
    custom = list.custom;
    notifyListeners();
  }

  Future<void> toggleDefault(String address, bool silenced) async {
    await NativeBridge.setDefaultSilenced(address, silenced);
    defaults = [
      for (final e in defaults)
        if (e.address == address) e.copyWith(silenced: silenced) else e,
    ];
    notifyListeners();
    await loadConversations();
  }

  Future<void> addCustom(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;
    await NativeBridge.addCustom(trimmed);
    await loadSilenceList();
    await loadConversations();
  }

  Future<void> removeCustom(String address) async {
    await NativeBridge.removeCustom(address);
    await loadSilenceList();
    await loadConversations();
  }

  /// Silence one or more senders (adds them to the custom silence list).
  Future<void> silenceMany(Iterable<String> addresses) async {
    for (final a in addresses) {
      await NativeBridge.addCustom(a);
    }
    await loadSilenceList();
    await loadConversations();
  }

  /// Delete one or more whole conversations from the device.
  Future<void> deleteConversations(Iterable<String> addresses) async {
    for (final a in addresses) {
      await NativeBridge.deleteThread(a);
    }
    await loadConversations();
  }

  Future<void> loadConversations() async {
    if (!smsGranted) {
      conversations = <Conversation>[];
      notifyListeners();
      return;
    }
    loadingConversations = true;
    notifyListeners();
    try {
      conversations = await NativeBridge.getConversations();
    } catch (_) {
      conversations = <Conversation>[];
    }
    loadingConversations = false;
    notifyListeners();
  }
}
