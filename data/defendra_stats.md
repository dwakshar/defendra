# Defendra Dataset — Build Stats
_Generated: 2026-05-28 18:03_

## Source row counts (before dedup)
- **seeds**: 80 rows
- **manual:collection_template.csv**: 3 rows
- **uci_spam**: 5,572 rows

## Deduplication
- Rows before dedup : **5,655**
- Exact duplicates removed : **403**
- Near-duplicates removed (norm-text match) : **31**
- Rows after dedup : **5,221**

### Class Balance (label)
| Value | Count | % |
| --- | --- | --- |
| 0 | 4,536 | 86.9% |
| 1 | 685 | 13.1% |

### Category Distribution
| Value | Count | % |
| --- | --- | --- |
| safe_generic | 4,514 | 86.5% |
| generic_spam | 624 | 12.0% |
| safe_transactional | 9 | 0.2% |
| kyc | 8 | 0.2% |
| safe_promo | 7 | 0.1% |
| otp | 7 | 0.1% |
| delivery | 7 | 0.1% |
| bank_impersonation | 6 | 0.1% |
| job | 6 | 0.1% |
| digital_arrest | 6 | 0.1% |
| electricity | 6 | 0.1% |
| safe_personal | 6 | 0.1% |
| lottery | 5 | 0.1% |
| refund | 5 | 0.1% |
| loan | 5 | 0.1% |

### Language Distribution
| Value | Count | % |
| --- | --- | --- |
| en | 5,171 | 99.0% |
| hinglish | 29 | 0.6% |
| hi | 21 | 0.4% |

### Source Distribution
| Value | Count | % |
| --- | --- | --- |
| uci_spam | 5,138 | 98.4% |
| manual | 80 | 1.5% |
| reddit | 2 | 0.0% |
| inbox | 1 | 0.0% |