# Tenant branding (FA-008)

How a tenant makes the two apps and the console its own, what it can change, and what it
cannot.

## What a tenant sets

An owner, director or tenant admin opens **Settings → Branding** in the console (C102,
WC-012) and fills four fields. The screen previews both apps live as they type, and saving
needs a step-up OTP (SEC-028) and is audited (`tenant_settings.update`).

| Field | Stored as | Used for |
|---|---|---|
| Field agent app name | `branding.app_name_agent` | The officer app's title, splash and home header; the console's own name for the tenant |
| Farmer app name | `branding.app_name_farmer` | The farmer app's title and home header |
| Primary colour | `branding.primary_colour` (`#RRGGBB`) | The `color.primary.*` tokens in both apps and the console |
| Logo | `branding.logo_blob_uri` (an https blob URI from `POST /v1/uploads`) | The splash and both home headers, and the console shell |
| Support phone | `branding.support_phone` (E.164) | Every "call support" action in both apps and the console profile menu |

The same values can be set through the API: `PATCH /v1/settings` with a `branding` object
(partial: the keys sent are merged, `null` resets one to its default). They are read back by
every surface from `GET /v1/settings/public`, which any signed-in role may call — so a store
manager's console and a farmer's phone brand themselves from the same row the owner edited.

Nothing else is a tenant's to change. SPEC 13.1 allows the primary colour and the logo; the
neutrals, the status colours, the confidence ramp, the visit badges and the whole type scale
stay the shipped tokens, because they carry meaning that must read the same in every tenant.

## How the colour becomes four tokens

A tenant supplies one colour. Hover, container and on-primary are **derived**, with a WCAG
contrast check at each step, so a brand cannot ship an unreadable screen (NF-009):

1. **primary** is darkened (lightened in the console's Dark theme) in 1 % lightness steps until
   it reaches its theme's minimum against both surface and background — 4.5:1 in Light and
   Dark, **7:1 in Sunlight**, which exists for a farmer in direct sun and must stay the
   strongest of the three. The primary is an icon and text colour, not only a fill, which is
   why it is held to text contrast.
2. **on-primary** is white or `#0B1A10`, whichever contrasts more with the corrected primary.
3. **hover** is the primary 20 % darker (lighter in Dark), kept at 4.5:1 under on-primary so a
   pressed button still shows its label.
4. **container** is the primary mixed into the surface until the primary reads on it at 4.5:1.
   The Sunlight theme has no tinted containers at all (SPEC 13.1), so it keeps plain white.

So a tenant that picks a bright orange (`#E0651B`, 3.0:1 on white) gets `#B85514` — and sees
`#B85514` in the C102 preview, because the preview runs the same function. The derivation
lives twice, once per language, and the two are held together by test:

* `apps/mobile/packages/core/lib/src/theme/{contrast,brand}.dart` — `packages/core/test/theme/brand_test.dart`
* `apps/console/lib/brand.ts` — `apps/console/lib/brand.test.ts`

Both assert the same hex values for the same input (`#3B4BD8` → primary `#3B4BD8`, hover
`#2533B7`, container `#E7E9FA`, on-primary `#FFFFFF` in Light). Change one and the other's
test fails.

## First frame

Both apps cache the pulled settings in Drift (`kv`, key `tenant.settings.public`) and read the
branding out of that cache **before the first frame** (`brandingOverrides`, the same shape
FA-004 uses for the saved language). A cold start with no network therefore opens in the
tenant's colour, name and logo rather than flashing the default green. A fresh install shows
the shipped brand until the first pull after login.

The console does the same with `localStorage`, keyed by tenant id, and injects the derived
tokens as a `<style>` after `tokens.css` — both console themes at once, so the theme toggle
needs no second pass.

The logo is loaded over the network. Offline, or when a tenant typed a URI that does not
resolve, both apps and the console fall back to the shipped leaf mark rather than leaving a
hole in the header.

## What branding cannot change

**The Android application label and the launcher icon stay per app.** They are compiled into
the APK a Play Store listing points at; one build serves every tenant, and a store listing
cannot vary per tenant. So the icon on the home screen and the name under it are "Mitra" and
"Kisan" (the working names of SPEC 1.2) whatever a tenant sets — the tenant's name and logo
appear the moment the app opens, on the splash and in the header, and everywhere inside.
Changing that would mean a per-tenant build and a per-tenant Play listing, which is a
distribution decision, not a settings one.

The console's name for a tenant is `app_name_agent`: the brand row carries one name per app
and no separate console name, and the officer app is the surface office staff recognise.

## Adding a second test tenant

The acceptance criterion of FA-008 is "a second test tenant renders with its brand without a
code change". Two fixture tenants exist for exactly that, with the same values on both sides:

* `apps/mobile/packages/core/lib/src/state/test_brands.dart` — `TestBrands.harvest` (indigo
  `#3B4BD8`) and `TestBrands.bhoomi` (terracotta `#B4362A`)
* `apps/console/lib/brand-context.test.tsx` — the same two, switched through `PATCH
  /v1/settings` on the settings API mock

They drive `apps/agent/test/branding_test.dart`, `apps/farmer/test/branding_test.dart`, the
`fa008_*` goldens in both apps and the console test above. All of them render the same widget
tree twice; the only difference between the two runs is the branding object.

To add a third, add a `TenantBranding` to `TestBrands` and a row to the tables in those tests.
No app or console code should need touching — if it does, that is the bug FA-008 is about.
