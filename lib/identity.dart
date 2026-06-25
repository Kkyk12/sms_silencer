/// Canonical sender identity — the Dart mirror of `Identity.kt`.
///
/// Conversation grouping, pinning and folder membership must use the *same*
/// rule the native side uses for silence/block matching, otherwise a contact
/// saved as +251… and messaging from 09… drifts out of its folder / loses its
/// pin. Keep this in sync with the Kotlin [Identity] object.
library;

/// Matches any non-digit. Hoisted to a top-level final so we compile the
/// pattern once instead of allocating a RegExp on every [normalizeAddress]
/// call (this runs in the inbox sort/filter hot path).
final RegExp _nonDigits = RegExp(r'\D');

/// Canonical key for an address. Ethiopian numbers collapse to their 9 national
/// digits (+251912345678 / 0912345678 / 912345678 → "912345678"); short codes
/// and alphanumeric sender IDs fall back to their case-folded text.
String normalizeAddress(String raw) {
  final digits = raw.replaceAll(_nonDigits, '');
  if (digits.length >= 12 && digits.startsWith('251')) {
    final rest = digits.substring(3);
    return rest.length <= 9 ? rest : rest.substring(rest.length - 9);
  }
  if (digits.length == 10 && digits.startsWith('0')) {
    return digits.substring(1);
  }
  if (digits.length >= 9) {
    return digits.substring(digits.length - 9);
  }
  return raw.trim().toLowerCase();
}

/// True when two addresses denote the same conversation/sender.
bool sameAddress(String a, String b) =>
    normalizeAddress(a) == normalizeAddress(b);
