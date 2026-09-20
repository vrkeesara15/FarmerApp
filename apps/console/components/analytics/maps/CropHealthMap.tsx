"use client";

/**
 * AN-006 crop health map: graduated markers per **district** on the existing Leaflet / OSM setup
 * (lib/map-config.ts). AN-014 — the API returns district-level cells only, so no farm location
 * or farmer identity ever reaches this map; the marker sits on the district centroid.
 */
import * as React from "react";
import L from "leaflet";
import { bandFor, CHOROPLETH_STEPS, type DistrictRollup } from "@/lib/mlops";
import { esc, fitTo, useLeafletMap } from "./base";
import { CHART } from "../charts/palette";

/** Five sequential steps of the primary hue (light to dark) plus an outbreak ring. */
const BAND_FILL = ["#E8EFE6", "#BFD9BD", "#8FC08C", "#5CA45C", "#2E7D32"] as const;

export interface CropHealthMapProps {
  districts: ReadonlyArray<DistrictRollup>;
  describe: (d: DistrictRollup) => string;
  onSelect?: (district: string) => void;
  selected?: string | null;
  attribution: string;
  label: string;
  height?: number;
}

export default function CropHealthMap({
  districts,
  describe,
  onSelect,
  selected,
  attribution,
  label,
  height = 380,
}: CropHealthMapProps) {
  const ref = React.useRef<HTMLDivElement>(null);
  const map = useLeafletMap(ref, attribution);
  const select = React.useRef(onSelect);
  select.current = onSelect;

  React.useEffect(() => {
    if (!map) return;
    const layer = L.layerGroup().addTo(map);
    const pts: L.LatLngExpression[] = [];
    const max = Math.max(0, ...districts.map((d) => d.cases));
    for (const d of districts) {
      if (d.latitude === null || d.longitude === null) continue;
      pts.push([d.latitude, d.longitude]);
      const band = bandFor(d.cases, max);
      L.circleMarker([d.latitude, d.longitude], {
        radius: 8 + (band / CHOROPLETH_STEPS) * 14,
        color: d.outbreaks > 0 ? CHART.bad : CHART.surface,
        weight: d.outbreaks > 0 ? 3 : 2,
        fillColor: BAND_FILL[Math.max(0, band - 1)] ?? BAND_FILL[0],
        fillOpacity: 0.85,
        className: `crop-health-pin crop-health-band-${band}${
          selected === d.district ? " crop-health-selected" : ""
        }`,
      })
        .bindTooltip(esc(describe(d)).replace(/\n/g, "<br>"))
        .on("click", () => select.current?.(d.district))
        .addTo(layer);
    }
    fitTo(map, pts, 8);
    return () => {
      layer.remove();
    };
  }, [map, districts, describe, selected]);

  return (
    <div
      ref={ref}
      role="region"
      aria-label={label}
      data-testid="crop-health-map"
      className="z-0 w-full overflow-hidden rounded-card border border-border"
      style={{ height }}
    />
  );
}

export { BAND_FILL };
