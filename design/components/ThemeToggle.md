# ThemeToggle

Light/Dark switch for the console. Persists to localStorage (guarded) and sets `data-theme` on <html>.

Source: `apps/console/components/ds/ThemeToggle.tsx` (tests: `ThemeToggle.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `value` | `'light' | 'dark'` | controlled (gallery) |
| `onChange` | `(theme) => void` |  |

## Variants

- uncontrolled (persisting)
- controlled

## States

- light
- dark

## Accessibility

- aria-label 'Toggle theme', aria-pressed reflects dark
- Inline init script applies the stored theme before first paint (no flash)

## Tokens used

- `color.surface`
- `color.border`
- `color.text.secondary`
- `radius.input`

## Notes

Lives in `apps/console/components/theme/`. Theme values come from tokens.json `$extensions.theme.dark` via `scripts/tokens-to-css.mjs`.
