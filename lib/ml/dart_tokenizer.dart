import 'dart:convert';

import 'package:flutter/services.dart';

/// Mirrors HuggingFace distilbert-base-multilingual-cased tokenizer:
///   do_lower_case=False, strip_accents=False, tokenize_chinese_chars=True.
///
/// Pipeline: preprocess (domain replacements) → clean_text → CJK-space →
///   whitespace-split → punc-split → WordPiece → pad to maxLength.
class DartTokenizer {
  static const int defaultMaxLength = 96;
  static const _urlPlaceholder = '<url>';
  static const _phonePlaceholder = '<phone>';
  static const _amountPlaceholder = '<amount>';
  static const _otpPlaceholder = '<otp>';

  Map<String, int> _vocab = {};
  bool _loaded = false;
  late int _padToken;
  late int _unkToken;
  late int _clsToken;
  late int _sepToken;
  String? _urlToken;
  String? _phoneToken;
  String? _amountToken;
  String? _otpToken;
  late List<String> _preservedTokens;

  DartTokenizer();

  DartTokenizer.fromVocab(Map<String, int> vocab)
      : _vocab = vocab,
        _loaded = true {
    _initDerivedState();
  }

  bool get isLoaded => _loaded;

  Map<String, int> get vocab {
    assert(_loaded, 'DartTokenizer.load() must be called before accessing vocab');
    return _vocab;
  }

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/ml/vocab.json');
    final Map<String, dynamic> parsed = json.decode(raw);
    _vocab = parsed.map((k, v) => MapEntry(k, (v as num).toInt()));
    _initDerivedState();
    _loaded = true;
  }

  Map<String, List<int>> tokenize(String text, {int maxLength = defaultMaxLength}) {
    if (!_loaded) throw StateError('DartTokenizer not loaded');
    if (maxLength < 2) throw ArgumentError.value(maxLength, 'maxLength', 'must be at least 2');

    final preprocessed = _preprocess(text);
    final words = _basicTokenize(preprocessed);
    final ids = <int>[_clsToken];

    for (final word in words) {
      if (ids.length >= maxLength - 1) break;
      final pieces = _wordpieceIds(word);
      for (final id in pieces) {
        if (ids.length >= maxLength - 1) break;
        ids.add(id);
      }
    }
    ids.add(_sepToken);

    final inputIds = List<int>.filled(maxLength, _padToken);
    final attentionMask = List<int>.filled(maxLength, 0);

    for (int i = 0; i < ids.length && i < maxLength; i++) {
      inputIds[i] = ids[i];
      attentionMask[i] = 1;
    }

    return {'input_ids': inputIds, 'attention_mask': attentionMask};
  }

  // ---------------------------------------------------------------------------
  // Pre-processing: domain-specific entity substitution (NOT lowercasing —
  // this is a cased model).  Placeholders are only injected if they exist in
  // the vocab so that the model never sees out-of-vocab tokens here.
  // ---------------------------------------------------------------------------

  String _preprocess(String text) {
    var out = text;
    out = _replaceIfSupported(
      out,
      RegExp(
        r'https?://\S+|(?:bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly|is\.gd|cutt\.ly|rb\.gy)/\S+',
        caseSensitive: false,
      ),
      _urlToken,
    );
    out = _replaceIfSupported(
      out,
      RegExp(r'(?<!\d)\+?(?:\d[\s\-]?){9,14}(?!\d)'),
      _phoneToken,
    );
    out = _replaceIfSupported(
      out,
      RegExp('(?:rs\\.?|inr|\\u20B9)\\s*[\\d,]+(?:\\.\\d+)?', caseSensitive: false),
      _amountToken,
    );
    out = _replaceIfSupported(out, RegExp(r'\b\d{4,8}\b'), _otpToken);
    return out;
  }

  String _replaceIfSupported(String text, RegExp regex, String? token) {
    if (token == null) return text;
    return text.replaceAllMapped(regex, (_) => ' $token ');
  }

  // ---------------------------------------------------------------------------
  // BERT BasicTokenizer (cased):
  //   1. _cleanText      — strip control chars, normalize all whitespace → ' '
  //   2. _addCjkSpaces   — wrap CJK codepoints with spaces (treats each as a
  //                        standalone token before whitespace-split)
  //   3. whitespace-split
  //   4. _splitOnPunc    — split each token on punctuation boundaries,
  //                        but never split preserved placeholder tokens
  // ---------------------------------------------------------------------------

  List<String> _basicTokenize(String text) {
    final cleaned = _cleanText(text);
    final spaced = _addCjkSpaces(cleaned);
    final rawTokens = spaced.trim().split(RegExp(r'\s+'));

    final result = <String>[];
    for (final token in rawTokens) {
      if (token.isEmpty) continue;
      if (_isPreservedToken(token)) {
        result.add(token);
      } else {
        result.addAll(_splitOnPunc(token));
      }
    }
    return result;
  }

  // Mirrors BERT _clean_text: remove NUL / U+FFFD / Cc+Cf controls; map all
  // whitespace variants to a plain space.
  String _cleanText(String text) {
    final buf = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final cp = text.codeUnitAt(i);
      if (cp == 0 || cp == 0xFFFD || _isControl(cp)) continue;
      buf.writeCharCode(_isWhitespace(cp) ? 0x20 : cp);
    }
    return buf.toString();
  }

  // Mirrors BERT _tokenize_chinese_chars.
  String _addCjkSpaces(String text) {
    final buf = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final cp = text.codeUnitAt(i);
      if (_isCjk(cp)) {
        buf.write(' ');
        buf.writeCharCode(cp);
        buf.write(' ');
      } else {
        buf.writeCharCode(cp);
      }
    }
    return buf.toString();
  }

  // Mirrors BERT _run_split_on_punc (without never_split — special tokens
  // won't appear in raw SMS input).
  List<String> _splitOnPunc(String token) {
    final result = <String>[];
    final buf = StringBuffer();
    for (int i = 0; i < token.length; i++) {
      final cp = token.codeUnitAt(i);
      if (_isPunc(cp)) {
        if (buf.isNotEmpty) {
          result.add(buf.toString());
          buf.clear();
        }
        result.add(String.fromCharCode(cp));
      } else {
        buf.writeCharCode(cp);
      }
    }
    if (buf.isNotEmpty) result.add(buf.toString());
    return result;
  }

  // ---------------------------------------------------------------------------
  // WordPiece: greedy longest-match-first, ## continuation prefix, [UNK] OOV.
  // ---------------------------------------------------------------------------

  List<int> _wordpieceIds(String word) {
    if (word.isEmpty) return [];
    final direct = _vocab[word];
    if (direct != null) return [direct];

    final ids = <int>[];
    int start = 0;
    while (start < word.length) {
      int end = word.length;
      int? found;
      while (start < end) {
        final sub = start == 0 ? word.substring(0, end) : '##${word.substring(start, end)}';
        final id = _vocab[sub];
        if (id != null) {
          found = id;
          break;
        }
        end--;
      }
      if (found == null) return [_unkToken];
      ids.add(found);
      start = end;
    }
    return ids;
  }

  // ---------------------------------------------------------------------------
  // Unicode classifiers — mirrors CPython unicodedata behaviour used by BERT.
  // ---------------------------------------------------------------------------

  bool _isCjk(int cp) {
    // Ranges from BERT tokenization_utils_base.py _is_chinese_char
    return (cp >= 0x4E00 && cp <= 0x9FFF) ||
        (cp >= 0x3400 && cp <= 0x4DBF) ||
        (cp >= 0x20000 && cp <= 0x2A6DF) ||
        (cp >= 0x2A700 && cp <= 0x2B73F) ||
        (cp >= 0x2B740 && cp <= 0x2B81F) ||
        (cp >= 0x2B820 && cp <= 0x2CEAF) ||
        (cp >= 0xF900 && cp <= 0xFAFF) ||
        (cp >= 0x2F800 && cp <= 0x2FA1F);
  }

  // Mirrors unicodedata.category(c).startswith('P') — covers the Unicode
  // punctuation categories (Po, Pd, Ps, Pe, Pi, Pf, Pc) used by BERT, plus
  // the ASCII punctuation ranges BERT hard-codes.
  bool _isPunc(int cp) {
    // ASCII hard-coded in BERT source
    if ((cp >= 33 && cp <= 47) ||
        (cp >= 58 && cp <= 64) ||
        (cp >= 91 && cp <= 96) ||
        (cp >= 123 && cp <= 126)) {
      return true;
    }
    // General Punctuation (U+2010–U+206F): dashes, quotes, ellipsis, etc.
    // U+2000–U+200A are Zs (spaces) — already consumed by whitespace-split.
    if (cp >= 0x2010 && cp <= 0x206F) return true;
    // Supplemental Punctuation
    if (cp >= 0x2E00 && cp <= 0x2E7F) return true;
    // CJK Symbols and Punctuation
    if (cp >= 0x3000 && cp <= 0x303F) return true;
    // Halfwidth / Fullwidth punctuation
    if (cp >= 0xFF01 && cp <= 0xFF0F) return true;
    if (cp >= 0xFF1A && cp <= 0xFF20) return true;
    if (cp >= 0xFF3B && cp <= 0xFF40) return true;
    if (cp >= 0xFF5B && cp <= 0xFF65) return true;
    // Devanagari danda (।) and double danda (॥) — Po category
    if (cp == 0x0964 || cp == 0x0965) return true;
    // Arabic punctuation
    if (cp >= 0x0600 && cp <= 0x060F) return true;
    // Miscellaneous punctuation
    if (cp >= 0x2300 && cp <= 0x23FF) return true;
    return false;
  }

  // Mirrors BERT _is_control: Cc / Cf Unicode categories, excluding \t \n \r.
  bool _isControl(int cp) {
    if (cp == 0x09 || cp == 0x0A || cp == 0x0D) return false; // kept as whitespace
    if (cp <= 0x1F) return true;          // C0 controls
    if (cp >= 0x7F && cp <= 0x9F) return true; // DEL + C1 controls
    // Cf (Format) — zero-width, directional, BOM, soft hyphen
    if (cp == 0x00AD) return true;
    if (cp >= 0x200B && cp <= 0x200F) return true;
    if (cp >= 0x202A && cp <= 0x202E) return true;
    if (cp >= 0x2060 && cp <= 0x2064) return true;
    if (cp == 0xFEFF) return true;
    return false;
  }

  // Mirrors BERT _is_whitespace: explicit list + Unicode Zs category.
  bool _isWhitespace(int cp) {
    if (cp == 0x20 || cp == 0x09 || cp == 0x0A || cp == 0x0D) return true;
    // Unicode Zs (Space Separator) category
    if (cp == 0xA0) return true;   // No-Break Space
    if (cp == 0x1680) return true; // Ogham Space Mark
    if (cp >= 0x2000 && cp <= 0x200A) return true; // En/Em/thin/etc. spaces
    if (cp == 0x202F) return true; // Narrow No-Break Space
    if (cp == 0x205F) return true; // Medium Mathematical Space
    if (cp == 0x3000) return true; // Ideographic Space
    return false;
  }

  // ---------------------------------------------------------------------------
  // Initialisation helpers
  // ---------------------------------------------------------------------------

  void _initDerivedState() {
    _padToken = _resolveSpecial(['[PAD]', '<pad>'], fallback: 0);
    _unkToken = _resolveSpecial(['[UNK]', '<unk>'], fallback: 100);
    _clsToken = _resolveSpecial(['[CLS]', '<s>'], fallback: 101);
    _sepToken = _resolveSpecial(['[SEP]', '</s>'], fallback: 102);

    _urlToken = _vocab.containsKey(_urlPlaceholder) ? _urlPlaceholder : null;
    _phoneToken = _vocab.containsKey(_phonePlaceholder) ? _phonePlaceholder : null;
    _amountToken = _vocab.containsKey(_amountPlaceholder) ? _amountPlaceholder : null;
    _otpToken = _vocab.containsKey(_otpPlaceholder) ? _otpPlaceholder : null;

    _preservedTokens = [
      ?_urlToken,
      ?_phoneToken,
      ?_amountToken,
      ?_otpToken,
    ]..sort((a, b) => b.length.compareTo(a.length));
  }

  int _resolveSpecial(List<String> candidates, {required int fallback}) {
    for (final t in candidates) {
      final id = _vocab[t];
      if (id != null) return id;
    }
    return fallback;
  }

  bool _isPreservedToken(String token) {
    for (final pt in _preservedTokens) {
      if (token == pt) return true;
    }
    return false;
  }
}
