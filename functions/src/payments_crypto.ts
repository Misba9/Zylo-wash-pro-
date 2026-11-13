import * as crypto from "crypto";

/** Constant-time hex HMAC compare; returns false on length mismatch (never throws). */
export function hmacHexEqual(payload: string, signature: string, secret: string): boolean {
  if (!secret || !signature) return false;
  const expected = crypto.createHmac("sha256", secret).update(payload).digest("hex");
  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(signature, "utf8");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/** Razorpay checkout signature: HMAC_SHA256(orderId|paymentId, key_secret). */
export function razorpayCheckoutSignature(
  orderId: string,
  paymentId: string,
  keySecret: string,
): string {
  return crypto.createHmac("sha256", keySecret).update(`${orderId}|${paymentId}`).digest("hex");
}

export function verifyRazorpayCheckoutSignature(args: {
  orderId: string;
  paymentId: string;
  signature: string;
  keySecret: string;
}): boolean {
  const expected = razorpayCheckoutSignature(args.orderId, args.paymentId, args.keySecret);
  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(args.signature, "utf8");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}
