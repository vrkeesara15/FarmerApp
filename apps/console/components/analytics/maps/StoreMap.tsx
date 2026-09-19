"use client";

/** C10 store map coloured by performance band (AN-001). */
import * as React from "react";
import L from "leaflet";
import type { StoreMapItem } from "@/lib/analytics";
import { BAND_COLOR, CHART } from "../charts/palette";
import { esc, fitTo, useLeafletMap } from "./base";

export interface StoreMapProps {
  stores: ReadonlyArray<StoreMapItem>;
  /** Tooltip body per store (already localised). */
  describe: (s: StoreMapItem) => string;
  onSelect?: (id: string) => void;
  attribution: string;
  label: string;
  height?: number;
}

export default function StoreMap({
  stores,
  describe,
  onSelect,
  attribution,
  label,
  height = 320,
}: StoreMapProps) {
  const ref = React.useRef<HTMLDivElement>(null);
  const map = useLeafletMap(ref, attribution);
  const select = React.useRef(onSelect);
  select.current = onSelect;

  React.useEffect(() => {
    if (!map) return;
    const layer = L.layerGroup().addTo(map);
    const pts: L.LatLngExpression[] = [];
    for (const s of stores) {
      if (s.lat === null || s.lon === null) continue;
      pts.push([s.lat, s.lon]);
      L.circleMarker([s.lat, s.lon], {
        radius: 8,
        color: CHART.surface,
        weight: 2,
        fillColor: BAND_COLOR[s.band] ?? CHART.none,
        fillOpacity: 1,
        className: `store-pin store-pin-${s.band}`,
      })
        .bindTooltip(esc(describe(s)).replace(/\n/g, "<br>"))
        .on("click", () => select.current?.(s.id))
        .addTo(layer);
    }
    fitTo(map, pts, 9);
    return () => {
      layer.remove();
    };
  }, [map, stores, describe]);

  return (
    <div
      ref={ref}
      role="region"
      aria-label={label}
      data-testid="store-map"
      className="z-0 w-full overflow-hidden rounded-card border border-border"
      style={{ height }}
    />
  );
}
