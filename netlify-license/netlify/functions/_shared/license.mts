import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

export function json(status: number, payload: unknown) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store"
    }
  });
}

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  const value = await request.json().catch(() => ({}));
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

export function normalizeKey(value: string) {
  return value.trim().replace(/[^A-Za-z0-9]/g, "").toUpperCase();
}

export function hashKey(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

export function validateDeviceID(value: string) {
  const deviceID = value.trim().toLowerCase();
  if (!/^[a-f0-9]{32}$/.test(deviceID)) throw new Error("设备标识格式无效");
  return deviceID;
}

export function requireAdmin(request: Request) {
  const expected = process.env.LICENSE_ADMIN_KEY || "";
  const authorization = request.headers.get("authorization") || "";
  const supplied = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  const a = Buffer.from(supplied);
  const b = Buffer.from(expected);
  if (!expected || a.length !== b.length || !timingSafeEqual(a, b)) {
    throw new Error("管理员授权失败");
  }
}

function supabaseConfig() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("后台未配置 Supabase 环境变量");
  return { url: url.replace(/\/$/, ""), key };
}

export async function supabase(path: string, init: RequestInit = {}) {
  const { url, key } = supabaseConfig();
  const headers = new Headers(init.headers);
  headers.set("apikey", key);
  headers.set("Authorization", "Bearer " + key);
  headers.set("Content-Type", "application/json");
  const response = await fetch(url + path, { ...init, headers });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;
  return { response, payload };
}

export function generatedKey() {
  const hex = randomBytes(8).toString("hex").toUpperCase();
  return "AC-" + hex.slice(0, 4) + "-" + hex.slice(4, 8) + "-" +
    hex.slice(8, 12) + "-" + hex.slice(12, 16);
}

export function licensePayload(row: { expires_at?: string | null } | null, message: string) {
  const expiresAt = row?.expires_at ? new Date(row.expires_at) : null;
  const remainingSeconds = expiresAt
    ? Math.max(0, Math.floor((expiresAt.getTime() - Date.now()) / 1000))
    : 0;
  return {
    ok: true,
    active: remainingSeconds > 0,
    expires_at: expiresAt?.toISOString() ?? null,
    remaining_seconds: remainingSeconds,
    message
  };
}
