/// A single received SMS, as read from the Android inbox via the native bridge.
class SmsMessage {
  final String address;
  final String body;
  final DateTime date;

  /// Whether this sender is currently silenced (no sound). Otherwise it rings.
  final bool silenced;

  SmsMessage({
    required this.address,
    required this.body,
    required this.date,
    required this.silenced,
  });

  factory SmsMessage.fromMap(Map<String, dynamic> map) {
    final millis = (map['date'] as num?)?.toInt() ?? 0;
    final addr = (map['address'] as String?)?.trim();
    return SmsMessage(
      address: (addr != null && addr.isNotEmpty) ? addr : 'Unknown',
      body: (map['body'] as String?) ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(millis),
      silenced: (map['silenced'] as bool?) ?? false,
    );
  }
}

/// A built-in (default) sender that can be silenced or allowed to ring.
class SilenceEntry {
  final String address;
  final bool silenced;

  const SilenceEntry({required this.address, required this.silenced});

  factory SilenceEntry.fromMap(Map<String, dynamic> map) => SilenceEntry(
        address: (map['address'] as String?) ?? '',
        silenced: (map['silenced'] as bool?) ?? true,
      );

  SilenceEntry copyWith({bool? silenced}) =>
      SilenceEntry(address: address, silenced: silenced ?? this.silenced);
}

/// The full silence configuration: built-in defaults plus user-added entries.
class SilenceList {
  final List<SilenceEntry> defaults;
  final List<String> custom;

  const SilenceList({required this.defaults, required this.custom});
}
