# DX-001 evaluation — `crop_quality_v1.tflite`

Held-out test split: 2066 images (public bootstrap data, source=public).

| Head | Accuracy | Balanced accuracy | n |
|---|---|---|---|
| plant | 0.9942 | 0.9955 | 2066 |
| quality | 0.9801 | 0.9798 | 6042 |
| crop | 0.9724 | 0.9769 | 1597 |
| retake_gate | 0.9813 | 0.9837 | 6198 |

Crop at p >= 0.6: coverage 0.964, accuracy when confident 0.9883. False retake rate on good plant photos: 0.0113.

## plant confusion (rows = truth, columns = prediction)

| truth \ pred | not_plant | plant | recall |
|---|---|---|---|
| not_plant | 468 | 1 | 0.998 |
| plant | 11 | 1586 | 0.993 |

## quality confusion (rows = truth, columns = prediction)

| truth \ pred | ok | blurry | dark | recall |
|---|---|---|---|---|
| ok | 1970 | 9 | 1 | 0.995 |
| blurry | 99 | 1875 | 3 | 0.948 |
| dark | 5 | 3 | 2077 | 0.996 |

## crop confusion (rows = truth, columns = prediction)

| truth \ pred | paddy | cotton | chilli | maize | tomato | groundnut | other | recall |
|---|---|---|---|---|---|---|---|---|
| paddy | 216 | 0 | 0 | 5 | 0 | 0 | 0 | 0.977 |
| cotton | 0 | 249 | 0 | 0 | 0 | 1 | 1 | 0.992 |
| chilli | 0 | 0 | 69 | 0 | 0 | 0 | 0 | 1.000 |
| maize | 1 | 0 | 0 | 234 | 1 | 0 | 6 | 0.967 |
| tomato | 0 | 0 | 1 | 2 | 200 | 0 | 7 | 0.952 |
| groundnut | 0 | 0 | 0 | 0 | 0 | 208 | 1 | 0.995 |
| other | 2 | 5 | 3 | 6 | 2 | 0 | 377 | 0.954 |
