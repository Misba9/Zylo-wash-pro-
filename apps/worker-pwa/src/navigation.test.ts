import { describe, it, expect } from "vitest";
import { seedBookings } from "../../../packages/shared-types/src/seed";
import { workerNavigateUrl } from "./location";

describe("ZYLO Field navigation", () => {
  it("uses exact booking serviceLocation coordinates", () => {
    const job = seedBookings().find((b) => b.id === "bk_1003")!;
    const { href, coordsOk } = workerNavigateUrl(job);
    expect(coordsOk).toBe(true);
    expect(href).toContain("https://www.google.com/maps/dir/?api=1&destination=");
    expect(href).toContain(String(job.serviceLocation!.latitude));
    expect(href).toContain(String(job.serviceLocation!.longitude));
  });

  it("does not invent coordinates for legacy bookings", () => {
    const job = seedBookings().find((b) => b.id === "bk_1004")!;
    const { href, coordsOk } = workerNavigateUrl(job);
    expect(coordsOk).toBe(false);
    expect(href).toContain("/maps/search/");
    expect(href).not.toMatch(/destination=\d/);
  });
});
