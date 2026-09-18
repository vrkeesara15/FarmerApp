# AppButton

Primary action button for the console. Maps 1:1 to the Flutter AppButton.

Source: `apps/console/components/ds/AppButton.tsx` (tests: `AppButton.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `variant` | `'primary' | 'secondary' | 'tertiary' | 'destructive'` | default primary |
| `size` | `'L' | 'M'` | L = 48px (touch target), M = 40px |
| `icon` | `ReactNode` | leading 24px outlined icon (lucide) |
| `loading` | `boolean` | spinner, aria-busy, disabled |
| `fullWidth` | `boolean` | stretch to container |
| `disabled` | `boolean` |  |
| `...ButtonHTMLAttributes` | `` | type, onClick, etc. |

## Variants

- primary: filled Leaf
- secondary: outlined Leaf on surface
- tertiary: text only
- destructive: filled danger

## States

- default
- hover (primary.hover)
- focus-visible ring
- disabled (50% opacity, no pointer)
- loading (spinner replaces icon, disabled, aria-busy)

## Accessibility

- Native <button>; keyboard and screen-reader friendly
- Loading sets aria-busy=true and disables the control
- Icons are aria-hidden; always pair with a text label
- Focus ring uses color.primary with 2px offset

## Tokens used

- `color.primary`
- `color.primary.hover`
- `color.primary.container`
- `color.primary.on`
- `color.danger`
- `color.surface`
- `radius.input`
- `size.touchTargetMin`
- `text.console.body`
- `font.weight.semibold`

## Notes

Console L is 48px rather than the mobile 56px primary-button height (size.primaryButtonHeight is mobile-only).

## Flutter

Primary/secondary/tertiary/destructive button; L = 56 dp full-width bottom action, M = 48 dp inline.

Source: `apps/mobile/packages/core/lib/src/widgets/app_button.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

### Props

| Prop | Type | Notes |
|---|---|---|
| `label` | `String` | required; never icon-only |
| `onPressed` | `VoidCallback?` | null disables |
| `variant` | `AppButtonVariant` | primary | secondary | tertiary | destructive |
| `size` | `AppButtonSize` | large (56 dp) | medium (48 dp) |
| `icon` | `IconData?` | leading 24 dp outlined icon |
| `loading` | `bool` | spinner + 'Loading' label, disabled |
| `expand` | `bool` | stretch to parent width (default true) |

### Variants

- primary: filled color.primary / on-primary text
- secondary: surface with primary border + text
- tertiary: text only
- destructive: filled color.status.danger

### States

- default
- pressed (primary.hover / tinted container)
- disabled (muted text, border-coloured fill)
- loading

### Accessibility

- `Semantics(button, enabled, label)`; loading prefixes the label with 'Loading'.
- Tap target padded to 48 dp minimum.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

### Tokens used

- `color.primary`
- `color.primary.hover`
- `color.primary.container`
- `color.primary.on`
- `color.status.danger`
- `color.text.muted`
- `color.border`
- `radius.card`
- `size.primaryButtonHeight`
- `size.touchTargetMin`
- `space.2`
- `space.4`
- `text.mobile.body`
- `text.mobile.label`

### Tests

Golden: app_button_{light,sunlight}.png
