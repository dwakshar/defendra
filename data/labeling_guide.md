# Defendra — Labeling Guide v1.0

Label the **normalized** text (placeholders applied, lowercase). When in doubt, ask: *would this message cause a reasonable person to hand over money or credentials?* If yes → scam.

---

## The one rule that resolves 80% of ambiguity

**Real institutions never ask you to act via SMS link or call a number in the message.**

Real bank/UPI/TRAI messages tell you something happened. Scam messages tell you to *do* something.

---

## Edge cases by category

### OTP (`category=otp`)

| Pattern | Label | Reason |
|---|---|---|
| "your otp is `<otp>`. do not share with anyone including bank officials." | **0** | Explicit do-not-share = real institution |
| "your otp is `<otp>`. share with our executive to complete kyc." | **1** | Asking to share OTP = always scam |
| OTP message, no share instruction, no suspicious URL | **0** | Legitimate — missing the warning is not scam signal |

### KYC (`category=kyc`)

| Pattern | Label | Reason |
|---|---|---|
| Contains `<url>` + urgency ("blocked", "suspended", "24 hours") | **1** | Urgency + link = scam pattern |
| "your kyc is due. visit nearest branch or call 1800-xxx." | **0** | Directs to known official channel, no link |
| Mentions aadhaar/pan + asks for details via link | **1** | No bank collects KYC via SMS link |

### Bank impersonation vs real bank alert (`bank_impersonation` vs `safe_transactional`)

This is the hardest pair. Decision tree:

1. Does the message contain a `<url>`?
   - Yes → **scam** (`bank_impersonation`). Real debit/credit alerts never include a link.
   - No → continue.
2. Does it ask you to call a number *embedded in the message* to "verify" or "unblock"?
   - Yes → **scam**. Real banks print their number on the card; they don't embed it in alerts.
   - No → continue.
3. Is the action described something that *already happened* (debit, credit, login)?
   - Yes → **safe** (`safe_transactional`).
   - No (asking you to do something) → **scam**.

### Delivery (`delivery`)

| Pattern | Label |
|---|---|
| Package on hold, pay fee via `<url>` | **1** |
| "deliver nahi hua, address update karo: `<url>`" | **1** |
| "your order has been delivered. rate your experience." | **0** (`safe_transactional`) |
| "out for delivery, expected by 6 pm" | **0** (`safe_transactional`) |

Legit courier companies (Delhivery, BlueDart, DTDC) **do not** charge re-delivery fees via SMS link.

### Electricity (`electricity`)

Real BESCOM/TATA Power/UPPCL messages: give a reference number, direct to official app/website by name, never ask you to call an agent's personal mobile.

Scam tells: personal mobile `<phone>` to "contact lineman/officer", disconnection "tonight at 9 pm" (fake urgency), no reference number.

### Digital arrest (`digital_arrest`)

Label **1** if message claims to be from: CBI, ED, NCB, TRAI, Cyber Cell, Supreme Court — **and** asks you to call back or face arrest/FIR. These agencies do not notify via SMS.

No legitimate agency uses the phrase "digital arrest."

### Job (`job`)

Registration/processing fee of any amount = **1**. No legitimate employer charges candidates.

WFH tasks like "like videos", "rate products", "write reviews" with per-task pay = **1**.

### Lottery (`lottery`)

Prize requires any upfront payment (tax, processing, stamp duty) = **1**. Always.

### Loan (`loan`)

Advance fee before disbursal = **1**. Legitimate lenders deduct fees from the loan amount, never collect upfront.

### Refund (`refund`)

Government/IT refunds are credited automatically — they never ask you to "verify" via link. Any message asking for action to receive a refund = **1**.

---

## Category assignment for scam messages

Use the **primary hook** — what is the scammer using to get compliance?

- OTP requested → `otp`
- KYC/document update → `kyc`
- Package/delivery problem → `delivery`
- Electricity bill/disconnection → `electricity`
- Police/CBI/court threat → `digital_arrest`
- Job offer with fee → `job`
- Prize/lottery win → `lottery`
- Fake bank alert with link → `bank_impersonation`
- Loan with advance fee → `loan`
- Refund/cashback needs action → `refund`

If a message hits multiple categories (e.g. fake bank alert + OTP request), pick the **dominant threat**. A fake SBI message asking for OTP → `bank_impersonation` (the impersonation is the hook; OTP is the payload).

---

## Language tagging

| Tag | When to use |
|---|---|
| `en` | All Latin script, no Hindi words |
| `hi` | Contains Devanagari (even one word) |
| `hinglish` | Latin script but uses Hindi vocabulary/grammar ("hai", "karein", "warna", "abhi") |

When Devanagari and Latin mix → `hi`.

---

## What NOT to add

- Promotional SMS from known brands that include a standard opt-out (`reply stop`) → `safe_promo`, even if aggressive
- OTP messages from apps you actually use (Swiggy, Zomato, GPay) — label **0**, they are real
- Ambiguous messages where you genuinely cannot decide after applying these rules → skip, do not force a label
