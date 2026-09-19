# Runbook: corpus rollback to the previous version

- **Owner:** agronomy lead (decision), ML / platform lead (execution)
- **Severity:** Sev 2 (Sev 1 if a wrong recommendation could harm crops at scale)
- **Detection:** M6: nightly evaluation job (DX-011) accuracy drop on the pilot test set; agronomist review queue reports (OPS-009); diagnosis error-rate spike.
- **Status:** placeholder until M6 (diagnosis engine). The storage side exists today: the `farmerapp-<env>-corpus` bucket is versioned and keeps the last 5 archived versions of each object (`infra/envs/*/main.tf`).

## Steps (to be confirmed when DX-* lands)

1. Freeze corpus publishing (pause the ingestion job / stop agronomist publishes).
2. List the versions of the corpus manifest and pick the last good generation:
   ```bash
   gcloud storage ls -a gs://farmerapp-$ENV-corpus/manifest.json
   ```
3. Restore it as the live object (copy the older generation over the current one):
   ```bash
   gcloud storage cp gs://farmerapp-$ENV-corpus/manifest.json#<generation> gs://farmerapp-$ENV-corpus/manifest.json
   ```
   Repeat for embeddings / index files named in that manifest (same generation date).
4. Restart the embed and worker services so they reload the corpus:
   ```bash
   gcloud run services update embed --region $REGION --project $PROJECT --update-env-vars CORPUS_ROLLBACK_AT=$(date -u +%Y%m%dT%H%M%SZ)
   gcloud run services update worker --region $REGION --project $PROJECT --update-env-vars CORPUS_ROLLBACK_AT=$(date -u +%Y%m%dT%H%M%SZ)
   ```
5. Re-run the evaluation job on the restored version (M6).

## Verification

- Evaluation accuracy back at the previous baseline; a spot check of 10 known cases by the agronomist.

## Communication

- Agronomists and product owner; if farmers received bad advice, the agronomy lead decides on a corrective message through the notify path (never automated).

## Follow-up

- Add the failing cases to the evaluation set before re-publishing.
