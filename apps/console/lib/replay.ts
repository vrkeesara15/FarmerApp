/**
 * C22 day replay playback (AN-003). Pure so it is unit-tested: the slider maps linearly onto
 * the day's time span (first to last event / point); the marker sits on the track at that
 * time (interpolated between kept points, held at the last point during a gap), and the
 * highlighted timeline item is the latest event at or before that time.
 */
import type { DayReplayOut, GapOut, ReplayPoint, TimelineEvent } from "./analytics";

export const SLIDER_MAX = 1000;

export interface Playback {
  startMs: number;
  endMs: number;
  points: Array<{ t: number; lat: number; lon: number }>;
  gaps: Array<{ start: number; end: number }>;
  /** Timeline events sorted by time with their index in the payload's timeline. */
  events: Array<{ t: number; index: number }>;
}

const ms = (iso: string) => Date.parse(iso);

export function buildPlayback(
  replay: Pick<DayReplayOut, "points" | "timeline" | "gaps">,
): Playback | null {
  const points = [...replay.points]
    .map((p: ReplayPoint) => ({ t: ms(p.ts), lat: p.lat, lon: p.lon }))
    .filter((p) => Number.isFinite(p.t))
    .sort((a, b) => a.t - b.t);
  const events = replay.timeline
    .map((e: TimelineEvent, index) => ({ t: ms(e.ts), index }))
    .filter((e) => Number.isFinite(e.t))
    .sort((a, b) => a.t - b.t || a.index - b.index);
  const times = [...points.map((p) => p.t), ...events.map((e) => e.t)];
  if (times.length === 0) return null;
  return {
    startMs: Math.min(...times),
    endMs: Math.max(...times),
    points,
    gaps: replay.gaps.map((g: GapOut) => ({ start: ms(g.start), end: ms(g.end) })),
    events,
  };
}

/** Slider value (0..SLIDER_MAX) -> epoch ms. */
export function sliderToTime(pb: Playback, value: number, max: number = SLIDER_MAX): number {
  const clamped = Math.max(0, Math.min(max, value));
  if (pb.endMs === pb.startMs) return pb.startMs;
  return Math.round(pb.startMs + ((pb.endMs - pb.startMs) * clamped) / max);
}

/** Epoch ms -> slider value. */
export function timeToSlider(pb: Playback, t: number, max: number = SLIDER_MAX): number {
  if (pb.endMs === pb.startMs) return 0;
  const v = ((t - pb.startMs) / (pb.endMs - pb.startMs)) * max;
  return Math.max(0, Math.min(max, Math.round(v)));
}

export function inGap(pb: Playback, t: number): boolean {
  return pb.gaps.some((g) => t > g.start && t < g.end);
}

export interface MarkerPosition {
  lat: number;
  lon: number;
  /** True while no location was recorded (a gap): the marker waits at the last point. */
  inGap: boolean;
}

/** Marker position at time t; null when the day has no points. */
export function positionAt(pb: Playback, t: number): MarkerPosition | null {
  const pts = pb.points;
  if (pts.length === 0) return null;
  const first = pts[0]!;
  const last = pts[pts.length - 1]!;
  const gap = inGap(pb, t);
  if (t <= first.t) return { lat: first.lat, lon: first.lon, inGap: gap };
  if (t >= last.t) return { lat: last.lat, lon: last.lon, inGap: gap };
  // Binary search for the last point at or before t.
  let lo = 0;
  let hi = pts.length - 1;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (pts[mid]!.t <= t) lo = mid;
    else hi = mid - 1;
  }
  const a = pts[lo]!;
  const b = pts[lo + 1] ?? a;
  if (gap || b.t === a.t) return { lat: a.lat, lon: a.lon, inGap: gap };
  const f = (t - a.t) / (b.t - a.t);
  return { lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f, inGap: false };
}

/** Index (into the payload's `timeline`) of the latest event at or before t; -1 before the first. */
export function activeTimelineIndex(pb: Playback, t: number): number {
  let found = -1;
  for (const e of pb.events) {
    if (e.t <= t) found = e.index;
    else break;
  }
  return found;
}

/**
 * Dashed segment for each gap: from the last kept point before it to the first one after it.
 * A gap at the very start or end of a session has only one side and draws no segment.
 */
export function gapSegments(
  replay: Pick<DayReplayOut, "points" | "gaps">,
): Array<{ gap: GapOut; from: [number, number]; to: [number, number] } | null> {
  const pts = [...replay.points].sort((a, b) => ms(a.ts) - ms(b.ts));
  return replay.gaps.map((gap) => {
    const s = ms(gap.start);
    const e = ms(gap.end);
    const before = [...pts].reverse().find((p) => ms(p.ts) <= s);
    const after = pts.find((p) => ms(p.ts) >= e);
    if (!before || !after) return null;
    return { gap, from: [before.lat, before.lon], to: [after.lat, after.lon] };
  });
}
