import { useEffect, useMemo, useRef, useState } from "react";
import { Booking, SERVICES, STATUS_LABEL, inr, canTransition } from "../../../packages/shared-types/src/index";
import { load, save, reset, fmtTime } from "./store";
import { isDemoMode } from "./firebase";
import { LIVE, watchAuth, loginEmail, registerWorker, findWorkerForUser, subscribeJobs, liveBookingUpdate, liveWorkerUpdate, liveLocation, clearLocation, logout as liveLogout, type User } from "./live";

const CHIP: Record<string, string> = { assigned:"#DBEAFE/#1D4ED8", en_route:"#FEF3C7/#B45309", arrived:"#E0E7FF/#3730A3", in_progress:"#CCFBF1/#0F766E", pending_verification:"#FCE7F3/#9D174D", completed:"#DCFCE7/#15803D", confirmed:"#E2E8F0/#475569", cancelled:"#FEE2E2/#B91C1C" };
function Chip({ s }: { s: string }) { const [bg, fg] = (CHIP[s] || "#E2E8F0/#475569").split("/"); return <span className="chip" style={{ background: bg, color: fg }}>{STATUS_LABEL[s as Booking["status"]] || s}</span>; }

export default function App() {
  const [state, setState] = useState(load);
  const [tab, setTab] = useState<"today" | "jobs" | "earnings" | "profile">("today");
  const [openId, setOpenId] = useState<string | null>(null);
  const [toast, setToast] = useState("");
  const [online, setOnline] = useState(navigator.onLine);
  const [tick, setTick] = useState(0);
  const [fbUser, setFbUser] = useState<User | null>(null);
  const [liveWorker, setLiveWorker] = useState<any>(null);
  const [liveJobs, setLiveJobs] = useState<any[] | null>(null);
  const [email, setEmail] = useState(""); const [pw, setPw] = useState(""); const [fullName, setFullName] = useState(""); const [authMode, setAuthMode] = useState<"login" | "register">("login"); const [authBusy, setAuthBusy] = useState(false); const [authErr, setAuthErr] = useState("");
  const locTimer = useRef<number | null>(null);
  useEffect(() => { save(state); }, [state]);
  useEffect(() => { const on = () => setOnline(true), off = () => setOnline(false); window.addEventListener("online", on); window.addEventListener("offline", off); return () => { window.removeEventListener("online", on); window.removeEventListener("offline", off); }; }, []);
  useEffect(() => { if (!toast) return; const t = setTimeout(() => setToast(""), 3200); return () => clearTimeout(t); }, [toast]);

  useEffect(() => { if (!LIVE) return; let unsub: (() => void) | undefined; const off = watchAuth(async (u) => { setFbUser(u); if (!u) { setLiveWorker(null); setLiveJobs(null); return; } const w: any = await findWorkerForUser(u).catch(() => null); if (w) { setLiveWorker({ ...w, uid: w.docId }); unsub = subscribeJobs(w.docId, setLiveJobs); } else setAuthErr("No worker profile for this email yet — use Register to create one."); }); return () => { off(); unsub?.(); }; }, []);
  const worker = LIVE ? liveWorker : state.workers.find(w => w.uid === state.workerUid) || null;
  const myJobs = useMemo(() => (LIVE && liveJobs ? [...liveJobs].sort((a: any, b: any) => String(a.scheduledAt).localeCompare(String(b.scheduledAt))) : state.bookings.filter(b => b.assignedWorkerUid === state.workerUid).sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt))), [state, liveJobs]);
  const active = myJobs.find(b => ["en_route", "arrived", "in_progress", "pending_verification"].includes(b.status));
  const next = myJobs.find(b => b.status === "assigned");
  const doneToday = myJobs.filter(b => b.status === "completed");
  const earnedToday = LIVE ? doneToday.reduce((n: number, b: any) => n + Math.round((b.priceSnapshot?.totalPaise || 0) * 0.7), 0) : (worker?.earningsTodayPaise || 0) + state.earningsExtra;
  const patch = (id: string, p: Partial<Booking>) => { if (LIVE) { liveBookingUpdate(id, { ...p, updatedAt: new Date().toISOString() }).catch((e: any) => setToast("Write failed: " + e.code)); if ((p as any).status === "arrived" && liveWorker) clearLocation(liveWorker.uid); return; } setState(s => ({ ...s, bookings: s.bookings.map(b => b.id === id ? { ...b, ...p, updatedAt: new Date().toISOString() } : b) })); };

  // Simulated live location while en_route (real mode: navigator.geolocation.watchPosition → recordWorkerLocation fn, PRD §6.3)
  useEffect(() => {
    if (!active || active.status !== "en_route") return;
    locTimer.current = window.setInterval(() => { setTick(t => t + 1); const la = 17.44 + Math.random() * 0.01, ln = 78.37 + Math.random() * 0.01; setState(s => ({ ...s, lastLoc: { lat: la, lng: ln, at: new Date().toISOString() } })); if (LIVE && liveWorker && active) liveLocation(liveWorker.uid, active.id, la, ln).catch(() => {}); }, 4000);
    return () => { if (locTimer.current) clearInterval(locTimer.current); };
  }, [active?.id, active?.status]);

  if (LIVE && worker && worker.status === "suspended") return (
    <div className="phone" style={{ paddingBottom: 20 }}>
      <div className="top"><div className="logo">Wash<span>Pro</span> Worker</div><p style={{ opacity: .85, fontSize: 13, margin: "8px 0 0" }}>Live mode · wash-pro-7f3b1</p></div>
      <div className="card" style={{ textAlign: "center", padding: 26 }}>
        <div style={{ fontSize: 38 }}>⛔</div>
        <b>Account suspended</b>
        <p className="muted">Your worker account has been suspended. Please contact the WashPro ops team.</p>
        <button className="btn btn-g" onClick={() => liveLogout()}>Sign out</button>
      </div>
    </div>);

  if (LIVE && !worker) return (
    <div className="phone" style={{ paddingBottom: 20 }}>
      <div className="top"><div className="logo">Wash<span>Pro</span> Worker</div><p style={{ opacity: .85, fontSize: 13, margin: "8px 0 0" }}>Live mode · wash-pro-7f3b1 · sign in with your work email</p></div>
      <div className="card"><b>{authMode === "login" ? "Worker sign-in" : "Register as a worker"}</b>
        <p className="muted">{authMode === "login" ? "Sign in with your work email and password." : "Create your account — you're approved instantly and can receive jobs right away."}</p>
        <div style={{ display: "flex", gap: 8, margin: "10px 0" }}>
          <button className={authMode === "login" ? "btn btn-p" : "btn btn-g"} style={{ flex: 1 }} onClick={() => { setAuthMode("login"); setAuthErr(""); }}>Login</button>
          <button className={authMode === "register" ? "btn btn-p" : "btn btn-g"} style={{ flex: 1 }} onClick={() => { setAuthMode("register"); setAuthErr(""); }}>Register</button>
        </div>
        {authMode === "register" && <input value={fullName} onChange={e => setFullName(e.target.value)} placeholder="Full name (e.g. Ramesh Kumar)" autoComplete="name" style={{ width: "100%", padding: 13, borderRadius: 12, border: "1px solid #D7E3EE", margin: "6px 0" }} />}
        <input value={email} onChange={e => setEmail(e.target.value)} placeholder="Email address" type="email" autoComplete="email" style={{ width: "100%", padding: 13, borderRadius: 12, border: "1px solid #D7E3EE", margin: "6px 0" }} />
        <input value={pw} onChange={e => setPw(e.target.value)} placeholder="Password (min 6 characters)" type="password" autoComplete={authMode === "login" ? "current-password" : "new-password"} style={{ width: "100%", padding: 13, borderRadius: 12, border: "1px solid #D7E3EE", margin: "6px 0" }} />
        <button className="btn btn-p" disabled={authBusy} onClick={async () => {
          setAuthErr(""); setAuthBusy(true);
          try {
            if (authMode === "register") {
              if (fullName.trim().length < 3) throw { code: "app/name", message: "Enter your full name" };
              if (pw.length < 6) throw { code: "app/pw", message: "Password must be at least 6 characters" };
              await registerWorker(fullName, email, pw);
            } else {
              await loginEmail(email, pw);
            }
          } catch (e: any) {
            const map: Record<string, string> = {
              "auth/configuration-not-found": "Email/Password is not enabled yet — Firebase Console → Authentication → enable Email/Password (docs/FIREBASE_WASH_PRO.md)",
              "auth/email-already-in-use": "This email is already registered — use Login instead.",
              "auth/invalid-credential": "Wrong email or password. Try again, or Register if you're new.",
              "auth/user-not-found": "No account with this email — use Register to create one.",
              "auth/wrong-password": "Wrong password. Please try again.",
              "auth/invalid-email": "Enter a valid email address.",
              "auth/weak-password": "Password must be at least 6 characters.",
              "auth/too-many-requests": "Too many attempts — wait a minute and retry.",
            };
            setAuthErr(map[e.code] || e.message || "Something went wrong");
          } finally { setAuthBusy(false); }
        }}>{authBusy ? "Please wait…" : authMode === "login" ? "Sign in & view my jobs" : "Create account"}</button>
        {authErr && <p style={{ color: "#DC2626", fontSize: 13 }}>{authErr}</p>}
        {fbUser && !liveWorker && <button className="btn btn-g" style={{ marginTop: 8 }} onClick={() => liveLogout()}>Sign out</button>}
        <p className="small muted" style={{ marginTop: 10 }}>Jobs, status updates and trip location write to Firestore in real time — the admin sees them instantly.</p>
      </div>
    </div>);

  if (!worker) return (
    <div className="phone" style={{ paddingBottom: 20 }}>
      <div className="top"><div className="logo">Wash<span>Pro</span> Worker</div><p style={{ opacity: .85, fontSize: 13, margin: "8px 0 0" }}>Sign in to see today's jobs · Hyderabad {isDemoMode && "· DEMO MODE"}</p></div>
      <div className="card"><b>Select your worker profile</b><p className="muted">Demo mode only — live workers sign in with email + password.</p>
        {state.workers.filter(w => w.status === "approved").map(w => (
          <button key={w.uid} className="check" onClick={() => { setState(s => ({ ...s, workerUid: w.uid, available: w.isAvailable })); setToast(`Welcome, ${w.name.split(" ")[0]}!`); }}>
            <span className="avatar" style={{ background: w.photoColor }}>{w.name.split(" ").map((x: string) => x[0]).join("")}</span>
            <span style={{ flex: 1 }}><b>{w.name}</b><br /><span className="muted">★ {w.rating} · {w.completedJobs} jobs · {w.serviceAreaIds.join(", ")}</span></span><span>→</span>
          </button>))}
        <p className="small muted" style={{ marginTop: 10 }}>Pending-approval workers (e.g. Vijay Singh) cannot sign in until an admin approves them.</p>
      </div>
    </div>);

  const open = myJobs.find(b => b.id === openId) || null;
  const service = open ? SERVICES.find(s => s.id === open.serviceId) : null;

  return (
    <div className="phone">
      <div className="top">
        <div className="toprow"><span className="logo">Wash<span>Pro</span></span><span className="pill"><span className={`dot ${online ? "" : "off"}`} />{online ? "Online" : "Offline — will retry"}</span></div>
        <div style={{ display: "flex", gap: 12, alignItems: "center", marginTop: 16 }}>
          <span className="avatar" style={{ background: worker.photoColor, width: 52, height: 52, fontSize: 19 }}>{worker.name.split(" ").map((x: string) => x[0]).join("")}</span>
          <div style={{ flex: 1 }}><div style={{ fontWeight: 800, fontSize: 17 }}>{worker.name}</div><div style={{ opacity: .8, fontSize: 12 }}>★ {worker.rating} · {worker.completedJobs} jobs completed</div></div>
          <div style={{ textAlign: "center" }}><button className={`switch ${(LIVE ? worker.isAvailable : state.available) ? "on" : ""}`} aria-label="availability" onClick={() => { if (LIVE && liveWorker) { liveWorkerUpdate(liveWorker.uid, { isAvailable: !liveWorker.isAvailable }); setLiveWorker({ ...liveWorker, isAvailable: !liveWorker.isAvailable }); setToast(liveWorker.isAvailable ? "You are now OFF shift" : "You are ON shift — eligible for jobs"); return; } setState(s => ({ ...s, available: !s.available })); setToast(state.available ? "You are now OFF shift" : "You are ON shift — eligible for jobs"); }} /><div style={{ fontSize: 10, opacity: .85, marginTop: 3 }}>{(LIVE ? worker.isAvailable : state.available) ? "ON SHIFT" : "OFF SHIFT"}</div></div>
        </div>
      </div>

      {tab === "today" && !open && <>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 10, margin: "14px 14px 0" }}>
          <div className="stat"><b>{myJobs.length}</b><span className="muted">Jobs today</span></div>
          <div className="stat"><b>{doneToday.length}</b><span className="muted">Completed</span></div>
          <div className="stat"><b>{inr(earnedToday)}</b><span className="muted">Earned today</span></div>
        </div>
        {active && <div className="card" style={{ borderColor: "#99F6E4", background: "#F0FDFD" }}><div className="toprow"><b>🔴 Active job</b><Chip s={active.status} /></div><p style={{ margin: "8px 0 4px", fontWeight: 700 }}>{active.serviceName} — {active.vehicleLabel}</p><p className="muted" style={{ margin: 0 }}>{active.addressSnapshot}</p>{active.status === "en_route" && <p className="small" style={{ color: "#0F766E" }}>📍 Sharing live location {state.lastLoc ? `· updated ${new Date(state.lastLoc.at).toLocaleTimeString("en-IN")} (${state.lastLoc.lat.toFixed(4)}, ${state.lastLoc.lng.toFixed(4)})` : "…"} · ping #{tick}</p>}<button className="btn btn-p" style={{ marginTop: 10 }} onClick={() => setOpenId(active.id)}>Continue job →</button></div>}
        {next && !active && <div className="card"><div className="toprow"><b>Next job · {fmtTime(next.scheduledAt)}</b><Chip s={next.status} /></div><p style={{ margin: "8px 0 4px", fontWeight: 700 }}>{next.serviceName} — {next.vehicleLabel}</p><p className="muted" style={{ margin: 0 }}>{next.customerName} · {next.addressLabel}</p><button className="btn btn-n" style={{ marginTop: 10 }} onClick={() => setOpenId(next.id)}>Open job →</button></div>}
        <div className="card"><b>Today's schedule</b>{myJobs.length === 0 && <p className="muted">No jobs assigned yet. Stay on shift — new jobs appear here.</p>}{myJobs.map(b => <JobRow key={b.id} b={b} onClick={() => setOpenId(b.id)} />)}</div>
      </>}

      {tab === "jobs" && !open && <div className="card"><b>All my jobs</b>{myJobs.map(b => <JobRow key={b.id} b={b} onClick={() => setOpenId(b.id)} />)}{myJobs.length === 0 && <p className="muted">No assigned jobs.</p>}<button className="btn btn-g" onClick={() => { reset(); location.reload(); }}>Reset demo data</button></div>}

      {tab === "earnings" && !open && <div className="card"><b>💰 Earnings</b>
        <div className="kv"><span>Today (completed + in hand)</span><b>{inr(earnedToday)}</b></div>
        <div className="kv"><span>Worker share</span><span>70% of booking value</span></div>
        <div className="kv"><span>Completed jobs (lifetime)</span><span>{worker.completedJobs}</span></div>
        <div className="kv"><span>Next payout</span><span>Friday · UPI</span></div>
        <p className="muted">Payouts are calculated by <code>calculateWorkerEarnings</code> and released by Finance (PRD §10.5). Cash collected must match completed cash jobs — differences need a reason.</p>
        {doneToday.map(b => <div key={b.id} className="kv"><span>{b.serviceName} · {b.id}</span><b>{inr(Math.round(b.priceSnapshot.totalPaise * 0.7))}</b></div>)}
      </div>}

      {tab === "profile" && !open && <div className="card"><b>Profile</b>
        <div className="kv"><span>Name</span><b>{worker.name}</b></div><div className="kv"><span>Email</span><span>{worker.email || fbUser?.email || "—"}</span></div>{worker.phone ? <div className="kv"><span>Phone</span><span>{worker.phone}</span></div> : null}
        <div className="kv"><span>Status</span><span className="chip" style={{ background: "#DCFCE7", color: "#15803D" }}>{worker.status}</span></div>
        <div className="kv"><span>Service areas</span><span>{worker.serviceAreaIds.join(", ")}</span></div>
        <div className="kv"><span>Services</span><span>{worker.serviceIds.join(", ")}</span></div>
        <button className="btn btn-g" style={{ marginTop: 12 }} onClick={() => { if (LIVE) { liveLogout(); setLiveWorker(null); } else setState(s => ({ ...s, workerUid: null })); }}>Switch worker / Sign out</button>
        <button className="btn btn-danger" style={{ marginTop: 8 }} onClick={() => { reset(); location.reload(); }}>Reset demo data</button>
        <p className="small muted">WashPro Worker PWA · installable · location shared only during an active trip (PRD §6.3). Photos upload to private Storage; never cached publicly.</p>
      </div>}

      {open && service && <div>
        <div className="card">
          <button className="btn btn-g" style={{ width: "auto", padding: "8px 14px" }} onClick={() => setOpenId(null)}>← Back</button>
          <div className="toprow" style={{ marginTop: 12 }}><b style={{ fontSize: 17 }}>{open.serviceName}</b><Chip s={open.status} /></div>
          <p className="muted" style={{ margin: "6px 0" }}>{open.id} · {open.bookingType} · ⏱ {open.estimatedDurationMinutes} min · <b style={{ color: "#12263A" }}>{inr(open.priceSnapshot.totalPaise)}</b> ({open.paymentMethod}{open.paymentMethod === "cash" ? ` · ${open.paymentStatus === "paid" ? "collected ✓" : "collect from customer"}` : ` · ${open.paymentStatus}`})</p>
          <div className="kv"><span>Customer</span><b>{open.customerName}</b></div>
          <div className="kv"><span>Vehicle</span><span>{open.vehicleLabel}</span></div>
          <div className="kv"><span>When</span><span>{fmtTime(open.scheduledAt)}</span></div>
          <div className="kv"><span>Location</span><span style={{ textAlign: "right", maxWidth: "60%" }}>{open.addressSnapshot}</span></div>
          <a className="btn btn-g" style={{ textDecoration: "none", marginTop: 10 }} href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(open.addressSnapshot)}`} target="_blank" rel="noreferrer">🧭 Navigate with Google Maps</a>
          <a className="btn btn-g" style={{ textDecoration: "none", marginTop: 8 }} href={`tel:${open.customerPhone.replace(/\s/g, "")}`}>📞 Call customer</a>
        </div>

        <div className="card"><b>Job workflow</b>
          {["assigned", "en_route", "arrived", "in_progress", "pending_verification", "completed"].map((s, i) => {
            const order = ["assigned", "en_route", "arrived", "in_progress", "pending_verification", "completed"];
            const cur = order.indexOf(open.status);
            return <div key={s} className={`step ${i < cur || open.status === "completed" && i <= cur ? "done" : i === cur ? "now" : ""}`}><span className="n">{i < cur || open.status === "completed" ? "✓" : i + 1}</span><span>{STATUS_LABEL[s as Booking["status"]]}</span></div>;
          })}
          {open.status === "assigned" && <button className="btn btn-p" onClick={() => { if (!canTransition(open.status, "en_route")) return; patch(open.id, { status: "en_route" }); setState(s => ({ ...s, lastLoc: { lat: 17.4435, lng: 78.3772, at: new Date().toISOString() } })); setToast("Trip started — location sharing ON"); }}>▶ Start trip (share location)</button>}
          {open.status === "en_route" && <><p className="small" style={{ color: "#0F766E" }}>📍 Live location sharing… {state.lastLoc && `last ping ${new Date(state.lastLoc.at).toLocaleTimeString("en-IN")}`}. Customer sees your last known location, not a fake ETA.</p><button className="btn btn-p" onClick={() => { patch(open.id, { status: "arrived" }); setToast("Arrived — location sharing stopped"); }}>📍 I've arrived (stop tracking)</button></>}
          {open.status === "arrived" && <button className="btn btn-p" onClick={() => patch(open.id, { status: "in_progress" })}>✓ Check in & start wash</button>}
        </div>

        {(open.status === "in_progress" || open.status === "pending_verification" || open.status === "completed") && <>
          <div className="card"><b>✅ Service checklist</b><p className="muted" style={{ margin: "4px 0 8px" }}>{open.checklistDone.length}/{service.checklist.length} done — all required before completion</p>
            <div className="progress"><i style={{ width: `${service.checklist.length ? open.checklistDone.length / service.checklist.length * 100 : 0}%` }} /></div>
            {service.checklist.map(item => { const done = open.checklistDone.includes(item); return <button key={item} className={`check ${done ? "done" : ""}`} disabled={open.status !== "in_progress"} onClick={() => patch(open.id, { checklistDone: done ? open.checklistDone.filter((x: string) => x !== item) : [...open.checklistDone, item] })}><span>{done ? "✅" : "⬜"}</span><span>{item}</span></button>; })}
            {open.status === "in_progress" && <button className="btn btn-p" style={{ marginTop: 12 }} disabled={open.checklistDone.length < service.checklist.length} onClick={() => { patch(open.id, { status: "pending_verification" }); setToast("Sent to customer for verification"); }}>Request customer verification →</button>}
            {open.checklistDone.length < service.checklist.length && open.status === "in_progress" && <p className="small muted" style={{ textAlign: "center" }}>Finish the checklist to continue.</p>}
          </div>
        </>}

        {open.status === "pending_verification" && <div className="card" style={{ textAlign: "center" }}><div style={{ fontSize: 34 }}>⏳</div><b>Waiting for customer verification</b><p className="muted">{LIVE ? "The customer confirms completion in their app — this job will update here automatically." : "Customer confirms in their app (or demo: confirm below as if customer tapped ✓)."}</p>
          {!LIVE && <button className="btn btn-p" onClick={() => { patch(open.id, { status: "completed", completedAt: new Date().toISOString(), paymentStatus: open.paymentMethod === "cash" ? "paid" : open.paymentStatus }); setState(s => ({ ...s, earningsExtra: s.earningsExtra + Math.round(open.priceSnapshot.totalPaise * 0.7) })); setToast(`Job complete! +${inr(Math.round(open.priceSnapshot.totalPaise * 0.7))} earned`); }}>✓ Simulate customer verification{open.paymentMethod === "cash" ? ` + collect ${inr(open.priceSnapshot.totalPaise)} cash` : ""}</button>}</div>}
        {open.status === "completed" && <div className="card" style={{ textAlign: "center", background: "#F0FDF4" }}><div style={{ fontSize: 34 }}>🎉</div><b>Job completed</b><p className="muted">You earned {inr(Math.round(open.priceSnapshot.totalPaise * 0.7))} (70% share){open.paymentMethod === "cash" && " · cash collected & recorded for finance reconciliation"}</p></div>}
      </div>}

      {!open && <nav className="nav">
        <button className={tab === "today" ? "on" : ""} onClick={() => setTab("today")}><i>🏠</i>Today</button>
        <button className={tab === "jobs" ? "on" : ""} onClick={() => setTab("jobs")}><i>🧽</i>My Jobs</button>
        <button className={tab === "earnings" ? "on" : ""} onClick={() => setTab("earnings")}><i>💰</i>Earnings</button>
        <button className={tab === "profile" ? "on" : ""} onClick={() => setTab("profile")}><i>👤</i>Profile</button>
      </nav>}
      {toast && <div className="toast">{toast}</div>}
    </div>
  );
}
function JobRow({ b, onClick }: { b: Booking; onClick: () => void }) {
  return <button className="check" onClick={onClick}><span style={{ fontSize: 22 }}>{b.serviceId === "deep-clean" ? "✨" : b.serviceId === "interior" ? "🧽" : "🚿"}</span><span style={{ flex: 1 }}><b>{b.serviceName}</b> · {fmtTime(b.scheduledAt)}<br /><span className="muted">{b.vehicleLabel} · {b.addressLabel}</span></span><Chip s={b.status} /></button>;
}
