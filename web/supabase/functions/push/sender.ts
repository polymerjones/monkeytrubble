// Push sender core (1.1.4). Runtime-neutral (Deno on Supabase, Node for tests): everything it needs comes in through `env` and
// `fetch`. One run: claim due pushes (push_claim), send each to each of the player's devices (APNs for iOS, FCM for Android),
// report every result (push_report). Secrets live only in Supabase function secrets, never in Git or the apps.
//
// Results per device: sent | dead (token gone: deleted) | retry (temporary: backoff) | quiet (22:00-08:00 on that device: morning).

export type Env = {
  SUPABASE_URL: string; SERVICE_ROLE_KEY: string;
  APNS_KEY_P8?: string; APNS_KEY_ID?: string; APNS_TEAM_ID?: string; APNS_BUNDLE_ID?: string;
  FCM_SERVICE_ACCOUNT?: string; // the service-account JSON, as a string
};
type Device = { token: string; platform: 'ios' | 'android'; env: 'prod' | 'sandbox'; lang: 'en' | 'es'; tz_min: number };
type Push = { id: number; player: string; kind: string; msg: string; args: unknown[]; attempts: number; devices: Device[] };
type Result = { id: number; token: string; result: 'sent' | 'dead' | 'retry' | 'quiet'; detail?: string; retry_in_s?: number };

// The words. {0}, {1}: the args from the database (a name). Same voice as the in-game news lines.
const TEXT: Record<string, Record<'en' | 'es', string>> = {
  duoInvite: { en: '🧩 {0} wants to build a puzzle with you!', es: '🧩 ¡{0} quiere armar un puzzle contigo!' },
  duoAccepted: { en: '🧩 {0} said yes! Your shared puzzle has started.', es: '🧩 ¡{0} dijo que sí! Su puzzle compartido empezó.' },
  duoDone: { en: '🧩 Your shared puzzle with {0} is complete! Collect your reward.', es: '🧩 ¡Tu puzzle compartido con {0} está completo! Recoge tu premio.' },
  request: { en: '🐒 {0} wants to be friends!', es: '🐒 ¡{0} quiere ser tu amigo!' },
  accepted: { en: '🐒 {0} accepted your friend request!', es: '🐒 ¡{0} aceptó tu solicitud de amistad!' },
  nudge: { en: '🍌 {0} nudged you. The monkeys are waiting.', es: '🍌 {0} te dio un toque. Los monos te esperan.' },
  tourneyInvite: { en: '🏆 {0} invited you to a Troop Tournament!', es: '🏆 ¡{0} te invitó a un Torneo de la Tropa!' },
  tourneyDone: { en: '🏆 Your Troop Tournament is over. See who won!', es: '🏆 Tu Torneo de la Tropa terminó. ¡Mira quién ganó!' },
};
export function words(msg: string, lang: 'en' | 'es', args: unknown[]): string {
  const t = TEXT[msg]?.[lang] ?? TEXT[msg]?.en ?? '🐒 Something happened in Monkey Trubble!';
  return t.replace(/\{(\d)\}/g, (_, i) => String(args[+i] ?? '').slice(0, 24));
}

// Quiet hours on the device: 22:00-08:00 local. Returns seconds until 08:00, or 0 when it's fine to send now.
export function quietFor(now: Date, tzMin: number): number {
  const local = new Date(now.getTime() + tzMin * 60e3), h = local.getUTCHours(), m = local.getUTCMinutes();
  if (h >= 8 && h < 22) return 0;
  const minsTo8 = ((8 * 60 - (h * 60 + m)) + 24 * 60) % (24 * 60);
  return Math.max(60, minsTo8 * 60);
}
const backoff = (attempts: number) => [60, 300, 900, 3600, 3 * 3600, 6 * 3600][Math.min(attempts, 6) - 1] ?? 3600;

// ---- signing (WebCrypto: the same in Deno and Node) ----
const b64url = (b: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof b === 'string' ? new TextEncoder().encode(b) : new Uint8Array(b as ArrayBuffer);
  let s = ''; for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const pemBody = (pem: string) => Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')), c => c.charCodeAt(0));
async function jwt(header: object, claims: object, key: CryptoKey, alg: AlgorithmIdentifier | EcdsaParams): Promise<string> {
  const head = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  return `${head}.${b64url(await crypto.subtle.sign(alg, key, new TextEncoder().encode(head)))}`;
}

export function makeSender(env: Env, fetchFn: typeof fetch = fetch, nowFn: () => Date = () => new Date()) {
  // Cached as promises, so parallel sends share one token (Apple throttles token refreshes: TooManyProviderTokenUpdates).
  let apns: { token: Promise<string>; at: number } | null = null, fcm: { token: Promise<{ token: string; project: string }>; until: number } | null = null;
  const rpc = async (fn: string, body: unknown) => {
    const r = await fetchFn(`${env.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/rpc/${fn}`, { method: 'POST',
      headers: { apikey: env.SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    if (!r.ok) throw new Error(`${fn} ${r.status}: ${await r.text()}`);
    return r.json();
  };
  // APNs provider token: ES256, reused for 40 minutes (Apple allows 20-60).
  function apnsToken(): Promise<string> {
    const t = nowFn().getTime();
    if (apns && t - apns.at < 40 * 60e3) return apns.token;
    const token = (async () => {
      const key = await crypto.subtle.importKey('pkcs8', pemBody(env.APNS_KEY_P8!), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
      return jwt({ alg: 'ES256', kid: env.APNS_KEY_ID }, { iss: env.APNS_TEAM_ID, iat: Math.floor(t / 1000) }, key, { name: 'ECDSA', hash: 'SHA-256' });
    })();
    apns = { token, at: t };
    token.catch(() => { apns = null });
    return token;
  }
  // FCM: a Google OAuth access token from the service account (RS256 assertion), reused until 5 minutes before it expires.
  function fcmToken(): Promise<{ token: string; project: string }> {
    const t = nowFn().getTime();
    if (fcm && t < fcm.until) return fcm.token;
    const token = fetchFcmToken(t);
    fcm = { token, until: t + 50 * 60e3 };
    token.then(v => { if (fcm?.token === token) fcm.until = t + (v as { expires: number }).expires; }, () => { fcm = null });
    return token;
  }
  async function fetchFcmToken(t: number): Promise<{ token: string; project: string; expires: number }> {
    const sa = JSON.parse(env.FCM_SERVICE_ACCOUNT!);
    const key = await crypto.subtle.importKey('pkcs8', pemBody(sa.private_key), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
    const iat = Math.floor(t / 1000);
    const assertion = await jwt({ alg: 'RS256', typ: 'JWT' }, { iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token', iat, exp: iat + 3600 }, key, { name: 'RSASSA-PKCS1-v1_5' });
    const r = await fetchFn('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${assertion}` });
    if (!r.ok) throw new Error(`oauth ${r.status}`);
    const j = await r.json();
    return { token: j.access_token, project: sa.project_id, expires: (j.expires_in - 300) * 1000 };
  }

  async function sendOne(p: Push, d: Device): Promise<Result> {
    const base = { id: p.id, token: d.token };
    const quiet = quietFor(nowFn(), d.tz_min);
    if (quiet) return { ...base, result: 'quiet', retry_in_s: quiet };
    const body = words(p.msg, d.lang, p.args);
    try {
      if (d.platform === 'ios') {
        if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID || !env.APNS_BUNDLE_ID) return { ...base, result: 'retry', detail: 'APNs not configured', retry_in_s: 3600 };
        const host = d.env === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
        const r = await fetchFn(`https://${host}/3/device/${d.token}`, { method: 'POST', headers: { authorization: `bearer ${await apnsToken()}`,
          'apns-topic': env.APNS_BUNDLE_ID, 'apns-push-type': 'alert', 'apns-priority': '10', 'apns-collapse-id': `${p.kind}-${p.id}` },
          body: JSON.stringify({ aps: { alert: { title: 'Monkey Trubble', body }, sound: 'default', 'thread-id': p.kind }, kind: p.kind }) });
        if (r.ok) return { ...base, result: 'sent' };
        const reason = await r.json().then((j: { reason?: string }) => j.reason ?? '').catch(() => '');
        if (r.status === 410 || ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'].includes(reason)) return { ...base, result: 'dead', detail: `${r.status} ${reason}` };
        if (r.status === 403 && reason === 'ExpiredProviderToken') apns = null;
        return { ...base, result: 'retry', detail: `${r.status} ${reason}`, retry_in_s: backoff(p.attempts) };
      }
      if (!env.FCM_SERVICE_ACCOUNT) return { ...base, result: 'retry', detail: 'FCM not configured', retry_in_s: 3600 };
      const { token, project } = await fcmToken();
      const r = await fetchFn(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, { method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: { token: d.token, notification: { title: 'Monkey Trubble', body }, data: { kind: p.kind },
          android: { priority: 'high', collapse_key: `${p.kind}-${p.id}`, notification: { channel_id: 'social', tag: `${p.kind}-${p.id}` } } } }) });
      if (r.ok) return { ...base, result: 'sent' };
      const err = await r.json().catch(() => ({})) as { error?: { status?: string; details?: { errorCode?: string }[] } };
      const code = err.error?.details?.find(x => x.errorCode)?.errorCode ?? err.error?.status ?? '';
      if (r.status === 404 || code === 'UNREGISTERED' || (r.status === 400 && code === 'INVALID_ARGUMENT')) return { ...base, result: 'dead', detail: `${r.status} ${code}` };
      if (r.status === 401) fcm = null;
      const after = Number(r.headers.get('retry-after')) || 0;
      return { ...base, result: 'retry', detail: `${r.status} ${code}`, retry_in_s: Math.max(after, backoff(p.attempts)) };
    } catch (e) {
      return { ...base, result: 'retry', detail: `network: ${(e as Error).message}`.slice(0, 200), retry_in_s: backoff(p.attempts) };
    }
  }

  // One run: up to `batches` claims of 50, reporting after each (an empty claim still reports, so device-less pushes finish).
  return async function run(batches = 4): Promise<{ claimed: number; results: Record<string, number> }> {
    const tally: Record<string, number> = {}; let claimed = 0;
    for (let b = 0; b < batches; b++) {
      const pushes: Push[] = await rpc('push_claim', { p_limit: 50 });
      claimed += pushes.length;
      const results = (await Promise.all(pushes.flatMap(p => p.devices.map(d => sendOne(p, d))))).flat();
      for (const r of results) tally[r.result] = (tally[r.result] || 0) + 1;
      await rpc('push_report', { p_results: results });
      if (pushes.length < 50) break;
    }
    return { claimed, results: tally };
  };
}
