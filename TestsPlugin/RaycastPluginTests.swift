import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct RaycastPluginTests {
    static let credits = #"""
    {
      "remaining_balance_credits": "125",
      "total_balance_credits": "500",
      "next_credits_at": "2026-10-18T00:00:00.000Z",
      "can_top_up": true,
      "can_upgrade_plan": true,
      "funding_subscription": {
        "tier": "pro",
        "source": "personal",
        "provider": "stripe",
        "status": "active",
        "canceled": false
      }
    }
    """#

    @Test(arguments: BundledPluginTestSupport.engines)
    func `monthly credits project as remaining of total`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(Self.credits, engine: engine)
        #expect(snapshot.primary?.usedPercent == 75)
        #expect(snapshot.primary?.windowMinutes == nil)
        #expect(snapshot.primary?.resetsAt == Self.date("2026-10-18T00:00:00.000Z"))
        #expect(snapshot.subscriptionRenewsAt == snapshot.primary?.resetsAt)
        #expect(snapshot.identity?.providerID == .raycast)
        #expect(snapshot.identity?.loginMethod == "Pro")
        #expect(snapshot.details.map(\.title) == ["Credits"])
        #expect(snapshot.details[0].rows.map(\.label) == ["Credits", "Renews", "Plan"])
        #expect(snapshot.details[0].rows[0].value == "125 of 500 left")
        #expect(snapshot.details[0].rows[2].value == "Pro")
        #expect(snapshot.providerCost == nil)
        #expect(snapshot.dataConfidence == .exact)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `website account payload maps remaining of total`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(#"""
        {
          "remaining_balance_credits": "337.3751",
          "total_balance_credits": "500.0",
          "next_credits_at": "2026-10-18T08:34:44Z",
          "funding_subscription": {"tier": "pro", "status": "active"}
        }
        """#, engine: engine)
        #expect(abs((snapshot.primary?.usedPercent ?? 0) - 32.525) < 0.01)
        #expect(snapshot.details[0].rows[0].value == "337.38 of 500 left")
        #expect(snapshot.identity?.loginMethod == "Pro")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `numeric amounts and Pro Plus labels are preserved`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(#"""
        {
          "remaining_balance_credits": 12.5,
          "total_balance_credits": 50,
          "funding_subscription": {"tier": "pro_plus"}
        }
        """#, engine: engine)
        #expect(snapshot.primary?.usedPercent == 75)
        #expect(snapshot.details[0].rows[0].value == "12.5 of 50 left")
        #expect(snapshot.identity?.loginMethod == "Pro+")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `rollover remaining above the current grant does not invent extra usage`(
        engine: ProviderPluginEngineKind) async throws
    {
        let snapshot = try await Self.fetch(#"""
        {"remaining_balance_credits":"750","total_balance_credits":"500"}
        """#, engine: engine)
        #expect(snapshot.primary?.usedPercent == 0)
        #expect(snapshot.details[0].rows[0].value == "750 of 500 left")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `zero allowance does not invent a quota window`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(#"""
        {"remaining_balance_credits":"0","total_balance_credits":"0","funding_subscription":{"tier":"max"}}
        """#, engine: engine)
        #expect(snapshot.primary == nil)
        #expect(snapshot.identity?.loginMethod == "Max")
        #expect(snapshot.details[0].rows[0].value == "0 of 0 left")
    }

    @Test(
        arguments: ["true", "false", "\"NaN\"", "\"Infinity\"", "\"\"", "[]", "{}", "1e400"],
        BundledPluginTestSupport.engines)
    func `invalid amounts fail instead of publishing exact zero`(
        value: String,
        engine: ProviderPluginEngineKind) async
    {
        await Self.expectFailure(.parseFailure) {
            _ = try await Self.fetch("{\"remaining_balance_credits\":\(value)}", engine: engine)
        }
    }

    @Test(arguments: ["null", "[]", "{}", "{\"funding_subscription\":{}}"], BundledPluginTestSupport.engines)
    func `empty credit responses stay unavailable`(body: String, engine: ProviderPluginEngineKind) async {
        await Self.expectFailure(.parseFailure) {
            _ = try await Self.fetch(body, engine: engine)
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `requests use the website session cookie and deadline`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try BundledPluginTestSupport.runtime(
            "raycast",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                #expect(
                    request.url?.absoluteString
                        == "https://www.raycast.com/frontend_api/current_user/ai_credits")
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "Cookie") == Self.fixtureCookie)
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
                #expect(request.timeoutInterval == 15)
                return try Self.response(request, body: Self.credits)
            })
        _ = try await runtime.fetchUsage(cookieResolver: Self.cookieResolver)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `empty browser import is a missing credential not a script crash`(
        engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try BundledPluginTestSupport.runtime(
            "raycast",
            engine: engine,
            transport: ProviderHTTPTransportHandler { _ in
                Issue.record("Must not fetch without a session cookie")
                throw ProviderPluginError.secretAccess("unreachable")
            })
        do {
            _ = try await runtime.fetchUsage(cookieResolver: { _, _ in
                throw ProviderPluginError.secretAccess("no browser session cookies were found")
            })
            Issue.record("Expected missing credential")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .missingCredential)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `missing session cookie stays unavailable`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try BundledPluginTestSupport.runtime(
            "raycast",
            engine: engine,
            transport: ProviderHTTPTransportHandler { _ in
                Issue.record("Must not fetch without __raycast_session")
                throw ProviderPluginError.secretAccess("unreachable")
            })
        do {
            _ = try await runtime.fetchUsage(cookieResolver: { _, _ in "csrf_token=only" })
            Issue.record("Expected missing session cookie")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .missingCredential)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `descriptor uses website cookies instead of a public API key`() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .raycast)
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(descriptor.fetchPlan.sourceModes == Set([.auto, .web]))
        #expect(descriptor.cli.name == "raycast")
        #if os(macOS)
        #expect(descriptor.metadata.browserCookieOrder == [.brave, .chrome])
        #endif
    }

    @Test(arguments: [
        (401, ProviderFetchClassifiedError.Kind.authenticationExpired),
        (403, .permissionDenied),
        (429, .rateLimited),
        (503, .providerUnavailable),
    ], BundledPluginTestSupport.engines)
    func `credit failures retain actionable classification`(
        failure: (Int, ProviderFetchClassifiedError.Kind),
        engine: ProviderPluginEngineKind) async
    {
        await Self.expectFailure(failure.1) {
            _ = try await Self.fetch("{}", engine: engine, status: failure.0)
        }
    }

    static func fetch(
        _ body: String,
        engine: ProviderPluginEngineKind,
        status: Int = 200) async throws -> UsageSnapshot
    {
        let runtime = try BundledPluginTestSupport.runtime(
            "raycast",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                try Self.response(request, body: body, status: status)
            })
        return try await runtime.fetchUsage(cookieResolver: Self.cookieResolver)
    }

    private static let fixtureCookie = "__raycast_session=fixture-session; csrf_token=fixture-csrf"

    private static let cookieResolver: ProviderPluginRuntime.CookieResolver = { provider, domain in
        #expect(provider == .raycast)
        #expect(domain == "raycast.com" || domain == "www.raycast.com")
        return Self.fixtureCookie
    }

    private static func expectFailure(
        _ kind: ProviderFetchClassifiedError.Kind,
        perform: () async throws -> Void) async
    {
        do {
            try await perform()
            Issue.record("Expected classified failure \(kind)")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == kind)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func date(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func response(
        _ request: URLRequest,
        body: String,
        status: Int = 200) throws -> (Data, URLResponse)
    {
        let response = try #require(HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]))
        return (Data(body.utf8), response)
    }
}
