---
summary: "Parked plan for Raycast monthly credit pacing. Do not implement until remaining/total wallet semantics are captured."
read_when:
  - Adding pace to the Raycast Credits bar
  - Interpreting remaining_balance_credits vs total_balance_credits
  - Capturing a rollover or top-up credits payload
---

# Raycast monthly pacing (parked)

Status: exploratory. Do not ship pace on the Credits bar until a live credits payload
with leftover monthly credits or a top-up is captured and the `total_balance_credits`
meaning is known.

## Goal

Show CodexBar's usual monthly even-burn verdict on the Raycast Credits bar (on pace /
in reserve / in deficit, plus lasts-until-reset or runs-out), using the existing
calendar-month pace path. History charts and `credits/details` stay out of this pass.

## Settled

- Credits already have used percent and `next_credits_at`. The missing piece is
  cycle length: `windowMinutes` is nil, and the descriptor defaults to
  `pace: .unsupported`.
- Cycle start is `next_credits_at` minus one calendar month. Raycast bills on the
  subscription anniversary ("same date each month"), and credit grants follow that
  monthly clock even on yearly billing.
- Stamp `ProviderPaceCapability.monthlyWindowSentinelMinutes` on the primary window
  when remaining, total, and renewal are all present. Set
  `pace: .calendarMonthResetWindow` on `RaycastProviderDescriptor`. Resolution
  replaces the 30-day sentinel with the real anniversary length. Same pattern as
  Notion and Command Code.
- Keep Swift `RaycastUsageFetcher` and bundled `raycast.ts` / `raycast.js` in
  lockstep.
- Early-cycle silence (no verdict until expected used is a few percent) is
  accepted.

## Blocker: what Total means

Pace compares **percent used** to **elapsed fraction of the month**. Percent used
today is `(total − remaining) / total`, clamped so leftover never becomes extra
usage. That formula is only a monthly burn rate if `total_balance_credits` is the
allowance for **this** cycle.

Working hypothesis, unproven: `total_balance_credits` is the **wallet** —
current monthly grant plus leftover monthly credits plus top-ups — and it rises
when you top up. `remaining_balance_credits` is what is left of that wallet.
Field names (`remaining_balance` / `total_balance`) read that way.

Every payload captured so far is consistent with that **and** with Total being
only the sticker monthly grant:

| Source | Remaining | Total |
| --- | --- | --- |
| Desktop `GET /api/v1/ai/credits` | 425.66 | 500 |
| Website Account card | 163 used of 500 | 500 |

On Pro, 500 is the monthly grant. With no leftover pack and no top-up, wallet
total and grant total are the same number. Those captures do not distinguish
the two.

Raycast's own rules that would move the wallet off the sticker grant
([Usage Limits](https://manual.raycast.com/ai/usage-limits),
[Billing](https://manual.raycast.com/billing)):

- Unused monthly credits roll over for one extra cycle; each monthly grant
  expires 60 days after it is granted.
- Top-ups (500 / 2,500 / 5,000 / 10,000) expire 12 months after purchase and
  can be bought before the monthly grant is empty. Spend is FIFO by expiry,
  so monthly credits usually go first.
- 10 Sep 2026 launch bonus: existing subscribers received two monthly packs
  at once, expiring after 30 days.
- Yearly Pro / Pro+ from 11 Sep 2026: next reset is 750 / 4,500 per month
  for the rest of that annual term.

### If Total is the wallet

Remaining stays at or below Total. Top-ups raise both. The Credits rows stay
honest as Left / Total of spendable credits.

Linear **monthly** pace on that used percent is still the risky part. Example:
Pro grant 500, 400 leftover, 500 top-up → Total 1,400. Spending 400 this month
is 29% of the wallet and 80% of this cycle's grant. The bar would look behind
an even monthly burn.

### If Total is this cycle's grant

Remaining can exceed Total after rollover or a top-up. The parser already
clamps that to 0% used (`750` vs `500` in tests). Pace would then read as a
large reserve even while the new month is being spent quickly.

Until a payload with extra grants exists, do not special-case either shape.

## Capture before implementing

Need one live `GET https://www.raycast.com/frontend_api/current_user/ai_credits`
body (website session cookie) from an account whose **Settings → Account →
Show details → Credit Activity** lists more than the current monthly grant.

Record, together:

1. The JSON: `remaining_balance_credits`, `total_balance_credits`,
   `next_credits_at`, `funding_subscription.tier`, and any extra fields.
2. Credit Activity rows: each grant's type (monthly / top-up / trial / bonus),
   amount, granted-at, expires-at.
3. What the Account card prints (used-of-N vs N-left).
4. Whether a top-up changes `total_balance_credits` immediately.

Useful extra captures, if available:

- Yearly Pro after the 750-credit reset, with Total 500 vs 750 vs leftover+750.
- The same account before and after buying a 500 top-up.

Do not use Keychain, desktop Bearer, or `settings_v2.db` for this. Website
cookie replay of `frontend_api` is enough.

## When unblocked

1. Decide whether used percent is of this month's grant or of the wallet. If
   Total is the wallet, monthly pace may need a grant-sized denominator from
   tier (500 / 3,000 / 7,500, or 750 / 4,500 for the yearly bump) rather than
   `total_balance_credits`.
2. Stamp the monthly sentinel and enable `calendarMonthResetWindow`.
3. Tests: sentinel minutes when renewal exists; capability mapping for
   `.raycast`; mid-cycle fixture; the leftover/top-up shape from the capture.
4. Docs: this file becomes shipped behavior in [raycast.md](raycast.md).

Surfaces that pick it up with no extra UI: Credits bar, `codexbar usage`,
menu-bar Auto pace. Session/weekly pace tokens stay empty; Raycast already
only advertises automatic and primary metrics.

## Out of scope

- `GET /api/v1/ai/credits/details` and any Today / 30-day spend chart. That
  route is desktop Bearer today; website cookies 401 on `backend.raycast.com`.
- Work-day ticks. Those apply to 7-day windows only.
- Decrypting Raycast's desktop vault or asking for an OAuth client.

## Files when this unblocks

- `Sources/CodexBarCore/Providers/Raycast/RaycastUsageFetcher.swift`
- `Sources/CodexBarCore/Providers/Raycast/RaycastProviderDescriptor.swift`
- `Sources/CodexBarCore/Resources/Plugins/raycast.ts` (and bundled `raycast.js`)
- `Tests/CodexBarTests/RaycastPluginTests.swift`
- `Tests/CodexBarTests/ProviderPaceCapabilityTests.swift` (add `.raycast` to
  the calendar-month list)
- `docs/raycast.md`
