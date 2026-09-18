"use client";

/**
 * Console session (FA-001 / SEC-020). The access token lives in memory only, so after a full
 * page load the provider restores it from the httpOnly refresh cookie (`session.refresh()`)
 * and exposes the signed-in user and role. Data hooks wait for `status === "authenticated"`.
 */
import * as React from "react";
import { getAuthToken, getCurrentUser, session, type AuthUser } from "./api";

export type SessionStatus = "loading" | "authenticated" | "anonymous";

export interface SessionState {
  status: SessionStatus;
  user: AuthUser | null;
  role: string | undefined;
  /** Re-read the session (e.g. after a 401 elsewhere). */
  reload: () => Promise<void>;
  signOut: () => Promise<void>;
}

const SessionContext = React.createContext<SessionState | null>(null);

function initialState(): { status: SessionStatus; user: AuthUser | null } {
  const user = getCurrentUser();
  return getAuthToken() && user
    ? { status: "authenticated", user }
    : { status: "loading", user: null };
}

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = React.useState(initialState);

  const reload = React.useCallback(async () => {
    const res = await session.refresh();
    setState(
      res ? { status: "authenticated", user: res.user } : { status: "anonymous", user: null },
    );
  }, []);

  React.useEffect(() => {
    if (state.status === "loading") void reload();
  }, [state.status, reload]);

  const signOut = React.useCallback(async () => {
    await session.end();
    setState({ status: "anonymous", user: null });
  }, []);

  const value = React.useMemo<SessionState>(
    () => ({ ...state, role: state.user?.role, reload, signOut }),
    [state, reload, signOut],
  );
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

/** The current session; outside a provider it reports `anonymous` (tests, gallery). */
export function useSession(): SessionState {
  const ctx = React.useContext(SessionContext);
  if (ctx) return ctx;
  return {
    status: "anonymous",
    user: null,
    role: undefined,
    reload: async () => undefined,
    signOut: async () => undefined,
  };
}
