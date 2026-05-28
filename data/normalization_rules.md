# Defendra — Text Normalization Spec v1.0

## Scope
Applied identically in Python (training) and Dart (inference).
Any divergence between implementations is a bug.

---

## Placeholder Token Set

| Token      | Replaces                                    |
|------------|---------------------------------------------|
| `<url>`    | HTTP/HTTPS URLs and known shortener domains |
| `<email>`  | Email addresses                             |
| `<phone>`  | Indian mobile numbers                       |
| `<amount>` | Monetary amounts with currency marker       |
| `<acct>`   | Bank account / card numbers (9–18 digits)   |
| `<otp>`    | Standalone 4–6 digit codes                  |
| `<date>`   | Date expressions                            |
| `<name>`   | Salutation + proper name patterns           |

Tokens are lowercase. After global lowercasing they remain unchanged.

---

## Regex Definitions

All patterns must be compiled with the **case-insensitive flag**.
Syntax is compatible with both Python `re` and Dart `RegExp`.

### 1. `<url>`
```
(?:https?://|www\.)[^\s<>"']+|(?:bit\.ly|tinyurl\.com|t\.co|goo\.gl|short\.gy|rb\.gy|ow\.ly|is\.gd|cutt\.ly|tiny\.one)[/\w\-?=&#%]+
```
Replace entire match with `<url>`.

### 2. `<email>`
```
[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}
```
Replace entire match with `<email>`.

### 3. `<phone>`
```
(?:\+91[\s\-]?|0091[\s\-]?|91[\s\-]?)?(?<![0-9])[6-9][0-9]{9}(?![0-9])
```
Matches Indian mobile (starts 6–9, exactly 10 digits). Negative lookaround
prevents matching the middle of a longer digit string.
Replace entire match with `<phone>`.

### 4. `<amount>`
```
(?:₹|Rs\.?|INR)\s*[0-9,]+(?:\.[0-9]{1,2})?|[0-9,]+(?:\.[0-9]{1,2})?\s*(?:₹|Rs\.?|INR|lakh|crore|thousand|k\b)
```
Matches "₹5,000", "Rs. 10000", "5000 Rs", "2 lakh", "1.5 crore".
Replace entire match with `<amount>`.

### 5. `<acct>`
```
(?<![0-9])[0-9]{9,18}(?![0-9])
```
Catches account numbers and 16-digit card numbers. Applied after `<phone>` and
`<amount>` so those digit strings are already replaced.
Replace entire match with `<acct>`.

### 6. `<otp>`
```
(?<![0-9])[0-9]{4,6}(?![0-9])
```
Catches residual standalone 4–6 digit codes (OTPs, PINs).
Replace entire match with `<otp>`.

### 7. `<date>`
```
(?:\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}|\d{1,2}\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{2,4})
```
Matches "12/05/2024", "12-05-24", "5 June 2024", "05 jan 2025".
Replace entire match with `<date>`.

### 8. `<name>`
```
(Dear|Hi|Hello|Namaskar|Namaste)\s+([A-Z][a-zA-Z]{1,20}(?:\s+[A-Z][a-zA-Z]{1,20})?)
```
Replace entire match with `<name>`.

**Python:** `re.sub(pattern, '<name>', text, flags=re.IGNORECASE)`
**Dart:** `text.replaceAll(RegExp(pattern, caseSensitive: false), '<name>')`

---

## Order of Operations

Execute in this exact order. Do not reorder.

```
1. <url>      — remove URLs before their embedded digits trigger later rules
2. <email>    — remove emails before @ or dots confuse other patterns
3. <phone>    — 10-digit Indian numbers; must precede <acct>
4. <amount>   — currency-marked numbers; must precede <acct>
5. <acct>     — longer digit strings; catches what <phone>/<amount> missed
6. <otp>      — residual 4–6 digit codes
7. <date>     — date expressions
8. <name>     — salutation + name
```

---

## Casing Rule

**Apply global lowercase after all replacements.**

```python
# Python
text = text.lower()
```
```dart
// Dart
text = text.toLowerCase();
```

Tokens `<url>`, `<phone>` etc. survive lowercase unchanged.
Devanagari is unaffected by `.lower()` / `.toLowerCase()`.

---

## Whitespace Handling

Apply **after** casing.

```
1. Replace \r\n, \r, \n with a single space
2. Collapse all runs of whitespace (including \u00A0, \u200B, \u200C, \u200D) to one space
3. Strip leading and trailing whitespace
```

**Python:**
```python
import re
text = re.sub(r'[\r\n]+', ' ', text)
text = re.sub(r'[\s\u00A0\u200B\u200C\u200D]+', ' ', text).strip()
```

**Dart:**
```dart
text = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
text = text.replaceAll(RegExp(r'[\s\u00A0\u200B\u200C\u200D]+'), ' ').trim();
```

---

## Devanagari Text

Leave all Devanagari characters (`\u0900`–`\u097F`) **as-is** through every
step. Do not transliterate, romanize, or remove them. The multilingual tokenizer
handles Devanagari natively. No special handling required.

---

## Complete Pipeline (pseudocode)

```
function normalize(raw: String) -> String:
    text = raw
    for (pattern, token) in ORDERED_REPLACEMENTS:
        text = replace_all(pattern, token, flags=CASE_INSENSITIVE, text)
    text = text.lower()
    text = collapse_whitespace(text)
    return text
```

---

## Test Vectors

A conforming implementation must produce these exact outputs:

| Input | Expected output |
|-------|----------------|
| `Call 9876543210 now!` | `call <phone> now!` |
| `Your OTP is 482910` | `your otp is <otp>` |
| `Pay ₹5,000 to settle` | `pay <amount> to settle` |
| `Visit http://bit.ly/abc` | `visit <url>` |
| `A/c 123456789012 debited` | `a/c <acct> debited` |
| `Dear Rahul please verify` | `<name> please verify` |
| `आपका खाता बंद होगा` | `आपका खाता बंद होगा` |
| `  Hello  \n  World  ` | `hello world` |
