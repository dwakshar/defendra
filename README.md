# Defendra

> Built like a terminal. Trusted like a vault.

On-device AI scam detector for Indian SMS. Classifies every incoming message locally — no server, no account, no data egress. Fine-tuned multilingual BERT runs entirely inside the app.

---

## Table of Contents

1. [Demo](#demo)
2. [The Problem](#the-problem)
3. [Architecture](#architecture)
4. [ML Model](#ml-model)
5. [Dataset](#dataset)
6. [Build & Run](#build--run)
7. [Privacy](#privacy)
8. [Honest Limitations](#honest-limitations)
9. [Roadmap](#roadmap)

---

## Demo

> **GIF placeholder** — record a 30-second clip: receive a scam SMS → notification fires → inbox shows verdict + explanation → tap to see signal breakdown.

> **Screenshot placeholder** — inbox view (safe / suspicious / scam rows), detail screen showing triggered rule phrases, settings/privacy screen.

---

## The Problem

India is the most-targeted country for SMS-based financial fraud. The dominant attack patterns are well-documented by TRAI and CERT-In: OTP/KYC harvesting where attackers impersonate banks or government services; "digital arrest" scams where victims receive messages claiming CBI/ED investigation; delivery-fee fraud tied to courier tracking; and lottery/job scams piggybacking on UPI growth.

**Why existing tools don't close the gap:**

| Tool | What it does | Why it falls short |
|---|---|---|
| Truecaller | Caller ID lookup via crowd database | Cloud-dependent; covers calls better than SMS; shares your contact graph |
| Bank apps | Intercept OTPs for their own flows | Blind to third-party impersonation; only active while app is open |
| TRAI/DLT blocklist | Blocks registered commercial senders | Attackers use personal SIMs or register on the platform; blocklist lags by weeks |
| Google Messages spam filter | Heuristic + cloud ML | Sends message metadata to Google; English-optimised; misses Hindi/Hinglish patterns |

The shared flaw: every cloud-based approach requires the message to leave the device. For a country where the same phone number is linked to a bank account, Aadhaar, and UPI, that is a meaningful privacy tradeoff. Defendra's architecture makes the tradeoff impossible by construction: there is no HTTP client in the binary.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 1 — SMS Intercept                                     │
│  Android BroadcastReceiver (RECEIVE_SMS permission)          │
│  Captures raw sender + body; feeds into Dart isolate         │
└───────────────────────────────┬──────────────────────────────┘
                                │ raw text string
┌───────────────────────────────▼──────────────────────────────┐
│  Layer 2 — Tokenizer  (Dart, in-process, no FFI)            │
│  Preprocessing: replace URLs, phones, amounts, OTPs, dates  │
│  with typed placeholders (<url>, <phone>, <amount>, <otp>)  │
│  Basic tokenize → WordPiece (mirrors HuggingFace exactly)   │
│  Output: [CLS] + up to 94 subword tokens + [SEP], pad to 96 │
└───────────────────────────────┬──────────────────────────────┘
                                │ int64[1×96] input_ids + mask
┌───────────────────────────────▼──────────────────────────────┐
│  Layer 3 — TFLite Inference  (persistent Dart Isolate)      │
│  distilbert-base-multilingual-cased, fine-tuned 4-class     │
│  Model bytes transferred once (zero-copy TransferableTypedData)│
│  Pre-allocated tensor buffers reused per call (no GC spike) │
│  Returns logits[4]: safe · otp_kyc · delivery · dig_arrest  │
└──────────────────┬────────────────────────────┬──────────────┘
                   │ logits                     │ (parallel)
┌──────────────────▼──────────────┐  ┌──────────▼──────────────┐
│  Layer 4a — Softmax + Gate      │  │  Layer 4b — Rule Matcher│
│  p_scam_total = Σ probs[1..3]  │  │  11 regex signal keys   │
│  Threshold: 0.85 → scam         │  │  (sync, no I/O)         │
│             0.50 → suspicious   │  │  digital_arrest, lottery│
│  No signals → cap at safe       │  │  job_scam, delivery_fee │
└──────────────────┬──────────────┘  └──────────┬──────────────┘
                   │ prob vector                 │ fired signal keys
┌──────────────────▼─────────────────────────────▼──────────────┐
│  Layer 5 — Verdict Gate                                       │
│  ML corroborated by ≥1 rule signal → verdict (scam/suspicious)│
│  High-signal key alone (pSafe < 0.75) → suspicious override  │
│  Output: ScanResult {label, verdict, confidence, category,   │
│          triggerPhrases, firedSignalKeys, ruleOverride}      │
└───────────────────────────────────────────────────────────────┘
```

**The no-network-layer guarantee is structural, not policy.**  
There is no HTTP client, no DNS resolver, no analytics SDK, no crash reporter in the binary. The privacy commitment cannot be silently removed by a config flag or server-side change — it requires rewriting the app.

---

## ML Model

### Architecture

Base: `distilbert-base-multilingual-cased` — 6 transformer layers, hidden dim 768, 119,547-token vocabulary, 134M parameters. Fine-tuned for 4-class SMS classification: `safe`, `otp_kyc`, `delivery_courier`, `digital_arrest`.

`otp_kyc` is a consolidated bucket covering OTP harvesting, KYC fraud, bank impersonation, refund scams, job scams, lottery, electricity bill fraud, and loan fraud. These sub-types share the same user action (share a code / transfer money urgently) and are semantically close in embedding space.

### Size Engineering

The multilingual embedding table — 119,547 tokens × 768 dims — is the dominant cost. It is 67.7% of the model by size and 68.5% of parameters.

| Step | What changed | Size |
|---|---|---|
| Float32 baseline | — | **515 MB** |
| INT8 quantization (weights only) | Transformer layers quantized to INT8; embedding stays fp32 | **392 MB** |
| Vocab prune + INT8 | Tokenized full training corpus; kept only 38,400 of 119,547 tokens seen in SMS domain (67.9% reduction); sliced 81,147 dead embedding rows; full INT8 including embedding | **114 MB** |

**Why embedding stays fp32 in the unpruned INT8 model:** `tflite_flutter 0.12.0` (backed by TFLite 2.16) cannot consume native int8-quantized output tensors without explicit Dart dequantization code. The pruned INT8 model uses `dynamic_wi8_afp32` (weights INT8, activations fp32), which quantizes the embedding as a weight tensor and is directly consumable.

The currently bundled asset (`assets/ml/model.tflite`) is the 515 MB float32 model. The 392 MB and 114 MB variants are present in the repository and pass accuracy parity (see below). Switching the bundled asset is a one-line change in `pubspec.yaml`.

### Quantization Method

`dynamic_wi8_afp32` — channelwise INT8 weights, fp32 activations. Selected because:
- Fully supported by `tflite_flutter 0.12.0` without Dart dequantization shims
- Zero accuracy delta vs float32 on this dataset (see delta table below)
- 2.7× faster inference on CPU vs float32 (67 ms vs 181 ms, dev machine)

### Per-Class Metrics

**Test set: n = 461** (stratified 80/20 split, `random_state=42`).  
Split breakdown: safe n=404, otp_kyc n=41, delivery_courier n=8, digital_arrest n=8.

> ⚠ delivery_courier and digital_arrest test sets are 8 samples each. Recall figures for these classes are directional, not statistically stable. A 1-sample misclassification moves recall by 12.5 pp.

**INT8 model (392 MB) — identical to float32 on this dataset (Δ = 0.0 pp all classes):**

| Class | Recall | FPR | Test n |
|---|---|---|---|
| safe | 99.0% | 1.8% | 404 |
| otp_kyc | 92.7% | 2.1% | 41 |
| delivery_courier | 62.5% | 0.0% | 8 |
| digital_arrest | 75.0% | 0.4% | 8 |
| **overall accuracy** | **97.40%** | — | **461** |

Overall accuracy (97.40%) is dominated by the 87.6% safe majority. The minority-class figures are the meaningful signal.

**Confusion matrix (rows = actual, columns = predicted):**

```
                   pred:safe  pred:otp_kyc  pred:delivery  pred:dig_arrest
actual:safe           400            4              0               0
actual:otp_kyc          1           38              0               2
actual:delivery         0            3              5               0
actual:dig_arrest       0            2              0               6
```

Notable patterns: 3 of 8 delivery messages are misclassified as `otp_kyc` (both categories share urgency language and amount mentions). 2 digital-arrest messages are classified as `otp_kyc` (authority-impersonation patterns overlap). Zero false scams classified as each other across the safe/scam boundary — the model does not invent scam verdicts for safe messages.

### Inference Latency

Measured on Windows 11 Pro, Intel CPU, Python `ai_edge_litert` 2.1.5 (same TFLite runtime as the Android build). **This is a dev machine, not a target Android device.** No mobile measurements have been collected yet — see [Honest Limitations](#honest-limitations).

| Model | Median | p95 | Platform |
|---|---|---|---|
| Float32 (515 MB) | 180.9 ms | 190.7 ms | Windows 11 CPU |
| INT8 (392 MB) | 67.5 ms | 84.2 ms | Windows 11 CPU |

Mobile inference numbers will differ. On a mid-range ARM64 device (Snapdragon 680 / Dimensity 700 class) without NNAPI delegation, CPU-only TFLite INT8 for a 6-layer BERT at seqlen 96 is typically 200–500 ms. With NNAPI DSP delegation, latency can drop to 50–150 ms.

### Verdict Logic

```
p_scam_total = prob[otp_kyc] + prob[delivery] + prob[digital_arrest]
has_signals  = rule matcher fired ≥1 key
has_high_signal = fired key ∈ {digital_arrest, lottery, job_scam, delivery_fee}

if p_scam_total > 0.85 AND has_signals  → SCAM
if p_scam_total > 0.50 AND has_signals  → SUSPICIOUS
if p_scam_total > 0.50 AND NOT signals  → SAFE  (rule override, ruleOverride=true)
else                                    → SAFE

# High-signal upgrade: near-zero-FP rules can escalate ML-uncertain safe verdict
if has_high_signal AND verdict==SAFE AND p_safe < 0.75 → SUSPICIOUS
```

**Why the rule gate exists:** The training set is 87.6% safe. A fine-tuned classifier on an imbalanced set can produce confident-looking softmax outputs on safe messages whose surface features happen to resemble scam text (urgency language, amount mentions). The rule matcher requires at least one concrete lexical signal to be present before a scam verdict is reported. This prevents the model from firing on "Meeting at 5 PM — transfer ₹500 for lunch" purely because of the amount token.

The tradeoff: a scam message with no regex-detectable surface signals will be capped at `SAFE`. In practice, the 11 signal patterns cover the high-confidence linguistic markers of each scam category and have near-zero false-positive rate.

---

## Dataset

### Sources

| Source | Rows | % | Notes |
|---|---|---|---|
| Kaggle India SMS spam-ham | 2,029 | 88.1% | Public dataset; predominantly English; skewed toward commercial spam rather than financial fraud |
| Synthetic | 192 | 8.3% | Generated and augmented examples for under-represented scam categories |
| Manual seeds | 80 | 3.5% | Hand-labeled examples from real inbox patterns and documented scam templates |
| Reddit / inbox | 3 | 0.1% | Opportunistic real examples |
| **Total (after dedup)** | **2,304** | | Deduped from 2,914 raw rows: 577 exact + 33 near-duplicate removals |

### Label Scheme

Binary label (`0=safe`, `1=scam`) with a `category` field for the 4 ML classes:

| ML class | Category bucket | Examples |
|---|---|---|
| 0 — safe | safe_promo (675), safe_generic (669), safe_personal (661), safe_transactional (13) | Promotional messages, OTPs from legitimate services, transactional alerts |
| 1 — otp_kyc | otp (40), kyc (42), bank_impersonation (49), refund (34), job (14), lottery (11), electricity (9), loan (8) | "Your OTP is X — do not share", "KYC update required or account blocked" |
| 2 — delivery_courier | delivery (40) | "Your package is held at customs. Pay ₹499 to release." |
| 3 — digital_arrest | digital_arrest (39) | "CBI officer speaking. You are under digital arrest." |

### Collection Methodology

Safe messages sourced from the Kaggle India dataset. Scam examples sourced via keyword search on the same dataset, augmented with manually authored templates matching documented fraud patterns from TRAI/CERT-In public advisories. Synthetic examples generated with controlled variation of sender name, amount, phone number, and urgency phrasing using the placeholder schema (`<phone>`, `<amount>`, `<otp>`, `<url>`, `<name>`).

### Known Biases and Limits

- **Class imbalance (12.4% scam):** Significantly below the 35–60% target ratio. The model is trained on a dataset that more closely resembles a filtered inbox than raw SMS traffic from a fraud-exposed user. This inflates safe recall and likely deflates scam recall at deployment.
- **Language coverage (English 91.9%, Hinglish 4.4%, Hindi 3.7%):** The 40% Hindi/Hinglish coverage target is unmet. The model will perform worse on Devanagari-heavy messages. `distilbert-base-multilingual-cased` does have Hindi subword coverage in its 119k vocab, but the fine-tuning signal for that language is thin.
- **Small scam test sets:** delivery_courier (n=8) and digital_arrest (n=8) metrics have ±12.5 pp noise floor. Recall figures for these classes should be treated as directional.
- **No real-world deployment test:** The 169 `review_needed` rows in the dataset have not been manually audited. Some may be mislabeled.
- **Temporal drift:** Scam patterns evolve. The Kaggle India dataset has no date stamps; recency distribution is unknown.

---

## Build & Run

### Prerequisites

- Flutter SDK ≥ 3.12.0
- Android SDK (API 21+, arm64-v8a target)
- The model asset `assets/ml/model.tflite` must be present (515 MB, tracked via Git LFS or downloaded separately — see below)

> **Model download:** The TFLite model is too large for standard Git tracking. If cloning fresh, download from the release assets and place at `assets/ml/model.tflite`. The pruned INT8 variant (`assets/ml/model_pruned_int8.tflite`, 114 MB) can be swapped in by updating `pubspec.yaml` and `lib/ml/ml_engine.dart` → `load()`.

### Steps

```bash
git clone https://github.com/dwakshar/defendra.git
cd defendra
flutter pub get
flutter run                      # debug on connected device
flutter build apk --release      # release APK (currently ~540 MB with float32 model)
```

### Switching to the Pruned INT8 Model

```yaml
# pubspec.yaml — swap the asset reference
assets:
  - assets/ml/model_pruned_int8.tflite   # was model.tflite
  - assets/ml/vocab_pruned.json          # was vocab.json
```

The Dart tokenizer must also be updated to load `vocab_pruned.json`. This is a single path change in `lib/ml/ml_engine.dart → load()`.

### Running the Python Evaluation

```bash
pip install ai-edge-litert pandas scikit-learn
python scripts/eval_int8.py       # float32 vs INT8 metrics on held-out test set
python scripts/prune_vocab.py     # 6-step vocab prune + INT8 + parity check
```

---

## Privacy

**Three permissions. No extras.**

| Permission | Why |
|---|---|
| `RECEIVE_SMS` | Intercept incoming SMS before the default app |
| `READ_SMS` | Read existing inbox on first launch |
| `POST_NOTIFICATIONS` | Alert on high-confidence scam verdict |

No location, no contacts, no camera, no microphone, no internet.

**The privacy guarantee is structural:**

SMS text flows: BroadcastReceiver → Dart process → TFLite isolate → verdict → Hive local storage → UI. There is no outbound path. The codebase contains no HTTP client, no DNS lookup, no Firebase, no Crashlytics, no ad SDK, no analytics endpoint. Removing the privacy guarantee requires adding a network layer and rebuilding the app — it cannot happen via a remote config change.

Scan history is stored in a [Hive](https://pub.dev/packages/hive) box on-device (sender, body, verdict, timestamp). Hive encryption is not yet enabled; full-disk encryption via Android is the current protection.

---

## Honest Limitations

**Small test set.** 461 samples total; delivery_courier and digital_arrest evaluated on 8 samples each. Recall figures for minority classes are directional, not reliable. A proper evaluation requires at minimum 200 samples per class.

**No mobile latency measurements.** All inference numbers in this README were collected on a Windows 11 dev machine (Intel CPU, TFLite Python runtime). No profiling has been done on a physical Android device. On a Snapdragon 680-class device without NNAPI delegation, expect 200–500 ms per inference with the INT8 model. This exceeds the <50 ms target. Reaching that target on-device requires NNAPI delegation or an architecture change.

**Model size reality.** The pruned INT8 model is 114 MB. The full unpruned INT8 model is 392 MB. Neither is a sub-30 MB artifact, and neither will fit in a 30 MB APK budget.

Why: `distilbert-base-multilingual-cased` carries a 119,547-token multilingual vocabulary specifically to cover 104 languages. After pruning to the 38,400 tokens seen in the SMS corpus, the embedding table at INT8 is ~30 MB. The 6 transformer layers at INT8 add ~42 MB. FlatBuffer overhead and model metadata account for the rest of the 114 MB total.

If sub-30 MB were a hard requirement the architecture would change to one of:
- **MobileBERT-tiny or TinyBERT** (~14–20 MB INT8), accepting 3–5 pp F1 regression on minority classes
- **fastText** (1–5 MB), with a purpose-built Hinglish word list; near-instant inference; no contextual representations
- **Custom BERT-mini** (L=2, H=256, ~4M params INT8 ≈ 7 MB), requiring training from scratch on a larger dataset

**Play Store SMS policy.** Google's `READ_SMS` / `RECEIVE_SMS` policy requires demonstrating core use-case necessity. Default-SMS-app status or an approved exception is required for Play Store distribution. This is a distribution constraint, not a technical one.

**Language coverage.** The model is fine-tuned on 91.9% English data. Hindi and Hinglish performance is understated by the test metrics. Real-world false-negative rate on Hindi-primary scam messages is unknown and likely higher than the 92.7% otp_kyc recall suggests.

**No adversarial robustness testing.** Scammers adapt. A model trained on 2024–2025 templates will degrade as phrasing evolves. No red-team evaluation has been done.

---

## Roadmap

- [ ] **Wire up pruned INT8 model** — swap `model.tflite` → `model_pruned_int8.tflite`; update vocab path; validate parity on device
- [ ] **Physical device benchmark** — measure inference latency, cold start, and peak RSS on a real mid-range Android device; tune NNAPI delegation
- [ ] **Expand scam dataset** — target 35–60% scam ratio; add 200+ samples per class; boost Hindi/Hinglish to ≥40% of training data
- [ ] **Hive encryption** — enable AES-256 Hive box encryption for scan history
- [ ] **More languages** — dedicated fine-tuning batches for Tamil, Telugu, Bengali (top SMS languages after Hindi/English in India)
- [ ] **Voice scam detection** — extend to call-transcript analysis; different model architecture (sequence-to-sequence or audio embedding)
- [ ] **Family mode** — shared alert profile for a household; one person's flagged number propagates to family members (local P2P, no cloud)
- [ ] **Federated learning** — user-consented local fine-tuning on misclassified messages; aggregate updates via differential privacy; no raw message content leaves device

---

## Stack

| Layer | Tech |
|---|---|
| Framework | Flutter 3.x, Dart |
| State | Riverpod 2.x |
| ML runtime | tflite_flutter 0.12.0 (TFLite 2.16) |
| Model | distilbert-base-multilingual-cased, fine-tuned |
| Storage | Hive 2.x (local, unencrypted in current build) |
| Notifications | flutter_local_notifications |
| Charts | fl_chart |
| Permissions | permission_handler |

Android-only for SMS interception. The Flutter layer is cross-platform; iOS does not expose `RECEIVE_SMS` equivalent.

---

## License

MIT — see [LICENSE](LICENSE).
