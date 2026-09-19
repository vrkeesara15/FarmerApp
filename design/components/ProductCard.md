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
| `stockAsOf` | `DateTime?` | UTC time the stock figure was true; appends `productStockAsOf(HH:mm)` |
| `priceIsEstimate` | `bool` | adds `productPriceEstimate` under the price (cached price list; the server prices the order) |
| `quantity` | `int?` | units in the cart; the added button reads `productInCart(n)` |
| `actionLabel / actionIcon` | `String? / IconData?` | replaces "Add" (M6 diagnosis result: "Order" / "Create order for farmer") |
| `showAction` | `bool` | false hides the button entirely — SPEC 3.4: a provisional diagnosis never shows a buy button (M6) |
| `actionKey` | `Key?` | key of the button (`DiagnosisKeys.orderProduct(sku)`) |

## Variants

- default
- own brand

## States

- in stock
- out of stock (add disabled)
- added
- stock at the nearest store without a store name (`productStockNearest`)

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

## Usage (FA-020 / FA-021 / FA-022)

A50 shows one card per SKU from the offline catalogue cache: `stockCount` = whole available units at the farmer's order store (`StockLevel.wholeUnits`), `storeName` from the nearest-store answer, `stockAsOf` from the snapshot, `priceIsEstimate: true`. Keys `product-<skuId>`.
