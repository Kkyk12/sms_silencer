import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';
import 'native_bridge.dart';

/// App-wide state: default-app status, runtime permissions, the silence list
/// (built-in defaults + user-added), and the received-message list.
class AppState extends ChangeNotifier {
  bool isDefaultSmsApp = false;
  bool smsGranted = false;
  bool notificationsGranted = false;
  bool contactsGranted = false;

  List<SilenceEntry> defaults = <SilenceEntry>[];
  List<String> custom = <String>[];
  List<SmsMessage> messages = <SmsMessage>[];
  bool loadingMessages = false;

  /// True once everything needed for filtering is in place.
  bool get isReady => isDefaultSmsApp && smsGranted;

  int get mutedDefaultsCount => defaults.where((e) => e.silenced).length;
  int get activeSilencedCount => mutedDefaultsCount + custom.length;

  Future<void> init() async {
    await refreshStatus();
    await loadSilenceList();
    await loadMessages();
  }

  /// Cheap refresh when returning to the foreground (after the system role/
  /// permission dialogs, which happen outside the app).
  Future<void> refreshOnResume() async {
    await refreshStatus();
    await loadMessages();
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
    await loadMessages();
  }

  Future<void> requestDefaultApp() async {
    await NativeBridge.requestDefaultSmsApp();
    // Real status update happens in refreshOnResume() when we come back.
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
    await loadMessages(); // re-evaluate the silenced/rings badges
  }

  Future<void> addCustom(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;
    await NativeBridge.addCustom(trimmed);
    await loadSilenceList();
    await loadMessages();
  }

  Future<void> removeCustom(String address) async {
    await NativeBridge.removeCustom(address);
    await loadSilenceList();
    await loadMessages();
  }

  Future<void> loadMessages() async {
    if (!smsGranted) {
      messages = <SmsMessage>[];
      notifyListeners();
      return;
    }
    loadingMessages = true;
    notifyListeners();
    try {
      messages = await NativeBridge.getMessages();
    } catch (_) {
      messages = <SmsMessage>[];
    }
    loadingMessages = false;
    notifyListeners();
  }
}
