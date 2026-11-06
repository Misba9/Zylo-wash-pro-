import { Booking, Payment, Subscription, SupportTicket, AuditLog, Vehicle, Address } from "./index";
const today = (h:number,m=0)=>{ const d=new Date(); d.setHours(h,m,0,0); return d.toISOString(); };
export const DEMO_CUSTOMER = { uid:"cust_demo", name:"Ahmed Khan", phone:"+91 98765 43210" };
export const SEED_VEHICLES: Vehicle[] = [
  { id:"v1", ownerUid:"cust_demo", nickname:"My Creta", category:"suv", make:"Hyundai", model:"Creta SX", color:"White", registrationNumber:"TS09 EX 4521", isDefault:true },
  { id:"v2", ownerUid:"cust_demo", nickname:"City Car", category:"sedan", make:"Honda", model:"City VX", color:"Silver", registrationNumber:"TS07 AB 8890", isDefault:false },
];
export const SEED_ADDRESSES: Address[] = [
  { id:"a1", ownerUid:"cust_demo", label:"Home", recipientName:"Ahmed Khan", contactPhone:"+91 98765 43210", addressLine:"Flat 1204, My Home Tridasa", locality:"Kondapur", city:"Hyderabad", postalCode:"500084", apartment:"My Home Tridasa", building:"Tower B", flatNumber:"1204", parkingSlot:"B2-47", accessInstructions:"Security gate 2 — ask guard to call flat", latitude:17.4622, longitude:78.3568, serviceAreaId:"kondapur" },
  { id:"a2", ownerUid:"cust_demo", label:"Office", recipientName:"Ahmed Khan", contactPhone:"+91 98765 43210", addressLine:"Mindspace IT Park, Building 12", locality:"Hitech City", city:"Hyderabad", postalCode:"500081", parkingSlot:"P1-112", accessInstructions:"Visitor parking, level P1", latitude:17.4435, longitude:78.3772, serviceAreaId:"hitech" },
];
export function seedBookings(): Booking[] {
  const base = { customerUid:"cust_demo", customerName:"Ahmed Khan", customerPhone:"+91 98765 43210", subscriptionId:null, occurrenceId:null, checklistDone:[] as string[], rating:null };
  return [
    { ...base, id:"bk_1003", vehicleId:"v1", vehicleLabel:"Hyundai Creta SX · TS09 EX 4521", vehicleCategory:"suv", addressId:"a1", addressLabel:"Home — Kondapur", addressSnapshot:"Flat 1204, My Home Tridasa, Kondapur 500084 · Slot B2-47", serviceAreaId:"kondapur", serviceId:"body-wash", serviceName:"Body Wash", assignedWorkerUid:"w1", workerName:"Ramesh Kumar", bookingType:"instant", status:"assigned", scheduledAt:today(11,30), estimatedDurationMinutes:45, priceSnapshot:{currency:"INR",subtotalPaise:44900,discountPaise:0,taxPaise:0,totalPaise:44900,pricingVersion:"hyd-2026.10-v1"}, paymentMethod:"online", paymentStatus:"paid", createdAt:today(9,2), updatedAt:today(9,20), completedAt:null },
    { ...base, id:"bk_1002", vehicleId:"v2", vehicleLabel:"Honda City VX · TS07 AB 8890", vehicleCategory:"sedan", addressId:"a2", addressLabel:"Office — Hitech City", addressSnapshot:"Mindspace IT Park Bldg 12, Hitech City 500081 · Slot P1-112", serviceAreaId:"hitech", serviceId:"interior", serviceName:"Interior Cleaning", assignedWorkerUid:null, workerName:null, bookingType:"scheduled", status:"confirmed", scheduledAt:today(16,0), estimatedDurationMinutes:50, priceSnapshot:{currency:"INR",subtotalPaise:54900,discountPaise:0,taxPaise:0,totalPaise:54900,pricingVersion:"hyd-2026.10-v1"}, paymentMethod:"cash", paymentStatus:"pending", createdAt:today(8,15), updatedAt:today(8,15), completedAt:null },
    { ...base, id:"bk_1001", vehicleId:"v1", vehicleLabel:"Hyundai Creta SX · TS09 EX 4521", vehicleCategory:"suv", addressId:"a1", addressLabel:"Home — Kondapur", addressSnapshot:"Flat 1204, My Home Tridasa, Kondapur 500084 · Slot B2-47", serviceAreaId:"kondapur", serviceId:"deep-clean", serviceName:"Deep Cleaning", assignedWorkerUid:"w5", workerName:"Kiran Reddy", bookingType:"scheduled", status:"completed", scheduledAt:today(7,0), estimatedDurationMinutes:120, priceSnapshot:{currency:"INR",subtotalPaise:134900,discountPaise:10000,taxPaise:0,totalPaise:124900,pricingVersion:"hyd-2026.10-v1"}, paymentMethod:"online", paymentStatus:"paid", rating:5, checklistDone:["done"], createdAt:today(6,0), updatedAt:today(9,0), completedAt:today(9,0) },
    { ...base, id:"bk_1004", customerUid:"cust_x", customerName:"Priya Sharma", customerPhone:"+91 98111 22334", vehicleId:"v9", vehicleLabel:"Maruti Baleno · TS08 CD 2210", vehicleCategory:"hatchback", addressId:"a9", addressLabel:"Home — Banjara Hills", addressSnapshot:"Road No 12, Banjara Hills 500034", serviceAreaId:"banjara", serviceId:"deep-clean", serviceName:"Deep Cleaning", assignedWorkerUid:null, workerName:null, bookingType:"instant", status:"confirmed", scheduledAt:today(13,0), estimatedDurationMinutes:90, priceSnapshot:{currency:"INR",subtotalPaise:99900,discountPaise:0,taxPaise:0,totalPaise:99900,pricingVersion:"hyd-2026.10-v1"}, paymentMethod:"online", paymentStatus:"paid", createdAt:today(10,5), updatedAt:today(10,5), completedAt:null },
    { ...base, id:"bk_1005", customerUid:"cust_z", customerName:"Rahul Mehta", customerPhone:"+91 97000 11223", vehicleId:"v8", vehicleLabel:"Kia Seltos · TS09 GH 7788", vehicleCategory:"suv", addressId:"a8", addressLabel:"Office — Gachibowli", addressSnapshot:"DLF Cyber City, Gachibowli 500032", serviceAreaId:"gachibowli", serviceId:"body-wash", serviceName:"Body Wash", assignedWorkerUid:"w2", workerName:"Suresh Yadav", bookingType:"scheduled", status:"en_route", scheduledAt:today(11,0), estimatedDurationMinutes:45, priceSnapshot:{currency:"INR",subtotalPaise:44900,discountPaise:0,taxPaise:0,totalPaise:44900,pricingVersion:"hyd-2026.10-v1"}, paymentMethod:"cash", paymentStatus:"pending", createdAt:today(8,40), updatedAt:today(10,50), completedAt:null },
  ];
}
export const SEED_SUBSCRIPTIONS: Subscription[] = [
  { id:"sub_501", customerUid:"cust_demo", vehicleId:"v1", vehicleLabel:"Hyundai Creta SX", addressId:"a1", planId:"shine-12", planName:"Shine 12", billingMode:"prepaid", status:"active", frequency:"Every 2–3 days", timeWindow:"07:00–09:00", visitBalance:7, totalVisits:12, nextVisitAt:today(7,0), createdAt:today(6,0) },
];
export const SEED_PAYMENTS: Payment[] = [
  { id:"pay_1", bookingId:"bk_1003", customerUid:"cust_demo", customerName:"Ahmed Khan", amountPaise:44900, method:"upi", status:"paid", providerRef:"pay_RzpDemo1003", createdAt:today(9,3) },
  { id:"pay_2", bookingId:"bk_1001", customerUid:"cust_demo", customerName:"Ahmed Khan", amountPaise:124900, method:"card", status:"paid", providerRef:"pay_RzpDemo1001", createdAt:today(6,5) },
  { id:"pay_3", bookingId:"bk_1002", customerUid:"cust_demo", customerName:"Ahmed Khan", amountPaise:54900, method:"cash", status:"pending_collection", providerRef:null, createdAt:today(8,15) },
  { id:"pay_4", bookingId:"bk_1004", customerUid:"cust_x", customerName:"Priya Sharma", amountPaise:99900, method:"upi", status:"paid", providerRef:"pay_RzpDemo1004", createdAt:today(10,6) },
  { id:"pay_5", bookingId:"bk_0998", customerUid:"cust_y", customerName:"Vikram Rao", amountPaise:34900, method:"upi", status:"refund_pending", providerRef:"pay_RzpDemo0998", createdAt:today(7,30) },
];
export const SEED_TICKETS: SupportTicket[] = [
  { id:"tkt_1", customerUid:"cust_demo", customerName:"Ahmed Khan", subject:"Worker arrived 15 min late", status:"open", priority:"medium", createdAt:today(9,30) },
  { id:"tkt_2", customerUid:"cust_x", customerName:"Priya Sharma", subject:"Request to reschedule deep clean", status:"in_progress", priority:"low", createdAt:today(8,0) },
];
export const SEED_AUDIT: AuditLog[] = [
  { id:"aud_1", actor:"ops@washpro.in", action:"assignWorker", target:"bk_1003 → Ramesh Kumar", reason:"Top recommendation (score 92)", createdAt:today(9,20) },
  { id:"aud_2", actor:"finance@washpro.in", action:"requestRefund", target:"pay_5 · ₹349", reason:"Customer cancelled within policy", createdAt:today(7,45) },
];
