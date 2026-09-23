import type { Config } from "@netlify/functions";
import {
  generatedKey,
  hashKey,
  json,
  normalizeKey,
  requireAdmin,
  readJson,
  supabase
} from "./_shared/license.mts";

export default async (request: Request) => {
  if (request.method !== "POST") return json(405, { ok: false, message: "仅支持 POST" });
  try {
    requireAdmin(request);
    const body = await readJson(request);
    const days = Math.max(1, Math.min(3650, Number(body.days || 30)));
    const quantity = Math.max(1, Math.min(500, Number(body.quantity || 1)));
    const note = String(body.note || "").trim().slice(0, 200);
    const keys = Array.from({ length: quantity }, () => generatedKey());
    const rows = keys.map((key) => ({
      key_hash: hashKey(normalizeKey(key)),
      key_hint: key.slice(-4),
      days,
      note
    }));
    const result = await supabase("/rest/v1/license_keys", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify(rows)
    });
    if (!result.response.ok) return json(502, { ok: false, message: "卡密写入数据库失败" });
    return json(200, { ok: true, keys, message: "卡密生成成功，请立即保存明文卡密" });
  } catch (error) {
    return json(401, {
      ok: false,
      message: error instanceof Error ? error.message : "生成失败"
    });
  }
};

export const config: Config = {
  path: "/api/license_generate",
  method: ["POST"]
};
