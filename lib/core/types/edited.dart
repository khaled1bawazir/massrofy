/// A tiny "present or absent" wrapper for update parameters — the difference
/// between *"leave this field alone"* and *"set this field to null"*.
///
/// ## Why a plain nullable parameter is not enough (for Flutter/Dart newcomers)
///
/// Consider an update method written the obvious way:
///
/// ```dart
/// Future<void> edit({int id, String? merchant}) { ... }
/// ```
///
/// Called as `edit(id: 1)` and as `edit(id: 1, merchant: null)`, the method
/// body sees **exactly the same thing**: `merchant == null`. There is no way
/// to tell "the caller did not mention the merchant" from "the caller wants
/// the merchant cleared". For an editing screen that must be able to blank a
/// wrongly-parsed merchant name (US-B5), that distinction is the whole
/// feature.
///
/// Wrapping the value one level deep restores it:
///
/// ```dart
/// edit(id: 1);                        // merchant is null      → not changing it
/// edit(id: 1, merchant: Edited(null)); // merchant is Edited(null) → clear it
/// edit(id: 1, merchant: Edited('IKEA'));                        → set it
/// ```
///
/// This is the same idea as Drift's own `Value<T>` (and as `Optional<T>` in
/// other languages). It is defined here in `core/` rather than reusing
/// Drift's so that `features/` code can express an edit without importing the
/// persistence library — architecture §3's layering rule, which allows
/// features to depend on data but keeps the domain vocabulary free of
/// storage types.
///
/// It matters more than it looks in a banking app: an update path that cannot
/// express "clear this" tends to grow a magic sentinel value instead (the
/// empty string, `-1`, `0`), and a magic sentinel in a money or date field is
/// how a real value gets silently destroyed.
library;

/// A value the caller explicitly wants written. Absence of an [Edited] (i.e.
/// a `null` [Edited] itself) means "do not touch this field".
final class Edited<T> {
  final T value;

  const Edited(this.value);

  @override
  String toString() => 'Edited(...)';
}
