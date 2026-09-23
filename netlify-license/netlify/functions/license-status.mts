import type { Config } from "@netlify/functions";
import {
  json,
  licensePayload,
  readJson,
  supabase,
  validateDeviceID
} from "./_shared/license.mts";

export default async (request: Request) => {
  if (request.method !== "POST") return json(405, { ok: false, message: "仅支持 POST" });

  try {
    const body = await readJson(request);
    const deviceID = validateDeviceID(String(body.device_id || ""));
    const query = new URLSearchParams({
      select: "expires_at",
      device_id: "eq." + deviceID,
      status: "eq.redeemed",
      expires_at: "gt." + new Date().toISOString(),
      order: "expires_at.desc",
      limit: "1"
    });
    const result = await supabase("/rest/v1/license_keys?" + query.toString());
    if (!result.response.ok || !Array.isArray(result.payload)) {
      return json(502, { ok: false, message: "授权数据库请求失败" });
    }
    return json(200, licensePayload(
      result.payload[0] || null,
      result.payload[0] ? "授权状态已更新" : "当前设备没有有效卡密"
    ));
  } catch (error) {
    return json(400, {
      ok: false,
      message: error instanceof Error ? error.message : "查询失败"
    });
  }
};

export const config: Config = {
  path: "/api/license_status.php",
  method: ["POST"]
};
