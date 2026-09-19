"use client";

/**
 * C22 day replay map (AN-003): track (solid, split at gaps), gap segments dashed with the
 * reason in a tooltip, stops, visit pins coloured by status, and the playback marker.
 */
import * as React from "react";
import L from "leaflet";
import type { DayReplayOut } from "@/lib/analytics";
import { gapSegments, type MarkerPosition } from "@/lib/replay";
import { CHART, VISIT_COLOR } from "../charts/palette";
import { esc, fitTo, useLeafletMap } from "./base";

export interface ReplayMapProps {
  replay: DayReplayOut;
  position: MarkerPosition | null;
  activeVisitId?: string | null;
  onSelectVisit?: (id: string) => void;
  gapLabel: (reason: string | null, durationS: number) => string;
  visitLabel: (v: DayReplayOut["visits"][number]) => string;
  stopLabel: (durationS: number) => string;
  attribution: string;
  label: string;
  height?: number;
}

export default function ReplayMap({
  replay,
  position,
  activeVisitId,
  onSelectVisit,
  gapLabel,
  visitLabel,
  stopLabel,
  attribution,
  label,
  height = 480,
}: ReplayMapProps) {
  const ref = React.useRef<HTMLDivElement>(null);
  const map = useLeafletMap(ref, attribution);
  const marker = React.useRef<L.CircleMarker | null>(null);
  const pins = React.useRef(new Map<string, L.CircleMarker>());
  const select = React.useRef(onSelectVisit);
  select.current = onSelectVisit;

  React.useEffect(() => {
    if (!map) return;
    const layer = L.layerGroup().addTo(map);
    const all: L.LatLngExpression[] = [];
    for (const line of replay.track.coordinates) {
      const latlngs = line.map(([lon, lat]) => [lat!, lon!] as L.LatLngTuple);
      all.push(...latlngs);
      L.polyline(latlngs, {
        color: CHART.text,
        weight: 3,
        opacity: 0.8,
        className: "replay-track",
      }).addTo(layer);
    }
    for (const seg of gapSegments(replay)) {
      if (!seg) continue;
      L.polyline([seg.from, seg.to], {
        color: "var(--color-danger)",
        weight: 3,
        dashArray: "6 6",
        className: "replay-gap",
      })
        .bindTooltip(esc(gapLabel(seg.gap.reason, seg.gap.duration_s)), { sticky: true })
        .addTo(layer);
    }
    for (const s of replay.stops) {
      L.circleMarker([s.lat, s.lon], {
        radius: 6,
        color: CHART.surface,
        weight: 2,
        fillColor: "var(--color-info)",
        fillOpacity: 1,
        className: "replay-stop",
      })
        .bindTooltip(esc(stopLabel(s.duration_s)))
        .addTo(layer);
    }
    pins.current.clear();
    for (const v of replay.visits) {
      all.push([v.lat, v.lon]);
      const pin = L.circleMarker([v.lat, v.lon], {
        radius: 9,
        color: CHART.surface,
        weight: 2,
        fillColor: VISIT_COLOR[v.colour] ?? CHART.none,
        fillOpacity: 1,
        className: `replay-visit replay-visit-${v.status}`,
      })
        .bindTooltip(esc(visitLabel(v)))
        .on("click", () => select.current?.(v.id))
        .addTo(layer);
      pins.current.set(v.id, pin);
    }
    fitTo(map, all, 16);
    return () => {
      layer.remove();
    };
  }, [map, replay, gapLabel, visitLabel, stopLabel]);

  React.useEffect(() => {
    if (!map) return;
    if (!position) {
      marker.current?.remove();
      marker.current = null;
      return;
    }
    if (!marker.current) {
      marker.current = L.circleMarker([position.lat, position.lon], {
        radius: 7,
        color: CHART.surface,
        weight: 3,
        fillColor: "var(--color-primary)",
        fillOpacity: 1,
        className: "replay-marker",
      }).addTo(map);
    }
    marker.current.setLatLng([position.lat, position.lon]);
    marker.current.setStyle({ fillOpacity: position.inGap ? 0.35 : 1 });
    marker.current.bringToFront();
  }, [map, position]);

  React.useEffect(() => {
    for (const [id, pin] of pins.current)
      pin.setStyle({ weight: id === activeVisitId ? 4 : 2, radius: id === activeVisitId ? 11 : 9 });
  }, [activeVisitId, replay]);

  return (
    <div
      ref={ref}
      role="region"
      aria-label={label}
      data-testid="replay-map"
      className="z-0 w-full overflow-hidden rounded-card border border-border"
      style={{ height }}
    />
  );
}
