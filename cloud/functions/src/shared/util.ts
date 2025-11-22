import type { HttpRequest, InvocationContext } from "@azure/functions";

export interface AuthUser {
  identityProvider?: string;
  userId?: string;
  userDetails?: string; // usually email or UPN
}

export function getAuthUser(req: HttpRequest, context: InvocationContext): AuthUser | undefined {
  const header = req.headers.get("x-ms-client-principal");
  if (!header) return undefined;
  try {
    const decoded = Buffer.from(header, "base64").toString("utf8");
    const payload = JSON.parse(decoded);
    return {
      identityProvider: payload?.identityProvider,
      userId: payload?.userId,
      userDetails: payload?.userDetails,
    };
  } catch (e) {
    context.error("Failed to decode client principal", e);
    return undefined;
  }
}

export function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v || !v.trim()) throw new Error(`Missing required environment variable: ${name}`);
  return v;
}

export function parseCsv(value?: string | null): string[] | undefined {
  if (!value) return undefined;
  return value
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export function guid(): string {
  // Simple GUID generator
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0,
      v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

