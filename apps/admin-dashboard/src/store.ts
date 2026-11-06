import { Booking, Worker, WORKERS, Payment, Subscription, SupportTicket, AuditLog, uid } from "../../../packages/shared-types/src/index";
import { seedBookings, SEED_PAYMENTS, SEED_SUBSCRIPTIONS, SEED_TICKETS, SEED_AUDIT } from "../../../packages/shared-types/src/seed";
const KEY = "washpro_admin_v1";
export interface AState { bookings: Booking[]; workers: Worker[]; payments: Payment[]; subscriptions: Subscription[]; tickets: SupportTicket[]; audit: AuditLog[]; role: string; services: {id:string;name:string;duration:number;hatchback:number;sedan:number;suv:number;luxury:number;active:boolean}[] }
function seed(): AState { return { bookings: seedBookings(), workers: WORKERS, payments: SEED_PAYMENTS, subscriptions: SEED_SUBSCRIPTIONS, tickets: SEED_TICKETS, audit: SEED_AUDIT, role:"Super Admin",
  services:[{id:"body-wash",name:"Body Wash",duration:45,hatchback:299,sedan:349,suv:449,luxury:599,active:true},{id:"interior",name:"Interior Cleaning",duration:60,hatchback:499,sedan:549,suv:649,luxury:799,active:true},{id:"deep-clean",name:"Deep Cleaning",duration:120,hatchback:999,sedan:1149,suv:1349,luxury:1699,active:true}] }; }
export function load(): AState { try { const r=localStorage.getItem(KEY); if(r) return { ...seed(), ...JSON.parse(r) }; } catch {} return seed(); }
export function save(s:AState){ try{ localStorage.setItem(KEY, JSON.stringify(s)); }catch{} }
export function reset(){ localStorage.removeItem(KEY); }
export const newAudit = (actor:string, action:string, target:string, reason?:string): AuditLog => ({ id: uid("aud"), actor, action, target, reason, createdAt: new Date().toISOString() });
export const fmtTime=(iso:string)=> new Date(iso).toLocaleString("en-IN",{day:"numeric",month:"short",hour:"numeric",minute:"2-digit",hour12:true});
