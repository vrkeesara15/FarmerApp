# TopBar

Header with tenant name (or switcher), global search, date range, notifications and profile.

Source: `apps/console/components/ds/TopBar.tsx` (tests: `TopBar.test.tsx`). Gallery: `/design`.

## Props

| Prop | Type | Notes |
|---|---|---|
| `tenantName` | `string` |  |
| `onTenantClick` | `() => void` | renders switcher trigger |
| `search / onSearchChange / onSearchSubmit` | `` |  |
| `dateRange / onDateRangeChange` | `DateRange` |  |
| `unreadNotifications` | `number` | badge, 99+ cap |
| `onNotificationsClick` | `() => void` |  |
| `user` | `{name, role?, avatarUrl?}` | initials fallback |
| `onProfileClick` | `() => void` |  |
| `actions` | `ReactNode` | e.g. ThemeToggle |

## Variants

- static tenant name
- tenant switcher

## States

- default
- with unread badge

## Accessibility

- <header>
- Notifications button aria-label includes unread count
- Profile button labelled 'Profile menu'; avatar img has empty alt
- Date range hidden below lg breakpoint (1024px check)

## Tokens used

- `color.surface`
- `color.border`
- `color.primary.container`
- `color.danger`
- `radius.input`
- `radius.pill`
- `text.console.heading`
- `text.console.small`
