---
summary: "POC working note: Raycast AI credits. Delete this file before opening a PR."
read_when:
  - Picking this provider back up
  - Talking to Raycast about OAuth or a website credits API
  - Opening a Raycast provider PR (delete this file first)
---

# Raycast credits POC

**Delete this file if this work ever becomes a PR.** It is a local discovery note, not
provider documentation.

**Status: website credits route exists (2026-09-23).** Desktop Bearer Auto is still blocked.
The site now loads the Account credits card via a **cookie-session** API. That is the OpenCode-shaped
path we wanted. Confirm a Cookie-only replay of that GET, then implement Auto cookies + Manual
Cookie header. Do not merge until that replay works.

This note is the discovery trail so a later attempt (or a conversation with Raycast) does not
repeat it.

## Website `frontend_api` (2026-09-23)

The Account page on [www.raycast.com](https://www.raycast.com) now shows the credits card
(“163 out of 500 credits **used**”, renews 18 Oct, Top Up). That UI calls:

```text
GET https://www.raycast.com/frontend_api/current_user/ai_credits
Cookie: <www.raycast.com session>
```

Same path exists on `https://backend.raycast.com/frontend_api/current_user/ai_credits`.
Unauthenticated response is Devise JSON:

```json
{"error":"You need to sign in or sign up before continuing."}
```

HTTP 401, `Content-Type: application/json`. This is a **signed-in website session**, not the
desktop OAuth Bearer. That is why `GET /api/v1/ai/credits` in Brave still 401s with cookies:
wrong route.

Site JS (`/_next/static/immutable/chunks/2sr_sw9wj-7k5.js`):

- Base path `/frontend_api/`
- Browser `fetch` with `credentials: "include"` (sends site cookies)
- Mutating helper also sets `X-CSRF-Token` from the non-HttpOnly `csrf_token` cookie and
  `X-Raycast-Vercel-Proxy: true`
- GET helper `f("current_user/ai_credits")` is a same-origin `fetch` of that path; CSRF is
  for POST/PUT/PATCH/DELETE
- Nearby: `GET /frontend_api/current_user`, Stripe billing portal, subscription interval

`/settings` is the account page; logged-out it redirects to `/users/sign_in?return_to=%2Fsettings`.

The card copy is **used / total**, not remaining (desktop was “429 of 500 left”). Mapping should
be `usedPercent = used / total`, reset from the renew date. Exact JSON field names were not in
the public sign-in chunks; copy them from DevTools on a 200.

**Do not use** `GET https://backend.raycast.com/api/v1/ai/credits` with website cookies.

### Still to prove before coding Auto

1. Replay `GET https://www.raycast.com/frontend_api/current_user/ai_credits` with only the
   Cookie header from that request (plus `Accept: application/json`). Expect 200 and used/total.
2. Note cookie **names** on `www.raycast.com` (session vs `csrf_token`).
3. If 200, CodexBar can follow OpenCode: Chrome/Brave cookie import for `raycast.com`, Manual
   Cookie header as fallback. Include Brave; this machine has no Chrome profile.

## What we wanted

Show remaining monthly Raycast AI credits in CodexBar, matching **Settings → Account** in the
desktop app (e.g. “429 of 500 left”, renews 18 Oct, Pro / Pro+ / Max).

Credits launched with Raycast’s September 2026 pricing change. They apply only to inference
Raycast hosts. BYOK, Bring Your Own Subscription, and local models do not count.

## The API (works, unofficial)

The desktop app (not the website) calls:

```text
GET https://backend.raycast.com/api/v1/ai/credits
Authorization: Bearer <desktop OAuth access_token>
Accept: application/json
```

No `X-Raycast-Signature-v2` on this GET. Chat completions are signed; this route is Bearer only.

Observed body fields the Account card uses:

| Field | Role |
| --- | --- |
| `remaining_balance_credits` | string or number (can be fractional, e.g. `425.664`) |
| `total_balance_credits` | string or number (plan grant, e.g. `500`) |
| `next_credits_at` | ISO-8601, e.g. `2026-10-18T08:34:44Z` |
| `funding_subscription.tier` | `pro` / `pro_plus` / `max` |
| `funding_subscription.status` / `source` / `provider` | e.g. active, personal, stripe |
| `can_top_up` / `can_upgrade_plan` | booleans for the Account card buttons |

Related unofficial routes in the same desktop handler, **not** used in the spike:

- `GET /api/v1/ai/credits/details?range=…&tz=…` (Show details)
- `GET /api/v1/pricing`
- `POST /api/v1/ai/credits/top_up`

Empty/missing amounts must fail closed. Remaining **above** `total` is rollover, not extra usage
(used percent stays 0). A zero total must not become 100% used.

Live CLI check on this machine (v1 Keychain Bearer, not a user-facing flow): `425.66 of 500 left`,
renews Oct 18, plan Pro, `usedPercent` ~14.9, `dataConfidence: exact`.

## Auth: 1.x vs 2.0

### Desktop 2.0 (current app, the target)

- Login is first-party PKCE against `https://www.raycast.com/oauth/authorize`.
- Redirect is `https://www.raycast.com/oauth-redirect?scheme=com.raycast` (or `com.raycast://oauth-callback` in custom builds).
- Token POST is `oauth/token` on the backend. Scope `read write`. Refresh tokens exist.
- After login the JS backend does `fr.set({ key: "OAuthTokenResponse", value: JSON.stringify(tokens) })`.
- That store is **encrypted `settings_v2.db`**, not Keychain. The access token is **not** a Keychain generic password.
- The **SQLCipher key** for that DB *is* in Keychain (`database_key` on the legacy service `Raycast`, plus a shared access group CodexBar cannot read). Native strings: persist DB key to legacy Keychain and to the shared group; `raydb-key-handoff` is private IPC between Raycast processes.
- `wdsAuthToken` in `com.raycast.macos` UserDefaults is a JWT; `GET /ai/credits` with it returned **401**.
- `~/.config/raycast/config.json` is the **1.x** layout. It was absent on this 2.0 install.

Decrypting `settings_v2.db` with `database_key` would yield `OAuthTokenResponse`. We rejected that as the product: it is reading Raycast’s vault, not a session the user created for CodexBar.

### Desktop 1.x (deprecated, leftover on this Mac)

- Keychain `service=Raycast`, `account=raycast-store_credentials`.
- JSON `{ oauth: { access_token }, user }`. That access token still authorized `/ai/credits` here.
- New 2.0-only installs never write this item. Do not build the provider around it.

### Website

- [raycast.com](https://www.raycast.com) does **not** host the credits UI. `/account` is the marketing homepage.
- Docs: balance is **Settings → Account in the app**.
- Opening `https://backend.raycast.com/api/v1/ai/credits` in Brave **does send cookies** and returns **401**.
- There are no website XHRs to that credits URL while using raycast.com. Cookie Auto (OpenCode/Cursor style) cannot work until Raycast puts usage on a site session.

## Options we considered

| | Idea | Outcome |
| --- | --- | --- |
| A | Keychain `database_key` + SQLCipher `settings_v2.db` + `OAuthTokenResponse` | Technically the only unattended 2.0 Auto. Rejected: decrypting the app DB is the wrong trust model. |
| B | Paste / env Bearer (`RAYCAST_ACCESS_TOKEN`) | The token is real, but a normal user cannot obtain it (no API key, no website bearer, Proxyman-only). Not a fallback we would ship. |
| C | CodexBar “Sign in with Raycast” (PKCE / device flow) | Raycast’s OAuth client is first-party. Redirect goes back to Raycast.app. No public client registration, no device-code grant in the 2.0 client. Needs Raycast to issue CodexBar a client. Unlikely. |
| D | Chrome/Brave cookies for **www.raycast.com**, Manual Cookie header as last resort | **Reopened 2026-09-23.** Site Account card calls `/frontend_api/current_user/ai_credits` with the website session. `GET /api/v1/ai/credits` with those cookies is still 401 (wrong API). Cookie-only replay of the **frontend_api** GET is the remaining proof. |

Honest v1 with current Raycast: **do not ship.**

## What to ask Raycast

Two asks, in likely-success order:

1. **Website credits (done on their side, 2026-09-23).** Account page calls
   `/frontend_api/current_user/ai_credits` with the site session. If Cookie replay of that GET
   returns 200, we do not need Raycast to do more for v1 Auto.
2. **OIDC / OAuth client for CodexBar (unlikely).** A registered client id, a `codexbar://` or localhost redirect, and a scope that can call `GET /api/v1/ai/credits` (or a documented equivalent). Then a Sign in button like Copilot. Reusing the desktop PKCE client and `com.raycast` redirect is not acceptable.

Until one of those exists, leave this branch parked.

## Code on this branch (spike only)

- Provider id `raycast`, bundled plugin `raycast.ts` → `GET /api/v1/ai/credits`, Bearer from env/settings/legacy `config.json`.
- Snapshot mapping and plugin tests are still valid **if** auth appears later.
- Do not document paste-token as something users should do.

## Live checks on this machine (2026-09-19)

- CLI built (`swift build --product CodexBarCLI`). `codexbar usage --provider raycast` without a token: `No available fetch strategy`.
- Same CLI with the leftover 1.x Keychain access token (not persisted to `~/.codexbar/config.json`): JSON snapshot as above.
- Menu bar app not rebuilt here: no full Xcode / `actool`. Installed `/Applications/CodexBar.app` is 0.61.0 and has no Raycast provider.
- Brave Cookies DB exists but is not readable from this agent or from Terminal (`authorization denied`).
