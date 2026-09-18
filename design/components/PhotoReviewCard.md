# PhotoReviewCard

Review card for a photo just taken in-app: thumbnail, pixel size and file size, a quality badge from the on-device gate with its retake tip, and Retake / Use buttons. Used by A41 (agent scouting review) and F22 (farmer photo check). Requirements: FM-004 (blurry photo rejected with retake tip), NF-004 (1280 px / q80 budget shown as the file size), DX-001 (gate result), FA-015 (only in-app photos reach this card).

Source: `apps/mobile/packages/core/lib/src/widgets/photo_review_card.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`). Tip text mapping: `lib/src/widgets/photo_tip_text.dart` (`CoreLocalizations.photoTip(key)`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `sizeBytes` | `int` | encoded size of the processed photo (`ProcessedPhoto.sizeBytes`); shown as whole KB |
| `width`, `height` | `int` | processed pixel size, e.g. 1280 × 960 |
| `quality` | `PhotoQualityResult?` | gate result; `null` = still checking |
| `thumbnail` | `ImageProvider?` | usually `MemoryImage(processed.bytes)`; placeholder icon when null |
| `index`, `total` | `int?` | "Photo 1 of 3" when both given (up to 3 photos, FM-004); otherwise "Check your photo" |
| `onRetake` | `VoidCallback` | always enabled |
| `onUse` | `VoidCallback` | wired only when `quality.isAcceptable` |

## Variants

- single (`photoReviewHeading`) / numbered (`photoReviewTitle` with index and total)

## States

| State | Badge | Tip line | Use photo |
|---|---|---|---|
| checking (`quality == null`) | info, hourglass, `photoQualityChecking` | none | disabled |
| ok (`tipKey == photo.tip.ok`) | success, check_circle_outline, `photoQualityOk` | `photoTipOk` | enabled |
| blurry (`photo.tip.blurry`) | danger, blur_on, `photoQualityBlurry` | `photoTipBlurry` | disabled |
| dark (`photo.tip.dark`) | warning, brightness_low_outlined, `photoQualityDark` | `photoTipDark` | disabled |

Dark wins over blurry (a dark frame has no edges to measure), matching `PhotoQualityResult.tipKey`.

## Accessibility

- Container `Semantics(label: "<title>, <badge>, <size>")`, e.g. "Photo 1 of 3, Good photo, 186 KB"; thumbnail excluded from semantics.
- Both buttons are `AppButton` medium (48 dp) with icon + visible text; the tip line is body size (16 sp), never caption (NF-009/NF-010).
- Badge and tip use colour plus icon plus words; Sunlight drops tinted containers and uses 2 dp borders via `AppThemeData.tint` / `borderWidth`.

## Tokens used

- `color.surface`, `color.border` (Card)
- `color.primary`, `color.primary.container` (thumbnail placeholder)
- `color.status.{success,warning,danger,info}` and their `.container`
- `color.text.secondary`
- `radius.card`, `radius.input`, `radius.pill`
- `space.1..4`, `space.12`
- `size.touchTargetMin` (medium buttons)
- `text.mobile.heading`, `text.mobile.body`, `text.mobile.label`, `text.mobile.caption`

## Copy keys

`photoReviewHeading`, `photoReviewTitle`, `photoQualityOk`, `photoQualityBlurry`, `photoQualityDark`, `photoQualityChecking`, `photoTipBlurry`, `photoTipDark`, `photoTipOk`, `photoRetake`, `photoUse`, `photoSizeKb`, `photoDimensions` (en, te, kn, hi, mr).

## Tests

`test/widgets/photo_review_card_test.dart` (ok / blurry / dark / checking, callbacks, disabled Use, thumbnail vs placeholder, touch targets, semantics, Telugu). Golden: `photo_review_card_{light,sunlight}.png` (ok numbered, blurry portrait, checking).
