/// A user-created chat folder that holds a set of conversation addresses.
class Folder {
  final String id;
  final String name;
  final List<String> addresses;

  const Folder({required this.id, required this.name, required this.addresses});

  factory Folder.fromMap(Map<String, dynamic> m) => Folder(
        id: m['id'] as String,
        name: m['name'] as String,
        addresses:
            ((m['addresses'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
}

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

/// One conversation thread (grouped by sender), for the inbox list.
class Conversation {
  final String address;
  final String? name;
  final String lastBody;
  final DateTime date;
  final int count;
  final int unread;
  final bool silenced;
  final bool pinned;
  final bool blocked;

  /// content:// URI for the contact's thumbnail photo; null if no contact photo.
  final String? photoUri;

  Conversation({
    required this.address,
    required this.name,
    required this.lastBody,
    required this.date,
    required this.count,
    required this.unread,
    required this.silenced,
    this.pinned = false,
    this.blocked = false,
    this.photoUri,
  });

  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : address;

  factory Conversation.fromMap(Map<String, dynamic> m) {
    final addr = (m['address'] as String?)?.trim();
    return Conversation(
      address: (addr != null && addr.isNotEmpty) ? addr : 'Unknown',
      name: (m['name'] as String?),
      lastBody: (m['body'] as String?) ?? '',
      date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num?)?.toInt() ?? 0),
      count: (m['count'] as num?)?.toInt() ?? 0,
      unread: (m['unread'] as num?)?.toInt() ?? 0,
      silenced: (m['silenced'] as bool?) ?? false,
      pinned: (m['pinned'] as bool?) ?? false,
      blocked: (m['blocked'] as bool?) ?? false,
      photoUri: m['photoUri'] as String?,
    );
  }
}

/// A message that is queued to be sent at a future time.
class ScheduledMessage {
  final String id;
  final String address;
  final String body;
  final DateTime scheduledTime;

  const ScheduledMessage({
    required this.id,
    required this.address,
    required this.body,
    required this.scheduledTime,
  });

  factory ScheduledMessage.fromMap(Map<String, dynamic> m) => ScheduledMessage(
        id: (m['id'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        scheduledTime: DateTime.fromMillisecondsSinceEpoch(
            (m['timeMillis'] as num?)?.toInt() ?? 0),
      );
}

/// A single message inside a thread (sent or received).
class ThreadMessage {
  final int id;
  final String body;
  final DateTime date;
  final bool outgoing;

  /// Subscription (SIM) id this message was sent/received on; -1 if unknown.
  final int subId;

  ThreadMessage({
    required this.id,
    required this.body,
    required this.date,
    required this.outgoing,
    this.subId = -1,
  });

  factory ThreadMessage.fromMap(Map<String, dynamic> m) => ThreadMessage(
        id: (m['id'] as num?)?.toInt() ?? 0,
        body: (m['body'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num?)?.toInt() ?? 0),
        outgoing: (m['outgoing'] as bool?) ?? false,
        subId: (m['subId'] as num?)?.toInt() ?? -1,
      );
}

/// An active SIM card.
class SimInfo {
  final int subId;
  final int slot;
  final String label;

  const SimInfo({required this.subId, required this.slot, required this.label});

  /// Short tag like "SIM1" / "SIM2" (slot is 0-based).
  String get shortLabel => 'SIM${slot + 1}';

  factory SimInfo.fromMap(Map<String, dynamic> m) => SimInfo(
        subId: (m['subId'] as num?)?.toInt() ?? -1,
        slot: (m['slot'] as num?)?.toInt() ?? 0,
        label: (m['label'] as String?) ?? 'SIM',
      );
}
