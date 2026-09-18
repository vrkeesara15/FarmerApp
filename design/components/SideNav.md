# SideNav

Collapsible left navigation for the console shell.

Source: `apps/console/components/ds/SideNav.tsx` (tests: `SideNav.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `items` | `SideNavItem[]` | href, label, icon, badge? |
| `collapsed` | `boolean` |  |
| `onCollapsedChange` | `(c) => void` |  |
| `activePath` | `string` | defaults to usePathname() |
| `header / footer` | `ReactNode` |  |

## Variants

- expanded (240px)
- collapsed (64px, icons + tooltips)

## States

- default
- active item (primary container)
- hover
- collapsed

## Accessibility

- <nav aria-label='Primary navigation'>
- aria-current=page on active link
- Collapsed items keep sr-only labels and title tooltips
- Toggle button has aria-expanded

## Tokens used

- `color.surface`
- `color.border`
- `color.background`
- `color.primary`
- `color.primary.container`
- `color.danger`
- `radius.input`
- `text.console.body`
