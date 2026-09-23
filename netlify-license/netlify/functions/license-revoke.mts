import type { Config } from "@netlify/functions";
import { json, requireAdmin, readJson, supabase } from "./_shared/license.mts";

export default async (request: Request) => {
  if (request.method !== "POST") return json(405, { ok: false, message: "仅支持 POST" });
  try {
    requireAdmin(request);
    const body = await readJson(request);
    const id = Number(body.id || 0);
    if (!Number.isInteger(id) || id <= 0) return json(400, { ok: false, message: "卡密 ID 无效" });
    const result = await supabase("/rest/v1/license_keys?id=eq." + id, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ status: "revoked" })
    });
    if (!result.response.ok) return json(502, { ok: false, message: "撤销失败" });
    return json(200, { ok: true, message: "卡密已撤销" });
  } catch (error) {
    return json(401, {
      ok: false,
      message: error instanceof Error ? error.message : "撤销失败"
    });
  }
};

export const config: Config = {
  path: "/api/license_revoke",
  method: ["POST"]
};
