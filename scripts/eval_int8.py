#!/usr/bin/env python3
"""
Full held-out evaluation: float32 vs INT8 TFLite models.
80/20 stratified split (seed=42) on defendra_dataset.csv.
Reports per-class recall, FPR, model sizes, and median inference latency.
"""

import io
import json
import os
import re
import sys
import time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

import numpy as np
import pandas as pd
from pathlib import Path
from sklearn.model_selection import train_test_split
from sklearn.metrics import confusion_matrix
from ai_edge_litert.interpreter import Interpreter

ROOT = Path(__file__).resolve().parent.parent
FLOAT32_PATH = ROOT / 'assets/ml/model_float32.tflite'
INT8_PATH    = ROOT / 'assets/ml/model_int8.tflite'
VOCAB_PATH   = ROOT / 'assets/ml/vocab.json'
DATASET_PATH = ROOT / 'data/defendra_dataset.csv'

MAX_SEQ_LEN = 96
CLS_ID, SEP_ID, PAD_ID, UNK_ID = 101, 102, 0, 100

CLASS_NAMES = ['safe', 'otp_kyc', 'delivery_courier', 'digital_arrest']

# ---------------------------------------------------------------------------
# Tokenizer — mirrors DartTokenizer and quantize_int8.py exactly
# ---------------------------------------------------------------------------

_URL_RE   = re.compile(r'https?://\S+|www\.\S+', re.I)
_PHONE_RE = re.compile(r'[\+\(]?[0-9][\d\s\-\(\)]{8,}[0-9]')
_AMT_RE   = re.compile(r'₹\s*[\d,]+(?:\.\d+)?|(?:rs|inr)\.?\s*[\d,]+(?:\.\d+)?', re.I)
_OTP_RE   = re.compile(r'\b\d{4,8}\b')
_PLACEHOLDER_RE = re.compile(r'^<\w+>$')


def _preprocess(text: str) -> str:
    text = _URL_RE.sub('<url>', text)
    text = _PHONE_RE.sub('<phone>', text)
    text = _AMT_RE.sub('<amount>', text)
    text = _OTP_RE.sub('<otp>', text)
    return text


def _is_cjk(cp: int) -> bool:
    return (
        0x4E00 <= cp <= 0x9FFF or 0x3400 <= cp <= 0x4DBF or
        0x20000 <= cp <= 0x2A6DF or 0xF900 <= cp <= 0xFAFF or
        0x2F800 <= cp <= 0x2FA1F
    )


def _basic_tokenize(text: str) -> list:
    chars = []
    for ch in text:
        chars.extend([' ', ch, ' '] if _is_cjk(ord(ch)) else [ch])
    text = ''.join(chars)

    tokens = []
    for raw in text.strip().split():
        if _PLACEHOLDER_RE.match(raw):
            tokens.append(raw)
            continue
        i, start, sub = 0, 0, []
        while i < len(raw):
            ch = raw[i]
            if ch.isprintable() and not (ch.isalnum() or ch.isspace()):
                if start < i:
                    sub.append(raw[start:i])
                sub.append(ch)
                start = i + 1
            i += 1
        if start < len(raw):
            sub.append(raw[start:])
        tokens.extend(sub)
    return [t for t in tokens if t]


def _wordpiece(word: str, vocab: dict) -> list:
    if len(word) > 100:
        return [UNK_ID]
    ids, start = [], 0
    while start < len(word):
        end = len(word)
        found_id = None
        while start < end:
            lookup = word[start:end] if start == 0 else '##' + word[start:end]
            if lookup in vocab:
                found_id = vocab[lookup]
                break
            end -= 1
        if found_id is None:
            return [UNK_ID]
        ids.append(found_id)
        start = end
    return ids


def tokenize(text: str, vocab: dict):
    text = _preprocess(text)
    words = _basic_tokenize(text)

    ids = [CLS_ID]
    for word in words:
        ids.extend(_wordpiece(word, vocab))
        if len(ids) >= MAX_SEQ_LEN - 1:
            break

    ids = ids[:MAX_SEQ_LEN - 1] + [SEP_ID]
    mask = [1] * len(ids) + [0] * (MAX_SEQ_LEN - len(ids))
    ids  = ids              + [PAD_ID] * (MAX_SEQ_LEN - len(ids))

    return (
        np.array([ids],  dtype=np.int64),
        np.array([mask], dtype=np.int64),
    )


# ---------------------------------------------------------------------------
# Class label mapping — mirrors quantize_int8.py
# ---------------------------------------------------------------------------

_OTP_KYC_CATS = {
    'otp', 'kyc', 'bank_impersonation', 'refund',
    'job', 'lottery', 'electricity', 'loan', 'generic_spam',
}


def ml_class(row) -> int:
    if int(row['label']) == 0:
        return 0
    cat = str(row.get('category', ''))
    if cat == 'delivery':
        return 2
    if cat == 'digital_arrest':
        return 3
    return 1


# ---------------------------------------------------------------------------
# Inference runner
# ---------------------------------------------------------------------------

def load_interpreter(model_path: Path) -> Interpreter:
    interp = Interpreter(model_path=str(model_path))
    interp.allocate_tensors()
    return interp


def run_inference(interp: Interpreter, input_ids: np.ndarray, attention_mask: np.ndarray) -> np.ndarray:
    in_details = interp.get_input_details()
    out_details = interp.get_output_details()

    for det in in_details:
        name = det['name'].lower()
        if 'attention' in name or 'mask' in name:
            interp.set_tensor(det['index'], attention_mask)
        else:
            interp.set_tensor(det['index'], input_ids)

    interp.invoke()
    return interp.get_tensor(out_details[0]['index'])[0]  # shape (4,)


def evaluate(model_path: Path, texts: list, labels: list, vocab: dict, warmup: int = 5):
    interp = load_interpreter(model_path)
    preds = []
    latencies = []

    for i, (text, _) in enumerate(zip(texts, labels)):
        ids, mask = tokenize(text, vocab)
        t0 = time.perf_counter()
        logits = run_inference(interp, ids, mask)
        t1 = time.perf_counter()
        preds.append(int(np.argmax(logits)))
        if i >= warmup:
            latencies.append((t1 - t0) * 1000)

    return np.array(preds), np.array(labels), np.array(latencies)


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

def per_class_metrics(y_true: np.ndarray, y_pred: np.ndarray, n_classes: int):
    """Returns (recall, fpr) per class."""
    cm = confusion_matrix(y_true, y_pred, labels=list(range(n_classes)))
    recalls, fprs = [], []
    for c in range(n_classes):
        tp = cm[c, c]
        fn = cm[c, :].sum() - tp
        fp = cm[:, c].sum() - tp
        tn = cm.sum() - tp - fn - fp

        recall = tp / (tp + fn) if (tp + fn) > 0 else float('nan')
        fpr    = fp / (fp + tn) if (fp + tn) > 0 else float('nan')
        recalls.append(recall)
        fprs.append(fpr)
    return recalls, fprs, cm


def print_metrics_table(label: str, recalls: list, fprs: list, cm: np.ndarray, latencies: np.ndarray):
    print(f'\n{"=" * 60}')
    print(f'  {label}')
    print(f'{"=" * 60}')
    print(f'  {"Class":<22} {"Recall":>8}  {"FPR":>8}  {"Support":>8}')
    print(f'  {"-" * 52}')
    for c, name in enumerate(CLASS_NAMES):
        support = int(cm[c, :].sum())
        r = recalls[c]
        f = fprs[c]
        r_str = f'{r * 100:.1f}%' if not np.isnan(r) else '   N/A'
        f_str = f'{f * 100:.1f}%' if not np.isnan(f) else '   N/A'
        print(f'  {name:<22} {r_str:>8}  {f_str:>8}  {support:>8}')
    print(f'\n  Median latency (CPU, excl. first {5} warmup): {np.median(latencies):.1f} ms')
    print(f'  p95 latency: {np.percentile(latencies, 95):.1f} ms')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print('=== Defendra INT8 Evaluation ===\n')

    print('Loading vocab...')
    vocab = json.loads(VOCAB_PATH.read_text(encoding='utf-8'))

    print('Loading dataset...')
    df = pd.read_csv(DATASET_PATH)
    df['ml_class'] = df.apply(ml_class, axis=1)

    print(f'  Total rows: {len(df):,}')
    print(f'  ML class distribution:')
    for c, name in enumerate(CLASS_NAMES):
        cnt = int((df['ml_class'] == c).sum())
        print(f'    class {c} ({name}): {cnt}')

    # Stratified 80/20 split on ml_class
    df_train, df_test = train_test_split(
        df, test_size=0.20, stratify=df['ml_class'], random_state=42
    )
    print(f'\n  Train: {len(df_train):,}  |  Test: {len(df_test):,}')
    print('  Test class distribution:')
    for c, name in enumerate(CLASS_NAMES):
        cnt = int((df_test['ml_class'] == c).sum())
        print(f'    class {c} ({name}): {cnt}')

    texts  = df_test['text'].tolist()
    labels = df_test['ml_class'].tolist()

    # ---- Float32 ----
    float_mb = FLOAT32_PATH.stat().st_size / 1024**2
    print(f'\n[Float32] {float_mb:.2f} MB — running inference on {len(texts)} test samples...')
    f32_preds, f32_labels, f32_lat = evaluate(FLOAT32_PATH, texts, labels, vocab)
    f32_recalls, f32_fprs, f32_cm = per_class_metrics(f32_labels, f32_preds, 4)
    f32_acc = (f32_preds == f32_labels).mean()
    print_metrics_table(f'Float32  ({float_mb:.2f} MB)', f32_recalls, f32_fprs, f32_cm, f32_lat)

    # ---- INT8 ----
    int8_mb = INT8_PATH.stat().st_size / 1024**2
    print(f'\n[INT8] {int8_mb:.2f} MB — running inference on {len(texts)} test samples...')
    i8_preds, i8_labels, i8_lat = evaluate(INT8_PATH, texts, labels, vocab)
    i8_recalls, i8_fprs, i8_cm = per_class_metrics(i8_labels, i8_preds, 4)
    i8_acc = (i8_preds == i8_labels).mean()
    print_metrics_table(f'INT8     ({int8_mb:.2f} MB)', i8_recalls, i8_fprs, i8_cm, i8_lat)

    # ---- Delta check (within 3 pp) ----
    print(f'\n{"=" * 60}')
    print('  DELTA: Float32 → INT8  (pass = within 3 percentage points)')
    print(f'  {"Class":<22} {"ΔRecall":>9}  {"ΔFPR":>9}  {"Pass?":>6}')
    print(f'  {"-" * 52}')
    all_pass = True
    for c, name in enumerate(CLASS_NAMES):
        dr = (i8_recalls[c] - f32_recalls[c]) * 100
        df_ = (i8_fprs[c]    - f32_fprs[c])    * 100
        if np.isnan(dr) or np.isnan(df_):
            status = ' N/A'
        else:
            ok = abs(dr) <= 3.0 and abs(df_) <= 3.0
            status = '  OK' if ok else ' FAIL'
            if not ok:
                all_pass = False
        dr_str  = f'{dr:+.1f}pp' if not np.isnan(dr)  else '   N/A'
        df_str  = f'{df_:+.1f}pp' if not np.isnan(df_) else '   N/A'
        print(f'  {name:<22} {dr_str:>9}  {df_str:>9}  {status}')

    verdict = 'PASS — all classes within 3 pp' if all_pass else 'FAIL — one or more classes exceed 3 pp'
    print(f'\n  Overall verdict: {verdict}')
    print(f'  Float32 accuracy: {f32_acc * 100:.2f}%')
    print(f'  INT8    accuracy: {i8_acc  * 100:.2f}%')

    # ---- Resume one-liner ----
    device_name = 'Windows 11 CPU (dev machine — not target mobile)'
    med_ms = np.median(i8_lat)
    size_mb = int8_mb

    print(f'\n{"=" * 60}')
    print('  TRUTHFUL RESUME / README ONE-LINER:')
    print(f'{"=" * 60}')
    print(f'''
Fine-tuned distilbert-base-multilingual-cased (134M params),
dynamic INT8-quantized (weights-only, embeddings fp32) to {size_mb:.0f} MB,
{med_ms:.0f}ms median inference on {device_name};
fully on-device — no cloud calls.

NOTE: The 392 MB size reflects that the multilingual embedding table
(119k vocab × 768 dims) remains fp32. True full-INT8 would reach ~134 MB
but requires embedding quantization (not yet implemented).
Defensible resume claim: "{size_mb:.0f} MB INT8-quantized model, fully on-device."
''')


if __name__ == '__main__':
    main()
