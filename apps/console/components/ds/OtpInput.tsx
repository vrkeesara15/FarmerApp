"use client";

import * as React from "react";
import { cn } from "@/lib/utils";
import { useT } from "@/lib/i18n-client";

export interface OtpInputProps {
  length?: number;
  value: string;
  onChange: (value: string) => void;
  /** Called when all boxes are filled. */
  onComplete?: (value: string) => void;
  error?: string;
  disabled?: boolean;
  /** Seconds before the resend link becomes active (default 30). */
  resendAfterSeconds?: number;
  onResend?: () => void;
  autoFocus?: boolean;
  className?: string;
}

export function OtpInput({
  length = 6,
  value,
  onChange,
  onComplete,
  error,
  disabled,
  resendAfterSeconds = 30,
  onResend,
  autoFocus,
  className,
}: OtpInputProps) {
  const t = useT();
  const refs = React.useRef<Array<HTMLInputElement | null>>([]);
  const [secondsLeft, setSecondsLeft] = React.useState(resendAfterSeconds);
  const errorId = React.useId();

  React.useEffect(() => {
    if (secondsLeft <= 0) return;
    const id = window.setInterval(() => setSecondsLeft((s) => Math.max(0, s - 1)), 1000);
    return () => window.clearInterval(id);
  }, [secondsLeft]);

  const digits = Array.from({ length }, (_, i) => value[i] ?? "");

  const commit = (next: string[]) => {
    const joined = next.join("");
    onChange(joined);
    if (joined.length === length && !next.includes("")) onComplete?.(joined);
  };

  const focus = (i: number) => refs.current[Math.max(0, Math.min(length - 1, i))]?.focus();

  const handleChange = (i: number, raw: string) => {
    const clean = raw.replace(/\D/g, "");
    if (!clean) {
      const next = [...digits];
      next[i] = "";
      commit(next);
      return;
    }
    const next = [...digits];
    // Paste or multi-char input: spread across boxes.
    for (let k = 0; k < clean.length && i + k < length; k++) next[i + k] = clean[k] ?? "";
    commit(next);
    focus(i + clean.length);
  };

  const handleKeyDown = (i: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Backspace" && !digits[i] && i > 0) {
      e.preventDefault();
      const next = [...digits];
      next[i - 1] = "";
      commit(next);
      focus(i - 1);
    } else if (e.key === "ArrowLeft") focus(i - 1);
    else if (e.key === "ArrowRight") focus(i + 1);
  };

  const handleResend = () => {
    onResend?.();
    setSecondsLeft(resendAfterSeconds);
  };

  return (
    <div className={cn("flex flex-col gap-2", className)}>
      <div className="flex gap-2" role="group" aria-describedby={error ? errorId : undefined}>
        {digits.map((d, i) => (
          <input
            key={i}
            ref={(el) => {
              refs.current[i] = el;
            }}
            value={d}
            onChange={(e) => handleChange(i, e.target.value)}
            onKeyDown={(e) => handleKeyDown(i, e)}
            onFocus={(e) => e.target.select()}
            disabled={disabled}
            autoFocus={autoFocus && i === 0}
            inputMode="numeric"
            autoComplete={i === 0 ? "one-time-code" : "off"}
            pattern="[0-9]*"
            maxLength={length}
            aria-label={t("otp.label", { n: i + 1 })}
            aria-invalid={error ? true : undefined}
            data-testid={`otp-${i}`}
            className={cn(
              "tnum size-12 rounded-input border border-border bg-surface text-center text-heading font-semibold text-text focus:outline-none focus:ring-2 focus:ring-primary disabled:opacity-50",
              error && "border-danger focus:ring-danger",
            )}
          />
        ))}
      </div>
      {error ? (
        <p id={errorId} role="alert" className="text-small text-danger">
          {error}
        </p>
      ) : null}
      <div className="text-small text-text-muted" aria-live="polite">
        {secondsLeft > 0 ? (
          <span data-testid="resend-timer">{t("otp.resendIn", { n: secondsLeft })}</span>
        ) : (
          <button
            type="button"
            onClick={handleResend}
            disabled={disabled}
            className="font-semibold text-primary hover:underline"
          >
            {t("otp.resend")}
          </button>
        )}
      </div>
    </div>
  );
}
