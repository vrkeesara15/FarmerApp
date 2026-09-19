/**
 * Role-based navigation (SPEC 2.6 permissions matrix + the `/v1/analytics/*` role lists in
 * docs/prs/M4-analytics-api.md). A SideNav entry is hidden when the signed-in role cannot
 * read the screen; the screens still handle 403 from the API with an explanatory state.
 * Routes without an entry here are visible to every role (their owners add their own).
 */

export const OWNER_HOME_ROLES = [
  "owner",
  "director",
  "tenant_admin",
  "auditor",
  "cluster_head",
  "store_manager",
] as const;

export const FIELD_TEAM_ROLES = [...OWNER_HOME_ROLES, "field_officer"] as const;

/** Officer location tracks: never store managers or other officers (SPEC 2.6). */
export const REPLAY_ROLES = [
  "owner",
  "director",
  "tenant_admin",
  "auditor",
  "cluster_head",
  "field_officer",
] as const;

export const FARMER_ROLES = [...OWNER_HOME_ROLES, "field_officer"] as const;

export const STORE_ROLES = [...OWNER_HOME_ROLES, "accountant"] as const;

export const ROUTE_ROLES: Readonly<Record<string, readonly string[]>> = {
  "/home": OWNER_HOME_ROLES,
  "/field-team": FIELD_TEAM_ROLES,
  "/farmers": FARMER_ROLES,
  "/stores": STORE_ROLES,
};

/** The route entry that governs a path (`/field-team/abc` -> `/field-team`). */
function routeFor(path: string): string | undefined {
  return Object.keys(ROUTE_ROLES)
    .filter((r) => path === r || path.startsWith(`${r}/`))
    .sort((a, b) => b.length - a.length)[0];
}

/** While the session loads (role unknown) nothing is hidden, so the nav does not jump. */
export function canSeeRoute(path: string, role: string | undefined): boolean {
  if (!role) return true;
  const route = routeFor(path);
  if (!route) return true;
  return ROUTE_ROLES[route]!.includes(role);
}

export function canSeeReplay(role: string | undefined): boolean {
  return !!role && (REPLAY_ROLES as readonly string[]).includes(role);
}

export function visibleNavItems<T extends { href: string }>(
  items: ReadonlyArray<T>,
  role: string | undefined,
): T[] {
  return items.filter((i) => canSeeRoute(i.href, role));
}

/** Which AN-011 filters a role can change (the API narrows the rest to the role's scope). */
export function filterVisibility(role: string | undefined): {
  cluster: boolean;
  store: boolean;
  officer: boolean;
} {
  switch (role) {
    case "cluster_head":
      return { cluster: false, store: true, officer: true };
    case "store_manager":
      return { cluster: false, store: false, officer: true };
    case "field_officer":
      return { cluster: false, store: false, officer: false };
    default:
      return { cluster: true, store: true, officer: true };
  }
}
