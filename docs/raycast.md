---
summary: "Raycast provider: unofficial AI credits API, session token sources, and monthly allowance mapping."
read_when:
  - Configuring Raycast AI credit tracking
  - Debugging Raycast access-token or credits parsing
  - Explaining why CodexBar asks for a Raycast session token
---

# Raycast Provider

[Raycast](https://www.raycast.com) Pro, Pro+, and Max plans include a monthly AI credit allowance. Credits launched
with Raycast's September 2026 pricing change: Pro includes 500 credits, Pro+ 3,000, and Max 7,500, with optional
top-ups. The in-app **Settings → Account** card shows remaining credits and the next renewal date.

Raycast does not publish a public usage API. CodexBar calls the same unofficial endpoint the desktop app uses:

```text
GET https://backend.raycast.com/api/v1/ai/credits
Authorization: Bearer <access token>
```

## Authentication

Raycast has no user-facing usage API key. The desktop app (Raycast 2.0) keeps the OAuth session inside an encrypted
local database, so CodexBar cannot read it the way it reads Hugging Face or Hermes login files.

Token sources, in precedence order:

1. CodexBar Settings → Providers → Raycast (`RAYCAST_ACCESS_TOKEN` via `codexbar config set-api-key`)
2. `RAYCAST_ACCESS_TOKEN`
3. `RAYCAST_TOKEN`
4. Legacy `~/.config/raycast/config.json` (or `~/.config/raycast-x/config.json`) `token` / `Token` / `accessToken`
5. `RAYCAST_CONFIG_PATH` pointing at a JSON file with one of those keys. When set, the default config files are never
   consulted.

```bash
printf '%s' "$RAYCAST_ACCESS_TOKEN" | codexbar config set-api-key --provider raycast --stdin
```

The token is the account access token the Raycast app sends to `backend.raycast.com`. It is not an AI model key and
it is not covered by a documented contract. If Raycast rejects it, paste a current session token.

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
