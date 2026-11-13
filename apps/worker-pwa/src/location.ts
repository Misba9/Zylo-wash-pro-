import { hasValidCoordinates, mapsDirectionsUrl, type Booking, type ServiceLocation } from "../../../packages/shared-types/src/index";

export function resolveServiceLocation(b: Booking): ServiceLocation {
  const sl = (b as any).serviceLocation as ServiceLocation | undefined;
  if (sl && (sl.formattedAddress || sl.latitude != null || sl.longitude != null)) return sl;
  return {
    addressId: b.addressId,
    addressLabel: b.addressLabel,
    formattedAddress: b.addressSnapshot,
    latitude: null,
    longitude: null,
  };
}

/** Navigation URL from booking snapshot only — never invent lat/lng. */
export function workerNavigateUrl(booking: Booking): { href: string; coordsOk: boolean } {
  const sl = resolveServiceLocation(booking);
  const lat = sl.latitude ?? null;
  const lng = sl.longitude ?? null;
  const coordsOk = hasValidCoordinates(lat, lng);
  if (coordsOk) return { href: mapsDirectionsUrl(lat as number, lng as number), coordsOk: true };
  const addressText = sl.formattedAddress || booking.addressSnapshot || "";
  return {
    href: `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(addressText)}`,
    coordsOk: false,
  };
}
