import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _kBox = 'settings';

// ---------------------------------------------------------------------------
// Sensitivity — notification confidence threshold (default 0.85)
// ---------------------------------------------------------------------------

class SensitivityNotifier extends StateNotifier<double> {
  SensitivityNotifier()
      : super(
          Hive.box(_kBox).get('notification_threshold',
              defaultValue: 0.85) as double,
        );

  void set(double v) {
    state = v;
    Hive.box(_kBox).put('notification_threshold', v);
  }
}

final sensitivityProvider =
    StateNotifierProvider<SensitivityNotifier, double>(
  (ref) => SensitivityNotifier(),
);

// ---------------------------------------------------------------------------
// Language preference — 'auto' | 'en' | 'hi' | 'hinglish'
// ---------------------------------------------------------------------------

class LanguageNotifier extends StateNotifier<String> {
  LanguageNotifier()
      : super(
          Hive.box(_kBox).get('language_preference',
              defaultValue: 'auto') as String,
        );

  void set(String v) {
    state = v;
    Hive.box(_kBox).put('language_preference', v);
  }
}

final languageProvider =
    StateNotifierProvider<LanguageNotifier, String>(
  (ref) => LanguageNotifier(),
);

// ---------------------------------------------------------------------------
// Whitelist — sender IDs that bypass ML classification
// ---------------------------------------------------------------------------

class WhitelistNotifier extends StateNotifier<List<String>> {
  WhitelistNotifier()
      : super(
          (Hive.box(_kBox)
                  .get('whitelist_senders', defaultValue: <String>[]) as List)
              .cast<String>(),
        );

  void add(String sender) {
    final s = sender.trim();
    if (s.isEmpty || state.contains(s)) return;
    state = [...state, s];
    _persist();
  }

  void remove(String sender) {
    state = state.where((s) => s != sender).toList();
    _persist();
  }

  void _persist() => Hive.box(_kBox).put('whitelist_senders', state);
}

final whitelistProvider =
    StateNotifierProvider<WhitelistNotifier, List<String>>(
  (ref) => WhitelistNotifier(),
);

// ---------------------------------------------------------------------------
// Light mode — persisted, visual wiring happens in polish step
// ---------------------------------------------------------------------------

class LightModeNotifier extends StateNotifier<bool> {
  LightModeNotifier()
      : super(
          Hive.box(_kBox).get('light_mode', defaultValue: false) as bool,
        );

  void toggle() {
    state = !state;
    Hive.box(_kBox).put('light_mode', state);
  }
}

final lightModeProvider =
    StateNotifierProvider<LightModeNotifier, bool>(
  (ref) => LightModeNotifier(),
);
