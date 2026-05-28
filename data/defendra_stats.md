# Defendra Dataset — Build Stats
_Generated: 2026-05-29 00:54_

## Source row counts (before dedup)
- **seeds**: 80 rows
- **manual:collection_template.csv**: 3 rows
- **synthetic**: 30 rows
- **kaggle_india**: 2,266 rows

## Deduplication
- Rows before dedup : **2,914**
- Exact duplicates removed : **577**
- Near-duplicates removed (norm-text match) : **33**
- Rows after dedup : **2,304**

### Class Balance (label)
| Value | Count | % |
| --- | --- | --- |
| 0 | 2,018 | 87.6% |
| 1 | 286 | 12.4% |

### Category Distribution
| Value | Count | % |
| --- | --- | --- |
| safe_promo | 675 | 29.3% |
| safe_generic | 669 | 29.0% |
| safe_personal | 661 | 28.7% |
| bank_impersonation | 49 | 2.1% |
| kyc | 42 | 1.8% |
| otp | 40 | 1.7% |
| delivery | 40 | 1.7% |
| digital_arrest | 39 | 1.7% |
| refund | 34 | 1.5% |
| job | 14 | 0.6% |
| safe_transactional | 13 | 0.6% |
| lottery | 11 | 0.5% |
| electricity | 9 | 0.4% |
| loan | 8 | 0.3% |

### Language Distribution
| Value | Count | % |
| --- | --- | --- |
| en | 2,117 | 91.9% |
| hinglish | 102 | 4.4% |
| hi | 85 | 3.7% |

### Source Distribution
| Value | Count | % |
| --- | --- | --- |
| kaggle_india | 2,029 | 88.1% |
| synthetic | 192 | 8.3% |
| manual | 80 | 3.5% |
| reddit | 2 | 0.1% |
| inbox | 1 | 0.0% |


## Health Checks
- **scam%**: 12.4%  (286 / 2,304) [FLAG: outside target 35-60%]
- **Hindi+Hinglish%**: 8.1%  (187 / 2,304) [FLAG: under 40% -- boost with synthetic Hindi batch]
- **review_needed rows**: 169  (manual audit recommended)

### Scam category row counts (flag if < 20)
  - otp                          40
  - job                          14 [FLAG: under 20 -- add more examples]
  - lottery                      11 [FLAG: under 20 -- add more examples]
  - loan                          8 [FLAG: under 20 -- add more examples]
  - refund                       34
  - kyc                          42
  - delivery                     40
  - electricity                   9 [FLAG: under 20 -- add more examples]
  - digital_arrest               39
  - bank_impersonation           49
  - generic_spam                  0 [FLAG: under 20 -- add more examples]

**Total issues flagged: 7**