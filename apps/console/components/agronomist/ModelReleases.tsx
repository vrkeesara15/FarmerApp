"use client";

/**
 * DX-012 model releases: the candidate on-device models with their DX-011 evaluation numbers,
 * the currently approved version, and the approve / reject gate. A decision needs step-up
 * (SEC-028) and is audited; a candidate without an evaluation run cannot be approved (the API
 * answers 409 `evaluation_missing`, and the button is disabled here too).
 */
import * as React from "react";
import { CheckCircle2, ShieldCheck, XCircle } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { DataTable, type DataTableColumn } from "@/components/ds/DataTable";
import { Dialog } from "@/components/ds/Dialog";
import { toast } from "@/components/ds/Toasts";
import { Badge } from "@/components/ui/badge";
import {
  PageHeader,
  QueryError,
  RoleGate,
  SessionGate,
  TextAreaField,
} from "@/components/admin/common";
import { StepUpProvider, isStepUpCancelled, useStepUp } from "@/components/admin/StepUp";
import { Note } from "@/components/growth/common";
import { formatDateTimeIst, formatNumber, formatPercent } from "@/lib/format";
import { useCurrentModel, useDecideRelease, useModelReleases } from "@/lib/hooks/mlops";
import { RELEASE_DECIDE_ROLES, RELEASE_READ_ROLES, type ModelRelease } from "@/lib/mlops";
import { useT } from "@/lib/i18n-client";
import { problemMessage } from "@/lib/problem-messages";
import { useSession } from "@/lib/session-context";
import { AgronomistSubNav } from "./common";

const STATUS_VARIANT: Record<string, "default" | "success" | "danger" | "neutral"> = {
  candidate: "default",
  approved: "success",
  rejected: "danger",
  retired: "neutral",
};

export function ModelReleases() {
  const t = useT();
  return (
    <div className="flex flex-col gap-4" data-screen="C62-models">
      <PageHeader title={t("models.title")} subtitle={t("models.subtitle")} />
      <AgronomistSubNav />
      <SessionGate>
        <RoleGate roles={RELEASE_READ_ROLES}>
          <StepUpProvider>
            <Releases />
          </StepUpProvider>
        </RoleGate>
      </SessionGate>
    </div>
  );
}

type Decision = "approve" | "reject" | "retire";

function Releases() {
  const t = useT();
  const { role } = useSession();
  const stepUp = useStepUp();
  const releases = useModelReleases();
  const current = useCurrentModel();
  const decide = useDecideRelease();
  const [pending, setPending] = React.useState<{
    release: ModelRelease;
    decision: Decision;
  } | null>(null);
  const [note, setNote] = React.useState("");
  const [error, setError] = React.useState<string | undefined>();
  const canDecide = !!role && RELEASE_DECIDE_ROLES.includes(role);
  const na = t("common.none");

  const columns: ReadonlyArray<DataTableColumn<ModelRelease>> = [
    {
      id: "version",
      header: t("models.column.version"),
      accessor: (r) => r.model_version,
      cell: (r) => <span className="tnum font-semibold">{r.model_version}</span>,
    },
    {
      id: "status",
      header: t("models.column.status"),
      cell: (r) => (
        <Badge variant={STATUS_VARIANT[r.status] ?? "default"} data-testid="release-status">
          {t(`models.status.${r.status}` as "models.status.candidate")}
        </Badge>
      ),
    },
    {
      id: "created",
      header: t("models.column.created"),
      accessor: (r) => r.created_at,
      cell: (r) => formatDateTimeIst(r.created_at),
    },
    {
      id: "cases",
      header: t("models.column.cases"),
      numeric: true,
      cell: (r) => (r.evaluation ? formatNumber(r.evaluation.cases) : na),
    },
    {
      id: "top1",
      header: t("models.column.top1"),
      numeric: true,
      cell: (r) =>
        r.evaluation?.top1_accuracy != null ? formatPercent(r.evaluation.top1_accuracy, 1) : na,
    },
    {
      id: "delta",
      header: t("models.column.delta"),
      numeric: true,
      cell: (r) =>
        r.top1_delta_points === null
          ? na
          : t("quality.evaluation.deltaPoints", { n: r.top1_delta_points.toFixed(1) }),
    },
    {
      id: "decision",
      header: t("models.column.decision"),
      cell: (r) =>
        r.status === "candidate" ? (
          canDecide ? (
            <span className="flex flex-wrap gap-2">
              <AppButton
                disabled={!r.evaluation}
                onClick={() => {
                  setNote("");
                  setError(undefined);
                  setPending({ release: r, decision: "approve" });
                }}
                data-testid={`approve-${r.model_version}`}
              >
                <CheckCircle2 className="size-4" aria-hidden="true" />
                {t("models.approve")}
              </AppButton>
              <AppButton
                variant="tertiary"
                onClick={() => {
                  setNote("");
                  setError(undefined);
                  setPending({ release: r, decision: "reject" });
                }}
              >
                <XCircle className="size-4" aria-hidden="true" />
                {t("models.reject")}
              </AppButton>
            </span>
          ) : (
            na
          )
        ) : (
          (r.decision_note ?? na)
        ),
    },
  ];

  const run = () => {
    if (!pending) return;
    setError(undefined);
    void stepUp
      .run((headers) =>
        decide.mutateAsync({
          id: pending.release.id,
          decision: pending.decision,
          note: note.trim() || null,
          headers,
        }),
      )
      .then(() => {
        toast.success(
          t(
            `models.toast.${pending.decision === "approve" ? "approved" : pending.decision === "reject" ? "rejected" : "retired"}`,
          ),
        );
        setPending(null);
      })
      .catch((err: unknown) => {
        if (isStepUpCancelled(err)) return;
        setError(problemMessage(err, t));
      });
  };

  const candidateWithoutEval = (releases.data?.items ?? []).some(
    (r) => r.status === "candidate" && !r.evaluation,
  );

  return (
    <>
      <section
        className="flex flex-col gap-1 rounded-card border border-border bg-surface p-4"
        data-testid="current-model"
      >
        <h2 className="text-heading font-semibold">{t("models.current")}</h2>
        {current.isLoading ? (
          <p className="text-small text-text-muted">{t("common.loading")}</p>
        ) : current.data ? (
          <>
            <p className="tnum text-body font-semibold">
              {t("models.currentRow", {
                name: current.data.model_name,
                version: current.data.model_version,
              })}
            </p>
            <p className="text-small text-text-muted">
              {current.data.approved_at
                ? t("models.approvedAt", { when: formatDateTimeIst(current.data.approved_at) })
                : na}
            </p>
            <p className="break-all text-small text-text-muted">
              {t("models.sha")}: <code>{current.data.sha256}</code>
            </p>
          </>
        ) : (
          <p className="text-body text-text-secondary" data-testid="no-current-model">
            {t("models.currentNone")}
          </p>
        )}
      </section>

      {candidateWithoutEval ? <Note tone="warning">{t("models.noEvaluation")}</Note> : null}

      {releases.error ? (
        <QueryError error={releases.error} onRetry={() => void releases.refetch()} />
      ) : (
        <DataTable
          columns={columns}
          rows={releases.data?.items ?? []}
          rowKey={(r) => r.id}
          loading={releases.isLoading}
          caption={t("models.title")}
          emptyTitle={t("models.emptyTitle")}
          emptyHelp={t("models.emptyHelp")}
        />
      )}

      <Dialog
        open={!!pending}
        onOpenChange={(o) => {
          if (!o) setPending(null);
        }}
        title={
          pending
            ? t(
                pending.decision === "approve"
                  ? "models.approveTitle"
                  : pending.decision === "reject"
                    ? "models.rejectTitle"
                    : "models.retireTitle",
                { version: pending.release.model_version },
              )
            : t("models.title")
        }
        description={
          pending
            ? t(
                pending.decision === "approve"
                  ? "models.approveHelp"
                  : pending.decision === "reject"
                    ? "models.rejectHelp"
                    : "models.retireHelp",
              )
            : undefined
        }
        confirmLabel={
          pending
            ? t(
                pending.decision === "approve"
                  ? "models.approve"
                  : pending.decision === "reject"
                    ? "models.reject"
                    : "models.retire",
              )
            : undefined
        }
        destructive={pending?.decision !== "approve"}
        loading={decide.isPending}
        error={error}
        onConfirm={run}
      >
        <div className="flex flex-col gap-3">
          <TextAreaField
            label={t("models.note")}
            placeholder={t("models.notePlaceholder")}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            rows={3}
          />
          <p className="flex items-start gap-2 text-small text-text-secondary">
            <ShieldCheck className="mt-0.5 size-4 shrink-0 text-primary" aria-hidden="true" />
            {t("stepUp.why")}
          </p>
        </div>
      </Dialog>
    </>
  );
}
