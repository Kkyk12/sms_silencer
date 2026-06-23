import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bllocker/models.dart';

void main() {
  group('SmsMessage.fromMap', () {
    test('parses a complete map', () {
      final msg = SmsMessage.fromMap({
        'address': '+1 555 010 1234',
        'body': 'Hello there',
        'date': 1700000000000,
        'silenced': true,
      });

      expect(msg.address, '+1 555 010 1234');
      expect(msg.body, 'Hello there');
      expect(msg.silenced, isTrue);
      expect(msg.date, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('falls back to safe defaults when fields are missing', () {
      final msg = SmsMessage.fromMap({});

      expect(msg.address, 'Unknown');
      expect(msg.body, '');
      expect(msg.silenced, isFalse);
      expect(msg.date.millisecondsSinceEpoch, 0);
    });

    test('treats a blank address as Unknown', () {
      final msg = SmsMessage.fromMap({'address': '   '});
      expect(msg.address, 'Unknown');
    });
  });
}
