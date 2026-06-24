import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'native_bridge.dart';

/// App-wide state: default-app status, runtime permissions, the silence list,
/// and the conversation list.
enum MsgFilter { rings, silenced, all }

class AppState extends ChangeNotifier {
  bool isDefaultSmsApp = false;
  bool smsGranted = false;
  bool notificationsGranted = false;
  bool contactsGranted = false;
  bool phoneGranted = false;

  /// True once the first real status check has completed. Until then the UI
  /// shouldn't show the "not default app" banner (avoids a startup flash).
  bool statusChecked = false;

  List<SilenceEntry> defaults = <SilenceEntry>[];
  List<String> custom = <String>[];
  List<Conversation> conversations = <Conversation>[];
  bool loadingConversations = false;
  bool _askedDefaultThisSession = false;
  ThemeMode themeMode = ThemeMode.system;
  MsgFilter msgFilter = MsgFilter.rings;
  List<Folder> folders = <Folder>[];
  String? activeFolderId;

  Set<String> pinnedAddresses = <String>{};
  Set<String> blockedAddresses = <String>{};
  List<String> templates = <String>[];

  /// Cached contact photo bytes keyed by conversation address.
  final Map<String, Uint8List?> contactPhotos = <String, Uint8List?>{};

  /// In-memory drafts: unsent text per conversation address.
  final Map<String, String> _drafts = <String, String>{};
  String getDraft(String address) => _drafts[address] ?? '';
  void saveDraft(String address, String text) {
    if (text.isEmpty) {
      _drafts.remove(address);
    } else {
      _drafts[address] = text;
    }
    notifyListeners(); // rebuild conversation list to show/hide draft label
  }

  bool get isReady => isDefaultSmsApp && smsGranted;
  int get mutedDefaultsCount => defaults.where((e) => e.silenced).length;
  int get activeSilencedCount => mutedDefaultsCount + custom.length;

  Future<void> init() async {
    await loadThemeMode(); // must be first — drives theme before first frame
    await Future.wait([
      refreshStatus(),
      loadSilenceList(),
      loadConversations(),
      loadFolders(),
      loadPinned(),
      loadBlocked(),
      loadTemplates(),
    ]);
  }

  Future<void> loadThemeMode() async {
    themeMode = _parseThemeMode(await NativeBridge.getThemeMode());
    notifyListeners();
  }

  void setMsgFilter(MsgFilter f) {
    msgFilter = f;
    notifyListeners();
  }

  void setActiveFolder(String? id) {
    activeFolderId = id;
    notifyListeners();
  }

  Future<void> loadFolders() async {
    folders = await NativeBridge.getFolders();
    notifyListeners();
  }

  Future<void> createFolder(String name) async {
    await NativeBridge.createFolder(name);
    await loadFolders();
  }

  Future<void> deleteFolder(String id) async {
    if (activeFolderId == id) activeFolderId = null;
    await NativeBridge.deleteFolder(id);
    await loadFolders();
  }

  Future<void> addConversationsToFolder(
      String folderId, List<String> addresses) async {
    await NativeBridge.addToFolder(folderId, addresses);
    await loadFolders();
  }

  // ── Pinned ─────────────────────────────────────────────────────────────────

  Future<void> loadPinned() async {
    pinnedAddresses = (await NativeBridge.getPinned()).toSet();
    notifyListeners();
  }

  bool isPinned(String address) => pinnedAddresses.contains(address);

  Future<void> addPin(String address) async {
    await NativeBridge.addPin(address);
    pinnedAddresses.add(address);
    notifyListeners();
  }

  Future<void> removePin(String address) async {
    await NativeBridge.removePin(address);
    pinnedAddresses.remove(address);
    notifyListeners();
  }

  Future<void> togglePin(String address) async {
    if (isPinned(address)) {
      await removePin(address);
    } else {
      await addPin(address);
    }
  }

  // ── Blocked ────────────────────────────────────────────────────────────────

  Future<void> loadBlocked() async {
    blockedAddresses = (await NativeBridge.getBlocked()).toSet();
    notifyListeners();
  }

  bool isBlocked(String address) => blockedAddresses.contains(address);

  Future<void> addBlocked(String address) async {
    await NativeBridge.addBlocked(address);
    blockedAddresses.add(address);
    notifyListeners();
  }

  Future<void> removeBlocked(String address) async {
    await NativeBridge.removeBlocked(address);
    blockedAddresses.remove(address);
    notifyListeners();
  }

  // ── Templates ──────────────────────────────────────────────────────────────

  Future<void> loadTemplates() async {
    templates = await NativeBridge.getTemplates();
    notifyListeners();
  }

  Future<void> saveTemplates(List<String> newTemplates) async {
    templates = newTemplates;
    notifyListeners();
    await NativeBridge.saveTemplates(newTemplates);
  }

  // ── Contact photos ─────────────────────────────────────────────────────────

  void _preloadPhotos() {
    for (final c in conversations) {
      if (c.photoUri != null && !contactPhotos.containsKey(c.address)) {
        NativeBridge.getContactPhotoBytes(c.photoUri!).then((bytes) {
          contactPhotos[c.address] = bytes;
          notifyListeners();
        });
      }
    }
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
    phoneGranted = await Permission.phone.isGranted;
    statusChecked = true;
    notifyListeners();
  }

  Future<void> requestPermissions() async {
    await <Permission>[
      Permission.sms,
      Permission.notification,
      Permission.contacts,
      Permission.phone,
    ].request();
    await refreshStatus();
    await loadConversations();
  }

  Future<void> requestDefaultApp() async {
    await NativeBridge.requestDefaultSmsApp();
  }

  /// On launch, make sure we have SMS + notification permission (so allowed
  /// messages can actually alert). Prompts only for whatever is missing.
  Future<void> ensureStartupPermissions() async {
    await refreshStatus();
    if (!smsGranted || !notificationsGranted || !phoneGranted) {
      await requestPermissions();
    }
  }

  Future<void> sendTestNotification() => NativeBridge.testNotification();

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

  Future<void> markRead(String address) async {
    await NativeBridge.markRead(address);
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
    _preloadPhotos();
  }
}
