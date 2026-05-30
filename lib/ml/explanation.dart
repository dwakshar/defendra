/// Typed output of the rule-matcher explainability pass.
///
/// Kept entirely separate from [ScanResult] / the TFLite inference path.
/// Compose at the call site:
///
///   final verdict     = await mlEngine.classify(text);   // unchanged
///   final explanation = RuleMatcher.explain(text);        // additive
library;

/// Full explainability payload for one SMS.
class Explanation {
  static const empty = Explanation(
    spans: [],
    signals: [],
    reason: 'No signals detected.',
  );

  /// Non-overlapping, sorted spans ready to drive [RichText] highlighting.
  /// Overlapping matches from different rules have been merged (union of ranges).
  final List<TriggerSpan> spans;

  /// Deduplicated, ordered list of fired signal keys (snake_case).
  final List<String> signals;

  /// One human-readable sentence composed from [signals].
  final String reason;

  const Explanation({
    required this.spans,
    required this.signals,
    required this.reason,
  });
}

/// A single contiguous span of matched text, tagged with the signal that fired.
class TriggerSpan {
  /// Byte offset of the first character of the match in the source string.
  final int start;

  /// Byte offset one past the last character (exclusive), same convention as
  /// [String.substring].
  final int end;

  /// The snake_case signal key that produced this span (e.g. 'urgency').
  final String signal;

  const TriggerSpan({
    required this.start,
    required this.end,
    required this.signal,
  });
}
