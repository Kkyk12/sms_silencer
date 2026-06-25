import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bllocker/identity.dart';

void main() {
  group('normalizeAddress', () {
    test('Ethiopian +251 / 251 / 09 / 9 formats collapse to one key', () {
      const key = '912345678';
      expect(normalizeAddress('+251912345678'), key);
      expect(normalizeAddress('251912345678'), key);
      expect(normalizeAddress('0912345678'), key);
      expect(normalizeAddress('912345678'), key);
      expect(normalizeAddress('+251 91 234 5678'), key);
      expect(normalizeAddress('(0912) 345-678'), key);
    });

    test('different subscriber numbers stay distinct', () {
      expect(
        normalizeAddress('0911223344') == normalizeAddress('0911223345'),
        isFalse,
      );
    });

    test('short codes and alphanumeric sender IDs compare as text', () {
      expect(normalizeAddress('830'), '830');
      expect(normalizeAddress('8161'), '8161');
      expect(normalizeAddress('Safaricom'), 'safaricom');
      expect(normalizeAddress('telebirr'), 'telebirr');
    });
  });

  group('sameAddress', () {
    test('matches the same contact across formats', () {
      expect(sameAddress('+251912345678', '0912345678'), isTrue);
      expect(sameAddress('251912345678', '912345678'), isTrue);
      expect(sameAddress('Awash Bank', 'awash bank'), isTrue);
    });

    test('does not match different numbers or a code vs a number', () {
      expect(sameAddress('0911223344', '0911223345'), isFalse);
      expect(sameAddress('830', '0911000830'), isFalse);
    });
  });
}
