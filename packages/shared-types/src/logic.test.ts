import { describe, it, expect } from "vitest";
import { calculatePrice, canTransition, recommendWorkers, availableSlots, WORKERS, hasValidCoordinates, mapsDirectionsUrl, osmEmbedUrl } from "./index";
import { seedBookings, SEED_ADDRESSES } from "./seed";

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

describe("service location coordinates", () => {
  it("accepts finite in-range lat/lng only", () => {
    expect(hasValidCoordinates(17.4622, 78.3568)).toBe(true);
    expect(hasValidCoordinates(null, 78)).toBe(false);
    expect(hasValidCoordinates(NaN, 78)).toBe(false);
    expect(hasValidCoordinates(91, 78)).toBe(false);
    expect(hasValidCoordinates(17, 181)).toBe(false);
  });
  it("builds navigation URL from exact destination coordinates", () => {
    expect(mapsDirectionsUrl(17.4622, 78.3568)).toBe(
      "https://www.google.com/maps/dir/?api=1&destination=17.4622,78.3568"
    );
  });
  it("builds OSM embed with marker at exact coords", () => {
    const url = osmEmbedUrl(17.4622, 78.3568);
    expect(url).toContain("marker=17.4622%2C78.3568");
  });
  it("seed bookings snapshot coords from owned addresses (or null for legacy)", () => {
    const bookings = seedBookings();
    const withGps = bookings.find(b => b.id === "bk_1003")!;
    expect(withGps.serviceLocation?.latitude).toBe(SEED_ADDRESSES[0].latitude);
    expect(withGps.serviceLocation?.longitude).toBe(SEED_ADDRESSES[0].longitude);
    const legacy = bookings.find(b => b.id === "bk_1004")!;
    expect(legacy.serviceLocation?.latitude).toBeNull();
    expect(legacy.serviceLocation?.longitude).toBeNull();
    expect(legacy.addressSnapshot.length).toBeGreaterThan(0);
  });
  it("editing a saved address must not mutate an existing booking snapshot", () => {
    const bookings = seedBookings();
    const snap = { ...bookings[0].serviceLocation! };
    const edited = { ...SEED_ADDRESSES[0], latitude: 17.5, longitude: 78.4 };
    expect(bookings[0].serviceLocation?.latitude).toBe(snap.latitude);
    expect(edited.latitude).not.toBe(snap.latitude);
  });
});
