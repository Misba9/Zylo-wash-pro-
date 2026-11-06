import { Booking, WORKERS, Worker } from "../../../packages/shared-types/src/index";
import { seedBookings } from "../../../packages/shared-types/src/seed";
const KEY = "washpro_worker_v1";
export interface WState { bookings: Booking[]; workers: Worker[]; workerUid: string | null; available: boolean; lastLoc: { lat:number; lng:number; at:string } | null; earningsExtra: number }
function seed(): WState { return { bookings: seedBookings(), workers: WORKERS, workerUid: null, available: true, lastLoc: null, earningsExtra: 0 }; }
export function load(): WState { try { const r = localStorage.getItem(KEY); if (r) return { ...seed(), ...JSON.parse(r) }; } catch {} return seed(); }
export function save(s: WState) { try { localStorage.setItem(KEY, JSON.stringify(s)); } catch {} }
export function reset() { localStorage.removeItem(KEY); }
export const fmtTime = (iso:string)=> new Date(iso).toLocaleTimeString("en-IN",{hour:"numeric",minute:"2-digit",hour12:true});
export const fmtDay = (iso:string)=> new Date(iso).toLocaleDateString("en-IN",{weekday:"short",day:"numeric",month:"short"});
