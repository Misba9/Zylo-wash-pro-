// WashPro shared domain types + authoritative business logic (PRD §5-12)
// Used by web apps (demo mode), mirrored by Cloud Functions (production).
export type Role = "customer" | "worker" | "admin" | "finance" | "super_admin";
export type VehicleCategory = "hatchback" | "sedan" | "suv" | "luxury";
export type BookingStatus = "requested"|"awaiting_payment"|"confirmed"|"assigned"|"en_route"|"arrived"|"in_progress"|"pending_verification"|"completed"|"cancelled"|"under_review";
export type PaymentStatus = "not_required"|"pending"|"authorized"|"paid"|"failed"|"refund_pending"|"partially_refunded"|"refunded";
export type PaymentMethod = "online" | "cash";
export type BookingType = "instant" | "scheduled" | "subscription";

export interface PriceSnapshot { currency:"INR"; subtotalPaise:number; discountPaise:number; taxPaise:number; totalPaise:number; pricingVersion:string }
export interface Vehicle { id:string; ownerUid:string; nickname:string; category:VehicleCategory; make:string; model:string; color:string; registrationNumber:string; isDefault:boolean }
export interface Address { id:string; ownerUid:string; label:string; recipientName:string; contactPhone:string; addressLine:string; locality:string; city:string; postalCode:string; apartment?:string; building?:string; flatNumber?:string; parkingSlot?:string; accessInstructions?:string; latitude:number; longitude:number; serviceAreaId:string }
export interface Service { id:string; name:string; tagline:string; icon:string; durationMinutes:Record<VehicleCategory,number>; pricePaise:Record<VehicleCategory,number>; inclusions:string[]; exclusions:string[]; checklist:string[]; cashEligible:boolean }
export interface ServiceArea { id:string; name:string; pincodes:string[]; cashEligible:boolean; active:boolean }
export interface Worker { uid:string; name:string; phone:string; status:"pending"|"approved"|"suspended"; isAvailable:boolean; serviceAreaIds:string[]; serviceIds:string[]; rating:number; completedJobs:number; distanceKm:number; activeJobs:number; earningsTodayPaise:number; photoColor:string }
export interface Booking {
  id:string; customerUid:string; customerName:string; customerPhone:string;
  vehicleId:string; vehicleLabel:string; vehicleCategory:VehicleCategory;
  addressId:string; addressLabel:string; addressSnapshot:string; serviceAreaId:string;
  serviceId:string; serviceName:string; assignedWorkerUid:string|null; workerName:string|null;
  bookingType:BookingType; status:BookingStatus; scheduledAt:string; estimatedDurationMinutes:number;
  priceSnapshot:PriceSnapshot; paymentMethod:PaymentMethod; paymentStatus:PaymentStatus;
  subscriptionId:string|null; occurrenceId:string|null; checklistDone:string[];
  rating:number|null; createdAt:string; updatedAt:string; completedAt:string|null; cancelReason?:string;
}
export interface SubscriptionPlan { id:string; name:string; billingMode:"prepaid"|"recurring"; visits:number; validityDays:number; pricePaise:Record<VehicleCategory,number>; frequency:string; popular?:boolean }
export interface Subscription { id:string; customerUid:string; vehicleId:string; vehicleLabel:string; addressId:string; planId:string; planName:string; billingMode:"prepaid"|"recurring"; status:"pending_payment"|"active"|"paused"|"past_due"|"cancelled"|"expired"; frequency:string; timeWindow:string; visitBalance:number; totalVisits:number; nextVisitAt:string; createdAt:string }
export interface Payment { id:string; bookingId:string|null; customerUid:string; customerName:string; amountPaise:number; method:PaymentMethod|"upi"|"card"; status:PaymentStatus|"collected"|"pending_collection"; providerRef:string|null; createdAt:string }
export interface SupportTicket { id:string; customerUid:string; customerName:string; subject:string; status:"open"|"in_progress"|"resolved"; priority:"low"|"medium"|"high"; createdAt:string }
export interface AuditLog { id:string; actor:string; action:string; target:string; reason?:string; createdAt:string }
export interface AppNotification { id:string; recipientUid:string; type:string; title:string; body:string; refId:string|null; read:boolean; createdAt:string }

export const PRICING_VERSION = "hyd-2026.10-v1";
export const GST_PCT = 0; // prices are inclusive for pilot; kept explicit in snapshot

export const SERVICE_AREAS: ServiceArea[] = [
  { id:"hitech", name:"Hitech City / Madhapur", pincodes:["500081","500033"], cashEligible:true, active:true },
  { id:"gachibowli", name:"Gachibowli / Financial District", pincodes:["500032","500089"], cashEligible:true, active:true },
  { id:"kondapur", name:"Kondapur", pincodes:["500084"], cashEligible:true, active:true },
  { id:"banjara", name:"Banjara Hills", pincodes:["500034"], cashEligible:false, active:true },
  { id:"jubilee", name:"Jubilee Hills", pincodes:["500033"], cashEligible:false, active:true },
  { id:"begumpet", name:"Begumpet / Secunderabad", pincodes:["500016","500003"], cashEligible:true, active:true },
];

export const SERVICES: Service[] = [
  { id:"body-wash", name:"Body Wash", tagline:"Exterior foam wash & shine", icon:"🚿", cashEligible:true,
    durationMinutes:{hatchback:30,sedan:35,suv:45,luxury:50},
    pricePaise:{hatchback:29900,sedan:34900,suv:44900,luxury:59900},
    inclusions:["Foam exterior wash","Tyre & rim cleaning","Glass cleaning","Microfibre dry & wax spray"],
    exclusions:["Interior cleaning","Engine bay wash"],
    checklist:["Pre-rinse & foam soak","Hand wash body panels","Clean tyres, rims & wheel arches","Clean all glass & mirrors","Dry with microfibre, apply wax spray","Final inspection walkaround"] },
  { id:"interior", name:"Interior Cleaning", tagline:"Vacuum, dashboard & upholstery care", icon:"🧽", cashEligible:true,
    durationMinutes:{hatchback:45,sedan:50,suv:60,luxury:70},
    pricePaise:{hatchback:49900,sedan:54900,suv:64900,luxury:79900},
    inclusions:["Full vacuum (seats, mats, boot)","Dashboard & console detailing","Door-pad & glass (inside)","Air-vent dusting"],
    exclusions:["Seat shampoo / extraction","Leather conditioning (add-on)"],
    checklist:["Remove mats & vacuum cabin","Vacuum seats & boot","Clean dashboard & centre console","Clean door pads & interior glass","Dust air vents & crevices","Replace mats, final check"] },
  { id:"deep-clean", name:"Deep Cleaning", tagline:"Complete inside-out detail", icon:"✨", cashEligible:false,
    durationMinutes:{hatchback:90,sedan:105,suv:120,luxury:150},
    pricePaise:{hatchback:99900,sedan:114900,suv:134900,luxury:169900},
    inclusions:["Everything in Body Wash + Interior","Seat & carpet shampoo","Leather clean & condition","AC vent sanitisation"],
    exclusions:["Paint correction / polishing","Ceramic coating"],
    checklist:["Full exterior foam wash & clay wipe","Engine bay gentle clean","Seat & carpet shampoo extraction","Leather clean & condition","Dashboard, vents & glass detail","Tyre dressing & final QC photos"] },
];

export const ADDONS = [
  { id:"tyre-dressing", name:"Tyre Dressing+", pricePaise:9900 },
  { id:"leather-care", name:"Leather Care", pricePaise:29900 },
  { id:"ac-sanitise", name:"AC Sanitisation", pricePaise:24900 },
  { id:"pet-hair", name:"Pet Hair Removal", pricePaise:19900 },
];

export const PLANS: SubscriptionPlan[] = [
  { id:"shine-8", name:"Shine 8", billingMode:"prepaid", visits:8, validityDays:30, frequency:"Alternate days", pricePaise:{hatchback:199900,sedan:229900,suv:289900,luxury:379900} },
  { id:"shine-12", name:"Shine 12", billingMode:"prepaid", visits:12, validityDays:30, frequency:"Every 2–3 days", popular:true, pricePaise:{hatchback:269900,sedan:309900,suv:389900,luxury:499900} },
  { id:"shine-daily", name:"Daily Shine (Recurring)", billingMode:"recurring", visits:26, validityDays:30, frequency:"Daily (Mon–Sat)", pricePaise:{hatchback:399900,sedan:449900,suv:549900,luxury:699900} },
];

export const WORKERS: Worker[] = [
  { uid:"w1", name:"Ramesh Kumar", phone:"+91 98XXX XX210", status:"approved", isAvailable:true, serviceAreaIds:["hitech","kondapur"], serviceIds:["body-wash","interior","deep-clean"], rating:4.9, completedJobs:412, distanceKm:1.2, activeJobs:1, earningsTodayPaise:124000, photoColor:"#0ea5e9" },
  { uid:"w2", name:"Suresh Yadav", phone:"+91 97XXX XX431", status:"approved", isAvailable:true, serviceAreaIds:["gachibowli","hitech"], serviceIds:["body-wash","interior"], rating:4.8, completedJobs:356, distanceKm:2.4, activeJobs:0, earningsTodayPaise:86000, photoColor:"#8b5cf6" },
  { uid:"w3", name:"Mohd. Imran", phone:"+91 99XXX XX876", status:"approved", isAvailable:true, serviceAreaIds:["banjara","jubilee"], serviceIds:["body-wash","interior","deep-clean"], rating:4.9, completedJobs:498, distanceKm:3.1, activeJobs:2, earningsTodayPaise:152000, photoColor:"#f59e0b" },
  { uid:"w4", name:"Anil Verma", phone:"+91 96XXX XX109", status:"approved", isAvailable:false, serviceAreaIds:["begumpet"], serviceIds:["body-wash"], rating:4.6, completedJobs:189, distanceKm:4.8, activeJobs:0, earningsTodayPaise:0, photoColor:"#10b981" },
  { uid:"w5", name:"Kiran Reddy", phone:"+91 95XXX XX654", status:"approved", isAvailable:true, serviceAreaIds:["kondapur","gachibowli"], serviceIds:["body-wash","deep-clean"], rating:4.7, completedJobs:267, distanceKm:1.9, activeJobs:1, earningsTodayPaise:98000, photoColor:"#ec4899" },
  { uid:"w6", name:"Vijay Singh", phone:"+91 94XXX XX321", status:"pending", isAvailable:false, serviceAreaIds:["hitech"], serviceIds:["body-wash"], rating:5.0, completedJobs:0, distanceKm:0.8, activeJobs:0, earningsTodayPaise:0, photoColor:"#64748b" },
];

export function calculatePrice(serviceId:string, category:VehicleCategory, addonIds:string[]=[], discountPaise=0): PriceSnapshot {
  const s = SERVICES.find(x=>x.id===serviceId); if(!s) throw new Error("Unknown service");
  const addons = ADDONS.filter(a=>addonIds.includes(a.id)).reduce((n,a)=>n+a.pricePaise,0);
  const subtotal = s.pricePaise[category] + addons;
  const tax = Math.round(subtotal * GST_PCT);
  return { currency:"INR", subtotalPaise:subtotal, discountPaise, taxPaise:tax, totalPaise:Math.max(0, subtotal - discountPaise + tax), pricingVersion:PRICING_VERSION };
}
export function durationFor(serviceId:string, category:VehicleCategory){ const s=SERVICES.find(x=>x.id===serviceId); return s? s.durationMinutes[category]:45; }
export const inr = (paise:number)=> "₹" + (paise/100).toLocaleString("en-IN",{maximumFractionDigits: paise%100?2:0});

const TRANSITIONS: Record<BookingStatus, BookingStatus[]> = {
  requested:["awaiting_payment","confirmed","cancelled"],
  awaiting_payment:["confirmed","cancelled"],
  confirmed:["assigned","cancelled","under_review"],
  assigned:["en_route","assigned","cancelled","under_review"],
  en_route:["arrived","cancelled"],
  arrived:["in_progress","under_review"],
  in_progress:["pending_verification","under_review"],
  pending_verification:["completed","in_progress","under_review"],
  completed:[], cancelled:[], under_review:["confirmed","assigned","cancelled"],
};
export const canTransition = (from:BookingStatus,to:BookingStatus)=> (TRANSITIONS[from]||[]).includes(to);
export const STATUS_LABEL: Record<BookingStatus,string> = { requested:"Requested", awaiting_payment:"Awaiting Payment", confirmed:"Confirmed", assigned:"Worker Assigned", en_route:"Worker En Route", arrived:"Worker Arrived", in_progress:"Wash In Progress", pending_verification:"Verify Completion", completed:"Completed", cancelled:"Cancelled", under_review:"Under Review" };

export interface Recommendation { worker:Worker; score:number; reasons:string[] }
export function recommendWorkers(booking:Pick<Booking,"serviceAreaId"|"serviceId">, workers:Worker[]): Recommendation[] {
  return workers.map(w=>{
    const reasons:string[]=[]; let score=0;
    if(w.status!=="approved"){ return {worker:w, score:-1, reasons:["Not approved"]}; }
    if(!w.isAvailable){ return {worker:w, score:-1, reasons:["Unavailable / off shift"]}; }
    if(w.serviceAreaIds.includes(booking.serviceAreaId)){ score+=30; reasons.push("Serves this area"); } else reasons.push("Outside usual area");
    if(w.serviceIds.includes(booking.serviceId)){ score+=25; reasons.push("Trained for this service"); }
    score += Math.round(w.rating*6); reasons.push(`★ ${w.rating} (${w.completedJobs} jobs)`);
    score += Math.max(0, 20 - w.distanceKm*4); reasons.push(`${w.distanceKm} km away`);
    score -= w.activeJobs*12; reasons.push(w.activeJobs? `${w.activeJobs} active job(s)` : "No active jobs");
    return {worker:w, score:Math.round(score), reasons};
  }).sort((a,b)=>b.score-a.score);
}

export function availableSlots(dateISO:string): {time:string; label:string; spots:number}[] {
  const slots=["07:00","08:30","10:00","11:30","13:00","14:30","16:00","17:30"];
  // deterministic pseudo-capacity so UI + tests are stable
  const seed=[...dateISO].reduce((n,c)=>n+c.charCodeAt(0),0);
  return slots.map((t,i)=>({ time:t, label:`${t} IST`, spots: ((seed+i*7)%4) }));
}
export const uid = (p="id")=> `${p}_${Math.random().toString(36).slice(2,9)}`;
export const nowISO = ()=> new Date().toISOString();
export function todayAt(time:string){ const d=new Date(); const [h,m]=time.split(":").map(Number); d.setHours(h,m,0,0); return d.toISOString(); }
