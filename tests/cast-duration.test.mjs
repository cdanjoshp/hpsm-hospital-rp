import assert from "node:assert/strict";
import test from "node:test";
import { CAST_DURATION_DAYS, castDurationDays, expectedCastRemovalAt, isCastDurationDays } from "../app/lib/cast-duration.ts";

test("cast duration accepts only whole days from one through five", () => {
  assert.deepEqual(CAST_DURATION_DAYS, [1, 2, 3, 4, 5]);
  for (const days of CAST_DURATION_DAYS) assert.equal(isCastDurationDays(days), true);
  for (const invalid of [0, 6, 1.5, "3", null, NaN]) assert.equal(isCastDurationDays(invalid), false);
});

test("removal preserves the application time and computes 24-hour days", () => {
  const appliedAt = "2026-09-28T17:15:00-03:00";
  assert.equal(expectedCastRemovalAt(appliedAt, 1), "2026-09-29T20:15:00.000Z");
  assert.equal(expectedCastRemovalAt(appliedAt, 5), "2026-10-03T20:15:00.000Z");
  assert.equal(expectedCastRemovalAt("data inválida", 1), null);
  assert.equal(castDurationDays(appliedAt, "2026-10-03T20:15:00Z"), 5);
  assert.equal(castDurationDays(appliedAt, "2026-09-30T08:15:00Z"), null);
});
