"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useMutation } from "@tanstack/react-query";
import { AppButton } from "@/components/ds/AppButton";
import { AppTextField } from "@/components/ds/AppTextField";
import { OtpInput } from "@/components/ds/OtpInput";
import { toast } from "@/components/ds/Toasts";
import { ThemeToggle } from "@/components/theme/ThemeToggle";
import { ApiError, auth, session } from "@/lib/api";
import { normaliseIndianMobile } from "@/lib/format";
import { t, type MessageKey } from "@/lib/i18n";

type Step =
  | { kind: "phone" }
  | {
      kind: "otp";
      phone: string;
      phoneMasked: string;
      expiresIn: number;
      resendAfter: number;
      resendsLeft: number;
    };

const minutes = (seconds: number | undefined) => Math.max(1, Math.ceil((seconds ?? 900) / 60));

/** Map a problem+json code to a user-facing message; undefined = not a login-specific error. */
export function loginErrorMessage(err: unknown): string | undefined {
  if (!(err instanceof ApiError)) return undefined;
  const p = err.problem;
  switch (p.code) {
    case "otp_invalid":
      return p.attempts_left === undefined
        ? t("login.failed")
        : `${t("login.failed")} ${t("login.attemptsLeft", { n: p.attempts_left })}`;
    case "otp_expired":
      return t("login.expired");
    case "otp_not_found":
      return t("login.alreadyUsed");
    case "otp_locked":
      return t("login.locked", { minutes: minutes(p.retry_after) });
    case "otp_rate_limited":
      return t("login.rateLimited", { minutes: minutes(p.retry_after) });
    case "user_not_found":
      return t("login.notRegistered");
    case "user_disabled":
      return t("login.disabled");
    case "validation_error":
      return t("login.phoneInvalid");
    default:
      return undefined;
  }
}

const isLocked = (err: unknown) => err instanceof ApiError && err.problem.code === "otp_locked";

export function LoginForm() {
  const router = useRouter();
  const [step, setStep] = React.useState<Step>({ kind: "phone" });
  const [phone, setPhone] = React.useState("");
  const [phoneError, setPhoneError] = React.useState<string | undefined>();
  const [code, setCode] = React.useState("");
  const [codeError, setCodeError] = React.useState<string | undefined>();
  const [locked, setLocked] = React.useState(false);

  const request = useMutation({
    mutationFn: (p: string) => auth.sendOtp(p),
    onSuccess: (res, p) => {
      setCode("");
      setCodeError(undefined);
      setLocked(false);
      setStep({
        kind: "otp",
        phone: p,
        phoneMasked: res.phone_masked,
        expiresIn: res.expires_in,
        resendAfter: res.resend_after,
        resendsLeft: res.resends_left,
      });
      if (res.channel === "whatsapp") toast.info(t("login.sentByWhatsApp"));
    },
    onError: (err) => {
      const message = loginErrorMessage(err);
      if (!message) return toast.fromError(err);
      if (isLocked(err)) setLocked(true);
      if (step.kind === "phone") setPhoneError(message);
      else setCodeError(message);
    },
  });

  const verify = useMutation({
    mutationFn: async ({ p, c }: { p: string; c: string }) => {
      const tokens = await auth.verifyOtp(p, c);
      await session.start(tokens);
      return tokens;
    },
    onSuccess: () => {
      toast.success(t("login.success"));
      router.push("/home");
    },
    onError: (err) => {
      const message = loginErrorMessage(err);
      if (!message) return toast.fromError(err);
      if (isLocked(err)) setLocked(true);
      setCodeError(message);
      setCode("");
    },
  });

  const submitPhone = (e: React.FormEvent) => {
    e.preventDefault();
    const n = normaliseIndianMobile(phone);
    if (!n) {
      setPhoneError(t("login.phoneInvalid"));
      return;
    }
    setPhoneError(undefined);
    request.mutate(n);
  };

  const submitCode = (value: string) => {
    if (step.kind !== "otp" || locked) return;
    if (!/^\d{6}$/.test(value)) {
      setCodeError(t("login.otpInvalid"));
      return;
    }
    setCodeError(undefined);
    verify.mutate({ p: step.phone, c: value });
  };

  const onOtpSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    submitCode(code);
  };

  if (step.kind === "phone") {
    return (
      <form
        onSubmit={submitPhone}
        className="flex flex-col gap-4"
        noValidate
        data-testid="login-phone-step"
      >
        <AppTextField
          label={t("login.phoneLabel")}
          helper={t("login.phoneHelper")}
          error={phoneError}
          phone
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          maxLength={14}
          autoFocus
          name="phone"
        />
        <AppButton type="submit" size="L" fullWidth loading={request.isPending}>
          {t("login.sendOtp")}
        </AppButton>
        <AppButton
          type="button"
          variant="tertiary"
          fullWidth
          onClick={() => toast.info(t("login.ssoSoon"))}
        >
          {t("login.sso")}
        </AppButton>
        <p className="text-center text-small text-text-muted">{t("login.devHint")}</p>
        <div className="flex justify-center">
          <ThemeToggle />
        </div>
      </form>
    );
  }

  const busy = verify.isPending || request.isPending;
  const resendsKey: MessageKey =
    step.resendsLeft === 1 ? "login.resendsLeftOne" : "login.resendsLeft";
  return (
    <form
      onSubmit={onOtpSubmit}
      className="flex flex-col gap-4"
      noValidate
      data-testid="login-otp-step"
      data-locked={locked ? "true" : undefined}
    >
      <div>
        <h2 className="text-heading">{t("login.otpTitle")}</h2>
        <p className="tnum text-body text-text-secondary">
          {t("login.otpSentTo", { phone: step.phoneMasked })}
        </p>
        <p className="text-small text-text-muted" data-testid="resends-left">
          {t(resendsKey, { n: step.resendsLeft })}
        </p>
      </div>
      <OtpInput
        value={code}
        onChange={setCode}
        onComplete={(v) => submitCode(v)}
        error={codeError}
        disabled={busy || locked}
        resendAfterSeconds={Math.min(step.resendAfter, step.expiresIn)}
        onResend={() => request.mutate(step.phone)}
        autoFocus
      />
      <AppButton type="submit" size="L" fullWidth loading={verify.isPending} disabled={locked}>
        {t("login.verify")}
      </AppButton>
      <AppButton
        type="button"
        variant="tertiary"
        fullWidth
        onClick={() => {
          setLocked(false);
          setCodeError(undefined);
          setStep({ kind: "phone" });
        }}
        disabled={verify.isPending}
      >
        {t("login.changeNumber")}
      </AppButton>
    </form>
  );
}
