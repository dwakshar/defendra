"""
build_dataset.py — Defendra training-data builder
Pandas + stdlib only. Runnable in Google Colab or locally.

Usage:
    python build_dataset.py

Outputs:
    defendra_dataset.csv   — unified, normalized, deduplicated dataset
    defendra_stats.md      — class / category / lang distribution summary
"""

# ============================================================
# CONFIG — edit these paths before running
# ============================================================

# Seed examples (already normalized; re-normalization is idempotent)
SEEDS_CSV = "data/seed_sms.csv"

# Your manual collection CSVs (same unified schema as seeds).
# Add as many paths as you have; leave empty list [] if none yet.
MANUAL_CSVS = [
    "data/collection_template.csv",
    # "data/my_reddit_batch.csv",
]

# Public / downloaded datasets.
# Each entry is a dict describing how to map it to the unified schema.
# See the PUBLIC_SOURCES list below for the format.
PUBLIC_CSVS = [
    {
        "path": "data/spam.csv",
        "source_tag": "uci_spam",     # value written to the 'source' column
        "encoding": "latin-1",        # UCI file uses latin-1
        # Column renames: {original_col: unified_col}
        # For columns that need value-mapping, handle in transform_fn below.
        "col_map": {"v2": "text"},
        # Optional callable(df) -> df applied after col_map.
        # Use it to map labels, fill categories, fill lang, etc.
        "transform_fn": "uci_transform",
    },
    # Add more public datasets here following the same pattern.
    # Example for a Kaggle dataset:
    # {
    #     "path": "data/kaggle_fraud_sms.csv",
    #     "source_tag": "kaggle_fraud",
    #     "encoding": "utf-8",
    #     "col_map": {"message": "text", "class": "label"},
    #     "transform_fn": "kaggle_fraud_transform",
    # },
]

# Output file paths
OUTPUT_CSV  = "data/defendra_dataset.csv"
OUTPUT_STATS_MD = "data/defendra_stats.md"

# ============================================================
# END CONFIG
# ============================================================

import os
import re
import sys
from datetime import datetime

import pandas as pd

# -----------------------------------------------------------
# Unified schema
# -----------------------------------------------------------
SCHEMA_COLS = ["text", "label", "category", "lang", "source"]


# -----------------------------------------------------------
# Normalization pipeline (mirrors normalization_rules.md v1.0)
# Order of operations matters — do not reorder.
# -----------------------------------------------------------

# 1. <url>
_URL = re.compile(
    r"(?:https?://|www\.)[^\s<>\"']+"
    r"|(?:bit\.ly|tinyurl\.com|t\.co|goo\.gl|short\.gy|rb\.gy|ow\.ly|is\.gd|cutt\.ly|tiny\.one)[/\w\-?=&#%]+",
    re.IGNORECASE,
)

# 2. <email>
_EMAIL = re.compile(
    r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}",
    re.IGNORECASE,
)

# 3. <phone> — Indian mobile numbers (6-9 prefix, exactly 10 digits)
_PHONE = re.compile(
    r"(?:\+91[\s\-]?|0091[\s\-]?|91[\s\-]?)?(?<![0-9])[6-9][0-9]{9}(?![0-9])",
    re.IGNORECASE,
)

# 4. <amount> — currency-marked monetary values
_AMOUNT = re.compile(
    r"(?:₹|Rs\.?|INR)\s*[0-9,]+(?:\.[0-9]{1,2})?"
    r"|[0-9,]+(?:\.[0-9]{1,2})?\s*(?:₹|Rs\.?|INR|lakh|crore|thousand|k\b)",
    re.IGNORECASE,
)

# 5. <acct> — 9–18 digit strings (applied after phone/amount)
_ACCT = re.compile(
    r"(?<![0-9])[0-9]{9,18}(?![0-9])",
    re.IGNORECASE,
)

# 6. <otp> — residual 4–6 digit codes (after acct strips longer ones)
_OTP = re.compile(
    r"(?<![0-9])[0-9]{4,6}(?![0-9])",
    re.IGNORECASE,
)

# 7. <date> — common date formats
_DATE = re.compile(
    r"(?:\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}"
    r"|\d{1,2}\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may"
    r"|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{2,4})",
    re.IGNORECASE,
)

# 8. <name> — salutation + capitalized name
_NAME = re.compile(
    r"(Dear|Hi|Hello|Namaskar|Namaste)\s+([A-Z][a-zA-Z]{1,20}(?:\s+[A-Z][a-zA-Z]{1,20})?)",
    re.IGNORECASE,
)

# Ordered list used by normalize()
_REPLACEMENTS = [
    (_URL,    "<url>"),
    (_EMAIL,  "<email>"),
    (_PHONE,  "<phone>"),
    (_AMOUNT, "<amount>"),
    (_ACCT,   "<acct>"),
    (_OTP,    "<otp>"),
    (_DATE,   "<date>"),
    (_NAME,   "<name>"),
]


def normalize(raw: str) -> str:
    """
    Apply the full Defendra normalization pipeline to a single text string.
    Produces the canonical form used for deduplication and model training.
    Devanagari characters pass through unchanged.
    """
    if not isinstance(raw, str):
        return ""

    text = raw

    # Steps 1–8: placeholder substitution in defined order
    for pattern, token in _REPLACEMENTS:
        text = pattern.sub(token, text)

    # Step 9: global lowercase (placeholder tokens are already lowercase)
    text = text.lower()

    # Step 10: whitespace normalization
    text = re.sub(r"[\r\n]+", " ", text)
    text = re.sub(r"[\s\u00A0\u200B\u200C\u200D]+", " ", text).strip()

    return text


# -----------------------------------------------------------
# Public-dataset transform functions
# Add one function per public dataset; reference by string name in CONFIG.
# Each receives a DataFrame with cols already renamed per col_map
# and must return a DataFrame with all SCHEMA_COLS present.
# -----------------------------------------------------------

def uci_transform(df: pd.DataFrame) -> pd.DataFrame:
    """
    Maps the UCI SMS Spam Collection (columns v1=ham/spam, v2=text)
    into the unified schema.
    """
    # v1 → binary label
    df["label"] = df["v1"].map({"ham": 0, "spam": 1})

    # Assign a coarse category so the field is never empty.
    # Real category tagging would require a second-pass classifier;
    # for now we use conservative defaults.
    df["category"] = df["label"].map({0: "safe_generic", 1: "generic_spam"})

    # All UCI messages are English
    df["lang"] = "en"

    # Drop the original v1 column (already mapped)
    df = df.drop(columns=["v1"], errors="ignore")

    return df


# Register transform functions by name so CONFIG strings resolve at runtime.
_TRANSFORM_REGISTRY = {
    "uci_transform": uci_transform,
    # "kaggle_fraud_transform": kaggle_fraud_transform,
}


# -----------------------------------------------------------
# Loaders
# -----------------------------------------------------------

def load_native(path: str) -> pd.DataFrame:
    """
    Load a CSV that already follows the unified schema (seeds, manual).
    Drops rows where 'text' is missing or blank.
    """
    df = pd.read_csv(path, dtype=str)
    # Keep only recognized schema columns; ignore extras silently
    df = df[[c for c in SCHEMA_COLS if c in df.columns]]
    df = df.dropna(subset=["text"])
    df = df[df["text"].str.strip() != ""]
    return df


def load_public(cfg: dict) -> pd.DataFrame:
    """
    Load a public/external dataset using the config dict.
    Applies col_map rename, then the named transform function.
    """
    path        = cfg["path"]
    source_tag  = cfg["source_tag"]
    encoding    = cfg.get("encoding", "utf-8")
    col_map     = cfg.get("col_map", {})
    transform   = _TRANSFORM_REGISTRY.get(cfg.get("transform_fn", ""))

    df = pd.read_csv(path, encoding=encoding, dtype=str)

    # Rename columns to unified names
    df = df.rename(columns=col_map)

    # Apply dataset-specific transformation
    if transform:
        df = transform(df)

    # Stamp the source tag
    df["source"] = source_tag

    # Keep only schema columns; fill any missing schema columns with ""
    for col in SCHEMA_COLS:
        if col not in df.columns:
            df[col] = ""
    df = df[SCHEMA_COLS]

    df = df.dropna(subset=["text"])
    df = df[df["text"].str.strip() != ""]

    return df


# -----------------------------------------------------------
# Deduplication
# -----------------------------------------------------------

def deduplicate(df: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    """
    Two-pass deduplication:
      Pass 1 — exact raw-text duplicates (keeps first occurrence).
      Pass 2 — near-duplicates: rows whose *normalized* text is identical
                after the full normalization pipeline (keeps first).

    Returns the cleaned DataFrame and a stats dict for reporting.
    """
    before = len(df)

    # Pass 1: exact match on raw text
    df = df.drop_duplicates(subset=["text"], keep="first")
    after_exact = len(df)
    exact_removed = before - after_exact

    # Pass 2: compute normalized text, then deduplicate on that
    df = df.copy()
    df["_norm_text"] = df["text"].apply(normalize)
    df = df.drop_duplicates(subset=["_norm_text"], keep="first")
    after_near = len(df)
    near_removed = after_exact - after_near

    # Replace raw text with the normalized version for training
    df["text"] = df["_norm_text"]
    df = df.drop(columns=["_norm_text"])

    stats = {
        "before":        before,
        "exact_removed": exact_removed,
        "near_removed":  near_removed,
        "after":         after_near,
    }
    return df.reset_index(drop=True), stats


# -----------------------------------------------------------
# Stats helpers
# -----------------------------------------------------------

def print_distribution(series: pd.Series, title: str) -> str:
    """
    Pretty-print a value_counts table and return the markdown version.
    """
    counts  = series.value_counts(dropna=False)
    total   = len(series)
    lines   = [f"\n### {title}", f"{'Value':<30} {'Count':>7} {'%':>7}", "-" * 46]
    for val, cnt in counts.items():
        pct = 100 * cnt / total if total else 0
        lines.append(f"{str(val):<30} {cnt:>7} {pct:>6.1f}%")
    block = "\n".join(lines)
    print(block)
    return block


def build_stats_markdown(df: pd.DataFrame, dedup_stats: dict, source_counts: dict) -> str:
    """Build the full stats summary markdown string."""
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# Defendra Dataset — Build Stats",
        f"_Generated: {ts}_",
        "",
        "## Source row counts (before dedup)",
    ]
    for src, cnt in source_counts.items():
        lines.append(f"- **{src}**: {cnt:,} rows")

    lines += [
        "",
        "## Deduplication",
        f"- Rows before dedup : **{dedup_stats['before']:,}**",
        f"- Exact duplicates removed : **{dedup_stats['exact_removed']:,}**",
        f"- Near-duplicates removed (norm-text match) : **{dedup_stats['near_removed']:,}**",
        f"- Rows after dedup : **{dedup_stats['after']:,}**",
        "",
    ]

    def _dist_block(series, title):
        counts = series.value_counts(dropna=False)
        total  = len(series)
        rows   = [f"### {title}", f"| Value | Count | % |", "| --- | --- | --- |"]
        for val, cnt in counts.items():
            pct = 100 * cnt / total if total else 0
            rows.append(f"| {val} | {cnt:,} | {pct:.1f}% |")
        return "\n".join(rows)

    lines.append(_dist_block(df["label"],    "Class Balance (label)"))
    lines.append("")
    lines.append(_dist_block(df["category"], "Category Distribution"))
    lines.append("")
    lines.append(_dist_block(df["lang"],     "Language Distribution"))
    lines.append("")
    lines.append(_dist_block(df["source"],   "Source Distribution"))

    return "\n".join(lines)


# -----------------------------------------------------------
# Main
# -----------------------------------------------------------

def main():
    frames = []
    source_counts = {}

    # ---- Load seed examples ----
    if os.path.exists(SEEDS_CSV):
        df_seeds = load_native(SEEDS_CSV)
        print(f"[seeds]   {len(df_seeds):>5} rows  <- {SEEDS_CSV}")
        source_counts["seeds"] = len(df_seeds)
        frames.append(df_seeds)
    else:
        print(f"[WARN] Seeds file not found: {SEEDS_CSV}", file=sys.stderr)

    # ---- Load manual collections ----
    for path in MANUAL_CSVS:
        if not os.path.exists(path):
            print(f"[WARN] Manual CSV not found, skipping: {path}", file=sys.stderr)
            continue
        df_m = load_native(path)
        print(f"[manual]  {len(df_m):>5} rows  <- {path}")
        source_counts[f"manual:{os.path.basename(path)}"] = len(df_m)
        frames.append(df_m)

    # ---- Load public datasets ----
    for cfg in PUBLIC_CSVS:
        path = cfg["path"]
        if not os.path.exists(path):
            print(f"[WARN] Public CSV not found, skipping: {path}", file=sys.stderr)
            continue
        df_p = load_public(cfg)
        tag  = cfg["source_tag"]
        print(f"[public]  {len(df_p):>5} rows  <- {path}  (source={tag})")
        source_counts[tag] = len(df_p)
        frames.append(df_p)

    if not frames:
        print("ERROR: no data loaded. Check CONFIG paths.", file=sys.stderr)
        sys.exit(1)

    # ---- Combine ----
    df_all = pd.concat(frames, ignore_index=True)
    print(f"\n[combined] {len(df_all):,} rows before dedup")

    # ---- Normalize + deduplicate ----
    # normalize() is already called inside deduplicate() for near-dupe pass.
    # For native CSVs (seeds/manual) the text is pre-normalized but running
    # normalize() again is safe and idempotent — placeholders don't re-trigger.
    df_clean, dedup_stats = deduplicate(df_all)

    print(f"\n[dedup]  exact removed : {dedup_stats['exact_removed']:,}")
    print(f"[dedup]  near  removed : {dedup_stats['near_removed']:,}")
    print(f"[dedup]  final rows    : {dedup_stats['after']:,}")

    # ---- Ensure label is int ----
    df_clean["label"] = pd.to_numeric(df_clean["label"], errors="coerce").fillna(-1).astype(int)

    # ---- Print distributions ----
    print("\n" + "=" * 50)
    print_distribution(df_clean["label"],    "Class Balance (label  0=legit 1=fraud)")
    print_distribution(df_clean["category"], "Category Distribution")
    print_distribution(df_clean["lang"],     "Language Distribution")
    print_distribution(df_clean["source"],   "Source Distribution")

    # ---- Write output CSV ----
    df_clean[SCHEMA_COLS].to_csv(OUTPUT_CSV, index=False, encoding="utf-8")
    print(f"\n[output]  dataset  -> {OUTPUT_CSV}")

    # ---- Write stats markdown ----
    stats_md = build_stats_markdown(df_clean, dedup_stats, source_counts)
    with open(OUTPUT_STATS_MD, "w", encoding="utf-8") as f:
        f.write(stats_md)
    print(f"[output]  stats md  -> {OUTPUT_STATS_MD}")

    print("\nDone.")


if __name__ == "__main__":
    main()
