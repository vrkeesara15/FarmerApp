# Model card — `siglip-base-patch16-224@2024-01` (embed service, DX-002)

| | |
|---|---|
| Contract identity | name `siglip-base-patch16-224`, version `2024-01`, dim **768** (the API pins the same: `DIAGNOSIS_ENCODER_NAME` / `DIAGNOSIS_ENCODER_VERSION`) |
| Source | Hugging Face [`google/siglip-base-patch16-224`](https://huggingface.co/google/siglip-base-patch16-224) |
| Pinned revision | `7fd15f0689c79d79e38b1c2e2e2370a7bf2761ed` (2024-09-26; the weights file is unchanged since the 2024-01 upload — later commits touched README / tokenizer only) |
| Source weights | `model.safetensors`, 812 672 320 bytes, sha256 `2c63cb7d1f2e95ba501893cbb8faeb4ea9a3af295498d35097126228659c2af8` (checked by `embed.fetch`; a mismatch fails the build) |
| Served weights | vision tower only (`SiglipVisionModel`, 93 M parameters), re-saved by `embed.fetch` with transformers 5.17.0: 371 561 688 bytes, sha256 `fad78ac32c19178047f8a7b4328c6970b521839f4a961e89417a74307a54f275` (reported by `GET /info` as `weights_sha256`; identical on macOS and in the Linux image) |
| Licence | **Apache-2.0** (model card metadata of the pinned revision) |
| Architecture | SigLIP ViT-B/16, 224 x 224 input, 12 layers, hidden 768; embedding = the multi-head attention pooling head output (`pooler_output`, SigLIP's `image_embeds`), L2-normalised by the service |
| Pre-processing | from the revision's `preprocessor_config.json`: resize to 224 x 224, bicubic, **no crop** (the whole photo is seen, aspect ratio squashed); x / 255; (x - 0.5) / 0.5. Checked against `transformers.SiglipImageProcessorPil` (integration test). EXIF orientation applied, all metadata dropped before inference |
| Training data (upstream) | WebLI (Google, web image–text pairs; not public). Not trained on crop-disease imagery |
| Paper | Zhai et al., *Sigmoid Loss for Language Image Pre-Training*, 2023 (arXiv:2303.15343) |

## Intended use here

Zero-training, general-purpose image embedding for the kNN over the agronomist-approved corpus
(SPEC 3.1–3.3): a query photo is compared with approved images of approved problems of the same
crop and encoder (cosine, pgvector HNSW). The encoder is **not** a classifier; the decision rule
(DX-003) and the agronomist review turn neighbours into a diagnosis.

## Known limitations

* Generic web-scale features: fine-grained lesion differences (e.g. blast vs brown spot) may be
  closer than the default thresholds assume. The DX-003 defaults (T1 0.92 / agreement 0.60 /
  floor 0.85) were tuned for the fake pixel encoder and **must be retuned per crop** on real field
  images (`ml/eval`) before `DIAGNOSIS_ENCODER=remote` answers farmers without review.
* On the synthetic seed images: two variants of one problem 0.975, two different problems 0.872,
  leaf vs non-plant ≤ 0.59 (scripts/check_remote_encoder.py). Synthetic leaves are unrealistically
  alike; do not read these as field accuracy.
* 224 x 224 squash: small lesions on a full-plant photo lose detail; the apps' framing guidance
  (leaf fills the frame) matters.
* No bias / fairness evaluation exists for Indian field conditions (lighting, phone cameras,
  regional varieties).

## Human gates

* **Licence review for commercial use** (Apache-2.0 weights; upstream training data terms) —
  legal sign-off before stg / prd.
* **Threshold tuning with field images** per crop (DX-003) from an `ml/eval` run on the
  agronomist-labelled held-out set.
* **Deployment** of the image to dev / stg (prd is human-only), and the infra follow-ups in
  docs/prs/M6-embed.md.

## Changing the model

A new model, revision or pre-processing is a **new `VERSION`** in `embed/spec.py`: rebuild the
image, re-embed the whole corpus into the new encoder's vectors (DX-012), then move the API pin
(`DIAGNOSIS_ENCODER_VERSION`). The service refuses (409) requests for any other name / version and
the API refuses responses for any other name / version / dim, so two embedding spaces are never
mixed.
