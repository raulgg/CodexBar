---
summary: "Raycast provider: unofficial AI credits API, session token sources, and monthly allowance mapping."
read_when:
  - Configuring Raycast AI credit tracking
  - Debugging Raycast access-token or credits parsing
  - Explaining why CodexBar asks for a Raycast session token
---

# Raycast Provider

**Not shippable.** Auth for Raycast 2.0 is blocked. The unofficial credits mapper is on this
branch as a spike only. See [raycast-spike.md](raycast-spike.md) for the full trail and what to
ask Raycast.

[Raycast](https://www.raycast.com) Pro, Pro+, and Max plans include a monthly AI credit allowance. Credits launched
with Raycast's September 2026 pricing change: Pro includes 500 credits, Pro+ 3,000, and Max 7,500, with optional
top-ups. The in-app **Settings → Account** card shows remaining credits and the next renewal date.

Raycast does not publish a public usage API. The desktop app calls:

```text
GET https://backend.raycast.com/api/v1/ai/credits
Authorization: Bearer <access token>
```

## Authentication

Blocked for 2.0. Website cookies get 401 on the credits URL. The desktop access token is not in
Keychain and is not something a user can paste. Do not ship Settings “paste a token.” Details:
[raycast-spike.md](raycast-spike.md).

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

- The credits endpoint is unofficial and can change without notice.
- Raycast 2.0 session auto-discovery is not implemented: the encryption key for `settings_v2.db` stays inside the
  running app.
- BYOK, Bring Your Own Subscription, and local models do not count against these credits and are not shown here.
