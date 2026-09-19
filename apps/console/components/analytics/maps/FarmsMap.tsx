"use client";

/** C31 farms map: every farm boundary as a polygon (GeoJSON from the 360 payload). */
import * as React from "react";
import L from "leaflet";
import type { Farmer360Out } from "@/lib/analytics";
import { esc, fitTo, useLeafletMap } from "./base";

export interface FarmsMapProps {
  farms: Farmer360Out["farms"];
  describe: (farm: Farmer360Out["farms"][number]) => string;
  attribution: string;
  label: string;
  height?: number;
}

export default function FarmsMap({
  farms,
  describe,
  attribution,
  label,
  height = 320,
}: FarmsMapProps) {
  const ref = React.useRef<HTMLDivElement>(null);
  const map = useLeafletMap(ref, attribution);

  React.useEffect(() => {
    if (!map) return;
    const layer = L.layerGroup().addTo(map);
    const all: L.LatLngExpression[] = [];
    for (const farm of farms) {
      const ring = farm.boundary?.coordinates[0];
      if (ring && ring.length >= 3) {
        const latlngs = ring.map(([lon, lat]) => [lat!, lon!] as L.LatLngTuple);
        all.push(...latlngs);
        L.polygon(latlngs, {
          color: "var(--color-primary)",
          weight: 2,
          fillColor: "var(--color-primary)",
          fillOpacity: 0.2,
          className: "farm-polygon",
        })
          .bindTooltip(esc(describe(farm)))
          .addTo(layer);
      } else if (farm.centroid) {
        const [lon, lat] = farm.centroid.coordinates;
        if (lat === undefined || lon === undefined) continue;
        all.push([lat, lon]);
        L.circleMarker([lat, lon], { radius: 6, color: "var(--color-primary)" })
          .bindTooltip(esc(describe(farm)))
          .addTo(layer);
      }
    }
    fitTo(map, all, 17);
    return () => {
      layer.remove();
    };
  }, [map, farms, describe]);

  return (
    <div
      ref={ref}
      role="region"
      aria-label={label}
      data-testid="farms-map"
      className="z-0 w-full overflow-hidden rounded-card border border-border"
      style={{ height }}
    />
  );
}
