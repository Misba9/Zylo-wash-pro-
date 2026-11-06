import { z } from "zod";
export const createBookingSchema = z.object({
  vehicleId: z.string().min(1), addressId: z.string().min(1), serviceId: z.string().min(1),
  bookingType: z.enum(["instant","scheduled","subscription"]),
  scheduledAt: z.string().datetime(), paymentMethod: z.enum(["online","cash"]),
  addonIds: z.array(z.string()).default([]), idempotencyKey: z.string().min(8),
});
export const assignWorkerSchema = z.object({ bookingId: z.string().min(1), workerUid: z.string().min(1), reason: z.string().optional() });
export const locationSchema = z.object({ bookingId: z.string().min(1), latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180), recordedAt: z.string().datetime() });
export const createSubscriptionSchema = z.object({ planId: z.string().min(1), vehicleId: z.string().min(1), addressId: z.string().min(1), timeWindow: z.string().min(1), idempotencyKey: z.string().min(8) });
export const phoneSchema = z.string().regex(/^\+91[6-9]\d{9}$/, "Valid Indian mobile required");
export const vehicleSchema = z.object({ nickname: z.string().min(1), category: z.enum(["hatchback","sedan","suv","luxury"]), make: z.string().min(1), model: z.string().min(1), color: z.string().min(1), registrationNumber: z.string().min(4) });
