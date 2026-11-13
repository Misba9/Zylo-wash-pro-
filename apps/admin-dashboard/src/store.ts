import { Booking, Worker, WORKERS, Payment, Subscription, SupportTicket, AuditLog, uid, Address } from "../../../packages/shared-types/src/index";
import { seedBookings, SEED_PAYMENTS, SEED_SUBSCRIPTIONS, SEED_TICKETS, SEED_AUDIT, SEED_ADDRESSES } from "../../../packages/shared-types/src/seed";
const KEY = "washpro_admin_v1";
export interface AState {
  bookings: Booking[]; workers: Worker[]; payments: Payment[]; subscriptions: Subscription[];
  tickets: SupportTicket[]; audit: AuditLog[]; addresses: Address[]; role: string;
  services: {id:string;name:string;duration:number;hatchback:number;sedan:number;suv:number;luxury:number;active:boolean;pricePaise?:{seater5:number;seater7:number}}[];
  addons: {id:string;name:string;pricePaise:number;durationMinutes:number;active:boolean;sortOrder:number;applicableServiceIds:string[];applicableSeatClasses:("seater5"|"seater7")[]}[];
  plans: {id:string;name:string;visits:number;validityDays:number;frequency:string;billingMode:"prepaid"|"recurring";pricePaise:{seater5:number;seater7:number};active:boolean;popular?:boolean}[];
}
function seed(): AState { return { bookings: seedBookings(), workers: WORKERS, payments: SEED_PAYMENTS, subscriptions: SEED_SUBSCRIPTIONS, tickets: SEED_TICKETS, audit: SEED_AUDIT, addresses: SEED_ADDRESSES, role:"Super Admin",
  services:[
    {id:"body-wash",name:"Body Wash",duration:40,hatchback:549,sedan:549,suv:649,luxury:649,active:true,pricePaise:{seater5:54900,seater7:64900}},
    {id:"interior",name:"Interior Cleaning",duration:50,hatchback:549,sedan:549,suv:649,luxury:649,active:true,pricePaise:{seater5:54900,seater7:64900}},
    {id:"deep-clean",name:"Deep Cleaning",duration:120,hatchback:1499,sedan:1499,suv:1899,luxury:1899,active:true,pricePaise:{seater5:149900,seater7:189900}},
  ],
  addons:[
    {id:"tyre-polish",name:"Tyre polishing",pricePaise:9900,durationMinutes:10,active:true,sortOrder:1,applicableServiceIds:["body-wash","deep-clean"],applicableSeatClasses:["seater5","seater7"]},
    {id:"fragrance",name:"Fragrance",pricePaise:4900,durationMinutes:5,active:true,sortOrder:2,applicableServiceIds:["body-wash","interior","deep-clean"],applicableSeatClasses:["seater5","seater7"]},
  ],
  plans:[
    {id:"weekly",name:"Weekly Wash",visits:4,validityDays:30,frequency:"Weekly",billingMode:"prepaid",pricePaise:{seater5:159600,seater7:199600},active:true},
    {id:"monthly",name:"Premium Monthly",visits:8,validityDays:30,frequency:"Twice weekly",billingMode:"prepaid",pricePaise:{seater5:269900,seater7:329900},active:true,popular:true},
  ],
}; }
export function load(): AState { try { const r=localStorage.getItem(KEY); if(r) return { ...seed(), ...JSON.parse(r) }; } catch {} return seed(); }
export function save(s:AState){ try{ localStorage.setItem(KEY, JSON.stringify(s)); }catch{} }
export function reset(){ localStorage.removeItem(KEY); }
export const newAudit = (actor:string, action:string, target:string, reason?:string): AuditLog => ({ id: uid("aud"), actor, action, target, reason, createdAt: new Date().toISOString() });
export const fmtTime=(iso:string)=> new Date(iso).toLocaleString("en-IN",{day:"numeric",month:"short",hour:"numeric",minute:"2-digit",hour12:true});
