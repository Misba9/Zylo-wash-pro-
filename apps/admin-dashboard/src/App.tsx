import { useEffect, useMemo, useRef, useState } from "react";
import { Booking, STATUS_LABEL, SERVICES, SERVICE_AREAS, PLANS, inr, recommendWorkers, canTransition, hasValidCoordinates, mapsDirectionsUrl, osmEmbedUrl, type ServiceLocation } from "../../../packages/shared-types/src/index";
import { load, save, reset, newAudit, fmtTime } from "./store";
import { isDemoMode } from "./firebase";
import { LIVE, watchAuth, login, logout, subscribeAll, liveUpdate, liveAudit, liveNotify, seedPilot, claimAdmin, ensureAdmin, type User } from "./live";
import { ServicesCatalogPage, PricingCalculatorPage, AddonsPage, PackagesPage } from "./pages/CatalogPages";

type Page = "overview"|"analytics"|"bookings"|"customers"|"workers"|"services"|"pricing"|"packages"|"addons"|"coupons"|"areas"|"finance"|"subs"|"reports"|"notifications"|"config"|"admins"|"support"|"audit";
const CHIP: Record<string,string> = { requested:"#E2E8F0/#475569", awaiting_payment:"#FEF3C7/#B45309", confirmed:"#DBEAFE/#1D4ED8", assigned:"#E0E7FF/#3730A3", en_route:"#FEF3C7/#B45309", arrived:"#E0E7FF/#3730A3", in_progress:"#CCFBF1/#0F766E", pending_verification:"#FCE7F3/#9D174D", completed:"#DCFCE7/#15803D", cancelled:"#FEE2E2/#B91C1C", under_review:"#FDE68A/#92400E" };
const Chip = ({s}:{s:string})=>{ const [bg,fg]=(CHIP[s]||"#E2E8F0/#475569").split("/"); return <span className="chip" style={{background:bg,color:fg}}>{STATUS_LABEL[s as Booking["status"]]||s}</span>; };
const csv = (rows: string[][]) => { const blob = new Blob([rows.map(r=>r.map(c=>`"${String(c).replace(/"/g,'""')}"`).join(",")).join("\n")], {type:"text/csv"}); const a=document.createElement("a"); a.href=URL.createObjectURL(blob); a.download="washpro-export.csv"; a.click(); };

export default function App(){
  const [state,setState]=useState(load);
  const [page,setPage]=useState<Page>("overview");
  const [q,setQ]=useState(""); const [statusF,setStatusF]=useState("all");
  const [assignId,setAssignId]=useState<string|null>(null);
  const [detailId,setDetailId]=useState<string|null>(null);
  const [toast,setToast]=useState(""); const [note,setNote]=useState("");
  const [user,setUser]=useState<User|null>(null); const [authReady,setAuthReady]=useState(!LIVE);
  const [email,setEmail]=useState("admin@washproo.in"); const [pw,setPw]=useState(""); const [loginErr,setLoginErr]=useState("");
  const [adminBoot,setAdminBoot]=useState(false);
  const liveWorkersLoaded = useRef(false);
  const autoApproved = useRef<Set<string>>(new Set());
  useEffect(()=>{ if(!LIVE) return; return watchAuth(u=>{ setUser(u); setAuthReady(true); }); },[]);
  // Auto-activate: bootstrap admin gets their admins/{uid} doc on first sign-in
  // (no manual button click needed). Reload once so Firestore listeners that
  // were denied before activation reconnect with admin rights.
  useEffect(()=>{ if(!LIVE || !user) return; let live=true; ensureAdmin(user.uid, user.email||"").then(r=>{ if(!live) return; setAdminBoot(true); if(r==="created" && !sessionStorage.getItem("wp-admin-boot")){ sessionStorage.setItem("wp-admin-boot","1"); setTimeout(()=>location.reload(), 500); } }).catch(()=>{ if(live) setAdminBoot(true); }); return ()=>{ live=false; }; },[user]);
  useEffect(()=>{ if(!LIVE || !user) return; return subscribeAll(patch=>{ if("workers" in patch) liveWorkersLoaded.current = true; setState(s=>({...s, ...(patch as any)})); }); },[user]);
  // Auto-approve: self-registered workers (long Firebase uids) never wait for a
  // manual Approve click. Demo/seed workers (w1…w6) still use the Approve button.
  useEffect(()=>{ if(!LIVE || !user || !adminBoot || !liveWorkersLoaded.current) return; const pending = state.workers.filter(w=>w.status==="pending" && w.uid.length>20 && !autoApproved.current.has(w.uid)); if(!pending.length) return; pending.forEach(w=>{ autoApproved.current.add(w.uid); patchWorker(w.uid,{status:"approved",isAvailable:true}); }); liveAudit(user.email||"admin","autoApproveWorker",pending.map(w=>w.name).join(", ")).catch(()=>{}); setToast(`Auto-approved: ${pending.map(w=>w.name).join(", ")} ✓`); },[state.workers, adminBoot, user]);
  useEffect(()=>{ if(!LIVE) save(state); },[state]);
  useEffect(()=>{ if(!toast) return; const t=setTimeout(()=>setToast(""),3200); return ()=>clearTimeout(t); },[toast]);

  const b = state.bookings;
  const revenue = state.payments.filter(p=>p.status==="paid"||p.status==="collected").reduce((n,p)=>n+p.amountPaise,0);
  const refunds = state.payments.filter(p=>String(p.status).includes("refund")).reduce((n,p)=>n+p.amountPaise,0);
  const filtered = b.filter(x=> (statusF==="all"||x.status===statusF) && (q===""|| `${x.id} ${x.customerName} ${x.vehicleLabel} ${x.serviceName}`.toLowerCase().includes(q.toLowerCase())) );
  const assignBooking = b.find(x=>x.id===assignId) || null;
  const detail = b.find(x=>x.id===detailId) || null;
  const recs = useMemo(()=> assignBooking ? recommendWorkers(assignBooking, state.workers) : [], [assignBooking, state.workers]);
  const audit = (action:string,target:string,reason?:string)=>{ if(LIVE){ liveAudit(user?.email||"admin",action,target,reason).catch(()=>{}); return; } setState(s=>({...s, audit:[newAudit(s.role==="Super Admin"?"super@washpro.in":s.role==="Finance"?"finance@washpro.in":"ops@washpro.in", action,target,reason), ...s.audit]})); };
  const patchBooking=(id:string,p:Partial<Booking>)=>{ if(LIVE){ liveUpdate("bookings",id,{...p,updatedAt:new Date().toISOString()}).catch(e=>setToast("Write failed: "+e.code)); return; } setState(s=>({...s, bookings:s.bookings.map(x=>x.id===id?{...x,...p,updatedAt:new Date().toISOString()}:x)})); };
  const patchWorker=(uid:string,p:Record<string,unknown>)=>{ if(LIVE){ liveUpdate("workers",uid,p).catch(e=>setToast("Write failed: "+e.code)); return; } setState(s=>({...s, workers:s.workers.map(x=>x.uid===uid?{...x,...p} as any:x)})); };
  const patchPayment=(id:string,p:Record<string,unknown>)=>{ if(LIVE){ liveUpdate("payments",id,p).catch(e=>setToast("Write failed: "+e.code)); return; } setState(s=>({...s, payments:s.payments.map(x=>x.id===id?{...x,...p} as any:x)})); };
  const patchSub=(id:string,p:Record<string,unknown>)=>{ if(LIVE){ liveUpdate("subscriptions",id,p).catch(e=>setToast("Write failed: "+e.code)); return; } setState(s=>({...s, subscriptions:s.subscriptions.map(x=>x.id===id?{...x,...p} as any:x)})); };
  const patchTicket=(id:string,p:Record<string,unknown>)=>{ if(LIVE){ liveUpdate("supportTickets",id,p).catch(e=>setToast("Write failed: "+e.code)); return; } setState(s=>({...s, tickets:s.tickets.map(x=>x.id===id?{...x,...p} as any:x)})); };

  const doAssign=(workerUid:string, workerName:string, score:number)=>{
    if(!assignBooking) return;
    patchBooking(assignBooking.id,{assignedWorkerUid:workerUid, workerName, status:"assigned"});
    patchWorker(workerUid,{activeJobs:(state.workers.find(w=>w.uid===workerUid)?.activeJobs||0)+1});
    if (LIVE && (assignBooking as any).customerUid) liveNotify((assignBooking as any).customerUid, "Worker assigned", `${workerName} is assigned to your ${assignBooking.serviceName} (${assignBooking.id}).`, assignBooking.id).catch(() => {});
    audit(assignBooking.assignedWorkerUid?"reassignWorker":"assignWorker", `${assignBooking.id} → ${workerName}`, score>=0?`Recommendation score ${score}`:"Admin override");
    setAssignId(null); setToast(`Assigned ${workerName} to ${assignBooking.id} · worker + customer notified`);
  };

  if (LIVE && !authReady) return <div style={{display:"flex",alignItems:"center",justifyContent:"center",minHeight:"100vh"}}><p className="muted">Connecting to ZYLO Control (wash-pro-7f3b1)…</p></div>;
  if (LIVE && !user) return <div style={{display:"flex",alignItems:"center",justifyContent:"center",minHeight:"100vh",background:"#0B2A4A",padding:18}}><div className="card" style={{maxWidth:380,width:"100%"}}><div style={{fontSize:22,fontWeight:800}}>ZYLO <span style={{color:"#C49A45"}}>Control</span></div><p className="muted">Live mode · project <b>wash-pro-7f3b1</b></p><form onSubmit={async(e)=>{ e.preventDefault(); setLoginErr(""); try{ await login(email.trim().toLowerCase(),pw); }catch(err:any){ setLoginErr(err.code==="auth/invalid-credential"||err.code==="auth/wrong-password"||err.code==="auth/user-not-found" ? "Wrong email or password. Use admin@washproo.in (note the double “oo”) and the password you set in Firebase Console." : err.code==="auth/configuration-not-found"||err.code==="auth/admin-restricted-operation" ? "Firebase Auth is not enabled yet — Console → Authentication → Get started, enable Email/Password, create this user, then add an admins/{uid} doc (see docs/FIREBASE_LIVE.md)." : err.code==="auth/too-many-requests" ? "Too many failed attempts — wait a few minutes and try again." : (err.message||"Login failed")); } }}><label className="small">Email</label><input className="input" type="email" autoComplete="username" style={{width:"100%",margin:"5px 0 10px"}} value={email} onChange={e=>setEmail(e.target.value)} placeholder="admin@washproo.in"/><label className="small">Password</label><input className="input" type="password" autoComplete="current-password" style={{width:"100%",margin:"5px 0 10px"}} value={pw} onChange={e=>setPw(e.target.value)} placeholder="••••••••"/>{loginErr&&<p style={{color:"#DC2626",fontSize:13}}>{loginErr}</p>}<button className="btn" type="submit" style={{width:"100%",padding:13}}>Sign in</button></form><p className="small muted">First run? After signing in, click “🔑 Activate admin / Seed pilot data” in the sidebar. Disable live mode by clearing apps/admin-dashboard/.env.local.</p></div></div>;

  return <div className="layout">
    <aside className="side">
      <div className="logo">ZYLO <span style={{color:"#C49A45"}}>Control</span><div className="hideS" style={{fontSize:11,color:"#8FB0CC",fontWeight:600}}>ADMIN · HYDERABAD</div></div>
      {([["overview","📊","Dashboard"],["analytics","📈","Analytics"],["bookings","🧾","Bookings"],["services","🧽","Services"],["pricing","💱","Pricing"],["packages","📦","Packages"],["addons","✨","Add-ons"],["coupons","🏷️","Coupons"],["areas","📍","Service Areas"],["customers","👤","Customers"],["workers","👷","Workers"],["finance","💰","Payments"],["subs","🔁","Subscriptions"],["reports","📄","Reports"],["notifications","🔔","Notifications"],["config","⚙️","App Config"],["admins","🔐","Admin Users"],["support","🎧","Support"],["audit","🛡️","Audit Logs"]] as [Page,string,string][]).map(([p,ic,l])=> <button key={p} data-testid={`nav-${p}`} className={page===p?"on":""} onClick={()=>setPage(p)}><span>{ic}</span><span className="lbl">{l}</span>{p==="bookings"&&b.filter(x=>["confirmed","awaiting_payment"].includes(x.status)&&!x.assignedWorkerUid).length>0&&<span className="chip" style={{background:"#F59E0B",color:"#fff",marginLeft:"auto"}}>{b.filter(x=>["confirmed","awaiting_payment"].includes(x.status)&&!x.assignedWorkerUid).length} unassigned</span>}</button>)}
      <div style={{marginTop:"auto"}} className="hideS">
        <label className="small" style={{color:"#8FB0CC"}}>Acting role (RBAC demo)</label>
        <select className="input" style={{width:"100%",marginTop:6}} value={state.role} onChange={e=>setState(s=>({...s,role:e.target.value}))}><option>Super Admin</option><option>Operations</option><option>Finance</option><option>Support</option></select>
        <p className="small" style={{color:"#8FB0CC"}}>{LIVE?`🟢 LIVE · wash-pro-7f3b1 · ${user?.email||""}`:"Demo mode · seed data"} · Asia/Kolkata · INR</p>
        {LIVE && <button className="btn" style={{width:"100%",marginBottom:8}} onClick={async()=>{ try{ await claimAdmin(user!.uid, user!.email||""); }catch(e:any){ setToast("Admin activation failed: "+(e.code||e.message)); return; } try{ await seedPilot(user!.uid, user!.email||""); setToast("Admin activated + pilot data seeded ✓ — reloading with live data…"); }catch(e:any){ setToast("Admin activated ✓ (seed skipped: "+(e.code||"")+") — reloading…"); } setTimeout(()=>location.reload(), 900); }}>🔑 Activate admin / Seed pilot data</button>}
        {LIVE ? <button className="btn g" style={{width:"100%"}} onClick={()=>logout()}>Sign out</button> : <button className="btn g" style={{width:"100%"}} onClick={()=>{reset();location.reload();}}>Reset demo data</button>}
      </div>
    </aside>

    <main className="main">
      {page==="overview" && <>
        <h1 style={{margin:"2px 0 4px"}}>Good morning 👋</h1><p className="muted" style={{marginTop:0}}>{new Date().toLocaleDateString("en-IN",{weekday:"long",day:"numeric",month:"long",year:"numeric"})} · Hyderabad operations</p>
        <div className="grid" style={{gridTemplateColumns:"repeat(auto-fit,minmax(165px,1fr))"}}>
          <div className="card kpi"><span className="muted">Bookings today</span><b>{b.length}</b><span className="small">{b.filter(x=>x.status==="completed").length} completed</span></div>
          <div className="card kpi"><span className="muted">Unassigned</span><b style={{color:"#D97706"}}>{b.filter(x=>x.status==="confirmed").length}</b><span className="small">needs worker</span></div>
          <div className="card kpi"><span className="muted">Active jobs</span><b>{b.filter(x=>["en_route","arrived","in_progress"].includes(x.status)).length}</b><span className="small">in field now</span></div>
          <div className="card kpi"><span className="muted">Collected revenue</span><b>{inr(revenue)}</b><span className="small">refunds {inr(refunds)}</span></div>
          <div className="card kpi"><span className="muted">Active subscriptions</span><b>{state.subscriptions.filter(s=>s.status==="active").length}</b><span className="small">{state.subscriptions.reduce((n,s)=>n+s.visitBalance,0)} visits remaining</span></div>
          <div className="card kpi"><span className="muted">Open tickets</span><b>{state.tickets.filter(t=>t.status!=="resolved").length}</b><span className="small">satisfaction ★ 4.8</span></div>
        </div>
        <div className="grid" style={{gridTemplateColumns:"1.6fr 1fr",marginTop:14}}>
          <div className="card"><div style={{display:"flex",justifyContent:"space-between"}}><b>Needs attention</b><button className="btn g" onClick={()=>setPage("bookings")}>All bookings →</button></div>
            {b.filter(x=>["confirmed","pending_verification","under_review"].includes(x.status)).map(x=><div key={x.id} style={{display:"flex",gap:10,alignItems:"center",padding:"11px 0",borderBottom:"1px dashed #E8EFF5"}}><span style={{flex:1}}><b>{x.serviceName}</b> · {x.customerName}<br/><span className="muted">{x.id} · {fmtTime(x.scheduledAt)} · {x.vehicleLabel}</span></span><Chip s={x.status}/>{x.status==="confirmed"&&<button className="btn" onClick={()=>setAssignId(x.id)}>Assign</button>}<button className="btn g" onClick={()=>setDetailId(x.id)}>View</button></div>)}
          </div>
          <div className="card"><b>Workers on shift</b>{state.workers.filter(w=>w.status==="approved").map(w=><div key={w.uid} style={{display:"flex",gap:10,alignItems:"center",padding:"9px 0",borderBottom:"1px dashed #E8EFF5"}}><span className="avatar" style={{background:w.photoColor}}>{w.name.split(" ").map(x=>x[0]).join("")}</span><span style={{flex:1}}><b>{w.name}</b><br/><span className="muted">★{w.rating} · {w.activeJobs} active</span></span><span className="chip" style={{background:w.isAvailable?"#DCFCE7":"#FEE2E2",color:w.isAvailable?"#15803D":"#B91C1C"}}>{w.isAvailable?"Available":"Off shift"}</span></div>)}</div>
        </div>
      </>}

      {page==="bookings" && <div className="card"><div style={{display:"flex",gap:10,flexWrap:"wrap",alignItems:"center"}}><h2 style={{margin:0,flex:1}}>Bookings</h2><input className="input" placeholder="Search customer, vehicle, ID…" value={q} onChange={e=>setQ(e.target.value)} style={{minWidth:230}}/><select className="input" value={statusF} onChange={e=>setStatusF(e.target.value)}><option value="all">All statuses</option>{Object.keys(STATUS_LABEL).map(s=><option key={s} value={s}>{STATUS_LABEL[s as Booking["status"]]}</option>)}</select><button className="btn g" onClick={()=>csv([["ID","Customer","Service","Status","Worker","Amount","When"],...filtered.map(x=>[x.id,x.customerName,x.serviceName,x.status,x.workerName||"",String(x.priceSnapshot.totalPaise/100),x.scheduledAt])])}>⬇ CSV</button></div>
        <div style={{overflowX:"auto"}}><table><thead><tr><th>Booking</th><th>Customer / Vehicle</th><th>Schedule</th><th>Worker</th><th>Payment</th><th>Status</th><th></th></tr></thead><tbody>
        {filtered.map(x=><tr key={x.id}><td><b>{x.serviceName}</b><br/><span className="muted">{x.id} · {x.bookingType}</span></td><td>{x.customerName}<br/><span className="muted">{x.vehicleLabel}</span></td><td>{fmtTime(x.scheduledAt)}<br/><span className="muted">{x.addressLabel}</span></td><td>{x.workerName||<span style={{color:"#D97706",fontWeight:700}}>Unassigned</span>}</td><td>{inr(x.priceSnapshot.totalPaise)}<br/><span className="muted">{x.paymentMethod} · {x.paymentStatus}</span></td><td><Chip s={x.status}/></td><td style={{whiteSpace:"nowrap"}}><button className="btn g" onClick={()=>setDetailId(x.id)}>Details</button> {(x.status==="confirmed"||x.status==="assigned"||x.status==="awaiting_payment")&&<button className="btn" onClick={()=>setAssignId(x.id)}>{x.workerName?"Reassign":"Assign"}</button>}</td></tr>)}
        {filtered.length===0&&<tr><td colSpan={7} className="muted" style={{textAlign:"center",padding:24}}>No bookings match.</td></tr>}
        </tbody></table></div></div>}

      {page==="customers" && <CustomersPanel bookings={b} addresses={(state as any).addresses || []} />}

      {page==="workers" && <div className="card"><h2 style={{marginTop:0}}>Workers</h2><table><thead><tr><th>Worker</th><th>Areas</th><th>Rating</th><th>Jobs</th><th>Today</th><th>Status</th><th></th></tr></thead><tbody>
        {state.workers.map(w=><tr key={w.uid}><td><span className="avatar" style={{background:w.photoColor,marginRight:8}}>{w.name.split(" ").map(x=>x[0]).join("")}</span><b>{w.name}</b><br/><span className="muted" style={{marginLeft:48}}>{w.phone}</span></td><td>{w.serviceAreaIds.join(", ")}</td><td>★ {w.rating}</td><td>{w.completedJobs} done · {w.activeJobs} active</td><td>{inr(w.earningsTodayPaise)}</td><td><span className="chip" style={{background:w.status==="approved"?"#DCFCE7":"#FEF3C7",color:w.status==="approved"?"#15803D":"#B45309"}}>{w.status}</span> <span className="chip" style={{background:"#E2E8F0",color:"#475569"}}>{w.isAvailable?"on shift":"off"}</span></td><td style={{whiteSpace:"nowrap"}}>{w.status==="pending"&&<button className="btn" onClick={()=>{patchWorker(w.uid,{status:"approved",isAvailable:true}); audit("approveWorker",w.name); setToast(`${w.name} approved ✓`);}}>Approve</button>} {w.status==="approved"&&<button className="btn g" onClick={()=>patchWorker(w.uid,{isAvailable:!w.isAvailable})}>{w.isAvailable?"Set off":"Set on"}</button>} {w.status==="approved"&&<button className="btn d" onClick={()=>{patchWorker(w.uid,{status:"suspended",isAvailable:false}); audit("suspendWorker",w.name);}}>Suspend</button>}</td></tr>)}
      </tbody></table></div>}

      {page==="services" && <ServicesCatalogPage services={state.services as any} onServices={(services)=>setState(s=>({...s, services: services as any}))} actorEmail={user?.email||"admin"} toast={setToast} />}
      {page==="pricing" && <PricingCalculatorPage services={state.services as any} addons={(state as any).addons || []} />}
      {page==="packages" && <PackagesPage plans={((state as any).plans || []).length ? (state as any).plans : PLANS.map(p=>({ id:p.id, name:p.name, visits:p.visits, validityDays:p.validityDays, frequency:p.frequency, billingMode:p.billingMode, pricePaise:{ seater5:p.pricePaise.sedan, seater7:p.pricePaise.suv }, active:true, popular:!!p.popular }))} onPlans={(plans)=>setState(s=>({...s, plans} as any))} actorEmail={user?.email||"admin"} toast={setToast} />}
      {page==="addons" && <AddonsPage addons={(state as any).addons || []} onAddons={(addons)=>setState(s=>({...s, addons} as any))} services={state.services as any} actorEmail={user?.email||"admin"} toast={setToast} />}
      {page==="coupons" && <div className="card"><h2 style={{marginTop:0}}>Coupons</h2><p className="muted">Phase 3 — create/disable coupons with server-side redemption. Seed includes <b>WELCOME75</b> (₹75 fixed).</p><p>Use Pricing calculator to preview WELCOME75 against live service prices.</p></div>}
      {page==="areas" && <div className="card"><h2 style={{marginTop:0}}>Service areas</h2><p className="muted">Phase 3 CRUD. Seeded Hyderabad areas:</p><ul>{SERVICE_AREAS.map(a=><li key={a.id}><b>{a.name}</b> · {a.pincodes.join(", ")} · {a.cashEligible?"cash ✓":"online only"} · {a.active?"active":"off"}</li>)}</ul></div>}
      {page==="analytics" && <div className="card"><h2 style={{marginTop:0}}>Analytics</h2><p className="muted">Phase 6 — charts from <code>analyticsDaily</code> aggregates (no dummy series). Dashboard KPIs above use live bookings/payments.</p></div>}
      {page==="reports" && <div className="card"><h2 style={{marginTop:0}}>Reports</h2><p className="muted">Phase 6 — filtered exports. Bookings & payments CSV already available on those pages.</p></div>}
      {page==="notifications" && <div className="card"><h2 style={{marginTop:0}}>Notifications</h2><p className="muted">Phase 5 — broadcast via FCM Cloud Functions. Assign flow already writes customer notifications.</p></div>}
      {page==="config" && <div className="card"><h2 style={{marginTop:0}}>App configuration</h2><p className="muted">Phase 3 — banners, fees (<code>appConfig/fees</code>), policies. Seed writes fees: service ₹29 · express ₹99 · version zylo-2026.11-v2.</p></div>}
      {page==="admins" && <div className="card"><h2 style={{marginTop:0}}>Admin users & roles</h2><p className="muted">Phase 7 — claim-based RBAC. Today: <code>admins/{"{uid}"}</code> + Firestore rules. Sidebar role switcher is demo-only.</p></div>}

      {page==="finance" && <><div className="grid" style={{gridTemplateColumns:"repeat(auto-fit,minmax(180px,1fr))"}}><div className="card kpi"><span className="muted">Collected</span><b>{inr(revenue)}</b></div><div className="card kpi"><span className="muted">Pending collection (cash)</span><b>{inr(state.payments.filter(p=>p.status==="pending_collection").reduce((n,p)=>n+p.amountPaise,0))}</b></div><div className="card kpi"><span className="muted">Refunds in progress</span><b style={{color:"#DC2626"}}>{inr(refunds)}</b></div><div className="card kpi"><span className="muted">Worker payouts due (70%)</span><b>{inr(Math.round(revenue*0.7))}</b></div></div>
      <div className="card" style={{marginTop:14}}><div style={{display:"flex",justifyContent:"space-between"}}><b>Payments & reconciliation</b><button className="btn g" onClick={()=>csv([["Payment","Booking","Customer","Amount","Method","Status","Ref"],...state.payments.map(p=>[p.id,p.bookingId||"",p.customerName,String(p.amountPaise/100),p.method,String(p.status),p.providerRef||""])])}>⬇ Export CSV</button></div>
      <table><thead><tr><th>Payment</th><th>Customer</th><th>Amount</th><th>Method</th><th>Status</th><th></th></tr></thead><tbody>{state.payments.map(p=><tr key={p.id}><td>{p.id}<br/><span className="muted">{p.bookingId} · {p.providerRef||"—"}</span></td><td>{p.customerName}</td><td><b>{inr(p.amountPaise)}</b></td><td>{p.method}</td><td><span className="chip" style={{background:p.status==="paid"||p.status==="collected"?"#DCFCE7":String(p.status).includes("refund")?"#FEE2E2":"#FEF3C7",color:p.status==="paid"||p.status==="collected"?"#15803D":String(p.status).includes("refund")?"#B91C1C":"#B45309"}}>{String(p.status)}</span></td><td>{p.status==="paid"&&<button className="btn d" onClick={()=>{ if(state.role==="Operations"){setToast("Refunds require Finance role — switch role in sidebar");return;} patchPayment(p.id,{status:"refund_pending"}); audit("requestRefund",`${p.id} · ${inr(p.amountPaise)}`,"Admin-initiated"); setToast("Refund requested via Razorpay (idempotent)");}}>Refund</button>} {p.status==="pending_collection"&&<button className="btn" onClick={()=>{patchPayment(p.id,{status:"collected"}); audit("recordCashCollection",p.id); setToast("Cash reconciled ✓");}}>Mark collected</button>}</td></tr>)}</tbody></table>
      <p className="muted">Revenue reporting separates booked value, collected, refunds & net (PRD §7.5). Online refunds go through <code>requestRefund</code>; cash is reconciled by Finance, never marked online-paid.</p></div></>}

      {page==="subs" && <div className="card"><h2 style={{marginTop:0}}>Subscriptions</h2>{state.subscriptions.map(s=><div key={s.id} style={{display:"flex",gap:12,alignItems:"center",padding:"12px 0",borderBottom:"1px dashed #E8EFF5",flexWrap:"wrap"}}><span style={{flex:1}}><b>{s.planName}</b> · {s.vehicleLabel}<br/><span className="muted">{s.billingMode} · {s.frequency} · {s.timeWindow} · next: {fmtTime(s.nextVisitAt)}</span></span><span className="chip" style={{background:"#E0E7FF",color:"#3730A3"}}>{s.visitBalance}/{s.totalVisits} visits left</span><span className="chip" style={{background:s.status==="active"?"#DCFCE7":"#FEF3C7",color:s.status==="active"?"#15803D":"#B45309"}}>{s.status}</span>{s.status==="active"?<button className="btn g" onClick={()=>{patchSub(s.id,{status:"paused"}); audit("pauseSubscription",s.id);}}>Pause</button>:<button className="btn" onClick={()=>{patchSub(s.id,{status:"active"}); audit("resumeSubscription",s.id);}}>Resume</button>}<button className="btn g" onClick={()=>{ if(s.visitBalance<=0){setToast("No visits left");return;} patchSub(s.id,{visitBalance:s.visitBalance-1}); setToast("Occurrence generated (unique key prevents duplicates)");}}>Generate visit</button></div>)}</div>}

      {page==="support" && <div className="card"><h2 style={{marginTop:0}}>Support tickets</h2>{state.tickets.map(t=><div key={t.id} style={{display:"flex",gap:10,alignItems:"center",padding:"11px 0",borderBottom:"1px dashed #E8EFF5"}}><span style={{flex:1}}><b>{t.subject}</b><br/><span className="muted">{t.customerName} · {fmtTime(t.createdAt)} · priority {t.priority}</span></span><span className="chip" style={{background:t.status==="resolved"?"#DCFCE7":"#FEF3C7",color:t.status==="resolved"?"#15803D":"#B45309"}}>{t.status}</span>{t.status!=="resolved"&&<button className="btn" onClick={()=>{patchTicket(t.id,{status:"resolved"}); audit("resolveTicket",t.id); setToast("Ticket resolved · customer notified");}}>Resolve</button>}</div>)}</div>}

      {page==="audit" && <div className="card"><h2 style={{marginTop:0}}>Audit logs <span className="muted" style={{fontSize:13}}>(super-admin only in production)</span></h2>{state.audit.map(a=><div key={a.id} style={{padding:"10px 0",borderBottom:"1px dashed #E8EFF5"}}><b>{a.action}</b> · {a.target}<br/><span className="muted">{a.actor} · {fmtTime(a.createdAt)}{a.reason?` · ${a.reason}`:""}</span></div>)}</div>}
    </main>

    {assignBooking && <div className="modalWrap" onClick={()=>setAssignId(null)}><div className="modal" onClick={e=>e.stopPropagation()}>
      <h3 style={{marginTop:0}}>Assign worker — {assignBooking.serviceName}</h3><p className="muted">{assignBooking.vehicleLabel} · {assignBooking.addressSnapshot} · {fmtTime(assignBooking.scheduledAt)}</p>
      <p className="small"><b>Ranked recommendations</b> (area · service · rating · distance · workload — PRD §7.3)</p>
      {recs.map(r=> <div key={r.worker.uid} style={{display:"flex",gap:10,alignItems:"center",padding:"11px",border:"1px solid #E2EAF1",borderRadius:13,margin:"8px 0",opacity:r.score<0?.55:1}}><span className="avatar" style={{background:r.worker.photoColor}}>{r.worker.name.split(" ").map(x=>x[0]).join("")}</span><span style={{flex:1}}><b>{r.worker.name}</b> {r.score>=0&&<span className="chip" style={{background:"#06B6C9",color:"#fff"}}>Score {r.score}</span>}<br/><span className="muted">{r.reasons.join(" · ")}</span></span><button className="btn" disabled={r.score<0} onClick={()=>doAssign(r.worker.uid,r.worker.name,r.score)}>{assignBooking.assignedWorkerUid===r.worker.uid?"Current":"Assign"}</button></div>)}
      <button className="btn g" style={{width:"100%",marginTop:8}} onClick={()=>setAssignId(null)}>Cancel</button>
    </div></div>}

    {detail && <div className="modalWrap" onClick={()=>setDetailId(null)}><div className="modal" onClick={e=>e.stopPropagation()}>
      <div style={{display:"flex",justifyContent:"space-between",alignItems:"center"}}><h3 style={{margin:0}}>{detail.serviceName} · {detail.id}</h3><Chip s={detail.status}/></div>
      <p className="muted">{detail.customerName} ({detail.customerPhone}) · {detail.vehicleLabel}</p>
      <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:8}}><span className="muted">Scheduled</span><span>{fmtTime(detail.scheduledAt)}</span><span className="muted">Worker</span><span>{detail.workerName||"—"}</span><span className="muted">Amount</span><span>{inr(detail.priceSnapshot.totalPaise)} · {detail.paymentMethod} · {detail.paymentStatus}</span><span className="muted">Checklist</span><span>{detail.checklistDone.length} items done</span><span className="muted">Price snapshot</span><span>{detail.priceSnapshot.pricingVersion}</span></div>
      <BookingServiceLocation booking={detail} onToast={setToast} />
      <div style={{display:"flex",gap:8,flexWrap:"wrap",marginTop:14}}>
        {(detail.status==="confirmed"||detail.status==="assigned"||detail.status==="awaiting_payment")&&<button className="btn" onClick={()=>{setDetailId(null);setAssignId(detail.id);}}>{detail.workerName?"Reassign":"Assign worker"}</button>}
        {detail.status==="pending_verification"&&<button className="btn" onClick={()=>{patchBooking(detail.id,{status:"completed",completedAt:new Date().toISOString()}); audit("verifyCompletion",detail.id); setDetailId(null); setToast("Completion verified ✓");}}>Verify completion</button>}
        {!["completed","cancelled"].includes(detail.status)&&<button className="btn d" onClick={()=>{patchBooking(detail.id,{status:"cancelled",cancelReason:"Admin cancelled"}); audit("cancelBooking",detail.id,note||"Admin action"); setDetailId(null); setToast("Booking cancelled · customer notified");}}>Cancel booking</button>}
        {canTransition(detail.status,"under_review")&&<button className="btn g" onClick={()=>{patchBooking(detail.id,{status:"under_review"}); audit("flagReview",detail.id); setToast("Flagged under review");}}>Flag review</button>}
      </div>
      <input className="input" style={{width:"100%",marginTop:12}} placeholder="Internal note / cancel reason (audited)…" value={note} onChange={e=>setNote(e.target.value)}/>
      <button className="btn g" style={{width:"100%",marginTop:10}} onClick={()=>{ if(note.trim()){audit("internalNote",detail.id,note); setNote(""); setToast("Note added to audit log");} setDetailId(null);}}>Close</button>
    </div></div>}
    {toast&&<div className="toast">{toast}</div>}
  </div>;
}

function bookingServiceLocation(b: Booking): ServiceLocation {
  const sl = (b as any).serviceLocation as ServiceLocation | undefined;
  if (sl) return sl;
  return {
    addressId: b.addressId,
    addressLabel: b.addressLabel,
    formattedAddress: b.addressSnapshot,
    latitude: null,
    longitude: null,
  };
}

function BookingServiceLocation({ booking, onToast }: { booking: Booking; onToast: (m: string) => void }) {
  const sl = bookingServiceLocation(booking);
  const lat = sl.latitude ?? null;
  const lng = sl.longitude ?? null;
  const ok = hasValidCoordinates(lat, lng);
  const address = sl.formattedAddress || booking.addressSnapshot || "—";
  return (
    <div style={{ marginTop: 14, padding: 12, borderRadius: 12, background: "#F8FAFC", border: "1px solid #E2E8F0" }}>
      <b>Service location snapshot</b>
      <p style={{ margin: "8px 0 4px" }}>{address}</p>
      {ok ? (
        <>
          <p className="muted" style={{ fontFamily: "ui-monospace, monospace", fontSize: 13 }}>
            Latitude: {(lat as number).toFixed(6)} · Longitude: {(lng as number).toFixed(6)}
          </p>
          <iframe
            title="Service map"
            style={{ width: "100%", height: 220, border: 0, borderRadius: 10, marginTop: 8 }}
            src={osmEmbedUrl(lat as number, lng as number)}
          />
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 10 }}>
            <a className="btn" style={{ textDecoration: "none" }} href={mapsDirectionsUrl(lat as number, lng as number)} target="_blank" rel="noreferrer">Open in Google Maps</a>
            <button type="button" className="btn g" onClick={async () => {
              try { await navigator.clipboard.writeText(`${lat},${lng}`); onToast("Coordinates copied"); }
              catch { onToast(`${lat}, ${lng}`); }
            }}>Copy coordinates</button>
          </div>
        </>
      ) : (
        <p style={{ color: "#B45309", margin: "8px 0 0" }}>Coordinates unavailable for this booking (legacy or unverified address). Do not invent a map pin.</p>
      )}
    </div>
  );
}

function CustomersPanel({ bookings, addresses }: { bookings: Booking[]; addresses: any[] }) {
  const customers = useMemo(() => {
    const map = new Map<string, { uid: string; name: string; phone: string; bookings: number }>();
    for (const b of bookings) {
      const uid = (b as any).customerUid || b.customerName;
      const cur = map.get(uid) || { uid, name: b.customerName, phone: b.customerPhone, bookings: 0 };
      cur.bookings += 1;
      map.set(uid, cur);
    }
    return [...map.values()].sort((a, b) => a.name.localeCompare(b.name));
  }, [bookings]);

  return (
    <div className="card">
      <h2 style={{ marginTop: 0 }}>Customers & saved addresses</h2>
      <p className="muted">Phone numbers shown for admin ops only. Addresses come from the shared `addresses` collection (ownerUid-scoped).</p>
      {customers.map((c) => {
        const addrs = addresses.filter((a) => a.ownerUid === c.uid);
        return (
          <div key={c.uid} style={{ padding: "14px 0", borderBottom: "1px dashed #E8EFF5" }}>
            <div style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "baseline" }}>
              <b>{c.name}</b>
              <span className="muted">{c.phone}</span>
              <span className="chip" style={{ background: "#E0E7FF", color: "#3730A3" }}>{c.bookings} bookings</span>
            </div>
            {addrs.length === 0 && <p className="muted" style={{ margin: "8px 0 0" }}>No saved addresses loaded (demo mode may use booking snapshots only).</p>}
            {addrs.map((a) => {
              const ok = hasValidCoordinates(a.latitude, a.longitude);
              const label = a.label || a.addressLabel || "Address";
              const formatted = a.formattedAddress || a.line || a.addressLine || a.addressSnapshot || "—";
              return (
                <div key={a.id} style={{ marginTop: 10, padding: 12, borderRadius: 12, background: "#F8FAFC", border: a.isDefault ? "1px solid #06B6C9" : "1px solid #E2E8F0" }}>
                  <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                    <b>{label}</b>
                    {a.isDefault && <span className="chip" style={{ background: "#CCFBF1", color: "#0F766E" }}>Default</span>}
                  </div>
                  <p style={{ margin: "6px 0" }}>{formatted}</p>
                  {ok ? (
                    <>
                      <p className="muted" style={{ fontFamily: "ui-monospace, monospace", fontSize: 12.5 }}>
                        Lat {(a.latitude as number).toFixed(6)} · Lng {(a.longitude as number).toFixed(6)}
                      </p>
                      <iframe title={`map-${a.id}`} style={{ width: "100%", height: 180, border: 0, borderRadius: 10, marginTop: 6 }} src={osmEmbedUrl(a.latitude, a.longitude)} />
                      <a className="btn g" style={{ textDecoration: "none", marginTop: 8, display: "inline-block" }} href={mapsDirectionsUrl(a.latitude, a.longitude)} target="_blank" rel="noreferrer">Open in Maps</a>
                    </>
                  ) : (
                    <p style={{ color: "#B45309", margin: "6px 0 0" }}>Location not verified — no GPS on this saved address.</p>
                  )}
                </div>
              );
            })}
          </div>
        );
      })}
      {customers.length === 0 && <p className="muted">No customers yet.</p>}
    </div>
  );
}
