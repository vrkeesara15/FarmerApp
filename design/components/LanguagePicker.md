# LanguagePicker

2-column grid of large (128 dp) tiles showing the script name, English name and a speaker button.

Source: `apps/mobile/packages/core/lib/src/widgets/language_picker.dart` (exported from `package:farmerapp_core/farmerapp_core.dart`).

## Props

| Prop | Type | Notes |
|---|---|---|
| `languages` | `List<LanguageOption>` | default: te, kn, hi, mr, en |
| `selected` | `Locale?` |  |
| `onSelected` | `ValueChanged<Locale>` | required |
| `onPlayAudio` | `ValueChanged<Locale>?` | speaker button hidden when null |

## Variants

- default
- with audio

## States

- unselected
- selected (primary border + tinted container, check icon)

## Accessibility

- Tile `Semantics(button, selected, label: '<native>, <english>')`.
- Speaker button is 48 dp with tooltip and label 'Listen'.
- Native names are literal script text (not translated) so every user can find their language.
- Icons are always paired with a visible text label (NF-009).
- Colours come from `AppThemeData.palette`; Sunlight swaps to black text, 2 dp borders, no tinted containers.

## Tokens used

- `color.surface`
- `color.primary`
- `color.primary.container`
- `color.border`
- `color.text.secondary`
- `radius.card`
- `space.3`
- `text.mobile.title`
- `text.mobile.caption`
- `size.touchTargetMin`

## Tests

Golden: language_picker_{light,sunlight}.png; app tests find it on first screen

