import { describe, expect, it } from "vitest";
import type { DayReplayOut } from "./analytics";
import {
  SLIDER_MAX,
  activeTimelineIndex,
  buildPlayback,
  gapSegments,
  positionAt,
  sliderToTime,
  timeToSlider,
} from "./replay";

// One hand-built day (UTC): points 09:00 -> 09:30 along a straight line, a gap 09:30 -> 10:30
// (no points), then 10:30 -> 11:00. Timeline events at known times.
const ts = (hhmm: string) => `2026-09-10T${hhmm}:00Z`;
const replay: Pick<DayReplayOut, "points" | "timeline" | "gaps"> = {
  points: [
    { ts: ts("09:00"), lat: 17.0, lon: 79.0, accuracy_m: 10 },
    { ts: ts("09:30"), lat: 17.3, lon: 79.3, accuracy_m: 10 },
    { ts: ts("10:30"), lat: 17.5, lon: 79.5, accuracy_m: 10 },
    { ts: ts("11:00"), lat: 17.6, lon: 79.8, accuracy_m: 10 },
  ],
  gaps: [
    { start: ts("09:30"), end: ts("10:30"), duration_s: 3600, duty_session_id: "d1", reason: null },
  ],
  timeline: [
    { ts: ts("09:00"), type: "duty_start", ref_id: "d1" },
    { ts: ts("09:10"), type: "visit_checkin", ref_id: "v1" },
    { ts: ts("09:25"), type: "visit_checkout", ref_id: "v1" },
    { ts: ts("09:30"), type: "gap_start" },
    { ts: ts("10:30"), type: "gap_end" },
    { ts: ts("11:00"), type: "duty_end", ref_id: "d1" },
  ],
};

describe("C22 playback", () => {
  const pb = buildPlayback(replay)!;

  it("maps the slider linearly over the day (09:00 .. 11:00)", () => {
    expect(new Date(sliderToTime(pb, 0)).toISOString()).toBe("2026-09-10T09:00:00.000Z");
    expect(new Date(sliderToTime(pb, SLIDER_MAX)).toISOString()).toBe("2026-09-10T11:00:00.000Z");
    expect(new Date(sliderToTime(pb, SLIDER_MAX / 4)).toISOString()).toBe(
      "2026-09-10T09:30:00.000Z",
    );
    expect(sliderToTime(pb, -5)).toBe(sliderToTime(pb, 0));
    expect(timeToSlider(pb, Date.parse(ts("10:00")))).toBe(500);
  });

  it("puts the marker on the track, interpolated between points", () => {
    // 09:15 is halfway between the first two points.
    const at = positionAt(pb, Date.parse(ts("09:15")))!;
    expect(at.lat).toBeCloseTo(17.15, 6);
    expect(at.lon).toBeCloseTo(79.15, 6);
    expect(at.inGap).toBe(false);
    // Slider 875 = 10:45: halfway 10:30 -> 11:00.
    const late = positionAt(pb, sliderToTime(pb, 875))!;
    expect(late.lat).toBeCloseTo(17.55, 6);
    expect(late.lon).toBeCloseTo(79.65, 6);
  });

  it("holds the marker at the last point during a gap and says so", () => {
    const mid = positionAt(pb, Date.parse(ts("10:00")))!;
    expect(mid).toEqual({ lat: 17.3, lon: 79.3, inGap: true });
  });

  it("clamps before the first and after the last point", () => {
    expect(positionAt(pb, Date.parse(ts("08:00")))).toMatchObject({ lat: 17.0, lon: 79.0 });
    expect(positionAt(pb, Date.parse(ts("12:00")))).toMatchObject({ lat: 17.6, lon: 79.8 });
  });

  it("highlights the latest timeline item at or before the slider time", () => {
    expect(activeTimelineIndex(pb, sliderToTime(pb, 0))).toBe(0); // duty start
    expect(activeTimelineIndex(pb, Date.parse(ts("09:12")))).toBe(1); // checked in
    expect(activeTimelineIndex(pb, Date.parse(ts("09:25")))).toBe(2); // exactly at checkout
    expect(activeTimelineIndex(pb, sliderToTime(pb, 500))).toBe(3); // 10:00, in the gap
    expect(activeTimelineIndex(pb, sliderToTime(pb, SLIDER_MAX))).toBe(5); // duty end
    expect(activeTimelineIndex(pb, Date.parse(ts("08:00")))).toBe(-1);
  });

  it("returns timeline indexes of the payload even when it is not sorted", () => {
    const shuffled = { ...replay, timeline: [replay.timeline[5]!, ...replay.timeline.slice(0, 5)] };
    const p2 = buildPlayback(shuffled)!;
    expect(activeTimelineIndex(p2, Date.parse(ts("09:12")))).toBe(2);
    expect(activeTimelineIndex(p2, Date.parse(ts("11:00")))).toBe(0);
  });

  it("draws a dashed segment across each gap between the points around it", () => {
    expect(gapSegments(replay)).toEqual([
      { gap: replay.gaps[0], from: [17.3, 79.3], to: [17.5, 79.5] },
    ]);
    // A gap at the start of the session has no point before it: no segment.
    const early = {
      ...replay,
      gaps: [{ ...replay.gaps[0]!, start: ts("08:00"), end: ts("08:50") }],
    };
    expect(gapSegments(early)).toEqual([null]);
  });

  it("has no playback for an empty day", () => {
    expect(buildPlayback({ points: [], timeline: [], gaps: [] })).toBeNull();
  });
});
