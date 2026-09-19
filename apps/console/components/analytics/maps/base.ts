"use client";

/**
 * Leaflet base for the console maps (C10 store map, C22 replay, C31 farms). OpenStreetMap
 * raster tiles, no API key. Only imported from lazily loaded modules (maps/index.tsx,
 * `ssr: false`): Leaflet touches `window` at import time.
 */
import * as React from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

export const OSM_TILES = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
/** India, for an empty map. */
export const INDIA_CENTER: L.LatLngExpression = [20.6, 78.9];

export function useLeafletMap(
  ref: React.RefObject<HTMLDivElement | null>,
  attribution: string,
): L.Map | null {
  const [map, setMap] = React.useState<L.Map | null>(null);
  React.useEffect(() => {
    if (!ref.current) return;
    const m = L.map(ref.current, {
      center: INDIA_CENTER,
      zoom: 5,
      zoomControl: true,
      attributionControl: true,
      scrollWheelZoom: false,
    });
    m.attributionControl.setPrefix(false);
    L.tileLayer(OSM_TILES, { maxZoom: 18, attribution }).addTo(m);
    setMap(m);
    return () => {
      m.remove();
      setMap(null);
    };
  }, [ref, attribution]);
  return map;
}

export function fitTo(map: L.Map, latlngs: L.LatLngExpression[], maxZoom = 15): void {
  if (latlngs.length === 0) return;
  if (latlngs.length === 1) {
    map.setView(latlngs[0]!, Math.min(maxZoom, 14));
    return;
  }
  map.fitBounds(L.latLngBounds(latlngs), { padding: [24, 24], maxZoom });
}

/** Escape text placed in Leaflet tooltips (they take HTML). */
export function esc(s: string): string {
  return s.replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!,
  );
}
