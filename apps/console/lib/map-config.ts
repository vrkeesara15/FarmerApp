/**
 * One map setup for every console map (C10 / C22 / C31 analytics maps and the C71 EvidenceMap):
 * Leaflet 1.9.4 with OpenStreetMap raster tiles, no API key. `NEXT_PUBLIC_MAP_TILE_URL`
 * overrides the tile URL (e.g. a tile proxy); the attribution text is the i18n key
 * `map.attribution` ("© OpenStreetMap contributors").
 */
export const MAP_TILE_URL =
  process.env.NEXT_PUBLIC_MAP_TILE_URL || "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

/** OSM standard tiles serve zoom 0-19. */
export const MAP_MAX_ZOOM = 19;
