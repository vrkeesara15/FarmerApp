"use client";

/**
 * Evidence map (C71, VA-002): GeoJSON points and polygons from a flag's evidence bundle on
 * OpenStreetMap tiles. Leaflet is lazy-loaded (next/dynamic, client only). Kept in
 * components/flags so the flag screens do not depend on the analytics maps.
 */
import dynamic from "next/dynamic";
import { MapPinOff } from "lucide-react";
import { Skeleton } from "@/components/ds/Skeleton";
import type { GeoPoint, GeoPolygon } from "@/lib/flags";
import { useT } from "@/lib/i18n-client";

const LeafletMap = dynamic(() => import("./EvidenceMapLeaflet"), {
  ssr: false,
  loading: () => <Skeleton className="h-72 w-full" />,
});

export function EvidenceMap({ points, polygons }: { points: GeoPoint[]; polygons: GeoPolygon[] }) {
  const t = useT();
  if (points.length === 0 && polygons.length === 0)
    return (
      <p
        className="flex items-center gap-2 text-small text-text-muted"
        data-testid="evidence-map-empty"
      >
        <MapPinOff className="size-4" aria-hidden="true" />
        {t("flagDetail.map.empty")}
      </p>
    );
  return <LeafletMap points={points} polygons={polygons} />;
}
