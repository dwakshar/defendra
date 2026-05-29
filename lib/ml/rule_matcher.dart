/// Regex-based high-confidence scam signal detector.
///
/// Runs synchronously alongside the ML model. Each rule either produces a
/// static reason string or, for urgency words, captures the matched term so
/// the UI can surface exactly which word triggered it.
class RuleMatcher {
  // ---------------------------------------------------------------------------
  // Static rules — reason string is always the same regardless of match text.
  // Pattern strings are const; compiled RegExps are lazy static finals.
  // ---------------------------------------------------------------------------

  static const _ruleSpecs = [
    (
      pattern:
          r'bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly|is\.gd|cutt\.ly|rb\.gy'
          r'|shorturl\.at|tiny\.cc|tr\.im|clck\.ru|shorte\.st|adf\.ly|bc\.vc',
      reason: 'Shortened URL detected',
    ),
    (
      // Indian mobile: optional +91 / 0 prefix, then [6-9] + 9 digits.
      pattern: r'(?:(?:\+91|0091|91)?[\s\-]?)[6-9]\d{9}(?!\d)',
      reason: 'Phone number in message body',
    ),
    (
      // ₹ / Rs / INR / rupees / lakh / crore followed by or preceded by digits.
      pattern: r'(?:₹|\brs\.?|\binr\b|rupees?)\s*[\d,]+'
          r'|\d[\d,]*\s*(?:lakh|crore|rupees?)\b'
          r'|[\d,]+\s*(?:lakh|crore)',
      reason: 'Money amount mentioned',
    ),
    (
      // OTP solicitation — English + Hindi + Hinglish.
      pattern: r'\botp\b|one.?time.?pass(?:word|code)?'
          r'|share.{0,10}otp|send.{0,10}otp|otp.{0,10}(?:share|send|batao)'
          r'|verification code|do not share.{0,20}otp|never share.{0,20}otp'
          r'|सत्यापन कोड|ओटीपी',
      reason: 'OTP solicitation',
    ),
    (
      // KYC / account-freeze urgency — English + Hindi.
      pattern: r'kyc|know your customer'
          r'|account.{0,20}(?:block|suspend|deactivat|freeze|band)'
          r'|update.{0,10}kyc|complete.{0,10}kyc|re-?kyc'
          r'|verify.{0,10}(?:account|identity|aadhaar|pan)'
          r'|link.{0,10}aadhaar|pan.{0,10}update|aadhaar.{0,10}update'
          r'|खाता.{0,15}(?:बंद|ब्लॉक|निलंबित)|केवाईसी|आधार.{0,10}सत्यापन'
          r'|पैन.{0,10}अपडेट',
      reason: 'KYC / account-block urgency',
    ),
    (
      // Law-enforcement / digital-arrest impersonation — English + Devanagari.
      pattern: r'digital arrest|cyber crime branch|cybercrime.{0,10}officer'
          r'|c\.b\.i|\bcbi\b|enforcement directorate|\bed\b.{0,15}officer'
          r'|narcotic(?:s)? bureau|\bncb\b|\bfir\b|money laundering'
          r'|arrest warrant|court.{0,10}notice|police.{0,15}warrant|interpol'
          r'|गिरफ्तार|एफआईआर|साइबर क्राइम|प्रवर्तन निदेशालय|सीबीआई'
          r'|मनी लॉन्ड्रिंग',
      reason: 'Law enforcement / digital-arrest impersonation',
    ),
    (
      pattern: r'\blottery\b|\bprize\b|you.{0,10}won|lucky draw|scratch.{0,10}card'
          r'|gift.{0,10}card|selected.{0,10}winner|claim.{0,10}prize'
          r'|congratulations.{0,30}(?:win|prize|reward)|reward.{0,15}crore',
      reason: 'Lottery / prize scam',
    ),
    (
      pattern: r'work from home|earn.{0,20}(?:per day|daily|roz)'
          r'|part.?time.{0,15}earn|whatsapp.{0,20}job|job.{0,20}whatsapp'
          r'|₹.{0,10}per.{0,5}(?:day|task|click)|task.{0,10}earn'
          r'|telegram.{0,20}earn|ghar baithe.{0,20}(?:earn|paise|kamao)'
          r'|घर बैठे.{0,20}(?:कमाई|पैसे)',
      reason: 'Job scam / WhatsApp recruitment',
    ),
    (
      pattern: r'customs.{0,20}(?:fee|clearance|duty)'
          r'|release.{0,15}package|package.{0,20}(?:held|seized|detained)'
          r'|parcel.{0,20}(?:held|seized|detained)|delivery.{0,10}fee',
      reason: 'Fake customs / delivery fee',
    ),
  ];

  // ---------------------------------------------------------------------------
  // Urgency rule — dynamic: includes the matched word in the reason string.
  // Must be static final (not const) because RegExp is not a const type.
  // ---------------------------------------------------------------------------

  static const _urgencyPattern =
      r'urgent(?:ly)?|immediately|expire[sd]?|expiry|deadline'
      r'|\bblock(?:ed)?\b|\bsuspend(?:ed)?\b|\bdeactivat(?:e[sd]?)?\b'
      r'|\babhi\b|\bturant\b|\bjaldi\b'
      // Devanagari: जल्दी (jaldi), बंद (closed/blocked), तुरंत (immediately)
      r'|जल्दी|बंद|तुरंत|अभी|फौरन';

  static final _urgencyRe = RegExp(_urgencyPattern, caseSensitive: false);

  // Compiled versions of static rules, built once on first call.
  static final List<RegExp> _compiled = [
    for (final r in _ruleSpecs) RegExp(r.pattern, caseSensitive: false),
  ];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns a list of human-readable descriptions for every rule that fires.
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

  /// Returns all regex match spans across every rule, sorted by start offset.
  /// Used by the detail screen to underline matched phrases in the SMS body.
  static List<RegExpMatch> allMatches(String text) {
    final matches = <RegExpMatch>[
      for (final re in _compiled) ...re.allMatches(text),
      ..._urgencyRe.allMatches(text),
    ];
    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }
}
