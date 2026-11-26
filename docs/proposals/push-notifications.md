# Real push notifications: plan (next project after 1.1.3)

## Why
Every notification today is **local**. Friend news only travels inside the once-a-day reminder:
- the page writes news it already knows into today's reminder;
- Android checks for news when the reminder is due;
- the iPhone checks with a background refresh that iOS runs when it chooses, and never after the app was force-quit.

So an invite or a tournament result can arrive hours late, or not at all. Real push is what makes social features feel alive, and Troop Tournaments benefit most.

## What it is
| Piece | iPhone | Android |
|---|---|---|
| Delivery service | Apple Push Notification service (APNs) | Firebase Cloud Messaging (FCM) |
| App side | `registerForRemoteNotifications`, `aps-environment` entitlement, send the device token to us | Firebase SDK, `google-services.json`, send the FCM token to us |
| Our server | `device_tokens` table (player, platform, token, updated_at, app_version), RLS on, written by `register_device(p_id, p_secret, platform, token)` | same |
| Sending | A Supabase Edge Function `push`, called from database triggers on: invite created, invite accepted, shared puzzle done, tournament invite, tournament finished. Signs an APNs JWT with our Apple key and calls FCM HTTP v1 with a service account | same |
| Taps | Already done in 1.1.3: `kind` in the payload → `__monkeyOpen(kind)` opens the right screen, from a cold launch or a running game | same |

**Respecting players**
- Only real activity from real friends.
- FRIEND NEWS off means no push. Tokens for players who turned it off are deleted.
- At most a handful a day (server-side rate limit per player).
- Nothing at night (send window from the player's time zone, stored with the token).
- Daily reminders stay local and unchanged.

**Diagnostics**
- Each send logs its status (`ok`, `unregistered`, `rate_limited`, `error`) in a `push_log` table, kept for 7 days.
- Apple and Google report dead tokens (`Unregistered` / `410`), which we delete.
- So a delivery failure can be told apart from a player who turned notifications off.

## What I need from Paul
1. **Apple:** in the developer account → Keys → create an APNs key (.p8). Send the Key ID and Team ID (976XKW42U9). The key file goes into Supabase secrets, never into the repo. Enable Push Notifications on the App ID.
2. **Google:** create a Firebase project for `com.paulfisher.monkeytrubble`, download `google-services.json`, and create a service-account key for FCM. That key also goes into Supabase secrets.
3. **Supabase:** run the migration (tables, functions, triggers) and deploy the Edge Function. I'll hand over the SQL and function code with the same review steps as the 1.1.3 migrations.
4. **Store review:** the App Store privacy label gains "device ID for app functionality" (the push token).

## Plan
1. Server: tables, register function, Edge Function and triggers, all tested on PGlite plus the staging Supabase project once it exists.
2. iOS: entitlement, registration, token upload, and payload `kind` (tap routing is already done).
3. Android: Firebase messaging service, token upload, and the same channel and taps.
4. Social Lab: a "push test" button that sends a real push to your own device through the Edge Function (dev builds only).
5. Ship to iPhone for a real-device test with Paul plus one friend, then turn on tournament pushes.

**Estimate:** 2–3 sessions once the Apple and Firebase keys exist.
