# ml/eval/testset — held-out, agronomist-labelled evaluation sets

The diagnosis pipeline (SPEC 3) is evaluated on photos it has **never** seen in the corpus.
A test set is a directory with one `manifest.csv`; `ml/eval/evaluate.py` runs every row
through the production decision path (encoder → pgvector kNN → DX-003 decision rule → DX-004
LLM fallback) against a tenant's approved corpus, in a transaction that is rolled back, and
writes a JSON report (top-1 accuracy per crop and per problem, corpus-answer share,
escalation rate, hallucinated out-of-scope labels).

## Layout

```
ml/eval/testset/
  README.md
  ci/manifest.csv            tiny synthetic set used by CI (tests/diagnosis/test_evaluate.py)
  pilot-<season>/            the real held-out field set (NOT in git; see below)
    manifest.csv
    images/<crop>/<problem>/<file>.jpg   (or gs:// URIs in the corpus bucket)
```

## `manifest.csv`

| column | meaning |
|---|---|
| `image` | path relative to the manifest, a `gs://<corpus bucket>/...` URI, or (CI only) `synthetic://leaf/<problem_code>/<variant>` / `synthetic://non_plant/<kind>/<variant>` |
| `crop` | crop code (`paddy`, `cotton`, `chilli`, `maize`, `tomato`, `groundnut`) or `unknown` (the pipeline must infer it) |
| `true_problem` | the agronomist's label: a `pest_or_disease.code` (e.g. `paddy_blast`), or `out_of_scope` for non-plant photos and unsupported crops (DX-010) |
| `district` | district of the field (context for the LLM fallback) |
| `season` | `kharif`, `rabi` or `zaid` |

Optional extra columns (ignored by the script, useful for slicing later): `labelled_by`,
`labelled_at`, `stage`, `part`, `severity`.

## Rules for the real set (human gate)

* **Held out**: no image of the test set (same sha256 or the same field visit) may be in
  the corpus. Split by field visit, not by photo, so near-duplicates do not leak.
* **Agronomist-labelled**: every row is labelled (and spot-checked by a second agronomist)
  before it enters a manifest; the labeller goes into `labelled_by`.
* **Field photos**: PlantVillage-like public lab images may bootstrap the corpus
  (`source = public`, SPEC 3.3) but never count as evaluation data — they overstate accuracy
  by 20–50 points on real field photos.
* **Coverage**: at least 20 photos per crop × problem the corpus claims to answer, plus a
  non-plant / unsupported-crop slice (walls, soil, hands, weeds of other crops, a crop outside
  the six) for DX-010.
* **Privacy**: photos only (EXIF stripped before they are stored here); no farmer names,
  phones or ids in the manifest (NF-011).
* Images and manifests of the real set live in the private corpus bucket, not in git.

## Run

From `apps/api` (after `make seed`, or against a tenant with an approved corpus):

```
uv run python ../../ml/eval/evaluate.py --manifest ../../ml/eval/testset/ci/manifest.csv --tenant fcc
```

`--llm fake` (default) keeps the run free; `--llm claude` measures the real fallback and
sends the test photos (EXIF stripped, crop context only) to the provider. The report lands
in `ml/eval/reports/latest.json` (`--out` to change). The nightly job, the console report
and the alert on a > 5 point drop are DX-011 (P1).
