# SyncStatusPill

Pill showing synced / pending n / failed; optional tap opens sync details.

Source: `apps/mobile/packages/core/lib/src/widgets/sync_status_pill.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `state` | `SyncState` | synced | pending | failed |
| `pendingCount` | `int` |  |
| `onTap` | `VoidCallback?` |  |

## Variants

- synced
- pending
- failed

## States

- static
- tappable

## Accessibility

- Cloud icon paired with the state text; `Semantics(button?, label)`.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.status.success`
- `color.status.successContainer`
- `color.status.warning`
- `color.status.warningContainer`
- `color.status.danger`
- `color.status.dangerContainer`
- `radius.pill`
- `border.width`
- `space.1`
- `space.3`
- `text.mobile.label`

## Tests

Widget tests: three states + tap + Telugu. Golden: sync_status_pill_{light,sunlight}.png

