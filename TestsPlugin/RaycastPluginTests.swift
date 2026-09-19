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
    func `requests use the declared origin token and deadline`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try BundledPluginTestSupport.runtime(
            "raycast",
            engine: engine,
            transport: ProviderHTTPTransportHandler { request in
                #expect(request.url?.absoluteString == "https://backend.raycast.com/api/v1/ai/credits")
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
                #expect(request.timeoutInterval == 15)
                return try Self.response(request, body: Self.credits)
            })
        _ = try await runtime.fetchUsage(secrets: ["RAYCAST_ACCESS_TOKEN": "fixture-token"])
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
        return try await runtime.fetchUsage(secrets: ["RAYCAST_ACCESS_TOKEN": "fixture-token"])
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
