// @ts-check
import { createClient } from "@supabase/supabase-js";

/**
 * Validates Twilio webhook authenticity by recomputing the expected HMAC-SHA1 signature
 * from the public webhook URL + sorted form fields and comparing it to X-Twilio-Signature.
 */
async function verifyTwilioSignature(
  req: Request,
  form: FormData,
  authToken: string,
  publicWebhookUrl: string
): Promise<boolean> {
  const signature = req.headers.get("X-Twilio-Signature") ?? "";
  if (!signature) return false;

  // Twilio signature base string: full webhook URL + concatenated sorted form fields.
  const pairs = [...form.entries()]
    .map(([k, v]) => [String(k), String(v)] as const)
    .sort(([a], [b]) => a.localeCompare(b));
  const payload = publicWebhookUrl + pairs.map(([k, v]) => `${k}${v}`).join("");

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(authToken),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"]
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));
  return signature === expected;
}

Deno.serve(async (req) => {
  const form = await req.formData();
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const twilioAuthToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  const publicWebhookUrl = Deno.env.get("PUBLIC_WEBHOOK_URL");

  if (!supabaseUrl || !serviceRoleKey || !twilioAuthToken || !publicWebhookUrl) {
    return new Response("Missing required environment configuration", { status: 500 });
  }

  const isValid = await verifyTwilioSignature(req, form, twilioAuthToken, publicWebhookUrl);
  if (!isValid) return new Response("invalid signature", { status: 401 });

  const to = String(form.get("To") ?? "");
  const from = String(form.get("From") ?? "");
  const body = String(form.get("Body") ?? "");

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const { error } = await supabase.from("sms_messages").insert({
    to_number: to,
    from_number: from,
    body,
    received_at: new Date().toISOString(),
  });
  if (error) return new Response("failed to persist inbound SMS", { status: 500 });

  return new Response("ok", { status: 200 });
});
