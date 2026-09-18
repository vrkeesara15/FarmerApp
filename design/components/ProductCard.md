# ProductCard

Image, name, pack, price (paise -> ₹), OwnBrandBadge, stock at nearest store, add button.

Source: `apps/mobile/packages/core/lib/src/widgets/product_card.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `name / pack` | `String` |  |
| `pricePaise` | `int` |  |
| `image` | `ImageProvider?` |  |
| `ownBrand` | `bool` |  |
| `stockCount` | `int?` | 0 = out of stock, null = hidden |
| `storeName` | `String?` |  |
| `added` | `bool` | secondary 'Added' button |
| `onAdd / onTap` | `VoidCallback?` |  |

## Variants

- default
- own brand

## States

- in stock
- out of stock (add disabled)
- added

## Accessibility

- Add button is a 48 dp AppButton with icon + text.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.background`
- `color.border`
- `color.text.muted`
- `color.text.secondary`
- `color.status.success`
- `color.status.danger`
- `radius.card`
- `radius.input`
- `space.1..3`
- `space.6`
- `space.12`
- `text.mobile.heading`
- `text.mobile.title`
- `text.mobile.caption`

## Tests

Golden: product_card_{light,sunlight}.png

