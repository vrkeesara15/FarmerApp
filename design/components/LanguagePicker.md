# LanguagePicker

2-column grid of large (144 dp) tiles showing the script name, the language's English name in the current UI language, and a speaker button labelled "Listen" in the tile's own language (so every tile is readable by its own speakers before any language is chosen).

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
- Speaker button is a 48 dp `TextButton.icon` (speaker icon + visible "Listen" text in that language, NF-009); semantics label `'<Listen> <native>'`.
- Audio playback itself arrives with the farmer audio assets (FM-001 / NF-009); the button is always present so the layout does not change later.
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

Golden: language_picker_{light,sunlight}.png; `test/widgets/language_picker_test.dart` renders it under all five locales; app tests find it on the first screen and switch the language live (FA-004).

