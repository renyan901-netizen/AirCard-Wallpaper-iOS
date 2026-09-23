import type { Config } from "@netlify/functions";
import {
  hashKey,
  json,
  normalizeKey,
  readJson,
  supabase,
  validateDeviceID
} from "./_shared/license.mts";

export default async (request: Request) => {
  if (request.method !== "POST") return json(405, { ok: false, message: "仅支持 POST" });

  try {
    const body = await readJson(request);
    const key = normalizeKey(String(body.license_key || ""));
    const deviceID = validateDeviceID(String(body.device_id || ""));
    if (key.length < 12 || key.length > 64) {
      return json(400, { ok: false, message: "卡密格式无效" });
    }

    const result = await supabase("/rest/v1/rpc/redeem_license", {
      method: "POST",
      body: JSON.stringify({
        p_key_hash: hashKey(key),
        p_device_id: deviceID
      })
    });
    if (!result.response.ok) return json(502, { ok: false, message: "授权数据库请求失败" });
    return json(result.payload?.ok === false ? 409 : 200, result.payload);
  } catch (error) {
    return json(400, {
      ok: false,
      message: error instanceof Error ? error.message : "兑换失败"
    });
  }
};

export const config: Config = {
  path: "/api/license_redeem.php",
  method: ["POST"]
};
