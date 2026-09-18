# SyncStatusPill

Pill showing synced / pending n / failed / syncing; optional tap opens A64 Sync details.

Source: `apps/mobile/packages/core/lib/src/widgets/sync_status_pill.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`). Live wrapper: `lib/src/widgets/sync_live.dart` `SyncStatusPillLive` reads `syncStatusProvider` (FA-025) and maps `SyncStatus` → `state` + `pendingCount`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `state` | `SyncState` | synced | pending | failed | syncing |
| `pendingCount` | `int` | shown in the pending label |
| `onTap` | `VoidCallback?` | opens A64 |

`SyncStatusPillLive({onTap})` takes only `onTap`; state comes from the provider.

## Variants

- synced — success green, cloud-done icon, `syncSynced`
- pending — warning amber, cloud-upload icon, `syncPending(count)`; the count is queued ops + photos still uploading
- failed — danger red, cloud-off icon, `syncFailed`; shown when any op was rejected by the server or a photo upload failed locally (a transport failure keeps the pill on pending: the engine retries with backoff, the OfflineBanner explains the network)
- syncing — info blue, cloud-sync icon, `syncSyncing`; while `SyncEngine.syncNow` runs

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
- `color.status.info`
- `color.status.infoContainer`
- `radius.pill`
- `border.width`
- `space.1`
- `space.3`
- `text.mobile.label`

## Tests

Widget tests: four states + tap + Telugu (`test/widgets/sync_status_pill_test.dart`); provider-driven states, engine round trip synced → pending → syncing → synced, failed after a rejection (`test/widgets/sync_live_test.dart`). Golden: sync_status_pill_{light,sunlight}.png (all four variants).
