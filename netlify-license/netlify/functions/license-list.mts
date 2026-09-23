import type { Config } from "@netlify/functions";
import { json, requireAdmin, supabase } from "./_shared/license.mts";

export default async (request: Request) => {
  if (request.method !== "GET") return json(405, { ok: false, message: "仅支持 GET" });
  try {
    requireAdmin(request);
    const query = new URLSearchParams({
      select: "id,key_hint,days,status,device_id,redeemed_at,expires_at,created_at,note",
      order: "id.desc",
      limit: "100"
    });
    const result = await supabase("/rest/v1/license_keys?" + query.toString());
    if (!result.response.ok || !Array.isArray(result.payload)) {
      return json(502, { ok: false, message: "读取卡密失败" });
    }
    return json(200, { ok: true, rows: result.payload });
  } catch (error) {
    return json(401, {
      ok: false,
      message: error instanceof Error ? error.message : "读取失败"
    });
  }
};

export const config: Config = {
  path: "/api/license_list",
  method: ["GET"]
};
