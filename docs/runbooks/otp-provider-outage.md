# Runbook: OTP provider outage and failover

- **Owner:** platform lead
- **Severity:** Sev 1 (nobody can log in on a new device; SPEC 12.1 action "switch provider")
- **Detection:** `SLO: OTP delivery below 95% for 10 min (sev1)` (burn > 2.5x of the 98%-in-30 s SLO over 10 min), spike in `farmerapp_otp_whatsapp_fallback` / `otp_sms_failed` / `otp_sms_undelivered` (business dashboard "OTP sent vs delivered vs WhatsApp fallback"), support calls. Related: OPS-013 OTP send spikes (SMS pumping).

## How OTP delivery works (farmerapp/auth/otp.py)

1. `POST /v1/auth/otp/send` sends the code by SMS (`OTP_PROVIDER` secret / adapter) and logs `event=otp_sent channel=sms`.
2. An SMS provider error falls back to WhatsApp immediately (`otp_sms_failed`, `otp_fallback_whatsapp`).
3. 30 s later a delivery check asks the provider: `otp_delivered`, or `otp_sms_undelivered` + WhatsApp resend of the same code.
So a degraded SMS provider already degrades to WhatsApp automatically; this runbook is for when that is not enough.

## Steps

1. Confirm the signal is real (not a logging change):
   ```bash
   gcloud logging read 'resource.labels.service_name="api" AND jsonPayload.event=("otp_sent" OR "otp_delivered" OR "otp_sms_failed" OR "otp_sms_undelivered" OR "otp_fallback_whatsapp")' \
     --project $PROJECT --freshness 30m --format='value(jsonPayload.event)' | sort | uniq -c
   ```
2. Check the provider status page / account (DLT template approval, balance, sender id). Provider credentials are in Secret Manager `otp-provider`; never paste them in chat.
3. SMS pumping instead of an outage (sends spike, delivery rate falls, many unknown numbers): confirm Cloud Armor OTP rate limiting is enforcing (prd) and look at the top client IPs:
   ```bash
   gcloud logging read 'resource.type="http_load_balancer" AND httpRequest.requestUrl:"/v1/auth/otp/send"' \
     --project $PROJECT --freshness 1h --format='value(httpRequest.remoteIp)' | sort | uniq -c | sort -rn | head
   ```
   Block an abusive range with a temporary Armor rule (priority 1500, `deny(403)`, `inIpRange(origin.ip, '<cidr>')`) and open a Sev 1 security ticket ([suspected-data-breach.md](suspected-data-breach.md) if accounts may be compromised).
4. Fail over to the secondary SMS provider (the `otp-provider` secret holds the provider config; the adapter choice is part of it). An admin adds a new secret version with the secondary's config, then forces a new revision so the API reads `latest`:
   ```bash
   gcloud secrets versions add otp-provider --project $PROJECT --data-file=secondary-otp-provider.json   # admin only
   gcloud run services update api --region $REGION --project $PROJECT \
     --update-env-vars OTP_FAILOVER_AT=$(date -u +%Y%m%dT%H%M%SZ)
   gcloud run services update worker --region $REGION --project $PROJECT \
     --update-env-vars OTP_FAILOVER_AT=$(date -u +%Y%m%dT%H%M%SZ)
   ```
   **Gap (human gate):** the real SMS / WhatsApp adapters (DLT-registered primary and secondary) are not built yet (FA-001 deferred); until they exist this step is a placeholder and WhatsApp fallback is the only automatic lever.
5. If both providers are down: tell officers that logged-in devices keep working (refresh tokens last 30 days, SEC-020); only new logins are blocked. Do not enable `OTP_DEV_CODE` in prd (the settings guard refuses to start).

## Verification

- `farmerapp_otp_delivered / farmerapp_otp_sent{channel=sms}` back above 98% for 30 minutes; the SLO alert closes.
- A test login on a pilot phone receives the SMS within 30 s.

## Communication

- `#farmerapp-ops` on detection and failover; ops lead tells cluster heads "new logins delayed, existing sessions unaffected".
- Provider incident reference recorded in the ticket.

## Follow-up

- Fail back to the primary once it is stable for 24 h (new secret version + new revision, same commands).
- Postmortem for Sev 1. Review the SLO burn window if the alert was noisy at low volume.
