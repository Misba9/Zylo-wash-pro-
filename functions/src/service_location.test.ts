import { describe, it } from "node:test";
import assert from "node:assert/strict";

function hasValidCoordinates(lat: unknown, lng: unknown): lat is number {
  return typeof lat === "number" && typeof lng === "number"
    && Number.isFinite(lat) && Number.isFinite(lng)
    && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

/** Mirrors createBooking snapshot rules without spinning up Firebase. */
function buildServiceLocation(addressId: string, addr: Record<string, unknown>) {
  const lat = typeof addr.latitude === "number" ? addr.latitude : null;
  const lng = typeof addr.longitude === "number" ? addr.longitude : null;
  const coordsOk = hasValidCoordinates(lat, lng);
  const formatted =
    (addr.formattedAddress || addr.line || addr.addressLine || "").toString() ||
    [addr.building, addr.slot, addr.locality || addr.area, addr.city]
      .filter((x) => x && String(x).trim() && String(x).trim() !== "—")
      .join(", ");
  return {
    addressId,
    addressLabel: (addr.label || "Address").toString(),
    formattedAddress: formatted,
    latitude: coordsOk ? lat : null,
    longitude: coordsOk ? lng : null,
  };
}

describe("createBooking serviceLocation snapshot", () => {
  it("copies owned address GPS when valid", () => {
    const sl = buildServiceLocation("addr_owned", {
      label: "Home",
      formattedAddress: "Tower B, Kondapur",
      latitude: 17.462201,
      longitude: 78.356812,
      ownerUid: "cust_1",
    });
    assert.equal(sl.latitude, 17.462201);
    assert.equal(sl.longitude, 78.356812);
  });

  it("does not invent coords for legacy addresses", () => {
    const sl = buildServiceLocation("addr_old", {
      label: "Parents",
      line: "Lane 3, Charminar",
      city: "Hyderabad",
    });
    assert.equal(sl.latitude, null);
    assert.equal(sl.longitude, null);
    assert.match(sl.formattedAddress, /Charminar/);
  });

  it("rejects NaN / out-of-range coordinates", () => {
    assert.equal(buildServiceLocation("x", { latitude: NaN, longitude: 78 }).latitude, null);
    assert.equal(buildServiceLocation("x", { latitude: 17, longitude: 200 }).latitude, null);
  });
});
