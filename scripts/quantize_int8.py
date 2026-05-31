#!/usr/bin/env python3
"""
INT8 post-training quantization for Defendra distilbert-base-multilingual-cased TFLite model.

Recipe: static_wi8_ai8 — weights INT8 (channelwise), activations INT8 (per-tensor).
Calibration: 200 samples, scam classes (delivery, digital_arrest, otpKyc) oversampled 4:1 vs safe.

Usage:
    py -3 scripts/quantize_int8.py
"""

import io
import json
import re
import sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
import numpy as np
import pandas as pd
from pathlib import Path

from ai_edge_quantizer import quantizer
from ai_edge_quantizer import recipe as qrecipe

ROOT = Path(__file__).resolve().parent.parent
MODEL_PATH  = ROOT / 'assets/ml/model.tflite'
VOCAB_PATH  = ROOT / 'assets/ml/vocab.json'
DATASET_PATH = ROOT / 'data/defendra_dataset.csv'
OUTPUT_PATH = ROOT / 'assets/ml/model_int8.tflite'

MAX_SEQ_LEN = 96
CLS_ID, SEP_ID, PAD_ID, UNK_ID = 101, 102, 0, 100

# ---------------------------------------------------------------------------
# Tokenizer — mirrors DartTokenizer exactly:
#   distilbert-base-multilingual-cased, do_lower_case=False, strip_accents=False
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


def _basic_tokenize(text: str) -> list[str]:
    # CJK wrap
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


def _wordpiece(word: str, vocab: dict) -> list[int]:
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


def tokenize(text: str, vocab: dict) -> tuple[np.ndarray, np.ndarray]:
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

    # Model input dtype is int64 (confirmed via get_input_details)
    return (
        np.array([ids],  dtype=np.int64),
        np.array([mask], dtype=np.int64),
    )


# ---------------------------------------------------------------------------
# Representative dataset — 200 samples, scam classes oversampled
# ---------------------------------------------------------------------------

_OTP_KYC_CATS = {
    'otp', 'kyc', 'bank_impersonation', 'refund',
    'job', 'lottery', 'electricity', 'loan', 'generic_spam',
}


def _ml_class(row) -> int:
    if row['label'] == 0:
        return 0
    cat = str(row.get('category', ''))
    if cat == 'delivery':
        return 2
    if cat == 'digital_arrest':
        return 3
    return 1  # otp_kyc bucket


def build_rep_texts(df: pd.DataFrame, n_per_class: int = 50) -> list[str]:
    df = df.copy()
    df['ml_class'] = df.apply(_ml_class, axis=1)

    buckets = []
    for cls_id in range(4):
        rows = df[df['ml_class'] == cls_id]
        replace = len(rows) < n_per_class
        if replace:
            print(f'  class {cls_id}: {len(rows)} rows -> oversampling with replacement to {n_per_class}')
        sampled = rows.sample(n=n_per_class, replace=replace, random_state=42)
        buckets.append(sampled)

    combined = pd.concat(buckets).sample(frac=1, random_state=42).reset_index(drop=True)
    dist = combined['ml_class'].value_counts().sort_index().to_dict()
    print(f'  Final 200-sample distribution: {dist}')
    return combined['text'].tolist()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print('=== Defendra INT8 PTQ ===\n')

    print('Loading vocab...')
    vocab = json.loads(VOCAB_PATH.read_text(encoding='utf-8'))
    print(f'  vocab size: {len(vocab):,}')

    print('Loading dataset...')
    df = pd.read_csv(DATASET_PATH)
    print(f'  rows: {len(df):,}  label dist: {df["label"].value_counts().to_dict()}')

    print('Building representative dataset (50 per class)...')
    texts = build_rep_texts(df, n_per_class=50)

    # Quick sanity check
    ids, mask = tokenize(texts[0], vocab)
    real_tokens = int(mask.sum())
    print(f'  Tokenize smoke test: "{texts[0][:60]}..." -> {real_tokens} real tokens')

    float_bytes = MODEL_PATH.stat().st_size
    print(f'\nFloat32 model: {float_bytes / 1024**2:.1f} MB  ({MODEL_PATH.name})')

    # -----------------------------------------------------------------------
    # Quantize: dynamic_wi8_afp32 — weights INT8 (channelwise), activations fp32.
    # Chosen over static_wi8_ai8 because tflite_flutter 0.12.0 (TFLite 2.16)
    # cannot consume int8 output tensors without explicit dequant in Dart, and
    # may encounter unsupported op versions from newer ai_edge_quantizer schema.
    # For BERT, >99% of bytes are weight matrices → size reduction is identical.
    # -----------------------------------------------------------------------
    print('\n[1/2] Loading model into ai_edge_quantizer (dynamic_wi8_afp32)...')
    qt = quantizer.Quantizer(
        float_model=str(MODEL_PATH),
        quantization_recipe=qrecipe.dynamic_wi8_afp32(),
    )
    print(f'  needs_calibration: {qt.need_calibration}')

    print('[2/2] Quantizing (no calibration pass needed for dynamic recipe)...')
    qresult = qt.quantize(
        serialize_to_path=str(OUTPUT_PATH),
    )

    int8_bytes = OUTPUT_PATH.stat().st_size
    ratio = float_bytes / int8_bytes

    print('\n' + '=' * 52)
    print('RESULT')
    print(f'  Float32 : {float_bytes / 1024**2:7.1f} MB')
    print(f'  INT8    : {int8_bytes  / 1024**2:7.1f} MB')
    print(f'  Ratio   : {ratio:.2f}x compression')
    print(f'  Saved → {OUTPUT_PATH.relative_to(ROOT)}')
    print('=' * 52)

    # Projection vs resume claim
    print(f'\n  Resume claims 25 MB.  Actual INT8: {int8_bytes/1024**2:.0f} MB.')
    if int8_bytes / 1024**2 > 30:
        print('  → 25 MB NOT achievable via PTQ alone. Architecture change required.')


if __name__ == '__main__':
    main()
