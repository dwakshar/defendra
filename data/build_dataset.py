"""
build_dataset.py — Defendra training-data builder
Pandas + stdlib only. Runnable in Google Colab or locally.

Usage:
    python build_dataset.py

Outputs:
    defendra_dataset.csv   — unified, normalized, deduplicated dataset
    defendra_stats.md      — class / category / lang distribution summary
    review_needed.csv      — kaggle_india rows flagged for manual audit
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

# Synthetic / augmented CSVs that already follow the unified schema.
# 'default_source' is used ONLY if the file's own 'source' column is
# missing or blank — existing values are preserved.
SYNTHETIC_CSVS = [
    {"path": "data/defendra_synthetic_dataset.csv",  "default_source": "synthetic"},
    {"path": "data/digital_arrest_synthetic.csv",    "default_source": "synthetic"},
    {"path": "data/kyc_synthetic.csv",               "default_source": "synthetic"},
    {"path": "data/otp_synthetic.csv",               "default_source": "synthetic"},
    {"path": "data/bank_impersonation_synthetic.csv","default_source": "synthetic"},
    {"path": "data/delivery_synthetic.csv",          "default_source": "synthetic"},
]

# Public / downloaded datasets.
# Each entry is a dict describing how to map it to the unified schema.
# UCI dropped: UK-English, promo-free, kills Hindi % and floods safe_generic.
# kaggle_india: Indian-English SMS, needs smart relabeling (spam ≠ scam).
PUBLIC_CSVS = [
    {
        "path": "data/spam_ham_india.csv",
        "source_tag": "kaggle_india",
        "encoding": "utf-8",
        # Msg → text; Label handled inside transform
        "col_map": {"Msg": "text"},
        "transform_fn": "kaggle_india_transform",
    },
    # Add more public datasets here following the same pattern.
]

# Output file paths
OUTPUT_CSV        = "data/defendra_dataset.csv"
OUTPUT_STATS_MD   = "data/defendra_stats.md"
OUTPUT_REVIEW_CSV = "data/review_needed.csv"   # rows flagged for manual check

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

# Scam categories (label=1) used for per-category health check
SCAM_CATEGORIES = {
    "otp", "kyc", "bank_impersonation", "delivery", "electricity",
    "digital_arrest", "job", "lottery", "loan", "refund", "generic_spam",
}


# -----------------------------------------------------------
# Metadata normalization — lang, label, category
# Applied defensively to EVERY source after load so future
# files with inconsistent values can't silently corrupt the schema.
# -----------------------------------------------------------

_LANG_MAP = {
    "english": "en",  "en": "en",  "eng": "en",
    "hindi":   "hi",  "hi": "hi",
    "hinglish": "hinglish", "hing": "hinglish",
}

_LABEL_TEXT_MAP = {
    "spam": 1, "scam": 1, "fraud": 1,
    "ham":  0, "safe": 0, "legit": 0,
}


def _normalize_lang_value(val: str) -> str:
    if not isinstance(val, str):
        return val
    key = val.strip().lower()
    mapped = _LANG_MAP.get(key)
    if mapped is None:
        print(f"[WARN] Unrecognized lang value: {val!r} — keeping as-is", file=sys.stderr)
        return val.strip()
    return mapped


def _normalize_label_value(val):
    """Coerce label to int. Handles numeric strings AND text like 'spam'/'ham'."""
    if pd.isna(val):
        return float("nan")
    s = str(val).strip()
    try:
        return int(float(s))
    except (ValueError, TypeError):
        return _LABEL_TEXT_MAP.get(s.lower(), float("nan"))


def normalize_metadata(df: pd.DataFrame) -> pd.DataFrame:
    """
    Defensive normalization of lang, label, and category applied to every
    source so schema violations from external files surface as warnings rather
    than silent corruption.
    """
    df = df.copy()

    if "lang" in df.columns:
        df["lang"] = df["lang"].apply(_normalize_lang_value)

    if "label" in df.columns:
        df["label"] = df["label"].apply(_normalize_label_value)

    if "category" in df.columns:
        df["category"] = df["category"].apply(
            lambda v: v.strip() if isinstance(v, str) else v
        )

    return df


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
# kaggle_india_transform helpers
# -----------------------------------------------------------

# Known legitimate Indian brands — presence → safe_promo (absent other fraud)
_LEGIT_BRANDS = re.compile(
    r"\b(airtel|wynk|vi\s+(?:app|movies|reward|customer|ka|ke)|vodafone\s+idea"
    r"|jio(?:mart|cinema|\b)|bsnl"
    r"|flipkart|amazon(?!\s+urgently)|myntra|ajio|nykaa|meesho"
    r"|shoppers.?stop|pantaloons|max\s+fashion|lifestyle\s+store|lenskart"
    r"|unlimited\s+fashion|reliance\s+smart|star\s+bazaar|jiomart|vishal\s+mega\s+mart"
    r"|dunzo|swiggy|zomato|bigbasket|bookmyshow|pvr\s+cinema"
    r"|paytm|phonepe|google\s+pay|gpay|cred\b"
    r"|hdfc\s+bank|icici\s+bank|axis\s+bank|kotak\s+bank|federal\s+bank"
    r"|yes\s+bank|state\s+bank|sbi\s+(?:bank|credit|offer)|indusind|idfc|rbl\s+bank"
    r"|bajaj\s+finance(?:\s+ltd)?|dhani\s+one|kreditbee|mpokket|olyv|smartcoin"
    r"|disney\+|hotstar|zee5|sonyliv|amazon\s+prime|voot|sun\s+nxt|erosnow|lionsgate"
    r"|cloudnine|vedix|redcliffe\s+labs"
    r"|digi\s+yatra|uidai|cert.in\s+goi|sancharsaathi|cybercrime\.gov"
    r"|r&b\s+(?:dubai|store)|style\s+union|shoppersstop\s+first\s+citizen"
    r"|samsung(?:\s+galaxy)?|epifi|fi\s+app|refyne)",
    re.IGNORECASE,
)

# Fraud: obfuscated text (0↔O substitution — always fake wallet/prize)
_FRAUD_OBFUSCATION = re.compile(
    r"(added\s+t0\s+your|credited\s+t0\s+your|b0nus\s+is\s+credited"
    r"|move\s+to\s+y0ur\s+bank|withdraw\s+n0w|oi1\.in|sr3\.in"
    r"|rs\.\s*\d+[,\s]*[0oO]{3}(?!\d))",  # e.g. Rs.38,OOO
    re.IGNORECASE,
)

# Fraud: winning / lottery / prize
_FRAUD_LOTTERY = re.compile(
    r"(winning\s+(parcel|fund|award|amount)"
    r"|apple\s+usa.*(?:arriv|thursday|deliver)"
    r"|your\s+winning\s+fund"
    r"|1\s*crore\s+rupees.*iphone"
    r"|iphone\s+15.*winning"
    r"|won\s+rs\.?\s*\d+\s*(lakh|crore)"
    r"|lucky\s+winner.*register"
    r"|congrat\w+.*won\s+(?:rs|a\s+\w+\s+car))",
    re.IGNORECASE,
)

# Fraud: win competition with per-reply charge
_FRAUD_COMPETITION = re.compile(
    r"(@rs\.?\s*5\s*/\s*ans|reply\s+a\s+or\s+b\s+@rs|win\s+(kia\s+sonet|bike\s+laptop))",
    re.IGNORECASE,
)

# Fraud: job scam — WhatsApp recruitment link is the smoking gun
_FRAUD_JOB = re.compile(
    r"(part.?time\s+job|urgently\s+recruit\w*|daily\s+salary\s+\d|earn\s+\d{3,}.*per\s+day"
    r"|earn\s+\d{3,}.*per\s+hour|click\s+joining.*wa\.me|joining.*wa\.me"
    r"|work\s+online.*earn\s+\d|online.*earn\s+\d+.*rubles)",
    re.IGNORECASE,
)

# Fraud: fake financial approval with known-bad shortlink domains
_FRAUD_DOMAINS = re.compile(
    r"(1kx\.in|gmg\.im|a0n\.in|p6x\.in|sr3\.in|oi1\.in|0kb\.in)",
    re.IGNORECASE,
)

# When fraud-domain + financial bait → bank_impersonation / loan
_FINANCIAL_BAIT = re.compile(
    r"(credit\s+card|loan\s+approv|credit\s+limit|bonus.*credit|prize|winning"
    r"|pre.?approv|insta\s+emi|cash\s+loan|rs\.?\s*\d{4,}.*withdraw)",
    re.IGNORECASE,
)

# Fraud: KYC / account-block urgency
_FRAUD_KYC = re.compile(
    r"(kyc.{0,25}(expir|pending|block|click|link|updat|complet)"
    r"|complete.{0,15}kyc.{0,15}(click|link|now)"
    r"|account.{0,20}block.{0,20}(verify|click|link)"
    r"|sim.{0,15}block.{0,20}(verify|click)"
    r"|number.{0,15}block.{0,20}(verify|click))",
    re.IGNORECASE,
)

# Fraud: government/law enforcement impersonation
_FRAUD_IMPERSONATION = re.compile(
    r"(digital\s+arrest|enforcement\s+directorate.*case"
    r"|cbi.*fraud.*case|income.tax.*arrest|cyber\s+crime.*warning.*click)",
    re.IGNORECASE,
)

# Borderline: real gambling apps — not illegal but predatory; flag for review
_GAMBLING = re.compile(
    r"(junglee\s+rummy|my\s*11\s*circle|rummy\s+(?:app|account|wallet|bonus)"
    r"|prize\s+pool.*entry\s+fees|play\s+free\s+rummy.*win\s+rs"
    r"|rs\.?\s*8850\s+welcome\s+bonus)",
    re.IGNORECASE,
)

# Borderline: financial promo without known brand — flag for review
_AMBIGUOUS_FINANCIAL = re.compile(
    r"(loan\s+approv|pre.?approv.*card|credit\s+limit\s+(?:up\s+to|ready)"
    r"|welcome\s+bonus.*deposit|rs\.?\s*\d{5,}\s*(?:bonus|reward|credited).*register)",
    re.IGNORECASE,
)

# Government advisory SMS — labeled spam in source, actually safe
_GOVT_ADVISORY = re.compile(
    r"(cert.in\s+goi|csk\.gov\.in|sancharsaathi\.gov|cybercrime\.gov"
    r"|pledge\.cvc\.nic\.in|uidai\s+recommends|digi\s+yatra\s+foundation"
    r"|dept\s+of\s+telecom|beware\s+of\s+fake\s+calls.*sancharsaathi"
    r"|trai\s+never\s+sends|do\s+not\s+(?:click|respond).*suspicious\s+link"
    r"|dot\s+toll.free|1800110420|cyber\s+swachhta\s+pakhwada)",
    re.IGNORECASE,
)

# Transactional ham signals
_TRANSACTIONAL = re.compile(
    r"(otp\s+(?:is|for|code)|one\s+time\s+password|\bawb\b.*pick"
    r"|order\s+(?:will\s+be\s+deliver|is\s+picked|deliver\w+\s+today)"
    r"|recharged.*enjoy|recharge.*success|balance.*(?:rs|inr)|(?:rs|inr).*balance"
    r"|account\s+credited|credited.*account|transaction\s+(?:done|complet)"
    r"|payment\s+received|booking\s+id|m.?ticket.*venue|seats?:.*[a-z]\d"
    r"|your\s+order\s+will\s+be|delivered\s+today|e.?receipt|e.?invoice"
    r"|wallet.*activated|kyc\s+complet.*success)",
    re.IGNORECASE,
)


def _classify_kaggle_spam(msg: str) -> tuple:
    """
    Returns (label, category, review_needed) for a kaggle_india spam row.

    Priority order:
      1. Obfuscation patterns            → fraud (refund)
      2. Lottery / fake prize signals    → fraud (lottery)
      3. Competition with reply charge   → fraud (lottery)
      4. Job scam with WA link           → fraud (job)
      5. Fraud domain + financial bait   → fraud (bank_impersonation/loan)
      6. KYC / account-block urgency     → fraud (kyc)
      7. Gov/law enforcement imperson.   → fraud (digital_arrest)
      8. Amazon/known-brand job scam     → fraud (job) — overrides brand check
      9. Govt advisory SMS               → safe_generic (mislabeled in source)
     10. Known legit brand               → safe_promo
     11. Gambling apps                   → safe_promo + review_needed=1
     12. Ambiguous financial promo       → safe_promo + review_needed=1
     13. Default                         → safe_promo + review_needed=1
    """
    # 1. Obfuscation
    if _FRAUD_OBFUSCATION.search(msg):
        return 1, "refund", 0

    # 2. Lottery / fake prize
    if _FRAUD_LOTTERY.search(msg):
        return 1, "lottery", 0

    # 3. Pay-per-reply competition
    if _FRAUD_COMPETITION.search(msg):
        return 1, "lottery", 0

    # 4. Job scam
    if _FRAUD_JOB.search(msg):
        return 1, "job", 0

    # 5. Fraud domain + financial bait
    if _FRAUD_DOMAINS.search(msg) and _FINANCIAL_BAIT.search(msg):
        # Distinguish loan vs bank_impersonation by content
        if re.search(r"\bloan\b", msg, re.IGNORECASE):
            return 1, "loan", 0
        return 1, "bank_impersonation", 0

    # 6. KYC / account-block
    if _FRAUD_KYC.search(msg):
        return 1, "kyc", 0

    # 7. Gov/law-enforcement impersonation
    if _FRAUD_IMPERSONATION.search(msg):
        return 1, "digital_arrest", 0

    # 8. Brand name used in job scam (e.g., "Amazon urgently recruiting")
    if re.search(r"(amazon|flipkart|google|tata)\s+urgently\s+recruit", msg, re.IGNORECASE):
        return 1, "job", 0
    if re.search(r"part.?time.*job.*wa\.me|earn.*day.*wa\.me", msg, re.IGNORECASE):
        return 1, "job", 0

    # 9. Govt advisory (mislabeled spam in source dataset)
    if _GOVT_ADVISORY.search(msg):
        return 0, "safe_generic", 0

    # 10. Known legit brand → safe_promo
    if _LEGIT_BRANDS.search(msg):
        return 0, "safe_promo", 0

    # 11. Gambling / real-money gaming — real apps but borderline predatory
    if _GAMBLING.search(msg):
        return 0, "safe_promo", 1

    # 12. Ambiguous financial promo — unrecognised brand, financial promise
    if _AMBIGUOUS_FINANCIAL.search(msg):
        return 0, "safe_promo", 1

    # 13. Default — unclassified; lean safe_promo per spec (precision > recall)
    return 0, "safe_promo", 1


def _classify_kaggle_ham(msg: str) -> str:
    """Returns category for a kaggle_india ham row."""
    stripped = msg.strip()

    # Very short messages are personal chats
    if len(stripped) < 40:
        return "safe_personal"

    # No real words (emoji/symbol-only messages)
    if not re.search(r"[a-zA-Z\u0900-\u097F]{3,}", stripped):
        return "safe_personal"

    # Transactional: OTPs, confirmations, delivery alerts, receipts
    if _TRANSACTIONAL.search(msg):
        return "safe_transactional"

    return "safe_generic"


# -----------------------------------------------------------
# Public-dataset transform functions
# Add one function per public dataset; reference by string name in CONFIG.
# Each receives a DataFrame with cols already renamed per col_map
# and must return a DataFrame with all SCHEMA_COLS present.
# -----------------------------------------------------------

def kaggle_india_transform(df: pd.DataFrame) -> pd.DataFrame:
    """
    Relabels the Kaggle India spam-ham SMS dataset for Defendra.

    CRITICAL: spam ≠ scam in this dataset.  Many 'spam' rows are legitimate
    promotional SMS from known Indian brands (Airtel, Vi, Jio, Flipkart …).
    Naively mapping spam→1 would wreck precision with embarrassing false
    positives on real brand promos.

    Strategy
    --------
    ham  → label=0, category=safe_personal | safe_transactional | safe_generic
    spam → heuristic rules:
             FRAUD signals  → label=1, scam category
             PROMO/safe     → label=0, safe_promo
             ambiguous      → label=0, safe_promo, review_needed=1

    Adds 'review_needed' column (1 = needs manual audit).
    Sets source="kaggle_india", lang="en".
    """
    labels      = []
    categories  = []
    review_flags = []

    for _, row in df.iterrows():
        msg       = str(row.get("text", ""))
        orig_label = str(row.get("Label", "")).strip().lower()

        if orig_label == "ham":
            labels.append(0)
            categories.append(_classify_kaggle_ham(msg))
            review_flags.append(0)
        else:
            # orig_label == "spam" — apply heuristic split
            lbl, cat, rev = _classify_kaggle_spam(msg)
            labels.append(lbl)
            categories.append(cat)
            review_flags.append(rev)

    df = df.copy()
    df["label"]        = labels
    df["category"]     = categories
    df["review_needed"] = review_flags
    df["lang"]         = "en"

    # Drop original label column (already mapped)
    df = df.drop(columns=["Label"], errors="ignore")

    return df


# Register transform functions by name so CONFIG strings resolve at runtime.
_TRANSFORM_REGISTRY = {
    "kaggle_india_transform": kaggle_india_transform,
}


# -----------------------------------------------------------
# Loaders
# -----------------------------------------------------------

def load_native(path: str) -> pd.DataFrame:
    """
    Load a CSV that already follows the unified schema (seeds, manual).
    Drops rows where 'text' is missing or blank.
    Applies defensive metadata normalization (lang, label, category).
    """
    df = pd.read_csv(path, dtype=str)
    # Keep only recognized schema columns; ignore extras silently
    df = df[[c for c in SCHEMA_COLS if c in df.columns]]
    df = df.dropna(subset=["text"])
    df = df[df["text"].str.strip() != ""]
    df = normalize_metadata(df)
    return df


def load_synthetic(cfg: dict) -> pd.DataFrame:
    """
    Load a synthetic/augmented CSV that already follows the unified schema.
    Preserves the file's own 'source' column if present and non-blank;
    falls back to cfg['default_source'] only for missing/empty values.
    Applies defensive metadata normalization (lang, label, category).
    """
    path           = cfg["path"]
    default_source = cfg.get("default_source", "synthetic")

    df = pd.read_csv(path, dtype=str)
    df = df[[c for c in SCHEMA_COLS if c in df.columns]]
    df = df.dropna(subset=["text"])
    df = df[df["text"].str.strip() != ""]

    # Fill missing/blank source with default; never overwrite existing values
    if "source" not in df.columns:
        df["source"] = default_source
    else:
        blank_mask = df["source"].isna() | (df["source"].str.strip() == "")
        df.loc[blank_mask, "source"] = default_source

    df = normalize_metadata(df)
    return df


def load_public(cfg: dict) -> pd.DataFrame:
    """
    Load a public/external dataset using the config dict.
    Applies col_map rename, then the named transform function.
    Applies defensive metadata normalization after transform.
    Preserves extra columns (e.g., review_needed) through this stage.
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

    # Ensure all schema columns present; fill missing with ""
    for col in SCHEMA_COLS:
        if col not in df.columns:
            df[col] = ""
    # Keep schema cols + review_needed if present
    keep = SCHEMA_COLS + (["review_needed"] if "review_needed" in df.columns else [])
    df = df[keep]

    df = df.dropna(subset=["text"])
    df = df[df["text"].str.strip() != ""]

    df = normalize_metadata(df)
    return df


# -----------------------------------------------------------
# Deduplication
# -----------------------------------------------------------

def deduplicate(df: pd.DataFrame) -> tuple:
    """
    Two-pass deduplication:
      Pass 1 — exact raw-text duplicates (keeps first occurrence).
      Pass 2 — near-duplicates: rows whose *normalized* text is identical
                after the full normalization pipeline (keeps first).

    Extra columns (e.g., review_needed) survive deduplication unchanged.
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
    """Pretty-print a value_counts table and return the markdown version."""
    counts  = series.value_counts(dropna=False)
    total   = len(series)
    lines   = [f"\n### {title}", f"{'Value':<30} {'Count':>7} {'%':>7}", "-" * 46]
    for val, cnt in counts.items():
        pct = 100 * cnt / total if total else 0
        lines.append(f"{str(val):<30} {cnt:>7} {pct:>6.1f}%")
    block = "\n".join(lines)
    print(block)
    return block


def print_health_checks(df: pd.DataFrame, review_count: int) -> list:
    """
    Print dataset health flags and return lines for the stats markdown.

    Checks:
      • scam% in 35-60%  (flag if outside — too low = useless, too high = imbalanced)
      • Hindi+Hinglish%  ≥ 40%  (flag if below — kaggle_india dilutes this)
      • review_needed count
      • per-scam-category row count ≥ 20  (flag any under)
    """
    total  = len(df)
    lines  = ["\n## Health Checks"]
    issues = 0

    # 1. Scam %
    scam_count = int((df["label"] == 1).sum())
    scam_pct   = 100 * scam_count / total if total else 0
    flag = " [FLAG: outside target 35-60%]" if not (35 <= scam_pct <= 60) else " [OK]"
    if "FLAG" in flag:
        issues += 1
    line = f"- **scam%**: {scam_pct:.1f}%  ({scam_count:,} / {total:,}){flag}"
    print(line)
    lines.append(line)

    # 2. Hindi + Hinglish %
    multi = int(df["lang"].isin(["hi", "hinglish"]).sum())
    multi_pct = 100 * multi / total if total else 0
    flag = " [FLAG: under 40% -- boost with synthetic Hindi batch]" if multi_pct < 40 else " [OK]"
    if "FLAG" in flag:
        issues += 1
    line = f"- **Hindi+Hinglish%**: {multi_pct:.1f}%  ({multi:,} / {total:,}){flag}"
    print(line)
    lines.append(line)

    # 3. review_needed count
    line = f"- **review_needed rows**: {review_count:,}  (manual audit recommended)"
    print(line)
    lines.append(line)

    # 4. Per-scam-category counts
    scam_df    = df[df["label"] == 1]
    cat_counts = scam_df["category"].value_counts()
    lines.append("\n### Scam category row counts (flag if < 20)")
    print("\n### Scam category row counts (flag if < 20)")
    for cat in SCAM_CATEGORIES:
        cnt  = int(cat_counts.get(cat, 0))
        flag = " [FLAG: under 20 -- add more examples]" if cnt < 20 else ""
        if flag:
            issues += 1
        line = f"  - {cat:<25} {cnt:>5}{flag}"
        print(line)
        lines.append(line)

    # Summary
    summary = f"\n**Total issues flagged: {issues}**"
    print(summary)
    lines.append(summary)
    return lines


def build_stats_markdown(
    df: pd.DataFrame,
    dedup_stats: dict,
    source_counts: dict,
    health_lines: list,
) -> str:
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
        rows   = [f"### {title}", "| Value | Count | % |", "| --- | --- | --- |"]
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
    lines.append("")
    lines.extend(health_lines)

    return "\n".join(lines)


# -----------------------------------------------------------
# Main
# -----------------------------------------------------------

def main():
    frames = []
    source_counts  = {}
    review_frames  = []   # collect review_needed rows across all public sources

    # ---- Load seed examples ----
    if os.path.exists(SEEDS_CSV):
        df_seeds = load_native(SEEDS_CSV)
        print(f"[seeds]      {len(df_seeds):>5} rows  <- {SEEDS_CSV}")
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
        print(f"[manual]     {len(df_m):>5} rows  <- {path}")
        source_counts[f"manual:{os.path.basename(path)}"] = len(df_m)
        frames.append(df_m)

    # ---- Load synthetic datasets ----
    for cfg in SYNTHETIC_CSVS:
        path = cfg["path"]
        if not os.path.exists(path):
            print(f"[WARN] Synthetic CSV not found, skipping: {path}", file=sys.stderr)
            continue
        df_s = load_synthetic(cfg)
        tag  = cfg.get("default_source", "synthetic")
        print(f"[synthetic]  {len(df_s):>5} rows  <- {path}  (source={tag})")
        source_counts[tag] = len(df_s)
        frames.append(df_s)

    # ---- Load public datasets ----
    for cfg in PUBLIC_CSVS:
        path = cfg["path"]
        if not os.path.exists(path):
            print(f"[WARN] Public CSV not found, skipping: {path}", file=sys.stderr)
            continue
        df_p = load_public(cfg)
        tag  = cfg["source_tag"]
        print(f"[public]     {len(df_p):>5} rows  <- {path}  (source={tag})")
        source_counts[tag] = len(df_p)

        # Collect review-flagged rows before stripping extra columns
        if "review_needed" in df_p.columns:
            flagged = df_p[df_p["review_needed"] == 1].copy()
            if len(flagged):
                print(f"  +-- {len(flagged):,} rows flagged review_needed=1")
                review_frames.append(flagged)

        frames.append(df_p)

    if not frames:
        print("ERROR: no data loaded. Check CONFIG paths.", file=sys.stderr)
        sys.exit(1)

    # ---- Combine ----
    df_all = pd.concat(frames, ignore_index=True)
    print(f"\n[combined]   {len(df_all):,} rows before dedup")

    # ---- Capture review_needed count before dedup strips extra cols ----
    review_count = int(df_all.get("review_needed", pd.Series(dtype=int)).sum()) \
                   if "review_needed" in df_all.columns else 0

    # ---- Normalize + deduplicate ----
    df_clean, dedup_stats = deduplicate(df_all)

    print(f"\n[dedup]  exact removed : {dedup_stats['exact_removed']:,}")
    print(f"[dedup]  near  removed : {dedup_stats['near_removed']:,}")
    print(f"[dedup]  final rows    : {dedup_stats['after']:,}")

    # ---- Ensure label is int (normalize_metadata handles text→int already;
    #      this coerces any remaining NaN/-1 edge cases from bad source data) ----
    df_clean["label"] = (
        pd.to_numeric(df_clean["label"], errors="coerce").fillna(-1).astype(int)
    )

    # ---- Print distributions ----
    print("\n" + "=" * 50)
    print_distribution(df_clean["label"],    "Class Balance (label  0=legit 1=scam)")
    print_distribution(df_clean["category"], "Category Distribution")
    print_distribution(df_clean["lang"],     "Language Distribution")
    print_distribution(df_clean["source"],   "Source Distribution")

    # ---- Health checks ----
    print("\n" + "=" * 50)
    health_lines = print_health_checks(df_clean, review_count)

    # ---- Write output CSV (schema cols only — strips review_needed) ----
    df_clean[SCHEMA_COLS].to_csv(OUTPUT_CSV, index=False, encoding="utf-8")
    print(f"\n[output]  dataset  -> {OUTPUT_CSV}")

    # ---- Write review_needed CSV ----
    if review_frames:
        df_review = pd.concat(review_frames, ignore_index=True)
        # Normalize text in review file too for easier reading
        df_review["text_norm"] = df_review["text"].apply(normalize)
        df_review.to_csv(OUTPUT_REVIEW_CSV, index=False, encoding="utf-8")
        print(f"[output]  review   -> {OUTPUT_REVIEW_CSV}  ({len(df_review):,} rows)")
    else:
        print("[output]  review   -> none flagged")

    # ---- Write stats markdown ----
    stats_md = build_stats_markdown(df_clean, dedup_stats, source_counts, health_lines)
    with open(OUTPUT_STATS_MD, "w", encoding="utf-8") as f:
        f.write(stats_md)
    print(f"[output]  stats md  -> {OUTPUT_STATS_MD}")

    print("\nDone.")


if __name__ == "__main__":
    main()
