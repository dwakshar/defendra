// ignore_for_file: avoid_redundant_argument_values

import 'dart:math';

import 'package:defendra/ml/dart_tokenizer.dart';
import 'package:defendra/ml/ml_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake vocab — minimal BERT-cased token set for deterministic tokenizer tests.
//
// Special tokens follow the distilbert-base-multilingual-cased convention:
//   [PAD]=0  [UNK]=100  [CLS]=101  [SEP]=102
//
// Domain placeholders are included so URL / phone / amount substitution paths
// are exercised (the tokenizer skips substitution when a placeholder is absent
// from the vocab).
// ---------------------------------------------------------------------------
const _fakeVocab = <String, int>{
  '[PAD]': 0,
  '[UNK]': 100,
  '[CLS]': 101,
  '[SEP]': 102,
  // Common subwords used in test sentences
  'your': 200,
  'account': 201,
  'has': 202,
  'been': 203,
  'click': 204,
  'link': 205,
  'urgent': 206,
  'please': 207,
  'bank': 208,
  'otp': 209,
  'send': 210,
  'you': 211,
  'won': 212,
  'the': 213,
  'a': 214,
  'to': 215,
  'and': 216,
  'is': 217,
  'it': 218,
  'in': 219,
  'for': 220,
  'pay': 221,
  'now': 222,
  // WordPiece continuation pieces
  '##ing': 300,
  '##ed': 301,
  '##er': 302,
  '##s': 303,
  // Domain placeholders — must match DartTokenizer's private constants
  '<url>': 400,
  '<phone>': 401,
  '<amount>': 402,
  '<otp>': 403,
};

// ---------------------------------------------------------------------------
// 4 scam-label classes: [safe, otpKyc, deliveryCourier, digitalArrest]
// High-signal keys that trigger the rule-override path in _buildResult:
//   digital_arrest | lottery | job_scam | delivery_fee
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // DartTokenizer — construction
  // =========================================================================

  group('DartTokenizer — construction', () {
    test('fromVocab() marks tokenizer as loaded', () {
      final tok = DartTokenizer.fromVocab(_fakeVocab);
      expect(tok.isLoaded, isTrue);
    });

    test('vocab getter returns the provided map', () {
      final tok = DartTokenizer.fromVocab(_fakeVocab);
      expect(tok.vocab, equals(_fakeVocab));
    });

    test('default constructor produces unloaded tokenizer', () {
      expect(DartTokenizer().isLoaded, isFalse);
    });

    test('tokenize() on unloaded instance throws StateError', () {
      expect(() => DartTokenizer().tokenize('hello'), throwsStateError);
    });

    test('maxLength < 2 throws ArgumentError', () {
      final tok = DartTokenizer.fromVocab(_fakeVocab);
      expect(() => tok.tokenize('hello', maxLength: 1), throwsArgumentError);
    });
  });

  // =========================================================================
  // DartTokenizer — output-shape invariants (all scenarios share these)
  // =========================================================================

  group('DartTokenizer — output-shape invariants', () {
    late DartTokenizer tok;
    setUp(() => tok = DartTokenizer.fromVocab(_fakeVocab));

    test('result always has input_ids and attention_mask keys', () {
      expect(
        tok.tokenize('hello world').keys,
        containsAll(['input_ids', 'attention_mask']),
      );
    });

    test('input_ids length equals maxLength=96', () {
      expect(tok.tokenize('your account click link')['input_ids']!.length, 96);
    });

    test('attention_mask length equals maxLength=96', () {
      expect(
        tok.tokenize('your account click link')['attention_mask']!.length,
        96,
      );
    });

    test('first token is always CLS (101)', () {
      for (final text in ['', 'hello', 'urgent click link your account']) {
        expect(tok.tokenize(text)['input_ids']![0], 101);
      }
    });

    test('attention_mask values are exclusively 0 or 1', () {
      final mask = tok.tokenize('your account has been click')['attention_mask']!;
      expect(mask.every((v) => v == 0 || v == 1), isTrue);
    });

    test('padding tokens (ID=0) always have attention_mask=0', () {
      final r = tok.tokenize('your');
      final ids = r['input_ids']!;
      final mask = r['attention_mask']!;
      for (int i = 0; i < ids.length; i++) {
        if (ids[i] == 0) expect(mask[i], 0, reason: 'PAD at idx $i must have mask=0');
      }
    });

    test('active attention count equals real token count', () {
      // 'your account' → CLS + your + account + SEP = 4 active
      final mask = tok.tokenize('your account')['attention_mask']!;
      expect(mask.where((v) => v == 1).length, 4);
    });
  });

  // =========================================================================
  // Scenario 4 — empty string
  // =========================================================================

  group('DartTokenizer — scenario 4: empty string', () {
    late DartTokenizer tok;
    setUp(() => tok = DartTokenizer.fromVocab(_fakeVocab));

    test('produces CLS then SEP then all PAD', () {
      final ids = tok.tokenize('')['input_ids']!;
      expect(ids[0], 101); // [CLS]
      expect(ids[1], 102); // [SEP]
      for (int i = 2; i < ids.length; i++) {
        expect(ids[i], 0, reason: 'Position $i should be PAD');
      }
    });

    test('exactly 2 active attention tokens (CLS + SEP)', () {
      final mask = tok.tokenize('')['attention_mask']!;
      expect(mask.where((v) => v == 1).length, 2);
    });

    test('output length is still 96', () {
      expect(tok.tokenize('')['input_ids']!.length, 96);
    });
  });

  // =========================================================================
  // Scenario 5 — very long SMS (>500 chars)
  // =========================================================================

  group('DartTokenizer — scenario 5: very long SMS (>500 chars)', () {
    late DartTokenizer tok;
    setUp(() => tok = DartTokenizer.fromVocab(_fakeVocab));

    test('output is always clamped to 96 tokens', () {
      final longText = 'your account has been click link ' * 20; // ~640 chars
      expect(longText.length, greaterThan(500));
      final r = tok.tokenize(longText);
      expect(r['input_ids']!.length, 96);
      expect(r['attention_mask']!.length, 96);
    });

    test('SEP lands at index 95 when input fills all slots', () {
      // Need > 94 words so the loop hits the ids.length >= 95 break.
      // CLS + 94 'your' tokens + SEP = 96; 100 words guarantees overflow.
      final r = tok.tokenize('your ' * 100);
      expect(r['input_ids']![95], 102); // [SEP]
      expect(r['attention_mask']![95], 1);
    });

    test('fully packed input has all-1 attention mask', () {
      final r = tok.tokenize('your ' * 100);
      expect(r['attention_mask']!.every((v) => v == 1), isTrue);
    });

    test('does not crash on 1 000-char SMS', () {
      expect(() => tok.tokenize('A' * 1000), returnsNormally);
    });
  });

  // =========================================================================
  // Scenario 6 — Hindi SMS
  // =========================================================================

  group('DartTokenizer — scenario 6: Hindi SMS', () {
    late DartTokenizer tok;
    setUp(() => tok = DartTokenizer.fromVocab(_fakeVocab));

    test('Hindi text does not throw', () {
      expect(
        () => tok.tokenize('आपका खाता बंद हो जाएगा। कृपया तुरंत सत्यापित करें।'),
        returnsNormally,
      );
    });

    test('output length is 96', () {
      final r = tok.tokenize('आपका खाता बंद हो जाएगा।');
      expect(r['input_ids']!.length, 96);
    });

    test('Hindi words not in vocab produce UNK (100)', () {
      final r = tok.tokenize('आपका');
      // CLS=101, UNK=100 for the Hindi word, SEP=102
      expect(r['input_ids']![1], 100);
    });

    test('Devanagari danda (।) is treated as punctuation', () {
      // U+0964 is in _isPunc — exercises the punctuation-split path
      final r = tok.tokenize('नमस्ते।');
      expect(r['input_ids']!.length, 96);
      expect(r['attention_mask']!.where((v) => v == 1).length, greaterThanOrEqualTo(2));
    });

    test('urgency signals in Hindi still produce valid output', () {
      // 'तुरंत' = urgency in Hindi, unknown in fake vocab → UNK, no crash
      final r = tok.tokenize('आपका OTP तुरंत share करें नहीं तो account band होगा');
      expect(r['input_ids']!.length, 96);
    });
  });

  // =========================================================================
  // Scenario 7 — Hinglish SMS
  // =========================================================================

  group('DartTokenizer — scenario 7: Hinglish SMS', () {
    late DartTokenizer tok;
    setUp(() => tok = DartTokenizer.fromVocab(_fakeVocab));

    test('Hinglish text does not throw', () {
      expect(
        () => tok.tokenize('Yaar tera account band ho gaya. Abhi link pe click kar.'),
        returnsNormally,
      );
    });

    test('English words in Hinglish get correct IDs', () {
      final ids = tok.tokenize('your account click link')['input_ids']!;
      // CLS=101, your=200, account=201, click=204, link=205, SEP=102, PAD…
      expect(ids, containsAllInOrder([101, 200, 201, 204, 205, 102]));
    });

    test('unknown Hinglish tokens map to UNK', () {
      final r = tok.tokenize('Yaar tera account');
      final ids = r['input_ids']!;
      // 'Yaar' and 'tera' → UNK; 'account' → 201
      expect(ids, contains(100)); // at least one UNK
      expect(ids, contains(201)); // account is known
    });

    test('output length is 96', () {
      final r = tok.tokenize('Tera account urgent hai, abhi bank click kar.');
      expect(r['input_ids']!.length, 96);
    });
  });

  // =========================================================================
  // Scenario 8 — URL-heavy SMS
  // =========================================================================

  group('DartTokenizer — scenario 8: URL-heavy SMS', () {
    late DartTokenizer tok;
    setUp(() => tok = DartTokenizer.fromVocab(_fakeVocab));

    test('https URL is replaced with <url> placeholder (token 400)', () {
      final ids = tok.tokenize('Click https://example.com now')['input_ids']!;
      expect(ids, contains(400));
    });

    test('bit.ly shortlink is replaced with <url> placeholder', () {
      final ids = tok.tokenize('Go to bit.ly/abc123 urgently')['input_ids']!;
      expect(ids, contains(400));
    });

    test('multiple URLs each become a separate <url> token', () {
      final ids = tok
          .tokenize('Check https://spam.com and also http://bit.ly/bad')['input_ids']!;
      final urlCount = ids.where((id) => id == 400).length;
      expect(urlCount, greaterThanOrEqualTo(2));
    });

    test('output length is 96 despite URL substitution', () {
      final r = tok.tokenize('https://bit.ly/x ' * 20);
      expect(r['input_ids']!.length, 96);
    });

    test('Indian phone number is replaced with <phone> placeholder (token 401)', () {
      final ids = tok.tokenize('Call 9876543210 immediately')['input_ids']!;
      expect(ids, contains(401));
    });

    test('rupee amount is replaced with <amount> placeholder (token 402)', () {
      final ids = tok.tokenize('Pay ₹5000 to claim prize')['input_ids']!;
      expect(ids, contains(402));
    });

    test('numeric OTP-like token is replaced with <otp> placeholder (token 403)', () {
      final ids = tok.tokenize('Your OTP is 482910')['input_ids']!;
      expect(ids, contains(403));
    });

    test('URL-only SMS has correct shape', () {
      final r = tok.tokenize('https://malicious.link/steal-data');
      expect(r['input_ids']!.length, 96);
      expect(r['attention_mask']!.where((v) => v == 1).length, greaterThanOrEqualTo(2));
    });
  });

  // =========================================================================
  // Scenario 9 — repeated inference stability
  // =========================================================================

  group('DartTokenizer — scenario 9: repeated inference stability', () {
    late DartTokenizer tok;
    setUp(() => tok = DartTokenizer.fromVocab(_fakeVocab));

    test('same text tokenized twice gives identical result (cache hit)', () {
      const sms = 'Your account has been click link urgently.';
      final r1 = tok.tokenize(sms);
      final r2 = tok.tokenize(sms);
      expect(r1['input_ids'], equals(r2['input_ids']));
      expect(r1['attention_mask'], equals(r2['attention_mask']));
    });

    test('cache hit does not corrupt CLS at position 0', () {
      const sms = 'your account click link';
      tok.tokenize(sms); // prime cache
      final r = tok.tokenize(sms); // hit cache
      expect(r['input_ids']![0], 101);
      expect(r['input_ids']!.length, 96);
    });

    test('different texts produce different token sequences', () {
      final r1 = tok.tokenize('your account');
      final r2 = tok.tokenize('click link');
      expect(r1['input_ids'], isNot(equals(r2['input_ids'])));
    });

    test('10 texts re-tokenized give the same result as first pass', () {
      final texts = List.generate(10, (i) => 'sms number $i urgent click link');
      final first = texts.map(tok.tokenize).map((r) => r['input_ids']!.toList()).toList();
      final second = texts.map(tok.tokenize).map((r) => r['input_ids']!.toList()).toList();
      for (int i = 0; i < texts.length; i++) {
        expect(first[i], equals(second[i]), reason: 'Mismatch at index $i');
      }
    });
  });

  // =========================================================================
  // Scenario 10 — 100 consecutive inferences without crash
  // =========================================================================

  group('DartTokenizer — scenario 10: 100 consecutive inferences', () {
    late DartTokenizer tok;
    setUp(() => tok = DartTokenizer.fromVocab(_fakeVocab));

    test('100 unique texts do not crash and always produce length-96 output', () {
      for (int i = 0; i < 100; i++) {
        final text = 'SMS $i: your account urgent click link send otp bank';
        final r = tok.tokenize(text);
        expect(r['input_ids']!.length, 96, reason: 'Failed at iteration $i');
        expect(r['attention_mask']!.length, 96, reason: 'Failed at iteration $i');
        expect(r['input_ids']![0], 101, reason: 'CLS missing at iteration $i');
      }
    });

    test('LRU cache stays bounded after 100+ unique texts (no crash on eviction)', () {
      for (int i = 0; i < 100; i++) {
        tok.tokenize('unique sms body number $i please click urgently');
      }
      // Re-tokenizing an early text may be a cache miss; must not crash.
      expect(() => tok.tokenize('unique sms body number 0 please click urgently'), returnsNormally);
    });

    test('100 repeated identical texts are served from cache without corruption', () {
      const sms = 'your account has been click link urgent';
      for (int i = 0; i < 100; i++) {
        final r = tok.tokenize(sms);
        expect(r['input_ids']![0], 101, reason: 'CLS corrupted at iteration $i');
        expect(r['input_ids']!.length, 96, reason: 'Length wrong at iteration $i');
      }
    });
  });

  // =========================================================================
  // Scenario 1 — MlEngine model-load state
  // =========================================================================

  group('MlEngine — scenario 1: model-load state', () {
    test('isReady is false and loadError is null before load()', () {
      final engine = MlEngine();
      expect(engine.isReady, isFalse);
      expect(engine.loadError, isNull);
      engine.dispose();
    });

    test('load() fails gracefully when asset bundle is unavailable', () async {
      // In the unit-test environment rootBundle has no registered assets, so
      // load() will catch the FlutterError and record it in loadError.
      TestWidgetsFlutterBinding.ensureInitialized();
      final engine = MlEngine();
      await engine.load();
      expect(engine.isReady, isFalse);
      expect(engine.loadError, isNotNull);
      engine.dispose();
    });

    test('dispose() before load() does not throw', () {
      final engine = MlEngine();
      expect(() => engine.dispose(), returnsNormally);
    });

    test('dispose() is idempotent', () {
      final engine = MlEngine();
      engine.dispose();
      expect(() => engine.dispose(), returnsNormally);
    });

    test('isReady remains false after dispose()', () {
      final engine = MlEngine();
      engine.dispose();
      expect(engine.isReady, isFalse);
    });
  });

  // =========================================================================
  // MlEngine — fallback path (isReady = false)
  // Scenarios 2, 3, 4, 5, 6, 7, 8, 9, 10 tested via the public API when
  // the model is not loaded. The fallback is deterministic and rule-driven.
  // =========================================================================

  group('MlEngine — fallback path (isReady = false)', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    // Scenario 2: classify() returns a well-formed ScanResult
    test('scenario 2 — classify() returns a ScanResult when not ready', () async {
      final result = await engine.classify('Hello');
      expect(result, isA<ScanResult>());
      expect(result.label, isA<ScamLabel>());
    });

    test('fallback always sets isError=true', () async {
      final result = await engine.classify('Hello world');
      expect(result.isError, isTrue);
    });

    // Scenario 3: confidence bounds
    test('scenario 3 — fallback confidence is either 0.0 or 0.75', () async {
      for (final sms in [
        'Hello there',
        'You have won a lucky draw prize!',
        'CBI officer calling. You are under digital arrest.',
        'Work from home earn ₹5000 per day via WhatsApp job.',
        '',
      ]) {
        final r = await engine.classify(sms);
        expect(
          r.confidence,
          anyOf(equals(0.0), equals(0.75)),
          reason: 'Unexpected confidence ${r.confidence} for: "$sms"',
        );
      }
    });

    // Scenario 4: empty string in fallback
    test('scenario 4 — empty string returns safe/0.0', () async {
      final result = await engine.classify('');
      expect(result.label, ScamLabel.safe);
      expect(result.confidence, 0.0);
      expect(result.isError, isTrue);
    });

    test('neutral SMS returns safe/0.0', () async {
      final result = await engine.classify('Hey, are you coming to the party tonight?');
      expect(result.label, ScamLabel.safe);
      expect(result.confidence, 0.0);
    });

    // High-signal key override tests
    test('lottery signal triggers otpKyc/0.75 fallback', () async {
      final result = await engine.classify(
        'Congratulations! You have won a lucky draw prize of ₹10 lakh.',
      );
      expect(result.label, ScamLabel.otpKyc);
      expect(result.confidence, 0.75);
      expect(result.ruleOverride, isTrue);
    });

    test('digital_arrest signal triggers otpKyc/0.75 fallback', () async {
      final result = await engine.classify(
        'CBI officer calling. You are under digital arrest. Do not tell anyone.',
      );
      expect(result.label, ScamLabel.otpKyc);
      expect(result.ruleOverride, isTrue);
    });

    test('job_scam signal triggers otpKyc/0.75 fallback', () async {
      final result = await engine.classify(
        'Work from home! Earn ₹5000 per day via WhatsApp job. Join now.',
      );
      expect(result.label, ScamLabel.otpKyc);
      expect(result.ruleOverride, isTrue);
    });

    test('delivery_fee signal triggers otpKyc/0.75 fallback', () async {
      final result = await engine.classify(
        'Your package is held at customs. Pay delivery fee to release package.',
      );
      expect(result.label, ScamLabel.otpKyc);
      expect(result.ruleOverride, isTrue);
    });

    test('broad-only signals (bank + OTP) do NOT trigger override', () async {
      // phone_number / bank_impersonation / otp_request alone must not override.
      // This guards against the false-positive fix described in _kHighSignalKeys.
      final result = await engine.classify(
        'Your HDFC Bank OTP is 482910. Do not share this with anyone.',
      );
      expect(result.label, ScamLabel.safe);
      expect(result.ruleOverride, isTrue); // fallback sets ruleOverride=true always
    });

    // Scenario 5: very long SMS in fallback path
    test('scenario 5 — very long SMS (>500 chars) does not crash', () async {
      final longSms = 'A' * 600;
      final result = await engine.classify(longSms);
      expect(result, isA<ScanResult>());
    });

    // Scenario 6: Hindi SMS
    test('scenario 6 — Hindi SMS returns valid ScanResult', () async {
      final result = await engine.classify(
        'आपका खाता बंद हो जाएगा। कृपया तुरंत सत्यापित करें।',
      );
      expect(result, isA<ScanResult>());
      expect(result.label, isA<ScamLabel>());
    });

    // Scenario 7: Hinglish SMS
    test('scenario 7 — Hinglish SMS returns valid ScanResult', () async {
      final result = await engine.classify(
        'Yaar tera account band ho gaya. Abhi click karo link pe.',
      );
      expect(result, isA<ScanResult>());
    });

    // Scenario 8: URL-heavy SMS fires rule signals
    test('scenario 8 — shortened URL fires shortened_url signal key', () async {
      final result = await engine.classify(
        'Click http://bit.ly/scam123 now! Urgent: your account will be blocked.',
      );
      expect(result.firedSignalKeys, contains('shortened_url'));
      expect(result.firedSignalKeys, contains('urgency'));
    });

    // Scenario 9: repeated inference stability in fallback
    test('scenario 9 — same SMS classified twice gives identical result', () async {
      const sms = 'Your OTP is 456789. Do not share this with anyone.';
      final r1 = await engine.classify(sms);
      final r2 = await engine.classify(sms);
      expect(r1.label, r2.label);
      expect(r1.confidence, r2.confidence);
      expect(r1.firedSignalKeys, equals(r2.firedSignalKeys));
    });

    // Scenario 10: 100 consecutive inferences in fallback
    test('scenario 10 — 100 consecutive inferences do not crash', () async {
      for (int i = 0; i < 100; i++) {
        final result = await engine.classify('Test SMS number $i urgent click link');
        expect(result, isA<ScanResult>(), reason: 'Failed at iteration $i');
      }
    });

    test('scan() is a functional alias for classify()', () async {
      const sms = 'Hello world';
      final classifyResult = await engine.classify(sms);
      final scanResult = await engine.scan(sms);
      expect(scanResult.label, classifyResult.label);
      expect(scanResult.confidence, classifyResult.confidence);
      expect(scanResult.isError, classifyResult.isError);
    });
  });

  // =========================================================================
  // MlEngine._softmax — via @visibleForTesting softmaxForTest()
  // =========================================================================

  group('MlEngine — softmax', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    test('output sums to 1.0', () {
      final result = engine.softmaxForTest([1.0, 2.0, 3.0, 0.5]);
      final sum = result.fold(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-6));
    });

    test('all outputs are in (0, 1)', () {
      final result = engine.softmaxForTest([1.0, 2.0, 3.0, 0.5]);
      for (final v in result) {
        expect(v, greaterThan(0.0));
        expect(v, lessThan(1.0));
      }
    });

    test('preserves argmax', () {
      final logits = [-10.0, 5.0, -10.0, -10.0]; // index 1 is max
      final result = engine.softmaxForTest(logits);
      final maxIdx = result.indexOf(result.reduce(max));
      expect(maxIdx, 1);
    });

    test('equal logits produce equal probabilities (~0.25 each)', () {
      final result = engine.softmaxForTest([0.0, 0.0, 0.0, 0.0]);
      for (final v in result) {
        expect(v, closeTo(0.25, 1e-6));
      }
    });

    test('extreme positive logit drives probability near 1.0', () {
      final result = engine.softmaxForTest([100.0, -100.0, -100.0, -100.0]);
      expect(result[0], greaterThan(0.99));
    });
  });

  // =========================================================================
  // MlEngine._buildResult — via @visibleForTesting buildResultForTest()
  // Scenarios 2 (valid prediction) and 3 (confidence bounds) for the
  // ML inference path.
  // =========================================================================

  group('MlEngine.buildResultForTest — label selection', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    // Scenario 2: correct label from logits
    test('scenario 2 — raw logits: argmax safe → ScamLabel.safe', () {
      final r = engine.buildResultForTest([10.0, -10.0, -10.0, -10.0], [], []);
      expect(r.label, ScamLabel.safe);
      expect(r.confidence, greaterThan(0.99));
    });

    test('scenario 2 — raw logits: argmax otpKyc → ScamLabel.otpKyc', () {
      final r = engine.buildResultForTest([-10.0, 10.0, -10.0, -10.0], [], []);
      expect(r.label, ScamLabel.otpKyc);
      expect(r.confidence, greaterThan(0.99));
    });

    test('scenario 2 — raw logits: argmax deliveryCourier', () {
      final r = engine.buildResultForTest([-10.0, -10.0, 10.0, -10.0], [], []);
      expect(r.label, ScamLabel.deliveryCourier);
    });

    test('scenario 2 — raw logits: argmax digitalArrest', () {
      final r = engine.buildResultForTest([-10.0, -10.0, -10.0, 10.0], [], []);
      expect(r.label, ScamLabel.digitalArrest);
    });

    test('scenario 2 — already-normalised probs are passed through unchanged', () {
      // sum=1.0, all >=0 → alreadyProbs=true → no second softmax
      final r = engine.buildResultForTest([0.7, 0.1, 0.1, 0.1], [], []);
      expect(r.label, ScamLabel.safe);
      expect(r.confidence, closeTo(0.7, 1e-6));
    });

    test('scenario 2 — already-normalised probs: otpKyc dominant', () {
      final r = engine.buildResultForTest([0.1, 0.7, 0.1, 0.1], [], []);
      expect(r.label, ScamLabel.otpKyc);
      expect(r.confidence, closeTo(0.7, 1e-6));
    });

    test('ruleOverride is false when no high-signal key fires', () {
      final r = engine.buildResultForTest([0.7, 0.1, 0.1, 0.1], [], []);
      expect(r.ruleOverride, isFalse);
    });

    test('throws StateError when logits length != 4', () {
      expect(() => engine.buildResultForTest([0.5, 0.5], [], []), throwsStateError);
      expect(() => engine.buildResultForTest([0.25, 0.25, 0.25, 0.25, 0.0], [], []), throwsStateError);
    });
  });

  group('MlEngine.buildResultForTest — scenario 3: confidence bounds', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    test('confidence is in [0, 1] for all-zero raw logits', () {
      final r = engine.buildResultForTest([0.0, 0.0, 0.0, 0.0], [], []);
      // softmax of equal values → 0.25 each
      expect(r.confidence, inInclusiveRange(0.0, 1.0));
      expect(r.confidence, closeTo(0.25, 1e-6));
    });

    test('confidence is in [0, 1] for extreme positive raw logit', () {
      final r = engine.buildResultForTest([100.0, -100.0, -100.0, -100.0], [], []);
      expect(r.confidence, inInclusiveRange(0.0, 1.0));
    });

    test('confidence is in [0, 1] for extreme negative raw logit', () {
      final r = engine.buildResultForTest([-100.0, 100.0, -100.0, -100.0], [], []);
      expect(r.confidence, inInclusiveRange(0.0, 1.0));
    });

    test('confidence is in [0, 1] for normalised probs input', () {
      for (final logits in [
        [0.25, 0.25, 0.25, 0.25],
        [0.9, 0.05, 0.025, 0.025],
        [0.0, 1.0, 0.0, 0.0],
      ]) {
        final r = engine.buildResultForTest(logits, [], []);
        expect(r.confidence, inInclusiveRange(0.0, 1.0), reason: 'logits=$logits');
      }
    });
  });

  group('MlEngine.buildResultForTest — rule override logic', () {
    late MlEngine engine;
    setUp(() => engine = MlEngine());
    tearDown(() => engine.dispose());

    test('lottery key overrides safe+low-confidence to otpKyc/0.75', () {
      // safe at 0.6 confidence (<0.75) + high-signal 'lottery' → override
      final r = engine.buildResultForTest([0.6, 0.2, 0.1, 0.1], [], ['lottery']);
      expect(r.label, ScamLabel.otpKyc);
      expect(r.confidence, 0.75);
      expect(r.ruleOverride, isTrue);
    });

    test('digital_arrest key overrides safe+low-confidence', () {
      final r = engine.buildResultForTest([0.6, 0.2, 0.1, 0.1], [], ['digital_arrest']);
      expect(r.label, ScamLabel.otpKyc);
      expect(r.ruleOverride, isTrue);
    });

    test('job_scam key overrides safe+low-confidence', () {
      final r = engine.buildResultForTest([0.6, 0.2, 0.1, 0.1], [], ['job_scam']);
      expect(r.label, ScamLabel.otpKyc);
      expect(r.ruleOverride, isTrue);
    });

    test('delivery_fee key overrides safe+low-confidence', () {
      final r = engine.buildResultForTest([0.6, 0.2, 0.1, 0.1], [], ['delivery_fee']);
      expect(r.label, ScamLabel.otpKyc);
      expect(r.ruleOverride, isTrue);
    });

    test('high-signal does NOT override when confidence >= 0.75', () {
      // safe at 0.9 — model is confident, rule must not override
      final r = engine.buildResultForTest([0.9, 0.05, 0.025, 0.025], [], ['lottery']);
      expect(r.label, ScamLabel.safe);
      expect(r.confidence, closeTo(0.9, 1e-6));
      expect(r.ruleOverride, isFalse);
    });

    test('broad-only key (phone_number) never triggers override', () {
      final r = engine.buildResultForTest([0.6, 0.2, 0.1, 0.1], [], ['phone_number']);
      expect(r.label, ScamLabel.safe);
      expect(r.ruleOverride, isFalse);
    });

    test('broad-only key (bank_impersonation) never triggers override', () {
      final r = engine.buildResultForTest([0.6, 0.2, 0.1, 0.1], [], ['bank_impersonation']);
      expect(r.label, ScamLabel.safe);
      expect(r.ruleOverride, isFalse);
    });

    test('override does not fire when ML label is already a scam class', () {
      // If the model already picked otpKyc, override logic is skipped
      // (condition: label == ScamLabel.safe)
      final r = engine.buildResultForTest([0.1, 0.6, 0.2, 0.1], [], ['lottery']);
      expect(r.label, ScamLabel.otpKyc);
      expect(r.ruleOverride, isFalse); // no override triggered; ML won
    });

    test('triggerPhrases and firedSignalKeys are forwarded into ScanResult', () {
      final r = engine.buildResultForTest(
        [0.6, 0.2, 0.1, 0.1],
        ['Lottery / prize scam'],
        ['lottery'],
      );
      expect(r.triggerPhrases, ['Lottery / prize scam']);
      expect(r.firedSignalKeys, ['lottery']);
    });
  });

  // =========================================================================
  // ScamLabel extensions
  // =========================================================================

  group('ScamLabel extensions', () {
    test('safe is not a scam', () => expect(ScamLabel.safe.isScam, isFalse));
    test('otpKyc is a scam', () => expect(ScamLabel.otpKyc.isScam, isTrue));
    test('deliveryCourier is a scam', () => expect(ScamLabel.deliveryCourier.isScam, isTrue));
    test('digitalArrest is a scam', () => expect(ScamLabel.digitalArrest.isScam, isTrue));

    test('labelDisplay is non-empty for all labels', () {
      for (final label in ScamLabel.values) {
        expect(label.labelDisplay, isNotEmpty);
      }
    });

    test('safe labelDisplay is "Safe"', () => expect(ScamLabel.safe.labelDisplay, 'Safe'));
    test('otpKyc labelDisplay is "OTP / KYC Scam"',
        () => expect(ScamLabel.otpKyc.labelDisplay, 'OTP / KYC Scam'));
    test('deliveryCourier labelDisplay is "Delivery Scam"',
        () => expect(ScamLabel.deliveryCourier.labelDisplay, 'Delivery Scam'));
    test('digitalArrest labelDisplay is "Digital Arrest"',
        () => expect(ScamLabel.digitalArrest.labelDisplay, 'Digital Arrest'));
  });

  // =========================================================================
  // ScanResult — construction and defaults
  // =========================================================================

  group('ScanResult — construction', () {
    test('required fields are stored correctly', () {
      const r = ScanResult(
        label: ScamLabel.otpKyc,
        confidence: 0.92,
        triggerPhrases: ['OTP solicitation'],
      );
      expect(r.label, ScamLabel.otpKyc);
      expect(r.confidence, 0.92);
      expect(r.triggerPhrases, ['OTP solicitation']);
    });

    test('optional fields default to safe values', () {
      const r = ScanResult(
        label: ScamLabel.safe,
        confidence: 0.0,
        triggerPhrases: [],
      );
      expect(r.firedSignalKeys, isEmpty);
      expect(r.ruleOverride, isFalse);
      expect(r.isError, isFalse);
    });

    test('isError flag is stored', () {
      const r = ScanResult(
        label: ScamLabel.safe,
        confidence: 0.0,
        triggerPhrases: [],
        isError: true,
      );
      expect(r.isError, isTrue);
    });

    test('firedSignalKeys is stored', () {
      const r = ScanResult(
        label: ScamLabel.digitalArrest,
        confidence: 0.98,
        triggerPhrases: [],
        firedSignalKeys: ['digital_arrest', 'urgency'],
      );
      expect(r.firedSignalKeys, containsAll(['digital_arrest', 'urgency']));
    });
  });
}
