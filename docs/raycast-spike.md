---
summary: "Working note: Raycast AI credits spike. Not a shipped provider. Auth is blocked for 2.0."
read_when:
  - Picking this provider back up
  - Talking to Raycast about OAuth or a website credits API
  - Deciding whether cookie Auto can work
---

# Raycast credits spike (temporary)

**Status: blocked.** Do not merge as a user-facing provider. The mapper and unofficial
`GET /api/v1/ai/credits` contract are real. There is no honest way for a 2.0 user to give
CodexBar a session.

This note is the discovery trail so a later attempt (or a conversation with Raycast) does not
repeat it.

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
| D | Chrome/Brave cookies for raycast.com, Manual Cookie header as last resort | **Dead.** Browser GET of the credits URL with cookies → 401. This agent also could not read Brave’s Cookies sqlite (macOS authorization denied even from Terminal). |

Honest v1 with current Raycast: **do not ship.**

## What to ask Raycast

Two asks, in likely-success order:

1. **Website credits (more likely).** Expose the same monthly remaining/total/renewal on an account URL under raycast.com, authenticated with the **site session** (cookie or site bearer). Then CodexBar can use the existing OpenCode-style ladder: Chrome/Brave cookie import, Manual Cookie header if import is off. The unofficial JSON we already map (`remaining_balance_credits`, `total_balance_credits`, `next_credits_at`, `funding_subscription.tier`) is enough.
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
