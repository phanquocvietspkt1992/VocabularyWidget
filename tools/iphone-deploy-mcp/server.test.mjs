import test from "node:test";
import assert from "node:assert/strict";
import { deviceAvailability, mergeDeploymentHistory, nextBuildNumber, parseLegacyDeployment } from "./server.mjs";

test("same-day deployment increments only the last successful counter", () => {
  assert.equal(nextBuildNumber("2026.11.15", { date: "2026.11.15", buildNumber: 1 }), 2);
});

test("a new local day starts at build one", () => {
  assert.equal(nextBuildNumber("2026.11.16", { date: "2026.11.15", buildNumber: 1 }), 1);
});

test("legacy successful deployment requires and extracts its evidence directory", () => {
  const parsed = parseLegacyDeployment("- Successful physical deployment: `2026.11.15` / `1` on device. Evidence: `/private/tmp/build-a` contains logs.\n");
  assert.equal(parsed.date, "2026.11.15");
  assert.equal(parsed.buildNumber, 1);
  assert.equal(parsed.evidenceDirectory, "/private/tmp/build-a");
  assert.equal(parseLegacyDeployment("No deployment recorded."), null);
});

test("device selection requires the listed physical device to be connected", () => {
  const output = "PQV IPhone 00008150-000215C11E12401C (UDID)\n connected iPhone 17 Pro Max physical";
  assert.deepEqual(deviceAvailability(output, "00008150-000215C11E12401C"), {
    found: true,
    connected: true,
    physical: true,
    detail: "PQV IPhone 00008150-000215C11E12401C (UDID)  connected iPhone 17 Pro Max physical",
  });
  assert.equal(deviceAvailability(output, "00000000-0000000000000000").found, false);
});

test("new manual deployment notes advance an existing MCP ledger", () => {
  const ledger = [{ date: "2026.11.15", buildNumber: 1, buildId: "iphone-first", deployedAt: "2026-11-15T20:00:00.000Z" }];
  const manual = { date: "2026.11.15", buildNumber: 2, source: "skill-history", deployedAt: "2026-11-15T00:00:00.000Z" };
  const merged = mergeDeploymentHistory(ledger, manual);
  assert.deepEqual(merged.map((item) => item.buildNumber), [1, 2]);
  assert.equal(nextBuildNumber("2026.11.15", merged.at(-1)), 3);
  assert.equal(mergeDeploymentHistory(merged, manual).length, 2);
});