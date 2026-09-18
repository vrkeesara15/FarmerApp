# ml/ondevice — on-device crop + quality model

Owner: ML. Milestone: M6 (DX-001), retraining M7+ (DX-012).

Planned content (SPEC 3.1):

- Training code for a small image classifier (< 8 MB TFLite) that returns: image quality (blur, exposure),
  leaf/plant present, and crop class for the 6 pilot crops. Runs under 400 ms on a 2 GB RAM Android device (DX-001).
- Dataset manifest builder over the field corpus bucket (`farmerapp-<env>-corpus`), split by district/season to
  avoid leakage; public seed images tagged `source=public` (SPEC 3.3).
- Export pipeline: quantised TFLite + metadata, versioned as `ondevice-v<major>.<minor>`; artefact copied into
  `apps/mobile/packages/core/assets/models/` by a PR, never hot-loaded.
- Monthly fine-tune as a Vertex AI pipeline with an approval gate (DX-012); acceptance = no top-1 drop > 5 points
  on `ml/eval/testset`.
