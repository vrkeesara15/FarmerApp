# OwnBrandBadge

Turmeric badge marking tenant own-brand SKUs.

Source: `apps/console/components/ds/OwnBrandBadge.tsx` (tests: `OwnBrandBadge.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `brandName` | `string` | defaults to 'Own brand' |
| `compact` | `boolean` | icon only, label sr-only + title |

## Variants

- default
- custom brand name
- compact

## States

- default

## Accessibility

- Compact keeps the name in sr-only text and title

## Tokens used

- `color.secondary.container`
- `color.secondary.on`
- `radius.pill`
- `text.console.small`

## Flutter

Turmeric pill marking the tenant's own products.

Source: `apps/mobile/packages/core/lib/src/widgets/own_brand_badge.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `(none)` | `` |  |

### Variants

- default

### States

- static

### Accessibility

- Star icon paired with 'Own brand' text.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.secondary`
- `color.secondary.container`
- `color.secondary.on`
- `radius.pill`
- `border.width`
- `space.1`
- `space.2`
- `text.mobile.caption`

### Tests

Golden: own_brand_badge_{light,sunlight}.png
