import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'models.dart';

/// Thin wrapper over the MethodChannel that talks to MainActivity.kt.
/// Every SMS-framework operation goes through here.
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('sms_guard/native');
  static const EventChannel _events = EventChannel('sms_guard/events');

  /// Stream of incoming non-silenced SMS events while the app is in the
  /// foreground. Each event is a map with "sender" and "body" keys.
  static Stream<Map<String, dynamic>> get smsEvents =>
      _events.receiveBroadcastStream().map(
            (e) => Map<String, dynamic>.from(e as Map),
          );

  /// Is this app currently Android's default SMS app? Filtering only works if so.
  static Future<bool> isDefaultSmsApp() async {
    final result = await _channel.invokeMethod<bool>('isDefaultSmsApp');
    return result ?? false;
  }

  /// Opens the system prompt asking the user to make this the default SMS app.
  static Future<void> requestDefaultSmsApp() {
    return _channel.invokeMethod<void>('requestDefaultSmsApp');
  }

  /// Built-in defaults (with on/off state) + user-added silenced entries.
  static Future<SilenceList> getSilenceList() async {
    final res = await _channel.invokeMapMethod<String, dynamic>('getSilenceList');
    if (res == null) return const SilenceList(defaults: [], custom: []);
    final defaultsRaw = (res['defaults'] as List?) ?? const [];
    final customRaw = (res['custom'] as List?) ?? const [];
    return SilenceList(
      defaults: defaultsRaw
          .map((e) => SilenceEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      custom: customRaw.map((e) => e.toString()).toList(),
    );
  }

  /// Toggle a built-in default sender on (silenced) or off (rings).
  static Future<void> setDefaultSilenced(String address, bool silenced) {
    return _channel.invokeMethod<void>(
      'setDefaultSilenced',
      {'address': address, 'silenced': silenced},
    );
  }

  static Future<void> addCustom(String address) {
    return _channel.invokeMethod<void>('addCustom', {'address': address});
  }

  static Future<void> removeCustom(String address) {
    return _channel.invokeMethod<void>('removeCustom', {'address': address});
  }

  static Future<List<SmsMessage>> getMessages() async {
    final result = await _channel.invokeListMethod<dynamic>('getMessages');
    if (result == null) return <SmsMessage>[];
    return result
        .map((e) => SmsMessage.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// One entry per conversation (sender), newest first.
  static Future<List<Conversation>> getConversations() async {
    final raw = await _channel.invokeListMethod<dynamic>('getConversations');
    if (raw == null) return <Conversation>[];
    return raw
        .map((e) => Conversation.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// All messages with one address, oldest first.
  static Future<List<ThreadMessage>> getThread(String address) async {
    final raw =
        await _channel.invokeListMethod<dynamic>('getThread', {'address': address});
    if (raw == null) return <ThreadMessage>[];
    return raw
        .map((e) => ThreadMessage.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<bool> sendSms(String address, String body,
      {int subId = -1}) async {
    final ok = await _channel.invokeMethod<bool>(
      'sendSms',
      {'address': address, 'body': body, 'subId': subId},
    );
    return ok ?? false;
  }

  /// Active SIM cards on the device (empty if READ_PHONE_STATE not granted).
  static Future<List<SimInfo>> getSims() async {
    final raw = await _channel.invokeListMethod<dynamic>('getSims');
    if (raw == null) return <SimInfo>[];
    return raw
        .map((e) => SimInfo.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> markRead(String address) {
    return _channel.invokeMethod<void>('markRead', {'address': address});
  }

  /// Saved contact name for a number, or null if not in Contacts.
  static Future<String?> getContactName(String address) {
    return _channel.invokeMethod<String>('getContactName', {'address': address});
  }

  static Future<String> getThemeMode() async {
    return (await _channel.invokeMethod<String>('getThemeMode')) ?? 'system';
  }

  static Future<void> setThemeMode(String mode) {
    return _channel.invokeMethod<void>('setThemeMode', {'mode': mode});
  }

  static Future<bool> deleteThread(String address) async {
    return (await _channel
            .invokeMethod<bool>('deleteThread', {'address': address})) ??
        false;
  }

  static Future<bool> deleteMessage(int id) async {
    return (await _channel.invokeMethod<bool>('deleteMessage', {'id': id})) ??
        false;
  }

  static Future<void> testNotification() {
    return _channel.invokeMethod<void>('testNotification');
  }

  static Future<List<Folder>> getFolders() async {
    final raw = await _channel.invokeListMethod<dynamic>('getFolders');
    if (raw == null) return [];
    return raw
        .map((e) => Folder.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<String> createFolder(String name) async {
    return (await _channel
            .invokeMethod<String>('createFolder', {'name': name})) ??
        '';
  }

  static Future<void> deleteFolder(String id) {
    return _channel.invokeMethod<void>('deleteFolder', {'id': id});
  }

  static Future<void> addToFolder(
      String folderId, List<String> addresses) {
    return _channel.invokeMethod<void>(
        'addToFolder', {'folderId': folderId, 'addresses': addresses});
  }

  // ── Pinned ────────────────────────────────────────────────────────────────

  static Future<List<String>> getPinned() async {
    final raw = await _channel.invokeListMethod<dynamic>('getPinned');
    return raw?.map((e) => e.toString()).toList() ?? [];
  }

  static Future<void> addPin(String address) =>
      _channel.invokeMethod<void>('addPin', {'address': address});

  static Future<void> removePin(String address) =>
      _channel.invokeMethod<void>('removePin', {'address': address});

  // ── Blocked ───────────────────────────────────────────────────────────────

  static Future<List<String>> getBlocked() async {
    final raw = await _channel.invokeListMethod<dynamic>('getBlocked');
    return raw?.map((e) => e.toString()).toList() ?? [];
  }

  static Future<void> addBlocked(String address) =>
      _channel.invokeMethod<void>('addBlocked', {'address': address});

  static Future<void> removeBlocked(String address) =>
      _channel.invokeMethod<void>('removeBlocked', {'address': address});

  // ── Quick reply templates ─────────────────────────────────────────────────

  static Future<List<String>> getTemplates() async {
    final raw = await _channel.invokeListMethod<dynamic>('getTemplates');
    return raw?.map((e) => e.toString()).toList() ?? [];
  }

  static Future<void> saveTemplates(List<String> templates) =>
      _channel.invokeMethod<void>('saveTemplates', {'templates': templates});

  // ── Scheduled messages ────────────────────────────────────────────────────

  static Future<String> scheduleMessage(
      String address, String body, int timeMillis) async {
    return (await _channel.invokeMethod<String>(
          'scheduleMessage',
          {'address': address, 'body': body, 'timeMillis': timeMillis},
        )) ??
        '';
  }

  static Future<void> cancelScheduledMessage(String msgId) =>
      _channel.invokeMethod<void>('cancelScheduledMessage', {'msgId': msgId});

  static Future<List<ScheduledMessage>> getScheduledMessages(
      String address) async {
    final raw =
        await _channel.invokeListMethod<dynamic>('getScheduledMessages');
    if (raw == null) return [];
    return raw
        .map((e) =>
            ScheduledMessage.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((m) => m.address == address || address.isEmpty)
        .toList();
  }

  // ── Contact photos ────────────────────────────────────────────────────────

  static Future<Uint8List?> getContactPhotoBytes(String photoUri) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
        'getContactPhotoBytes', {'photoUri': photoUri});
    return bytes;
  }

  // ── Intent deep-link ──────────────────────────────────────────────────────

  /// Phone number/address from the launching intent, or null if the app was
  /// opened normally (not via a "Send message" shortcut in the phone dialer).
  static Future<String?> getInitialAddress() {
    return _channel.invokeMethod<String>('getInitialAddress');
  }

  // ── Default SMS SIM ───────────────────────────────────────────────────────

  /// The subscription ID of the default SMS SIM (-1 if unavailable).
  static Future<int> getDefaultSmsSubId() async {
    return (await _channel.invokeMethod<int>('getDefaultSmsSubId')) ?? -1;
  }
}
