/// The closed set of string transforms a rule pack may name in its
/// `extract[].transform` list (ADR-007 §5.2).
///
/// ## Why the set is closed, and why an unknown name is a hard error
///
/// A rule pack can be **imported by the user** (ADR-007's answer to R-11).
/// If `transform: ["nomalizeNumerals"]` — one letter wrong — silently did
/// nothing, an Arabic-numeral amount would reach `Money.parse` unconverted,
/// fail, and land the message in the review queue. The user would see
/// "couldn't parse" and have no idea their pack has a typo in it. Worse, a
/// transform that partially applied could produce a *wrong number that looks
/// right*, which in a banking app is the failure mode to design against
/// above all others.
///
/// So: [lookup] returns `null` for an unknown name and the loader turns that
/// into a load-time rejection of the whole pack. Fail loudly, at import time,
/// where a human is standing there able to act.
///
/// ## A note for readers new to Dart
///
/// `typedef FieldTransform = String Function(String);` names a *function
/// type*. In Dart, functions are values: they can be stored in a `Map`,
/// passed as arguments, and returned. The map below is therefore a lookup
/// table from a name in JSON to an actual callable — the mechanism that lets
/// declarative data drive real behaviour without any `eval`.
library;

import '../../core/money/numeral_normalizer.dart';

/// A pure, total function from one string to another. Pure matters: these
/// run inside the ingestion isolate on untrusted-ish input, and a transform
/// with a side effect would be unreviewable.
typedef FieldTransform = String Function(String);

abstract final class FieldTransforms {
  /// Trailing store/terminal/reference digit runs and separators that ride
  /// along with a merchant name, e.g. `EXTRA MART 0042` or
  /// `JARIR BOOKSTORE - 7712`.
  ///
  /// Only the **trailing** run is stripped. A leading or embedded number is
  /// often part of the actual brand ("7 ELEVEN", "STC PAY"), and eating it
  /// would merge unrelated merchants — the "too loose" half of risk R-5.
  static final RegExp _trailingRefPattern = RegExp(
    r'[\s\-#,._]*(?:No\.?|#)?\s*\d{2,}\s*$',
    caseSensitive: false,
  );

  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Everything that is not an ASCII digit. Applied *after*
  /// [normalizeNumerals], so Arabic-Indic digits have already become ASCII
  /// and are not thrown away here.
  static final RegExp _nonDigit = RegExp(r'[^0-9]');

  static const Map<String, FieldTransform> _byName = <String, FieldTransform>{
    // Shared with `Money.parse` and manual entry — one implementation, so
    // the numeral rule can never drift between the parser and the form.
    'normalizeNumerals': normalizeNumerals,
    'trim': _trim,
    'upper': _upper,
    'lower': _lower,
    'collapseWs': _collapseWs,
    'stripTrailingRef': _stripTrailingRef,
    'digitsOnly': _digitsOnly,
  };

  /// Returns the transform named [name], or `null` if there is no such
  /// transform. Callers must treat `null` as a rejectable error — see the
  /// library doc comment for why.
  static FieldTransform? lookup(String name) => _byName[name];

  /// The names this build understands, for the loader's error message. A
  /// user staring at "unknown transform 'nomalizeNumerals'" is helped
  /// enormously by being shown the seven valid spellings.
  static Iterable<String> get knownNames => _byName.keys;

  /// Applies [names] left to right. Assumes every name was already validated
  /// at load time.
  static String applyAll(String value, List<String> names) {
    String result = value;
    for (final String name in names) {
      final FieldTransform? transform = lookup(name);
      if (transform != null) {
        result = transform(result);
      }
    }
    return result;
  }

  static String _trim(String v) => v.trim();
  static String _upper(String v) => v.toUpperCase();
  static String _lower(String v) => v.toLowerCase();
  static String _collapseWs(String v) => v.replaceAll(_whitespaceRun, ' ');
  static String _stripTrailingRef(String v) =>
      v.replaceFirst(_trailingRefPattern, '').trim();
  static String _digitsOnly(String v) => v.replaceAll(_nonDigit, '');
}

/// Reduces a captured instrument identifier to the only form this app is
/// permitted to store.
///
/// ## This is a security control, not a formatting helper (NFR-S2)
///
/// Architecture §4.2 is blunt: *"there is no column able to hold a full
/// PAN"*. Bank SMS already print masked identifiers (`****4821`,
/// `SA**...1234`, `xxxx1234`), but a rule pack could capture more than it
/// should — through a badly-written group, or, for an imported pack,
/// deliberately. This function is the last gate before an identifier becomes
/// an [InstrumentReference], and it **cannot be configured to keep more than
/// four digits**. There is no `maskPolicy: "full"`, and adding one would
/// require changing this file, in the open, where a reviewer would see it.
abstract final class InstrumentMask {
  /// The only supported policy name. Any other value is rejected at load
  /// time by the rule-pack loader.
  static const String last4Policy = 'last4';

  static final RegExp _nonDigit = RegExp(r'[^0-9]');

  /// Returns the storable masked form of [captured], e.g. `****4821`.
  ///
  /// Returns `null` when the capture contains fewer than four digits — an
  /// identifier we cannot mask meaningfully is one we decline to record,
  /// rather than storing something misleading like `****7`. The field then
  /// reads as explicitly unknown (AC-B1.3), which is the honest answer.
  static String? maskLast4(String captured) {
    // The captured text has already been through the pipeline's
    // normalisation, so any Arabic-Indic digits are ASCII by now.
    final String digits = captured.replaceAll(_nonDigit, '');
    if (digits.length < 4) {
      return null;
    }
    return '****${digits.substring(digits.length - 4)}';
  }
}
