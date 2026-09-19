"use client";

/**
 * Leaflet renderer for EvidenceMap (loaded lazily by ./EvidenceMap.tsx so Leaflet never enters
 * the main bundle). OpenStreetMap raster tiles (override with NEXT_PUBLIC_MAP_TILE_URL);
 * points are vector circle markers (no marker image assets), polygons outline farms.
 */
import * as React from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import type { GeoPoint, GeoPolygon } from "@/lib/flags";
import { useT } from "@/lib/i18n-client";

const TILE_URL =
  process.env.NEXT_PUBLIC_MAP_TILE_URL ?? "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

function cssVar(name: string, fallback: string): string {
  if (typeof window === "undefined") return fallback;
  const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return v || fallback;
}

export default function EvidenceMapLeaflet({
  points,
  polygons,
}: {
  points: GeoPoint[];
  polygons: GeoPolygon[];
}) {
  const t = useT();
  const ref = React.useRef<HTMLDivElement>(null);

  React.useEffect(() => {
    if (!ref.current) return;
    const map = L.map(ref.current, { scrollWheelZoom: false, attributionControl: true });
    L.tileLayer(TILE_URL, {
      maxZoom: 19,
      attribution: "&copy; OpenStreetMap contributors",
    }).addTo(map);
    const primary = cssVar("--color-primary", "#1F6B3A");
    const danger = cssVar("--color-danger", "#C62828");
    const bounds = L.latLngBounds([]);
    polygons.forEach((p, i) => {
      const rings = p.coordinates.map((ring) => ring.map(([lng, lat]) => L.latLng(lat, lng)));
      const layer = L.polygon(rings, { color: primary, weight: 2, fillOpacity: 0.15 }).addTo(map);
      layer.bindTooltip(p.label ?? t("flagDetail.map.polygon", { n: i + 1 }));
      bounds.extend(layer.getBounds());
    });
    points.forEach((p, i) => {
      const [lng, lat] = p.coordinates;
      const marker = L.circleMarker([lat, lng], {
        radius: 7,
        color: danger,
        weight: 2,
        fillColor: danger,
        fillOpacity: 0.6,
        className: "evidence-point",
      }).addTo(map);
      marker.bindTooltip(p.label ?? t("flagDetail.map.point", { n: i + 1 }));
      bounds.extend([lat, lng]);
    });
    if (bounds.isValid()) map.fitBounds(bounds, { padding: [24, 24], maxZoom: 17 });
    else map.setView([17.97, 79.59], 10);
    return () => {
      map.remove();
    };
  }, [points, polygons, t]);

  return (
    <div
      ref={ref}
      className="h-72 w-full overflow-hidden rounded-card border border-border"
      role="img"
      aria-label={t("flagDetail.map.label", { points: points.length, polygons: polygons.length })}
      data-testid="evidence-map"
    />
  );
}
