"use client";

/** C60 photo gallery: thumbnails from the signed URLs, click to open with zoom (1x-4x). */
import * as React from "react";
import { ImageOff, Minus, Plus, RotateCcw } from "lucide-react";
import { AppButton } from "@/components/ds/AppButton";
import { Dialog } from "@/components/ds/Dialog";
import type { DiagnosisPhoto } from "@/lib/diagnosis";
import { useT } from "@/lib/i18n-client";

const ZOOMS = [1, 1.5, 2, 3, 4] as const;

export function PhotoGallery({ photos }: { photos: ReadonlyArray<DiagnosisPhoto> }) {
  const t = useT();
  const [open, setOpen] = React.useState<number | null>(null);
  const [zoom, setZoom] = React.useState(0);
  const current = open === null ? null : photos[open];
  const show = (i: number) => {
    setZoom(0);
    setOpen(i);
  };
  return (
    <section
      className="flex flex-col gap-2"
      aria-labelledby="photos-heading"
      data-testid="photo-gallery"
    >
      <h3 id="photos-heading" className="text-body font-semibold">
        {t("review.photos")}
      </h3>
      <div className="flex flex-wrap gap-2">
        {photos.map((p, i) => (
          <button
            key={p.blob_uri}
            type="button"
            onClick={() => show(i)}
            aria-label={t("review.openPhoto", { n: i + 1 })}
            className="overflow-hidden rounded-card border border-border focus:outline-none focus:ring-2 focus:ring-primary"
          >
            {p.signed_url ? (
              // eslint-disable-next-line @next/next/no-img-element -- short-lived signed URLs
              <img
                src={p.signed_url}
                alt={t("review.photoAlt", { n: i + 1 })}
                className="h-32 w-44 object-cover"
              />
            ) : (
              <span className="flex h-32 w-44 items-center justify-center bg-background text-text-muted">
                <ImageOff className="size-6" aria-hidden="true" />
              </span>
            )}
          </button>
        ))}
      </div>
      <Dialog
        open={open !== null}
        onOpenChange={(o) => !o && setOpen(null)}
        title={t("review.photoAlt", { n: (open ?? 0) + 1 })}
        cancelLabel={t("common.close")}
        className="max-w-4xl"
      >
        <div className="flex items-center gap-2" data-testid="photo-zoom-controls">
          <AppButton
            variant="secondary"
            size="M"
            aria-label={t("review.zoomOut")}
            icon={<Minus aria-hidden="true" />}
            disabled={zoom === 0}
            onClick={() => setZoom((z) => Math.max(0, z - 1))}
          />
          <span className="tnum w-14 text-center text-small" data-testid="zoom-level">
            {t("review.zoomLevel", { n: Math.round(ZOOMS[zoom]! * 100) })}
          </span>
          <AppButton
            variant="secondary"
            size="M"
            aria-label={t("review.zoomIn")}
            icon={<Plus aria-hidden="true" />}
            disabled={zoom === ZOOMS.length - 1}
            onClick={() => setZoom((z) => Math.min(ZOOMS.length - 1, z + 1))}
          />
          <AppButton
            variant="tertiary"
            size="M"
            aria-label={t("review.zoomReset")}
            icon={<RotateCcw aria-hidden="true" />}
            onClick={() => setZoom(0)}
          />
        </div>
        <div className="max-h-[60vh] overflow-auto rounded-card border border-border bg-background">
          {current?.signed_url ? (
            // eslint-disable-next-line @next/next/no-img-element -- short-lived signed URLs
            <img
              src={current.signed_url}
              alt={t("review.photoAlt", { n: (open ?? 0) + 1 })}
              style={{ width: `${ZOOMS[zoom]! * 100}%`, maxWidth: "none" }}
              className="block"
            />
          ) : null}
        </div>
      </Dialog>
    </section>
  );
}
