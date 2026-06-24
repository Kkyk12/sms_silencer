import 'package:flutter/services.dart';

import 'models.dart';

/// Thin wrapper over the MethodChannel that talks to MainActivity.kt.
/// Every SMS-framework operation goes through here.
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('sms_guard/native');

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

  static Future<bool> sendSms(String address, String body) async {
    final ok = await _channel
        .invokeMethod<bool>('sendSms', {'address': address, 'body': body});
    return ok ?? false;
  }

  static Future<void> markRead(String address) {
    return _channel.invokeMethod<void>('markRead', {'address': address});
  }
}
