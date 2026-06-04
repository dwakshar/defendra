# Defendra

On-device SMS scam classifier for Android. Fine-tuned multilingual BERT, fully offline, zero data egress.

> Built like a terminal. Trusted like a vault.

---

## The Problem

India is among the most-targeted countries for SMS-based financial fraud (TRAI/CERT-In, FY2024). The dominant countermeasures — DLT sender blocklists, Truecaller caller-ID, bank-side OTP guards — inspect the sender, not the message body. Attackers route around them using personal SIMs or freshly registered commercial headers. Cloud-based content filters address the gap but send message text offdevice; on a phone linked to Aadhaar, UPI, and a bank account, that is a non-trivial privacy cost.

---

## What Makes It Different

**Content analysis.** Every byte of the SMS body is tokenized and scored — not matched against a sender database or blocklist.  
**No network layer, by architecture.** The binary contains no HTTP client, no DNS resolver, no analytics SDK. Data egress requires rewriting the app.  
**Explainable verdicts.** Every SCAM or SUSPICIOUS flag surfaces the specific regex signals that contributed to it.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  1. Sources         BroadcastReceiver (RECEIVE_SMS)              │
│                     Manual scan (paste / share-to)               │
├──────────────────────────────────────────────────────────────────┤
│  2. Platform        Kotlin BroadcastReceiver                     │
│                     → Flutter MethodChannel → Dart               │
├──────────────────────────────────────────────────────────────────┤
│  3. ML Engine       Dart WordPiece tokenizer                     │
│                     → LiteRT interpreter (CPU / XNNPACK)         │
│                     → regex rule matcher → verdict logic         │
├──────────────────────────────────────────────────────────────────┤
│  4. Business Logic  Riverpod providers                           │
│                     (InboxProvider, ScannerProvider)             │
├──────────────────────────────────────────────────────────────────┤
│  5. Storage / UI    Hive (local) → Flutter UI                    │
│                     No outbound path at any layer                │
└──────────────────────────────────────────────────────────────────┘
```

Privacy is a constraint, not a policy — there is no network layer in the binary.

---

## Tech Stack

| Component          | Technology                                                    |
|--------------------|---------------------------------------------------------------|
| Framework          | Flutter 3.44, Dart                                            |
| State management   | Riverpod 2.x                                                  |
| ML runtime         | LiteRT (`flutter_litert`)                                     |
| Storage            | Hive 2.x (local; encryption not yet enabled)                  |
| Platform bridge    | Kotlin BroadcastReceiver via Flutter MethodChannel            |
| Model training     | PyTorch + HuggingFace Transformers, Google Colab / Kaggle     |
| Model conversion   | litert-torch (`torch.export` → StableHLO → `.tflite`)         |

Android-only. iOS does not expose a `RECEIVE_SMS` equivalent.

---

## ML Pipeline

### Dataset

~2,300 labelled SMS after deduplication from ~2,900 raw rows. Sources: Kaggle India spam-ham corpus (majority), manually authored templates derived from TRAI/CERT-In documented scam patterns, and a small number of real inbox examples.

Two meaningfully populated classes: **safe** (~2,018 rows) and **scam** (~286 rows). The training corpus is approximately 87% safe — close to a filtered real inbox, not a balanced fraud dataset. A four-class taxonomy (`otp_kyc` / `delivery_courier` / `digital_arrest`) is modelled as output heads but **per-class data collection is ongoing and insufficient for reliable held-out evaluation**. In operational terms this is a binary classifier: safe vs. scam.

### Training

- Base: `distilbert-base-multilingual-cased` — 6 transformer layers, hidden dim 768, 119,547-token multilingual vocabulary
- Split: **group split by template ID**, not random row split. Messages sharing a template land in the same partition; no paraphrase of a training example appears in the test set.
- Class-weighted cross-entropy loss to compensate for the 87 / 13 class imbalance.

### Conversion Gate

A converted model is accepted only when all three checks pass on the `.tflite` output:

1. `interpreter.allocate_tensors()` completes without error
2. Zero Flex ops — all ops resolved to built-in TFLite kernels
3. Finite, non-NaN logits on a fixed probe input

Conversion path: `torch.export` → litert-torch → StableHLO → `.tflite`.

### Model Size

| Variant                          | Size              |
|----------------------------------|-------------------|
| Float32 (current bundled asset)  | ~540 MB           |
| INT8 dynamic-range               | [PLACEHOLDER] MB  |

The dominant cost is the embedding table: 119,547 tokens × 768 dims ≈ 350 MB at float32. Reducing to a Play Store-acceptable APK budget requires vocabulary pruning (retain only tokens observed in the SMS domain) or switching to a smaller architecture; both are roadmap items.

### Verdict Logic

```
p_scam      = model output probability for the scam class
rule_signal = regex rule matcher fired ≥ 1 pattern

if p_scam > 0.85  AND rule_signal  → SCAM
if p_scam > 0.50  AND rule_signal  → SUSPICIOUS
else                               → SAFE
```

The rule gate is a deliberate design choice, not a patch. Fine-tuning on an 87% safe corpus can produce confident-looking softmax outputs on safe messages whose surface features resemble scam text (urgency phrasing, amount tokens). Requiring at least one concrete lexical signal before issuing a scam verdict prevents the model from firing on coincidental feature overlap — e.g., "Transfer ₹500 for lunch." The tradeoff is explicit: a scam message that leaves no regex-detectable trace is capped at SAFE. The 11 current rule patterns cover the high-confidence linguistic markers of documented Indian SMS fraud categories.

### Metrics

Evaluated on a held-out test set (group split; no template overlap with training data):

| Metric                                 | Value                                         |
|----------------------------------------|-----------------------------------------------|
| Scam-class recall                      | [PLACEHOLDER]                                 |
| Safe false-positive rate               | [PLACEHOLDER]                                 |
| On-device inference latency — p50      | [PLACEHOLDER]                                 |
| On-device inference latency — p95      | [PLACEHOLDER]                                 |
| Device under test                      | [PLACEHOLDER, e.g. Snapdragon 4 Gen 1]        |

Dev-machine numbers (Windows 11, Intel CPU, Python litert runtime) are not reported here; they do not predict Android inference performance.

### Known Limitations

- **Binary today.** Effective two-class classifier. The 4-class taxonomy is pending data collection to a defensible per-class threshold.
- **Thin scam data.** ~286 scam examples; minority class is structurally under-represented relative to real fraud exposure rates.
- **Model size.** ~540 MB float32 / [PLACEHOLDER] MB INT8. Neither variant fits in a standard APK without vocabulary pruning or an architecture change.
- **No GPU delegation.** The model graph includes `GATHER_ND` ops (embedding lookup) and int64 tensors, both unsupported by the Android GPU delegate. Inference runs on CPU via XNNPACK.
- **Language coverage.** Fine-tuned on ~92% English data. Performance on Hindi and Hinglish is structurally understated; real-world false-negative rate on Devanagari-heavy scam messages is unknown.

---

## Build & Run

### Prerequisites

- Flutter SDK ≥ 3.44
- Android SDK, API 21+, `arm64-v8a` target
- Git LFS — the `.tflite` asset exceeds GitHub's 100 MB file limit and is tracked via LFS

### Steps

```bash
git clone [PLACEHOLDER — GitHub URL]
cd defendra
git lfs pull                      # downloads assets/ml/model.tflite (~540 MB)
flutter pub get
flutter run                       # debug build on connected device
flutter build apk --release       # release APK
```

The model lives at `assets/ml/`. Its filename is declared in `pubspec.yaml`; swapping to a quantized variant is a one-line change there plus a corresponding path update in `lib/ml/ml_engine.dart`.

### Distribution

Google Play requires apps using `READ_SMS` / `RECEIVE_SMS` to hold default-SMS-app status or an approved exception — neither applies here. Defendra ships via **F-Droid and direct APK**. Play Store distribution is a roadmap item contingent on exception approval.

---

## Privacy

| Permission           | Required for                                               |
|----------------------|------------------------------------------------------------|
| `RECEIVE_SMS`        | Intercept incoming SMS before the system default app       |
| `READ_SMS`           | Scan the existing inbox on first launch                    |
| `POST_NOTIFICATIONS` | Alert the user on a high-confidence SCAM verdict           |

No location. No contacts. No camera. No microphone. No internet.

SMS text flows: `BroadcastReceiver → MethodChannel → Dart isolate → LiteRT → rule matcher → verdict → Hive → UI`. There is no outbound path at any layer. The codebase contains no HTTP client, no Firebase, no Crashlytics, no analytics endpoint. Removing this guarantee requires adding a network layer and rebuilding the app — it cannot happen via a remote config change.

Scan history (sender, body, verdict, timestamp) is stored in a Hive box on-device. Hive encryption is not yet enabled; device-level full-disk encryption is the current protection boundary.

Open source: [PLACEHOLDER — GitHub URL].

---

## Roadmap

- **4-class taxonomy** — `otp_kyc` / `delivery_courier` / `digital_arrest` as distinct evaluated output classes, contingent on reaching ≥ 200 held-out examples per class.
- **Hindi / Hinglish expansion** — dedicated fine-tuning corpus; target ≥ 40% non-English training data.
- **Additional Indian languages** — Tamil, Telugu, Bengali.
- **Voice / call scam detection** — transcript or audio-embedding approach; requires a different model architecture.
- **Hive encryption** — AES-256 for the on-device scan history box.
- **Play Store distribution** — subject to SMS-permission exception approval.

---

## Screenshots / Demo

[PLACEHOLDER — inbox screenshot: safe / suspicious / scam row states]  
[PLACEHOLDER — detail screen: verdict breakdown + triggered rule signals]  
[PLACEHOLDER — 30-second demo GIF: incoming scam SMS → notification → verdict screen]

---

[PLACEHOLDER — engineering write-up: model conversion, verdict logic, size engineering]

---

## License

MIT — see [LICENSE](LICENSE).
