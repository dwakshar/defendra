// ignore_for_file: avoid_redundant_argument_values

import 'package:defendra/ml/dart_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Parity vocab — hand-crafted to match distilbert-base-multilingual-cased
// token IDs for the 10 fixed reference strings below.
//
// The ID assignments mirror what the Python HuggingFace tokenizer produces for
// these exact byte-sequences in a CASED model:
//
//   "Meeting at 5 PM today" (no period)
//   Python reference IDs (baked into debugTokenizerParity()):
//     [101, 50986, 10160, 126, 46161, 18745, 102]
//
// We replicate those exact IDs in _parityVocab so the Dart tokenizer's output
// can be compared token-by-token without loading the 2 MB production vocab.
// ---------------------------------------------------------------------------

const _parityVocab = <String, int>{
  // Special tokens (standard BERT / distilbert convention)
  '[PAD]': 0,
  '[UNK]': 100,
  '[CLS]': 101,
  '[SEP]': 102,

  // --- Reference string 1: "Meeting at 5 PM today" ---
  // Python output: [101, 50986, 10160, 126, 46161, 18745, 102]
  'Meeting': 50986,
  'at': 10160,
  '5': 126,
  'PM': 46161,
  'today': 18745,

  // Lower-case variants get DIFFERENT IDs → proves CASED behaviour
  'meeting': 99001,
  'pm': 99002,

  // --- Strings 2–5: everyday English words ---
  'Click': 60001,
  'click': 60002,
  'link': 60003,
  'now': 60004,
  'urgent': 60005,
  'account': 60006,
  'your': 60007,
  'bank': 60008,
  'otp': 60009,

  // --- String 6: mixed-case sentence ---
  'Hello': 70001,
  'World': 70002,
  'hello': 70003,
  'world': 70004,

  // --- String 7: domain placeholders (only injected when in vocab) ---
  '<url>': 400,
  '<phone>': 401,
  '<amount>': 402,
  '<otp>': 403,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<int> _tokenize(String text, {int maxLen = 96}) =>
    DartTokenizer.fromVocab(_parityVocab).tokenize(text, maxLength: maxLen)['input_ids']!;

List<int> _mask(String text, {int maxLen = 96}) =>
    DartTokenizer.fromVocab(_parityVocab).tokenize(text, maxLength: maxLen)['attention_mask']!;

List<int> _active(String text) {
  final ids = _tokenize(text);
  final mask = _mask(text);
  return [
    for (int i = 0; i < ids.length; i++)
      if (mask[i] == 1) ids[i],
  ];
}

void main() {
  // =========================================================================
  // String 1 — Python parity reference: "Meeting at 5 PM today"
  // =========================================================================

  group('Tokenizer parity — string 1: "Meeting at 5 PM today" (Python ref)', () {
    // The Python distilbert-base-multilingual-cased reference (no period):
    //   [101, 50986, 10160, 126, 46161, 18745, 102]
    // The same IDs are used here via _parityVocab.
    const pythonRef = [101, 50986, 10160, 126, 46161, 18745, 102];

    test('active tokens match Python reference exactly', () {
      final active = _active('Meeting at 5 PM today');
      expect(active, equals(pythonRef));
    });

    test('CLS=101 at position 0', () {
      expect(_tokenize('Meeting at 5 PM today')[0], 101);
    });

    test('SEP=102 immediately after last word token', () {
      final active = _active('Meeting at 5 PM today');
      expect(active.last, 102);
    });

    test('output length is always maxLength=96', () {
      expect(_tokenize('Meeting at 5 PM today').length, 96);
    });
  });

  // =========================================================================
  // String 2 — CASED: uppercase vs lowercase produce different IDs
  // =========================================================================

  group('Tokenizer parity — string 2: CASED model preserves case', () {
    test('"Meeting" (capital M) → ID 50986', () {
      final ids = _active('Meeting');
      expect(ids[1], 50986); // ids[0]=CLS, ids[1]=Meeting, ids[2]=SEP
    });

    test('"meeting" (lowercase) → ID 99001 (different from capital)', () {
      final ids = _active('meeting');
      expect(ids[1], 99001);
    });

    test('"Meeting" and "meeting" produce different token IDs', () {
      final capId = _active('Meeting')[1];
      final lowId = _active('meeting')[1];
      expect(capId, isNot(equals(lowId)));
    });

    test('"PM" (uppercase) → ID 46161', () {
      final ids = _active('PM today');
      expect(ids[1], 46161);
    });

    test('"pm" (lowercase) → ID 99002 (different from PM)', () {
      final ids = _active('pm today');
      expect(ids[1], 99002);
    });
  });

  // =========================================================================
  // String 3 — empty string
  // =========================================================================

  group('Tokenizer parity — string 3: empty string', () {
    test('active tokens are exactly [CLS, SEP]', () {
      expect(_active(''), equals([101, 102]));
    });

    test('output IDs length = 96', () {
      expect(_tokenize('').length, 96);
    });

    test('all remaining positions are PAD (0)', () {
      final ids = _tokenize('');
      for (int i = 2; i < ids.length; i++) {
        expect(ids[i], 0, reason: 'Position $i should be PAD');
      }
    });

    test('attention mask has exactly 2 active tokens', () {
      expect(_mask('').where((v) => v == 1).length, 2);
    });
  });

  // =========================================================================
  // String 4 — single known word
  // =========================================================================

  group('Tokenizer parity — string 4: single known word "account"', () {
    test('active tokens are [CLS=101, account=60006, SEP=102]', () {
      expect(_active('account'), equals([101, 60006, 102]));
    });

    test('attention count is 3', () {
      expect(_mask('account').where((v) => v == 1).length, 3);
    });
  });

  // =========================================================================
  // String 5 — OOV (unknown) word maps to [UNK]=100
  // =========================================================================

  group('Tokenizer parity — string 5: OOV word → UNK (100)', () {
    test('word absent from vocab → UNK token', () {
      final ids = _active('Zyxwvutsrqponmlkji');
      expect(ids[1], 100); // UNK
    });

    test('Hindi Devanagari word not in vocab → UNK', () {
      final ids = _active('आपका');
      expect(ids, contains(100));
    });

    test('UNK still produces length-96 output', () {
      expect(_tokenize('Zyxwvutsrqponmlkji').length, 96);
    });
  });

  // =========================================================================
  // String 6 — URL placeholder substitution
  // =========================================================================

  group('Tokenizer parity — string 6: URL → <url> placeholder (400)', () {
    test('https URL is replaced → token 400 in output', () {
      expect(_active('Click https://spam.com now'), contains(400));
    });

    test('bit.ly shortlink is replaced → token 400', () {
      expect(_active('Go to bit.ly/scam'), contains(400));
    });

    test('plain non-shortened URL (example.com) is NOT replaced', () {
      // The preprocess regex only replaces https://... or known shorteners.
      // A bare domain without https:// and not a shortener is left as-is.
      // 'example' is OOV → UNK; token 400 should NOT appear.
      final ids = _active('Visit example.com today');
      // 400 would appear only if the URL matched — it should not here.
      // The bare 'example.com' doesn't match https://\S+ or known shortener prefixes.
      expect(ids, isNot(contains(400)));
    });
  });

  // =========================================================================
  // String 7 — phone number placeholder
  // =========================================================================

  group('Tokenizer parity — string 7: phone → <phone> placeholder (401)', () {
    test('10-digit Indian number → token 401', () {
      expect(_active('Call 9876543210 now'), contains(401));
    });

    test('+91 number → token 401', () {
      expect(_active('Contact +91 9876543210'), contains(401));
    });
  });

  // =========================================================================
  // String 8 — amount placeholder
  // =========================================================================

  group('Tokenizer parity — string 8: amount → <amount> placeholder (402)', () {
    test('₹ + digits → token 402', () {
      expect(_active('Pay ₹5000'), contains(402));
    });

    test('Rs. + digits → token 402', () {
      expect(_active('Pay Rs.2000'), contains(402));
    });
  });

  // =========================================================================
  // String 9 — seqlen-96 padding / truncation
  // =========================================================================

  group('Tokenizer parity — string 9: seqlen-96 padding/truncation', () {
    test('short text padded to exactly 96 IDs', () {
      expect(_tokenize('Hello').length, 96);
      expect(_mask('Hello').length, 96);
    });

    test('long text truncated to exactly 96 IDs', () {
      final long = 'account ' * 200;
      expect(_tokenize(long).length, 96);
    });

    test('SEP lands at index 95 when input overflows', () {
      final long = 'account ' * 200;
      expect(_tokenize(long)[95], 102); // SEP
      expect(_mask(long)[95], 1);
    });

    test('packed input has all-1 attention mask', () {
      final long = 'your ' * 200;
      expect(_mask(long).every((v) => v == 1), isTrue);
    });

    test('PAD positions always have mask=0', () {
      final ids = _tokenize('Hello');
      final mask = _mask('Hello');
      for (int i = 0; i < ids.length; i++) {
        if (ids[i] == 0) expect(mask[i], 0, reason: 'PAD at $i must have mask=0');
      }
    });
  });

  // =========================================================================
  // String 10 — Hinglish phrase (mixed known/unknown tokens)
  // =========================================================================

  group('Tokenizer parity — string 10: Hinglish (mixed known/OOV)', () {
    test('English words in Hinglish get their expected IDs', () {
      final ids = _active('your account urgent now');
      // CLS=101, your=60007, account=60006, urgent=60005, now=60004, SEP=102
      expect(ids, containsAllInOrder([101, 60007, 60006, 60005, 60004, 102]));
    });

    test('Hinglish OOV words produce UNK (100)', () {
      // 'Yaar' and 'tera' are absent from _parityVocab
      expect(_active('Yaar tera account'), contains(100));
    });

    test('known English word in Hinglish context has correct ID', () {
      final ids = _active('Tera account deactivate hoga');
      expect(ids, contains(60006)); // 'account' = 60006
    });

    test('Hinglish text produces length-96 output', () {
      expect(_tokenize('Yaar tera account urgent hai abhi click kar link pe').length, 96);
    });

    test('OTP placeholder injected correctly inside Hinglish', () {
      // "Your OTP is 482910" — 6-digit number matches <otp> pattern
      final ids = _active('Your OTP is 482910 share karein');
      expect(ids, contains(403)); // <otp> = 403
    });
  });
}
