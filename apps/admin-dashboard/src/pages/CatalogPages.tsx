/**
 * Phase 2 — Services, Pricing calculator, Packages, Add-ons.
 * Brand: ZYLO (#123F36 / #2A6B5C / #C49A45)
 */
import { useMemo, useState } from "react";
import {
  inr,
  quoteBookingPrice,
  quoteToPriceSnapshot,
  seatPricesToLegacy,
  DEFAULT_APP_FEES,
  type SeatClass,
} from "../../../../packages/shared-types/src/index";
import { LIVE, liveUpdate, liveSet, liveAudit } from "../live";

export type CatalogService = {
  id: string;
  name: string;
  tagline?: string;
  duration?: number;
  hatchback?: number;
  sedan?: number;
  suv?: number;
  luxury?: number;
  pricePaise?: { seater5: number; seater7: number };
  durationMinutes?: { seater5: number; seater7: number } | number;
  active?: boolean;
  popular?: boolean;
  featured?: boolean;
  categoryId?: string;
  cashEligible?: boolean;
  sortOrder?: number;
  archived?: boolean;
};

type AddonRow = {
  id: string;
  name: string;
  pricePaise: number;
  durationMinutes: number;
  active: boolean;
  sortOrder: number;
  applicableServiceIds: string[];
  applicableSeatClasses: SeatClass[];
};

type PlanRow = {
  id: string;
  name: string;
  description?: string;
  visits: number;
  validityDays: number;
  frequency: string;
  billingMode: "prepaid" | "recurring";
  pricePaise: { seater5: number; seater7: number };
  active: boolean;
  popular?: boolean;
};

function rupeesField(paise: number) {
  return Math.round(paise / 100);
}

function toSeatPrices(s: CatalogService): { seater5: number; seater7: number } {
  if (s.pricePaise?.seater5 != null) return s.pricePaise;
  const h = Number(s.hatchback ?? 0);
  const sed = Number(s.sedan ?? h);
  const suv = Number(s.suv ?? sed);
  const lux = Number(s.luxury ?? suv);
  // Seed may be rupees (<10000) or paise
  const mul = sed > 0 && sed < 10000 ? 100 : 1;
  return { seater5: Math.round(sed * mul), seater7: Math.round(suv * mul) };
}

function toSeatDuration(s: CatalogService): { seater5: number; seater7: number } {
  if (s.durationMinutes && typeof s.durationMinutes === "object") {
    return s.durationMinutes as { seater5: number; seater7: number };
  }
  const d = Number(s.duration ?? s.durationMinutes ?? 45);
  return { seater5: d, seater7: d };
}

type Props = {
  services: CatalogService[];
  addons: AddonRow[];
  plans: PlanRow[];
  onServices: (next: CatalogService[]) => void;
  onAddons: (next: AddonRow[]) => void;
  onPlans: (next: PlanRow[]) => void;
  actorEmail: string;
  toast: (m: string) => void;
};

export function ServicesCatalogPage({
  services,
  onServices,
  actorEmail,
  toast,
}: Pick<Props, "services" | "onServices" | "actorEmail" | "toast">) {
  const [draftName, setDraftName] = useState("");
  const [draft5, setDraft5] = useState(549);
  const [draft7, setDraft7] = useState(649);

  const saveService = async (s: CatalogService) => {
    const pricePaise = toSeatPrices(s);
    const durationMinutes = toSeatDuration(s);
    const legacy = seatPricesToLegacy(pricePaise);
    const payload = {
      name: s.name,
      tagline: s.tagline ?? "",
      categoryId: s.categoryId ?? "general",
      pricePaise,
      durationMinutes,
      // Keep legacy rupee fields for older Flutter readers during migration
      hatchback: rupeesField(legacy.hatchback),
      sedan: rupeesField(legacy.sedan),
      suv: rupeesField(legacy.suv),
      luxury: rupeesField(legacy.luxury),
      duration: durationMinutes.seater5,
      cashEligible: s.cashEligible !== false,
      active: s.active !== false,
      archived: !!s.archived,
      popular: !!s.popular,
      featured: !!s.featured,
      sortOrder: s.sortOrder ?? 0,
      updatedAt: new Date().toISOString(),
    };
    if (LIVE) {
      await liveUpdate("services", s.id, payload);
    }
    onServices(services.map((x) => (x.id === s.id ? { ...x, ...payload } : x)));
    await liveAudit(actorEmail, "updateService", s.id, s.name).catch(() => {});
    toast(`Saved ${s.name} · new bookings use new prices`);
  };

  const addService = async () => {
    const name = draftName.trim();
    if (!name) return;
    const id = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    if (!id || services.some((s) => s.id === id)) {
      toast("Invalid or duplicate service id");
      return;
    }
    const pricePaise = { seater5: draft5 * 100, seater7: draft7 * 100 };
    const durationMinutes = { seater5: 45, seater7: 60 };
    const row: CatalogService = {
      id,
      name,
      tagline: "",
      pricePaise,
      durationMinutes,
      hatchback: draft5,
      sedan: draft5,
      suv: draft7,
      luxury: draft7,
      duration: 45,
      active: true,
      cashEligible: true,
      sortOrder: services.length + 1,
      categoryId: "general",
    };
    if (LIVE) {
      await liveSet("services", id, {
        ...row,
        createdAt: new Date().toISOString(),
      });
    }
    onServices([...services, row]);
    await liveAudit(actorEmail, "createService", id, name).catch(() => {});
    setDraftName("");
    toast(`Created service ${name}`);
  };

  return (
    <>
      <div className="card">
        <h2 style={{ marginTop: 0 }}>
          Services{" "}
          <span className="muted" style={{ fontSize: 13 }}>
            · 5-seater / 7-seater · paise on server · snapshots preserved
          </span>
        </h2>
        {services
          .filter((s) => !s.archived)
          .map((s) => {
            const seats = toSeatPrices(s);
            const dur = toSeatDuration(s);
            return (
              <div
                key={s.id}
                style={{
                  display: "flex",
                  gap: 10,
                  alignItems: "center",
                  padding: "12px 0",
                  borderBottom: "1px dashed #E8EFF5",
                  flexWrap: "wrap",
                }}
              >
                <b style={{ minWidth: 140 }}>{s.name}</b>
                <label className="small">
                  5-seater ₹
                  <input
                    className="input"
                    style={{ width: 88, padding: "6px 8px" }}
                    type="number"
                    value={rupeesField(seats.seater5)}
                    onChange={(e) => {
                      const v = Number(e.target.value);
                      onServices(
                        services.map((x) =>
                          x.id === s.id
                            ? {
                                ...x,
                                pricePaise: {
                                  seater5: v * 100,
                                  seater7: toSeatPrices(x).seater7,
                                },
                                sedan: v,
                                hatchback: v,
                              }
                            : x,
                        ),
                      );
                    }}
                  />
                </label>
                <label className="small">
                  7-seater ₹
                  <input
                    className="input"
                    style={{ width: 88, padding: "6px 8px" }}
                    type="number"
                    value={rupeesField(seats.seater7)}
                    onChange={(e) => {
                      const v = Number(e.target.value);
                      onServices(
                        services.map((x) =>
                          x.id === s.id
                            ? {
                                ...x,
                                pricePaise: {
                                  seater5: toSeatPrices(x).seater5,
                                  seater7: v * 100,
                                },
                                suv: v,
                                luxury: v,
                              }
                            : x,
                        ),
                      );
                    }}
                  />
                </label>
                <label className="small">
                  ⏱ 5s
                  <input
                    className="input"
                    style={{ width: 64, padding: "6px 8px" }}
                    type="number"
                    value={dur.seater5}
                    onChange={(e) => {
                      const v = Number(e.target.value);
                      onServices(
                        services.map((x) =>
                          x.id === s.id
                            ? {
                                ...x,
                                durationMinutes: {
                                  seater5: v,
                                  seater7: toSeatDuration(x).seater7,
                                },
                                duration: v,
                              }
                            : x,
                        ),
                      );
                    }}
                  />
                </label>
                <button className="btn g" onClick={() => saveService(s)}>
                  Save
                </button>
                <button
                  className="btn"
                  onClick={() =>
                    onServices(
                      services.map((x) =>
                        x.id === s.id ? { ...x, active: !(x.active !== false) } : x,
                      ),
                    )
                  }
                >
                  {s.active !== false ? "Disable" : "Enable"}
                </button>
                <button
                  className="btn d"
                  onClick={async () => {
                    const next = { ...s, archived: true, active: false };
                    if (LIVE) await liveUpdate("services", s.id, { archived: true, active: false });
                    onServices(services.map((x) => (x.id === s.id ? next : x)));
                    toast(`Archived ${s.name}`);
                  }}
                >
                  Archive
                </button>
                <span
                  className="chip"
                  style={{
                    background: s.active !== false ? "#DCFCE7" : "#FEE2E2",
                    color: s.active !== false ? "#15803D" : "#B91C1C",
                  }}
                >
                  {s.active !== false ? "Active" : "Paused"}
                </span>
              </div>
            );
          })}
      </div>

      <div className="card" style={{ marginTop: 14 }}>
        <b>Add service</b>
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginTop: 10 }}>
          <input
            className="input"
            placeholder="Service name"
            value={draftName}
            onChange={(e) => setDraftName(e.target.value)}
          />
          <label className="small">
            5-seater ₹
            <input
              className="input"
              style={{ width: 88 }}
              type="number"
              value={draft5}
              onChange={(e) => setDraft5(Number(e.target.value))}
            />
          </label>
          <label className="small">
            7-seater ₹
            <input
              className="input"
              style={{ width: 88 }}
              type="number"
              value={draft7}
              onChange={(e) => setDraft7(Number(e.target.value))}
            />
          </label>
          <button className="btn" onClick={addService}>
            Create
          </button>
        </div>
      </div>
    </>
  );
}

export function PricingCalculatorPage({
  services,
  addons,
}: Pick<Props, "services" | "addons">) {
  const active = services.filter((s) => s.active !== false && !s.archived);
  const [serviceId, setServiceId] = useState(active[0]?.id ?? "");
  const [seat, setSeat] = useState<SeatClass>("seater5");
  const [express, setExpress] = useState(true);
  const [coupon, setCoupon] = useState("WELCOME75");
  const [addonId, setAddonId] = useState("");

  const breakdown = useMemo(() => {
    const s = active.find((x) => x.id === serviceId) || active[0];
    if (!s) return null;
    const pricePaise = toSeatPrices(s);
    const durationMinutes = toSeatDuration(s);
    const addon = addons.find((a) => a.id === addonId && a.active);
    try {
      const q = quoteBookingPrice({
        service: {
          id: s.id,
          name: s.name,
          pricePaise,
          durationMinutes,
          active: true,
          archived: false,
        },
        seatClass: seat,
        express,
        addonPaise: addon?.pricePaise ?? 0,
        coupon: coupon.trim()
          ? {
              code: coupon.trim().toUpperCase(),
              discountType: "fixed",
              discountValue: coupon.trim().toUpperCase() === "WELCOME75" ? 7500 : 0,
              active: true,
            }
          : null,
        fees: DEFAULT_APP_FEES,
      });
      return { q, snap: quoteToPriceSnapshot(q) };
    } catch {
      return null;
    }
  }, [active, serviceId, seat, express, coupon, addonId, addons]);

  return (
    <div className="card">
      <h2 style={{ marginTop: 0 }}>Pricing calculator</h2>
      <p className="muted">
        Same engine as Cloud Function <code>quoteBookingPrice</code>. Historical bookings are
        never rewritten.
      </p>
      <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom: 16 }}>
        <label className="small">
          Service
          <select
            className="input"
            value={serviceId}
            onChange={(e) => setServiceId(e.target.value)}
          >
            {active.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </label>
        <label className="small">
          Vehicle
          <select
            className="input"
            value={seat}
            onChange={(e) => setSeat(e.target.value as SeatClass)}
          >
            <option value="seater5">5 Seater</option>
            <option value="seater7">7 Seater</option>
          </select>
        </label>
        <label className="small">
          Add-on
          <select
            className="input"
            value={addonId}
            onChange={(e) => setAddonId(e.target.value)}
          >
            <option value="">None</option>
            {addons
              .filter((a) => a.active)
              .map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} ({inr(a.pricePaise)})
                </option>
              ))}
          </select>
        </label>
        <label className="small" style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <input
            type="checkbox"
            checked={express}
            onChange={(e) => setExpress(e.target.checked)}
          />
          Express / Wash Now
        </label>
        <label className="small">
          Coupon
          <input
            className="input"
            value={coupon}
            onChange={(e) => setCoupon(e.target.value)}
            placeholder="WELCOME75"
          />
        </label>
      </div>
      {breakdown ? (
        <div
          style={{
            background: "linear-gradient(135deg,#123F36,#2A6B5C)",
            color: "#fff",
            borderRadius: 12,
            padding: 18,
            maxWidth: 420,
          }}
        >
          <div style={{ color: "#C49A45", fontWeight: 700, marginBottom: 8 }}>ZYLO quote</div>
          <Row label="Base service" value={inr(breakdown.q.basePaise)} />
          {breakdown.q.addonPaise > 0 && (
            <Row label="Add-ons" value={inr(breakdown.q.addonPaise)} />
          )}
          <Row label="Service fee" value={inr(breakdown.q.serviceFeePaise)} />
          {breakdown.q.expressFeePaise > 0 && (
            <Row label="Express charge" value={inr(breakdown.q.expressFeePaise)} />
          )}
          {breakdown.q.discountPaise > 0 && (
            <Row label="Discount" value={`−${inr(breakdown.q.discountPaise)}`} />
          )}
          <div
            style={{
              borderTop: "1px solid rgba(255,255,255,.25)",
              marginTop: 10,
              paddingTop: 10,
              display: "flex",
              justifyContent: "space-between",
              fontWeight: 800,
              fontSize: 18,
            }}
          >
            <span>Final payable</span>
            <span style={{ color: "#C49A45" }}>{inr(breakdown.q.totalPaise)}</span>
          </div>
          <p className="small" style={{ opacity: 0.75, marginBottom: 0 }}>
            {breakdown.snap.pricingVersion} · {breakdown.q.estimatedDurationMinutes} min
          </p>
        </div>
      ) : (
        <p className="muted">Add an active service to preview pricing.</p>
      )}
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", padding: "4px 0" }}>
      <span style={{ opacity: 0.85 }}>{label}</span>
      <span>{value}</span>
    </div>
  );
}

export function AddonsPage({
  addons,
  onAddons,
  services,
  actorEmail,
  toast,
}: Pick<Props, "addons" | "onAddons" | "services" | "actorEmail" | "toast">) {
  const [name, setName] = useState("");
  const [price, setPrice] = useState(99);

  const save = async (a: AddonRow) => {
    if (LIVE) await liveSet("addons", a.id, { ...a, updatedAt: new Date().toISOString() });
    onAddons(addons.map((x) => (x.id === a.id ? a : x)));
    await liveAudit(actorEmail, "updateAddon", a.id).catch(() => {});
    toast(`Saved add-on ${a.name}`);
  };

  const create = async () => {
    const id = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    if (!id) return;
    const row: AddonRow = {
      id,
      name: name.trim(),
      pricePaise: price * 100,
      durationMinutes: 15,
      active: true,
      sortOrder: addons.length + 1,
      applicableServiceIds: services.map((s) => s.id),
      applicableSeatClasses: ["seater5", "seater7"],
    };
    if (LIVE) await liveSet("addons", id, row);
    onAddons([...addons, row]);
    setName("");
    toast(`Created ${row.name}`);
  };

  return (
    <div className="card">
      <h2 style={{ marginTop: 0 }}>Add-ons</h2>
      {addons.map((a) => (
        <div
          key={a.id}
          style={{
            display: "flex",
            gap: 10,
            alignItems: "center",
            padding: "10px 0",
            borderBottom: "1px dashed #E8EFF5",
            flexWrap: "wrap",
          }}
        >
          <b style={{ minWidth: 140 }}>{a.name}</b>
          <label className="small">
            ₹
            <input
              className="input"
              style={{ width: 88 }}
              type="number"
              value={rupeesField(a.pricePaise)}
              onChange={(e) =>
                onAddons(
                  addons.map((x) =>
                    x.id === a.id ? { ...x, pricePaise: Number(e.target.value) * 100 } : x,
                  ),
                )
              }
            />
          </label>
          <button className="btn g" onClick={() => save(a)}>
            Save
          </button>
          <button
            className="btn"
            onClick={() =>
              onAddons(addons.map((x) => (x.id === a.id ? { ...x, active: !x.active } : x)))
            }
          >
            {a.active ? "Disable" : "Enable"}
          </button>
        </div>
      ))}
      <div style={{ display: "flex", gap: 10, marginTop: 12, flexWrap: "wrap" }}>
        <input
          className="input"
          placeholder="Add-on name"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <input
          className="input"
          type="number"
          style={{ width: 100 }}
          value={price}
          onChange={(e) => setPrice(Number(e.target.value))}
        />
        <button className="btn" onClick={create}>
          Create add-on
        </button>
      </div>
    </div>
  );
}

export function PackagesPage({
  plans,
  onPlans,
  actorEmail,
  toast,
}: Pick<Props, "plans" | "onPlans" | "actorEmail" | "toast">) {
  const save = async (p: PlanRow) => {
    if (LIVE) await liveSet("plans", p.id, { ...p, updatedAt: new Date().toISOString() });
    onPlans(plans.map((x) => (x.id === p.id ? p : x)));
    await liveAudit(actorEmail, "updatePlan", p.id).catch(() => {});
    toast(`Saved package ${p.name}`);
  };

  return (
    <div className="card">
      <h2 style={{ marginTop: 0 }}>Subscription packages</h2>
      {plans.map((p) => (
        <div
          key={p.id}
          style={{
            display: "flex",
            gap: 10,
            alignItems: "center",
            padding: "12px 0",
            borderBottom: "1px dashed #E8EFF5",
            flexWrap: "wrap",
          }}
        >
          <span style={{ flex: 1, minWidth: 180 }}>
            <b>{p.name}</b>
            <br />
            <span className="muted">
              {p.billingMode} · {p.visits} washes · {p.validityDays || 30}d · {p.frequency}
            </span>
          </span>
          <label className="small">
            5s ₹
            <input
              className="input"
              style={{ width: 100 }}
              type="number"
              value={rupeesField(p.pricePaise.seater5)}
              onChange={(e) =>
                onPlans(
                  plans.map((x) =>
                    x.id === p.id
                      ? {
                          ...x,
                          pricePaise: {
                            seater5: Number(e.target.value) * 100,
                            seater7: x.pricePaise.seater7,
                          },
                        }
                      : x,
                  ),
                )
              }
            />
          </label>
          <label className="small">
            7s ₹
            <input
              className="input"
              style={{ width: 100 }}
              type="number"
              value={rupeesField(p.pricePaise.seater7)}
              onChange={(e) =>
                onPlans(
                  plans.map((x) =>
                    x.id === p.id
                      ? {
                          ...x,
                          pricePaise: {
                            seater5: x.pricePaise.seater5,
                            seater7: Number(e.target.value) * 100,
                          },
                        }
                      : x,
                  ),
                )
              }
            />
          </label>
          <button className="btn g" onClick={() => save(p)}>
            Save
          </button>
          <span
            className="chip"
            style={{
              background: p.active ? "#DCFCE7" : "#FEE2E2",
              color: p.active ? "#15803D" : "#B91C1C",
            }}
          >
            {p.active ? "Active" : "Off"}
          </span>
        </div>
      ))}
      {plans.length === 0 && (
        <p className="muted">No packages yet — run Activate admin / Seed pilot data.</p>
      )}
    </div>
  );
}
