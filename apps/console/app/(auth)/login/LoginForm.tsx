"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useMutation } from "@tanstack/react-query";
import { AppButton } from "@/components/ds/AppButton";
import { AppTextField } from "@/components/ds/AppTextField";
import { OtpInput } from "@/components/ds/OtpInput";
import { toast } from "@/components/ds/Toasts";
import { ThemeToggle } from "@/components/theme/ThemeToggle";
import { ApiError, auth, setAuthToken } from "@/lib/api";
import { normaliseIndianMobile } from "@/lib/format";
import { t } from "@/lib/i18n";

type Step =
  | { kind: "phone" }
  | { kind: "otp"; phone: string; requestId: string; expiresInSeconds: number };

export function LoginForm() {
  const router = useRouter();
  const [step, setStep] = React.useState<Step>({ kind: "phone" });
  const [phone, setPhone] = React.useState("");
  const [phoneError, setPhoneError] = React.useState<string | undefined>();
  const [code, setCode] = React.useState("");
  const [codeError, setCodeError] = React.useState<string | undefined>();

  const request = useMutation({
    mutationFn: (p: string) => auth.requestOtp(p),
    onSuccess: (res, p) => {
      setCode("");
      setCodeError(undefined);
      setStep({
        kind: "otp",
        phone: p,
        requestId: res.requestId,
        expiresInSeconds: res.expiresInSeconds,
      });
    },
    onError: (err) => {
      if (err instanceof ApiError && err.problem.errors?.phone)
        setPhoneError(t("login.phoneInvalid"));
      else toast.fromError(err);
    },
  });

  const verify = useMutation({
    mutationFn: ({ requestId, c }: { requestId: string; c: string }) =>
      auth.verifyOtp(requestId, c),
    onSuccess: (res) => {
      setAuthToken(res.accessToken);
      toast.success(t("login.success"));
      router.push("/home");
    },
    onError: (err) => {
      setCodeError(err instanceof ApiError && err.status === 401 ? t("login.failed") : undefined);
      if (!(err instanceof ApiError && err.status === 401)) toast.fromError(err);
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
    if (step.kind !== "otp") return;
    if (!/^\d{6}$/.test(value)) {
      setCodeError(t("login.otpInvalid"));
      return;
    }
    setCodeError(undefined);
    verify.mutate({ requestId: step.requestId, c: value });
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

  return (
    <form
      onSubmit={onOtpSubmit}
      className="flex flex-col gap-4"
      noValidate
      data-testid="login-otp-step"
    >
      <div>
        <h2 className="text-heading">{t("login.otpTitle")}</h2>
        <p className="tnum text-body text-text-secondary">
          {t("login.otpSentTo", { phone: step.phone })}
        </p>
      </div>
      <OtpInput
        value={code}
        onChange={setCode}
        onComplete={(v) => submitCode(v)}
        error={codeError}
        disabled={verify.isPending}
        resendAfterSeconds={Math.min(30, step.expiresInSeconds)}
        onResend={() => request.mutate(step.phone)}
        autoFocus
      />
      <AppButton type="submit" size="L" fullWidth loading={verify.isPending}>
        {t("login.verify")}
      </AppButton>
      <AppButton
        type="button"
        variant="tertiary"
        fullWidth
        onClick={() => setStep({ kind: "phone" })}
        disabled={verify.isPending}
      >
        {t("login.changeNumber")}
      </AppButton>
    </form>
  );
}
