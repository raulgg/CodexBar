import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

/// Plugin-engine coverage for the bundled Raycast credits script.
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
    func `monthly credits become one meter with the remaining balance`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(Self.credits, engine: engine)
        #expect(snapshot.primary?.usedPercent == 75)
        #expect(snapshot.primary?.windowMinutes == nil)
        #expect(snapshot.primary?.resetsAt == Self.date("2026-10-18T00:00:00.000Z"))
        #expect(snapshot.primary?.resetDescription == "125 / 500 credits left")
        #expect(snapshot.subscriptionRenewsAt == nil)
        #expect(snapshot.identity?.providerID == .raycast)
        #expect(snapshot.identity?.loginMethod == "Pro")
        #expect(snapshot.details.isEmpty)
        #expect(snapshot.providerCost == nil)
        #expect(snapshot.dataConfidence == .exact)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `website account payload maps left and total`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(#"""
        {
          "remaining_balance_credits": "337.3751",
          "total_balance_credits": "500.0",
          "next_credits_at": "2026-10-18T08:34:44Z",
          "funding_subscription": {"tier": "pro", "status": "active"}
        }
        """#, engine: engine)
        #expect(abs((snapshot.primary?.usedPercent ?? 0) - 32.525) < 0.01)
        #expect(snapshot.primary?.resetDescription == "337.38 / 500 credits left")
        #expect(snapshot.details.isEmpty)
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
        #expect(snapshot.primary?.resetDescription == "12.5 / 50 credits left")
        #expect(snapshot.details.isEmpty)
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
        #expect(snapshot.primary?.resetDescription == "750 / 500 credits left")
        #expect(snapshot.details.isEmpty)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `zero allowance does not invent a quota window`(engine: ProviderPluginEngineKind) async throws {
        let snapshot = try await Self.fetch(
            #"""
            {"remaining_balance_credits":"0","total_balance_credits":"0",
            "next_credits_at":"2026-10-18T00:00:00.000Z","funding_subscription":{"tier":"max"}}
            """#,
            engine: engine)
        #expect(snapshot.primary == nil)
        #expect(snapshot.subscriptionRenewsAt == Self.date("2026-10-18T00:00:00.000Z"))
        #expect(snapshot.identity?.loginMethod == "Max")
        #expect(snapshot.details[0].rows.map(\.label) == ["Left", "Total"])
        #expect(snapshot.details[0].rows.map(\.value) == ["0", "0"])
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
    func `requests use the website session cookie headers and timeout`(
        engine: ProviderPluginEngineKind) async throws
    {
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
                #expect(request.value(forHTTPHeaderField: "Origin") == "https://www.raycast.com")
                #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.raycast.com/settings")
                #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("Chrome/") == true)
                #expect(request.timeoutInterval == 22)
                return try Self.response(request, body: Self.credits)
            })
        _ = try await runtime.fetchUsage(
            settings: ["webTimeoutSeconds": "22"],
            cookieResolver: Self.cookieResolver)
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
            #expect(error.message ==
                "No Raycast session cookies found. Sign in at www.raycast.com/settings or paste a Cookie header.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `empty session cookie value stays unavailable`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try BundledPluginTestSupport.runtime(
            "raycast",
            engine: engine,
            transport: ProviderHTTPTransportHandler { _ in
                Issue.record("Must not fetch with an empty __raycast_session")
                throw ProviderPluginError.secretAccess("unreachable")
            })
        do {
            _ = try await runtime.fetchUsage(cookieResolver: { _, _ in
                "__raycast_session=; csrf_token=fixture-csrf"
            })
            Issue.record("Expected missing session cookie")
        } catch let error as ProviderFetchClassifiedError {
            #expect(error.kind == .missingCredential)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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

    @Test(arguments: BundledPluginTestSupport.engines)
    func `a jar without the session cookie is rejected and the next session is used`(
        engine: ProviderPluginEngineKind) async throws
    {
        let sessions = SessionQueue([
            "theme=dark; other=1",
            "theme=dark; __raycast_session=fixture-session; csrf_token=fixture-csrf; other=1",
        ])
        let rejected = RejectedIDs()
        let runtime = try BundledPluginTestSupport.runtime(
            "raycast",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                #expect(request.value(forHTTPHeaderField: "Cookie") == Self.fixtureCookie)
                return try Self.response(request, body: Self.credits)
            })
        let snapshot = try await runtime.fetchUsage(
            cookieSessionResolver: { domain, _ in
                #expect(domain == "www.raycast.com")
                return await sessions.next()
            },
            cookieSessionInvalidator: { domain, id in
                #expect(domain == "www.raycast.com")
                rejected.append(id)
            })
        #expect(snapshot.identity?.loginMethod == "Pro")
        #expect(rejected.values.count == 1)
        #expect(await sessions.remaining == 0)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `an expired session is rejected before the next browser session`(
        engine: ProviderPluginEngineKind) async throws
    {
        let sessions = SessionQueue([
            "__raycast_session=expired",
            "__raycast_session=fixture-session",
        ])
        let runtime = try BundledPluginTestSupport.runtime(
            "raycast",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
                await sessions.record(cookie)
                if cookie.contains("expired") {
                    return try Self.response(request, body: "{}", status: 401)
                }
                return try Self.response(request, body: Self.credits)
            })
        let snapshot = try await runtime.fetchUsage(
            cookieSessionResolver: { _, _ in await sessions.next() },
            cookieSessionInvalidator: { _, _ in })
        #expect(await sessions.attempts == ["__raycast_session=expired", "__raycast_session=fixture-session"])
        #expect(snapshot.primary?.resetDescription == "125 / 500 credits left")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `permission denied does not try another session`(engine: ProviderPluginEngineKind) async throws {
        let sessions = SessionQueue([
            "__raycast_session=fixture-blocked",
            "__raycast_session=later",
        ])
        let runtime = try BundledPluginTestSupport.runtime(
            "raycast",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                try Self.response(request, body: "{}", status: 403)
            })
        await Self.expectFailure(.permissionDenied) {
            _ = try await runtime.fetchUsage(
                cookieSessionResolver: { _, _ in await sessions.next() },
                cookieSessionInvalidator: { _, _ in Issue.record("403 must keep the current session") })
        }
        #expect(await sessions.remaining == 1)
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
        #expect(domain == "www.raycast.com")
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

    private actor SessionQueue {
        private var headers: [String]
        private(set) var attempts: [String] = []

        init(_ headers: [String]) { self.headers = headers }

        var remaining: Int {
            self.headers.count
        }

        func next() -> ProviderPluginCookieSession? {
            guard !self.headers.isEmpty else { return nil }
            return .init(
                header: self.headers.removeFirst(),
                source: "fixture",
                origin: "https://www.raycast.com")
        }

        func record(_ cookie: String) { self.attempts.append(cookie) }
    }

    private final class RejectedIDs: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ id: String) {
            self.lock.withLock { self.storage.append(id) }
        }

        var values: [String] {
            self.lock.withLock { self.storage }
        }
    }
}
