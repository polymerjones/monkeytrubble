// Supabase Edge Function `push` (Deno). Called every minute by pg_cron (see docs/proposals/push-notifications.md "Go-live
// steps") with the header x-push-secret; anyone else gets 401. All keys come from the function's secrets:
//   PUSH_CRON_SECRET, SERVICE_ROLE_KEY (or the built-in SUPABASE_SERVICE_ROLE_KEY), APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID,
//   APNS_BUNDLE_ID (com.paulfisher.MonkeyTrubble), FCM_SERVICE_ACCOUNT (the JSON). SUPABASE_URL is provided by Supabase.
import { makeSender } from './sender.ts';

const env = (k: string) => Deno.env.get(k) ?? undefined;
const send = makeSender({
  SUPABASE_URL: env('SUPABASE_URL')!, SERVICE_ROLE_KEY: env('SERVICE_ROLE_KEY') ?? env('SUPABASE_SERVICE_ROLE_KEY')!,
  APNS_KEY_P8: env('APNS_KEY_P8'), APNS_KEY_ID: env('APNS_KEY_ID'), APNS_TEAM_ID: env('APNS_TEAM_ID'), APNS_BUNDLE_ID: env('APNS_BUNDLE_ID'),
  FCM_SERVICE_ACCOUNT: env('FCM_SERVICE_ACCOUNT'),
});

Deno.serve(async req => {
  const secret = env('PUSH_CRON_SECRET');
  if (!secret || req.headers.get('x-push-secret') !== secret) return new Response('unauthorized', { status: 401 });
  try {
    return Response.json(await send());
  } catch (e) {
    console.error('[push]', e);
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
