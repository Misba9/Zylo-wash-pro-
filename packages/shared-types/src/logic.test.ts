import { describe, it, expect } from "vitest";
import { calculatePrice, canTransition, recommendWorkers, availableSlots, WORKERS } from "./index";

describe("pricing (PRD §5.5, §8.3)", () => {
  it("calculates authoritative price in paise with pricing version", () => {
    const p = calculatePrice("body-wash", "suv");
    expect(p.totalPaise).toBe(44900); expect(p.currency).toBe("INR"); expect(p.pricingVersion).toContain("v1");
  });
  it("adds add-ons and discount", () => {
    const p = calculatePrice("body-wash", "sedan", ["tyre-dressing"], 5000);
    expect(p.subtotalPaise).toBe(34900 + 9900); expect(p.totalPaise).toBe(34900 + 9900 - 5000);
  });
  it("rejects unknown service", () => { expect(() => calculatePrice("nope", "sedan")).toThrow(); });
});
describe("booking state machine (PRD §8.1)", () => {
  it("allows happy path, blocks skipping", () => {
    expect(canTransition("confirmed", "assigned")).toBe(true);
    expect(canTransition("assigned", "en_route")).toBe(true);
    expect(canTransition("confirmed", "completed")).toBe(false);
    expect(canTransition("completed", "assigned")).toBe(false);
  });
});
describe("assignment scoring (PRD §7.3)", () => {
  it("ranks approved available area-matched worker first, excludes pending", () => {
    const recs = recommendWorkers({ serviceAreaId: "kondapur", serviceId: "body-wash" }, WORKERS);
    expect(recs[0].score).toBeGreaterThan(0);
    expect(recs.find(r => r.worker.uid === "w6")!.score).toBe(-1);
    expect(recs.find(r => r.worker.uid === "w4")!.score).toBe(-1); // unavailable
  });
});
describe("slots", () => { it("returns deterministic slots", () => { expect(availableSlots("2026-10-20")).toHaveLength(8); }); });
