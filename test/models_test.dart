import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bllocker/models.dart';

void main() {
  group('ThreadMessage.fromMap', () {
    test('parses outgoing message with a failed status', () {
      final m = ThreadMessage.fromMap({
        'id': 7,
        'body': 'hi',
        'date': 1700000000000,
        'outgoing': true,
        'status': 'failed',
        'subId': 2,
      });
      expect(m.id, 7);
      expect(m.outgoing, isTrue);
      expect(m.status, SendStatus.failed);
      expect(m.failed, isTrue);
      expect(m.sending, isFalse);
      expect(m.subId, 2);
    });

    test('defaults status to sent when missing', () {
      final m = ThreadMessage.fromMap({'body': 'x', 'outgoing': true});
      expect(m.status, SendStatus.sent);
      expect(m.failed, isFalse);
    });

    test('incoming messages never report failed/sending', () {
      final m = ThreadMessage.fromMap({'outgoing': false, 'status': 'failed'});
      expect(m.failed, isFalse);
      expect(m.sending, isFalse);
    });
  });

  group('Conversation.fromMap', () {
    test('blank address falls back to Unknown', () {
      final c = Conversation.fromMap({'address': '   '});
      expect(c.address, 'Unknown');
    });

    test('parses unread + pinned + blocked flags', () {
      final c = Conversation.fromMap({
        'address': '0912345678',
        'unread': 3,
        'pinned': true,
        'blocked': false,
      });
      expect(c.unread, 3);
      expect(c.pinned, isTrue);
      expect(c.blocked, isFalse);
    });
  });
}
