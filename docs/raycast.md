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

Automatic: same browser-cookie import as OpenCode Go (`Browser.defaultImportOrder`, Chrome among
the shared Chromium sources). The session cookie is `__raycast_session` on `raycast.com`.

Manual: paste the Cookie header from a signed-in [Account](https://www.raycast.com/settings)
request. Cookie-only GET is enough; CSRF is not required for this route.

Do not paste the desktop OAuth Bearer. Do not send website cookies to
`backend.raycast.com/api/v1/ai/credits` (401).

## Data shown

The bundled `raycast.ts` plugin owns the HTTP request and snapshot mapping:

| Field | Display |
| --- | --- |
| `remaining_balance_credits` | **Left**, under the **Credits** heading |
| `total_balance_credits` | **Total** |
| `next_credits_at` | Meter reset time and **Renews**, with the date, year, and time |
| `funding_subscription.tier` | Header plan label (`pro` → Pro, `pro_plus` → Pro+, `max` → Max) |

When both amounts are present and the total is above zero, the primary meter is percent used.

Remaining can exceed the current grant when unused monthly credits roll over. CodexBar still uses the reported total as
the denominator and does not invent extra usage. A zero total leaves the meter off rather than showing 100% used.

Top-up packages and the Show details breakdown (`GET /api/v1/ai/credits/details`) are not fetched yet.

Monthly even-burn pacing is parked until a live credits payload with leftover monthly
credits or a top-up shows what `total_balance_credits` measures. See
[raycast-pacing.md](raycast-pacing.md).

## Limitations

- The website credits route is unofficial and can change without notice.
- Automatic import needs a signed-in www.raycast.com session (`__raycast_session`) in a browser
  CodexBar already imports (same order as OpenCode Go).
- BYOK, Bring Your Own Subscription, and local models do not count against these credits and are not shown here.
