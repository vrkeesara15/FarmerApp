"use client";

/**
 * SEC-028 step-up dialog and hook. `useStepUp().run(call)` runs an admin call; when the API
 * answers 401 `step_up_required` it opens this dialog, sends a code to the admin's own phone,
 * verifies it and retries the call with `X-Step-Up-Token`. The token is held in memory by
 * lib/step-up.ts only; closing the dialog rejects with `StepUpCancelledError`.
 */
import * as React from "react";
import { ShieldCheck } from "lucide-react";
import { Dialog } from "@/components/ds/Dialog";
import { OtpInput } from "@/components/ds/OtpInput";
import { ApiError, type OtpSendResponse } from "@/lib/api";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { StepUpCancelledError, runWithStepUp, stepUpApi } from "@/lib/step-up";

type Headers = Record<string, string>;

interface StepUpContextValue {
  /** Open the dialog; resolves true once verified, false when cancelled. */
  authenticate: () => Promise<boolean>;
}

const StepUpContext = React.createContext<StepUpContextValue | null>(null);

export function StepUpProvider({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = React.useState(false);
  const pending = React.useRef<((ok: boolean) => void) | null>(null);

  const authenticate = React.useCallback(
    () =>
      new Promise<boolean>((resolve) => {
        pending.current?.(false);
        pending.current = resolve;
        setOpen(true);
      }),
    [],
  );

  const finish = React.useCallback((ok: boolean) => {
    const resolve = pending.current;
    pending.current = null;
    setOpen(false);
    resolve?.(ok);
  }, []);

  const value = React.useMemo(() => ({ authenticate }), [authenticate]);
  return (
    <StepUpContext.Provider value={value}>
      {children}
      {open ? <StepUpDialog onDone={finish} /> : null}
    </StepUpContext.Provider>
  );
}

export interface StepUpRunner {
  /** Run an admin call, stepping up and retrying once on 401 `step_up_required`. */
  run: <T>(call: (headers: Headers) => Promise<T>) => Promise<T>;
}

export function useStepUp(): StepUpRunner {
  const ctx = React.useContext(StepUpContext);
  if (!ctx) throw new Error("useStepUp must be used inside <StepUpProvider>");
  const { authenticate } = ctx;
  return React.useMemo(
    () => ({ run: (call) => runWithStepUp(call, authenticate) }),
    [authenticate],
  );
}

export function isStepUpCancelled(err: unknown): boolean {
  return err instanceof StepUpCancelledError;
}

function StepUpDialog({ onDone }: { onDone: (ok: boolean) => void }) {
  const t = useT();
  const [sent, setSent] = React.useState<OtpSendResponse | null>(null);
  const [code, setCode] = React.useState("");
  const [error, setError] = React.useState<string | undefined>();
  const [busy, setBusy] = React.useState(false);
  const started = React.useRef(false);

  const send = React.useCallback(async () => {
    setError(undefined);
    try {
      setSent(await stepUpApi.send());
    } catch (err) {
      setError(problemMessage(err, t));
    }
  }, [t]);

  React.useEffect(() => {
    if (started.current) return;
    started.current = true;
    void send();
  }, [send]);

  const verify = async (value = code) => {
    if (!/^\d{6}$/.test(value)) {
      setError(t("stepUp.codeInvalid"));
      return;
    }
    setBusy(true);
    setError(undefined);
    try {
      await stepUpApi.verify(value);
      onDone(true);
    } catch (err) {
      const left =
        err instanceof ApiError && typeof err.problem.attempts_left === "number"
          ? ` ${t("stepUp.attemptsLeft", { n: err.problem.attempts_left })}`
          : "";
      setError(`${problemMessage(err, t)}${left}`);
      setCode("");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog
      open
      onOpenChange={(o) => {
        if (!o) onDone(false);
      }}
      title={t("stepUp.title")}
      description={sent ? t("stepUp.sentTo", { phone: sent.phone_masked }) : t("stepUp.sending")}
      confirmLabel={t("stepUp.verify")}
      onConfirm={() => void verify()}
      loading={busy}
      error={error}
    >
      <div className="flex flex-col gap-3" data-testid="step-up-dialog">
        <p className="flex items-start gap-2 text-small text-text-secondary">
          <ShieldCheck className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden="true" />
          {t("stepUp.why")}
        </p>
        <OtpInput
          value={code}
          onChange={setCode}
          onComplete={(v) => void verify(v)}
          disabled={busy || !sent}
          resendAfterSeconds={sent?.resend_after ?? 30}
          onResend={() => void send()}
          autoFocus
        />
      </div>
    </Dialog>
  );
}
