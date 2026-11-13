export function uniqueSuffix() {
  return `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`;
}

export function fakeVehicle() {
  const s = uniqueSuffix().toUpperCase().slice(0, 4);
  return {
    nickname: `E2E ${s}`,
    registration: `TS09EE${s.slice(0, 4)}`,
    seatClass: "seater5" as const,
  };
}

export function fakeAddress() {
  const s = uniqueSuffix();
  return {
    label: `E2E Home ${s}`,
    line: `Plot ${s}, Hitec City`,
    city: "Hyderabad",
    postalCode: "500081",
    latitude: 17.4485,
    longitude: 78.3908,
  };
}
