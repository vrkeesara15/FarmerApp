# Runbook: payment webhook backlog (and DLQ replay for any topic)

- **Owner:** platform lead, with the finance lead for money questions
- **Severity:** Sev 1 for `payment.webhook` (payment failure, SPEC 12.3); Sev 2 for every other topic
- **Detection:** `[env] payment.webhook: message in dead-letter queue (OPS-004, sev1)`, `[env] payment.webhook: oldest unacked > 10 min (OPS-004, sev1)`, `[env] webhook down (OPS-001, sev1)`; the SLO "payment webhook processed within 2 min 99.9%" (any webhook in the DLQ breaches it). Same alerts exist per topic (`visit.created`, `farmer.registered`, `diagnosis.requested`, `order.created`, `location.batch`, `notify.send`).

## How it flows

`POST /v1/webhooks/razorpay` (api) verifies the HMAC signature and replay window, stores a
`webhook_event` row (idempotent by provider event id) and publishes
`{"tenant_id", "webhook_event_id", "event_id"}` to `payment.webhook`. The push subscription
`payment.webhook.worker` delivers it to the worker, which applies the event once (a row that is
no longer `received` is left alone). After 5 failed deliveries Pub/Sub moves the message to
`payment.webhook.dlq`, kept 7 days in the pull subscription `payment.webhook.dlq.replay`.
**Replaying is safe**: applying is idempotent per `webhook_event` row.

## Steps

1. Scope: how many messages, how old, which topic.
   ```bash
   TOPIC=payment.webhook
   gcloud pubsub subscriptions describe $TOPIC.worker --project $PROJECT --format='value(pushConfig.pushEndpoint)'
   gcloud monitoring time-series list --project $PROJECT \
     --filter="metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND resource.label.subscription_id=\"$TOPIC.dlq.replay\"" \
     --interval-start-time=$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-30 min' +%Y-%m-%dT%H:%M:%SZ) \
     --format='value(points[0].value.int64Value)'
   ```
2. Why is the worker failing? Look at its errors and at the endpoint:
   ```bash
   gcloud logging read 'resource.labels.service_name="worker" AND (jsonPayload.level="error" OR httpRequest.status>=500 OR jsonPayload.event=("payment_webhook_message_malformed" OR "payment_event_handler_failed"))' \
     --project $PROJECT --freshness 1h --limit 50 --format json | jq -r '.[] | [.timestamp, .jsonPayload.event, .jsonPayload.error] | @tsv'
   gcloud run services describe worker --region $REGION --project $PROJECT --format='value(status.latestReadyRevisionName)'
   ```
   Typical causes: bad worker deploy (roll back: `gcloud run services update-traffic worker --region $REGION --project $PROJECT --to-revisions <previous>=100`), Cloud SQL down ([cloud-sql-failover-restore.md](cloud-sql-failover-restore.md)), Razorpay API errors (the provider status page), worker at max instances.
3. **Fix the cause first.** Replaying into a broken worker only sends the messages back to the DLQ.
4. Replay the DLQ (pull, republish to the main topic with the same attributes, then ack). Run from a trusted shell with `jq`; batches of 100:
   ```bash
   TOPIC=payment.webhook
   SUB=$TOPIC.dlq.replay
   while :; do
     gcloud pubsub subscriptions pull $SUB --project $PROJECT --limit 100 --format=json > /tmp/dlq.json
     [ "$(jq length /tmp/dlq.json)" -eq 0 ] && break
     jq -c '.[]' /tmp/dlq.json | while read -r m; do
       data=$(echo "$m" | jq -r '.message.data' | base64 --decode)
       attrs=$(echo "$m" | jq -r '(.message.attributes // {}) | to_entries | map("\(.key)=\(.value)") | join(",")')
       if [ -n "$attrs" ]; then
         gcloud pubsub topics publish $TOPIC --project $PROJECT --message "$data" --attribute "$attrs" >/dev/null
       else
         gcloud pubsub topics publish $TOPIC --project $PROJECT --message "$data" >/dev/null
       fi
       gcloud pubsub subscriptions ack $SUB --project $PROJECT --ack-ids "$(echo "$m" | jq -r .ackId)" >/dev/null
     done
   done
   rm -f /tmp/dlq.json
   ```
   The payloads carry ids only (no card or UPI data), but still delete the temp file.
5. Events Razorpay could not deliver at all (endpoint down): Razorpay retries failed webhooks for up to 24 h; after that, re-send them from the Razorpay dashboard (Webhooks, failed deliveries) or run reconciliation (step 6).
6. Reconcile the affected day(s) so finance sees any mismatch (dry run; notifies accountants):
   ```bash
   gcloud run jobs execute reconcile-payments --region $REGION --project $PROJECT \
     --args="reconcile-payments,--tenant-id,<tenant-uuid>,--date,<YYYY-MM-DD>" --wait
   ```

## Verification

- `payment.webhook.dlq.replay` undelivered = 0 and `payment.webhook.worker` oldest unacked < 60 s.
- Logs show `webhook_applied` for the replayed `event_id`s; the waiting payments (A53 screen) flipped to paid.
- `reconcile-payments` reports `mismatches=0` for the day (or finance has the list).

## Communication

- Sev 1: `#farmerapp-ops` + finance lead on detection; store managers are told that UPI payments shown as pending will update without re-collecting (never ask the farmer to pay twice).

## Follow-up

- Postmortem for Sev 1. If a message is poison (fails again after replay), capture it in the ticket, ack it out of the DLQ only after finance confirms the payment state manually.
