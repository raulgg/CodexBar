---
summary: "Raycast provider: unofficial AI credits API, session token sources, and monthly allowance mapping."
read_when:
  - Configuring Raycast AI credit tracking
  - Debugging Raycast access-token or credits parsing
  - Explaining why CodexBar asks for a Raycast session token
---

# Raycast Provider

Website session cookies can read monthly credits. See [raycast-poc.md](raycast-poc.md) for
the discovery trail. Delete that POC note before opening a PR.

[Raycast](https://www.raycast.com) Pro, Pro+, and Max plans include a monthly AI credit allowance. Credits launched
with Raycast's September 2026 pricing change: Pro includes 500 credits, Pro+ 3,000, and Max 7,500, with optional
top-ups. The in-app **Settings → Account** card shows remaining credits and the next renewal date.

The desktop app still uses Bearer `GET /api/v1/ai/credits`. CodexBar uses the **website**
session instead:

```text
GET https://www.raycast.com/frontend_api/current_user/ai_credits
Cookie: __raycast_session=…; csrf_token=…
```

## Authentication

Automatic: Chrome, then Brave, cookies for `www.raycast.com` (must include `__raycast_session`).
That import runs inside **CodexBar.app** (Full Disk Access + Brave/Chrome Safe Storage). A
`swift build` CLI binary usually cannot read Brave cookies and reports no session found.

Manual: Cookie source Manual, paste the Cookie header from a signed-in
[Account](https://www.raycast.com/settings) request. Cookie-only GET is enough; CSRF is not
required for this route.

```bash
# after enabling the provider, from a signed-in www.raycast.com Network request:
# paste Cookie header in Settings, or in ~/.codexbar/config.json:
# "cookieSource": "manual", "cookieHeader": "__raycast_session=…; csrf_token=…"
```

Do not paste the desktop OAuth Bearer. Do not send website cookies to
`backend.raycast.com/api/v1/ai/credits` (401).

## Data shown

The bundled `raycast.ts` plugin owns the HTTP request and snapshot mapping:

| Field | Display |
| --- | --- |
| `remaining_balance_credits`, `total_balance_credits` | Primary meter **Credits** as percent used, plus "N of M left" |
| `next_credits_at` | Meter reset time and **Renews** date |
| `funding_subscription.tier` | Plan label (`pro` → Pro, `pro_plus` → Pro+, `max` → Max) |

Remaining can exceed the current grant when unused monthly credits roll over. CodexBar still uses the reported total as
the denominator and does not invent extra usage. A zero total leaves the meter off rather than showing 100% used.

Top-up packages and the Show details breakdown (`GET /api/v1/ai/credits/details`) are not fetched yet.

## Limitations

- The website credits route is unofficial and can change without notice.
- Automatic import needs a signed-in www.raycast.com session in Chrome or Brave (`__raycast_session`).
- BYOK, Bring Your Own Subscription, and local models do not count against these credits and are not shown here.
