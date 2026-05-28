# Defendra

> Built like a terminal. Trusted like a vault.

![Phase](https://img.shields.io/badge/Phase%200-Foundation-lightgrey?style=flat-square)

Privacy-first, on-device AI scam detection for India. No cloud. No surveillance. Just signal.

---

## Stack

| Layer       | Tech                                          |
|-------------|-----------------------------------------------|
| Framework   | Flutter 3.x (Android primary, iOS supported)  |
| State       | Riverpod 2.x                                  |
| ML          | TFLite Flutter (on-device inference)          |
| Storage     | Hive (local, encrypted in Phase 2)            |
| Permissions | permission_handler                            |
| Fonts       | Inter + JetBrains Mono via google_fonts       |

---

## Build

```bash
flutter pub get
flutter run
```

---

## Roadmap

- [x] Phase 0 — Foundation & monochrome shell
- [ ] Phase 1 — SMS interception & storage
- [ ] Phase 2 — On-device ML inference
- [ ] Phase 3 — Stats, history, light theme
- [ ] Phase 4 — Polish, notifications, release
