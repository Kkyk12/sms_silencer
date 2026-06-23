import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bllocker/models.dart';

void main() {
  group('SilenceEntry', () {
    test('fromMap parses address and silenced', () {
      final e = SilenceEntry.fromMap({'address': '830', 'silenced': false});
      expect(e.address, '830');
      expect(e.silenced, isFalse);
    });

    test('defaults to silenced when flag missing', () {
      final e = SilenceEntry.fromMap({'address': 'Safaricom'});
      expect(e.silenced, isTrue);
    });

    test('copyWith toggles silenced and keeps address', () {
      const e = SilenceEntry(address: 'telebirr', silenced: true);
      final off = e.copyWith(silenced: false);
      expect(off.address, 'telebirr');
      expect(off.silenced, isFalse);
    });
  });
}
