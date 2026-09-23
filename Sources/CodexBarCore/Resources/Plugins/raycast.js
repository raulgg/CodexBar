defineProvider({
  id: "raycast",
  name: "Raycast",
  endpoints: ["https://www.raycast.com"],
  settings: [],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["www.raycast.com", "raycast.com"],
  async fetchUsage(ctx) {
    const sessionCookie = (value) => /(?:^|;\s*)__raycast_session=/.test(value);
    const missingSession = () => {
      throw ctx.fail.missingCredential(
        "No Raycast website session found. Sign in at www.raycast.com/settings in Chrome or Brave. " +
          "Automatic import needs Full Disk Access (the packaged app, not a repo CLI build). " +
          "Otherwise set Cookie source to Manual and paste a header that includes __raycast_session.",
      );
    };
    let cookie = "";
    // Query raycast.com so Domain=.raycast.com cookies match (.contains).
    // www.raycast.com does not match host_key ".raycast.com".
    for (const domain of ["raycast.com", "www.raycast.com"]) {
      try {
        const header = await ctx.browser.cookieHeader(domain);
        if (sessionCookie(header)) {
          cookie = header;
          break;
        }
      } catch (error) {
        void error;
      }
    }
    if (!cookie) missingSession();
    const response = await ctx.http.get("https://www.raycast.com/frontend_api/current_user/ai_credits", {
      timeoutSeconds: 15,
      headers: { Cookie: cookie, Accept: "application/json" },
    });
    if (response.status === 401) {
      throw ctx.fail.authenticationExpired(
        "Raycast website session expired. Sign in at www.raycast.com/settings or paste a fresh Cookie header.",
      );
    }
    if (response.status === 403) {
      throw ctx.fail.permissionDenied("Raycast denied access to AI credits for this account.");
    }
    if (response.status === 429) throw ctx.fail.rateLimited("Raycast credits requests are rate limited.");
    if (response.status >= 500) {
      throw ctx.fail.providerUnavailable(`Raycast credits API returned HTTP ${response.status}.`);
    }
    if (response.status !== 200) {
      throw ctx.fail.apiFailure(`Raycast credits API returned HTTP ${response.status}.`);
    }

    const fail = (field) => {
      throw ctx.fail.parseFailure(`Invalid Raycast credits response: ${field}`);
    };
    const object = (value, field) => {
      if (value === undefined || value === null) return {};
      if (typeof value !== "object" || Array.isArray(value)) return fail(field);
      return value;
    };
    const number = (value, field) => {
      if (value === undefined || value === null) return undefined;
      if (typeof value === "number") {
        return Number.isFinite(value) ? value : fail(field);
      }
      if (typeof value !== "string") return fail(field);
      const trimmed = value.trim();
      if (trimmed === "") return fail(field);
      if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(trimmed)) return fail(field);
      const parsed = Number(trimmed);
      return Number.isFinite(parsed) ? parsed : fail(field);
    };
    const text = (value) => (typeof value === "string" ? value.trim() || undefined : undefined);
    const amount = (value) =>
      Number.isInteger(value)
        ? String(value)
        : ctx.format.number(value, { minimumFractionDigits: 0, maximumFractionDigits: 2 });
    const planLabel = (tier) => {
      switch (tier) {
        case "pro":
          return "Pro";
        case "pro_plus":
          return "Pro+";
        case "max":
          return "Max";
        default:
          return tier;
      }
    };

    let decoded;
    try {
      decoded = JSON.parse(response.bodyText);
    } catch (error) {
      void error;
      return fail("expected JSON");
    }
    const root = object(decoded, "expected an object");
    const remaining = number(root.remaining_balance_credits, "remaining_balance_credits");
    const total = number(root.total_balance_credits, "total_balance_credits");
    if (remaining === undefined && total === undefined) return fail("no credit amounts");
    if (remaining !== undefined && remaining < 0) return fail("remaining_balance_credits");
    if (total !== undefined && total < 0) return fail("total_balance_credits");

    let renewal;
    if (root.next_credits_at !== undefined && root.next_credits_at !== null) {
      if (typeof root.next_credits_at !== "string") return fail("next_credits_at");
      try {
        renewal = ctx.date.iso(root.next_credits_at);
      } catch (error) {
        void error;
        return fail("next_credits_at");
      }
    }
    const funding = object(root.funding_subscription, "funding_subscription");
    const plan = planLabel(text(funding.tier));
    const rows = [];
    if (remaining !== undefined && total !== undefined) {
      rows.push({ label: "Credits", value: `${amount(remaining)} of ${amount(total)} left` });
    } else if (remaining !== undefined) {
      rows.push({ label: "Credits remaining", value: amount(remaining) });
    } else if (total !== undefined) {
      rows.push({ label: "Credit allowance", value: amount(total) });
    }
    if (renewal) rows.push({ label: "Renews", value: ctx.format.monthDay(renewal) });
    if (plan) rows.push({ label: "Plan", value: plan });

    return {
      primary:
        remaining !== undefined && total !== undefined && total > 0
          ? {
              usedPercent: ctx.pct(Math.max(0, total - remaining), total),
              resetsAt: renewal,
            }
          : undefined,
      details: rows.length ? [{ title: "Credits", rows }] : undefined,
      subscriptionRenewsAt: renewal,
      identity: plan ? { loginMethod: plan } : undefined,
      dataConfidence: "exact",
    };
  },
});
