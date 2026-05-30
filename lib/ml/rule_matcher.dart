import 'explanation.dart';

/// Regex-based high-confidence scam signal detector.
///
/// Each rule carries a snake_case key (for UI chips/signal maps), a
/// human-readable reason string (stored in ScanRecord.triggeredRules), and the
/// compiled pattern. Runs synchronously alongside the ML model.
class RuleMatcher {
  // ---------------------------------------------------------------------------
  // Static rules
  // ---------------------------------------------------------------------------

  static const _ruleSpecs = [
    (
      key: 'shortened_url',
      pattern:
          r'bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly|is\.gd|cutt\.ly|rb\.gy'
          r'|shorturl\.at|tiny\.cc|tr\.im|clck\.ru|shorte\.st|adf\.ly|bc\.vc',
      reason: 'Shortened URL detected',
    ),
    (
      key: 'phone_number',
      pattern: r'(?:(?:\+91|0091|91)?[\s\-]?)[6-9]\d{9}(?!\d)',
      reason: 'Phone number in message body',
    ),
    (
      key: 'amount_mentioned',
      pattern:
          r'(?:₹|\brs\.?|\binr\b|rupees?)\s*[\d,]+'
          r'|\d[\d,]*\s*(?:lakh|crore|rupees?)\b'
          r'|[\d,]+\s*(?:lakh|crore)',
      reason: 'Money amount mentioned',
    ),
    (
      key: 'otp_request',
      // Removed "do not share OTP" / "never share OTP" — protective warnings
      // inside every legitimate bank OTP SMS; caused near-100% false-positive
      // rate on real 2FA messages.
      // Removed bare `\botp\b` and `share.{0,10}otp` — both matched "do not
      // share your OTP" as a substring (prefix outside the pattern window).
      // `send.{0,10}otp` and `otp.{0,10}(share|send|batao)` kept: these
      // indicate the sender is requesting the OTP, not delivering it.
      pattern: r'one.?time.?pass(?:word|code)?'
          r'|send.{0,10}otp|otp.{0,10}(?:share|send|batao|dijiye|do)'
          r'|सत्यापन कोड|ओटीपी',
      reason: 'OTP solicitation',
    ),
    (
      key: 'kyc_fraud',
      pattern:
          r'kyc|know your customer'
          r'|account.{0,20}(?:block|suspend|deactivat|freeze|band)'
          r'|update.{0,10}kyc|complete.{0,10}kyc|re-?kyc'
          r'|verify.{0,10}(?:account|identity|aadhaar|pan)'
          r'|link.{0,10}aadhaar|pan.{0,10}update|aadhaar.{0,10}update'
          r'|खाता.{0,15}(?:बंद|ब्लॉक|निलंबित)|केवाईसी|आधार.{0,10}सत्यापन'
          r'|पैन.{0,10}अपडेट',
      reason: 'KYC / account-block urgency',
    ),
    (
      key: 'bank_impersonation',
      pattern:
          r'\b(?:sbi|hdfc|icici|axis|kotak|pnb|bob|canara|union bank'
          r'|yes bank|idfc|rbl|federal bank|indusind)\b'
          r'|your.{0,10}bank.{0,10}(?:account|card)'
          r'|debit.{0,10}(?:block|suspend|freeze)'
          r'|credit.{0,10}(?:block|suspend|freeze)',
      reason: 'Bank impersonation',
    ),
    (
      key: 'digital_arrest',
      pattern:
          r'digital arrest|cyber crime branch|cybercrime.{0,10}officer'
          r'|c\.b\.i|\bcbi\b|enforcement directorate|\bed\b.{0,15}officer'
          r'|narcotic(?:s)? bureau|\bncb\b|\bfir\b|money laundering'
          r'|arrest warrant|court.{0,10}notice|police.{0,15}warrant|interpol'
          r'|गिरफ्तार|एफआईआर|साइबर क्राइम|प्रवर्तन निदेशालय|सीबीआई'
          r'|मनी लॉन्ड्रिंग',
      reason: 'Law enforcement / digital-arrest impersonation',
    ),
    (
      key: 'lottery',
      pattern:
          r'\blottery\b|\bprize\b|you.{0,10}won|lucky draw|scratch.{0,10}card'
          r'|gift.{0,10}card|selected.{0,10}winner|claim.{0,10}prize'
          r'|congratulations.{0,30}(?:win|prize|reward)|reward.{0,15}crore',
      reason: 'Lottery / prize scam',
    ),
    (
      key: 'job_scam',
      pattern:
          r'work from home|earn.{0,20}(?:per day|daily|roz)'
          r'|part.?time.{0,15}earn|whatsapp.{0,20}job|job.{0,20}whatsapp'
          r'|₹.{0,10}per.{0,5}(?:day|task|click)|task.{0,10}earn'
          r'|telegram.{0,20}earn|ghar baithe.{0,20}(?:earn|paise|kamao)'
          r'|घर बैठे.{0,20}(?:कमाई|पैसे)',
      reason: 'Job scam / WhatsApp recruitment',
    ),
    (
      key: 'delivery_fee',
      pattern:
          r'customs.{0,20}(?:fee|clearance|duty)'
          r'|release.{0,15}package|package.{0,20}(?:held|seized|detained)'
          r'|parcel.{0,20}(?:held|seized|detained)|delivery.{0,10}fee',
      reason: 'Fake customs / delivery fee',
    ),
  ];

  // ---------------------------------------------------------------------------
  // Urgency rule — dynamic: includes the matched word in the reason string.
  // ---------------------------------------------------------------------------

  static const _urgencyKey = 'urgency';

  // Removed bare `\bblock(ed)?\b` and `\bsuspend(ed)?\b` — these fire on
  // legitimate bank notifications ("Your card has been blocked for security").
  // Replaced with action-demand forms: "will be blocked", "get blocked" etc.
  static const _urgencyPattern =
      r'urgent(?:ly)?|immediately|expire[sd]?|expiry|deadline'
      r'|will.{0,5}(?:block|suspend|deactivat)|(?:get|be).{0,5}(?:blocked|suspended)'
      r'|\bdeactivat(?:e[sd]?)?\b'
      r'|\babhi\b|\bturant\b|\bjaldi\b'
      r'|जल्दी|तुरंत|अभी|फौरन';

  static final _urgencyRe = RegExp(_urgencyPattern, caseSensitive: false);

  static final List<RegExp> _compiled = [
    for (final r in _ruleSpecs) RegExp(r.pattern, caseSensitive: false),
  ];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Noun phrase for composing the reason sentence.
  static const _signalNouns = <String, String>{
    'shortened_url': 'a suspicious shortened URL',
    'phone_number': 'an embedded phone number',
    'amount_mentioned': 'a money amount',
    'otp_request': 'an OTP request',
    'kyc_fraud': 'a KYC / account-block prompt',
    'bank_impersonation': 'bank impersonation',
    'digital_arrest': 'law enforcement impersonation',
    'lottery': 'a prize or lottery claim',
    'job_scam': 'a suspicious job offer',
    'delivery_fee': 'a fake delivery fee',
    'urgency': 'urgency language',
  };

  /// All regex match spans across every rule, sorted by start offset.
  /// Used by the detail screen to underline matched phrases in the SMS body.
  static List<RegExpMatch> allMatches(String text) {
    final matches = <RegExpMatch>[
      for (final re in _compiled) ...re.allMatches(text),
      ..._urgencyRe.allMatches(text),
    ];
    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  /// Builds a single sentence from fired signal keys.
  /// e.g. "Contains urgency language, an OTP request, and bank impersonation."
  static String buildReasonSentence(List<String> keys) {
    if (keys.isEmpty) return 'No signals detected.';
    final phrases = keys.map((k) => _signalNouns[k] ?? k).toList();
    if (phrases.length == 1) return 'Contains ${phrases[0]}.';
    final last = phrases.last;
    final rest = phrases.sublist(0, phrases.length - 1);
    return 'Contains ${rest.join(', ')}, and $last.';
  }

  // ---------------------------------------------------------------------------
  // Signal metadata for UI
  // ---------------------------------------------------------------------------

  /// Display label for a signal key (shown inside chips).
  static String chipLabel(String key) => key;

  /// Returns a fully composed [Explanation] for [text]:
  /// merged + sorted [TriggerSpan] list, deduplicated signal keys, and a
  /// human-readable reason sentence.
  ///
  /// Compose at the call site alongside the unchanged classify() result:
  ///   final verdict     = await mlEngine.classify(text);
  ///   final explanation = RuleMatcher.explain(text);
  static Explanation explain(String text) {
    // --- collect raw spans per rule, tagged with signal key ---
    final raw = <TriggerSpan>[];
    for (int i = 0; i < _ruleSpecs.length; i++) {
      for (final m in _compiled[i].allMatches(text)) {
        raw.add(
          TriggerSpan(start: m.start, end: m.end, signal: _ruleSpecs[i].key),
        );
      }
    }
    for (final m in _urgencyRe.allMatches(text)) {
      raw.add(TriggerSpan(start: m.start, end: m.end, signal: _urgencyKey));
    }
    raw.sort((a, b) => a.start.compareTo(b.start));

    // --- merge overlapping spans (union of ranges; keep first signal key) ---
    final spans = <TriggerSpan>[];
    for (final span in raw) {
      if (spans.isEmpty || span.start >= spans.last.end) {
        spans.add(span);
      } else if (span.end > spans.last.end) {
        final prev = spans.last;
        spans[spans.length - 1] = TriggerSpan(
          start: prev.start,
          end: span.end,
          signal: prev.signal,
        );
      }
    }

    // --- deduplicated signal keys in rule-definition order ---
    final seen = <String>{};
    final signals = <String>[];
    for (int i = 0; i < _ruleSpecs.length; i++) {
      if (_compiled[i].hasMatch(text) && seen.add(_ruleSpecs[i].key)) {
        signals.add(_ruleSpecs[i].key);
      }
    }
    if (_urgencyRe.hasMatch(text) && seen.add(_urgencyKey)) {
      signals.add(_urgencyKey);
    }

    return Explanation(
      spans: spans,
      signals: signals,
      reason: buildReasonSentence(signals),
    );
  }

  /// Returns both reason strings and signal keys in a single regex pass.
  /// Prefer this over calling match() + matchSignals() separately.
  static ({List<String> reasons, List<String> keys}) matchAll(String text) {
    final reasons = <String>[];
    final keys = <String>[];
    for (int i = 0; i < _ruleSpecs.length; i++) {
      if (_compiled[i].hasMatch(text)) {
        reasons.add(_ruleSpecs[i].reason);
        keys.add(_ruleSpecs[i].key);
      }
    }
    final urgencyMatch = _urgencyRe.firstMatch(text);
    if (urgencyMatch != null) {
      reasons.add("Urgency language: '${urgencyMatch[0]}'");
      keys.add(_urgencyKey);
    }
    return (reasons: reasons, keys: keys);
  }

  /// Human-readable reason strings for every rule that fires.
  /// Stored in ScanRecord.triggeredRules — do not change format.
  static List<String> match(String text) {
    final triggered = <String>[];
    for (int i = 0; i < _ruleSpecs.length; i++) {
      if (_compiled[i].hasMatch(text)) {
        triggered.add(_ruleSpecs[i].reason);
      }
    }
    final urgencyMatch = _urgencyRe.firstMatch(text);
    if (urgencyMatch != null) {
      triggered.add("Urgency language: '${urgencyMatch[0]}'");
    }
    return triggered;
  }

  // ---------------------------------------------------------------------------
  // Explanation — typed composite result for the detail UI
  // ---------------------------------------------------------------------------

  /// Snake_case signal keys for every rule that fires.
  /// Used by the detail screen for chips and reason sentence.
  static List<String> matchSignals(String text) {
    final keys = <String>[];
    for (int i = 0; i < _ruleSpecs.length; i++) {
      if (_compiled[i].hasMatch(text)) {
        keys.add(_ruleSpecs[i].key);
      }
    }
    if (_urgencyRe.hasMatch(text)) keys.add(_urgencyKey);
    return keys;
  }
}
