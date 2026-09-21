# Decisions pending the owner — placeholders currently in use

The build uses the values below so work can continue. Each is a placeholder, not a
recommendation. Confirm or change them before the pilot; every one is a single settings or
variable change, not a code rewrite. Recorded 2026-09-20 on the owner's instruction to
"have them as placeholders for now".

## Business rules

| Item | Placeholder in use | Where it lives | Why it matters |
|---|---|---|---|
| Churn window for the farmer churn-risk list | 90 days without a purchase or verified visit | analytics segments (AN-004) | Drives who appears on the churn list and in campaign segments |
| Acreage bands for segments | small < 2, medium 2–5, large > 5 acres | analytics segments | Segment sizes and campaign targeting |
| Spend bands for segments | low < ₹5,000, medium ₹5,000–25,000, high > ₹25,000 per season | analytics segments | As above |
| Credit due days when no harvest month is known | 90 days | tenant settings (`credit_due_days`) | Khata due dates and overdue buckets |
| Store manager credit limit cap | ₹50,000 before cluster-head approval | tenant settings | ST-007 approval routing |
| Discount above policy (VA-E09) | 10% | rule YAML | Sales-anomaly flags |
| Incentive cut-off day (VA-E09) | 25th of the month | rule YAML | Late-cancellation flags |
| Travel allowance rate | ₹3 per km | tenant settings | FA-023 payouts |
| Minimum visit duration, geofence radius | 5 minutes, 150 m | tenant settings | Visit scoring |
| Unexplained tracking gap | 3 hours, 24-hour grace | rule YAML | Coaching flag |
| Outbreak rule | ≥ N confirmed cases and ≥ k× the trailing 4-week mean, per district and week | rule YAML | Farmer alerts |

## Infrastructure cost shape (NF-015)

| Option | Monthly cost | Notes |
|---|---|---|
| Pilot as specified (HA Cloud SQL + read replica, console min 1) | ~₹52,400 | 2.1× the ₹25,000 pilot budget |
| Pilot trimmed (zonal SQL, no replica, console min 0) | ~₹23,500 | Fits the budget; loses automatic failover and a read replica |
| 50 stores with committed-use discount, no replica | ~₹77,500 | Against the ₹1,00,000 budget |
| 50 stores without the discount or with a replica | ~₹1,14,700 | Over budget |

**Currently configured:** the spec's shape (HA + replica in production). The trimmed shape is a
tfvars change per environment.

**Not in the NF-015 budget:** SMS and LLM usage, about ₹1,94,800/month at 50 stores — larger
than the infrastructure bill. Needs its own budget line and per-tenant alerts (already built).

## Legal and policy text (TODO-LEGAL)

- Employee location policy (VV-010) and farmer consent notice: placeholder copy, version `2026-09-v1`.
- Outbreak advisories are sent to farmers without marketing consent, on the basis that crop
  protection is not marketing. Tenant-switchable; needs a legal view.
- Grievance officer name and contact for the DPDP flows.
- Google Roads API (road snapping for travel allowance) would send officer GPS tracks outside
  India. Off everywhere; needs a data protection impact assessment before it is enabled.
