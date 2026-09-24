import Foundation
import Testing
@testable import CodexBarCore

struct RaycastNativeSupportTests {
    @Test
    func `descriptor uses the shared cookie broker instead of a public API key`() async {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .raycast)
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(descriptor.fetchPlan.sourceModes == Set([.auto, .web]))
        #expect(descriptor.cli.name == "raycast")
        #expect(descriptor.metadata.usesDetailBackedWindow)
        #expect(descriptor.presentation.menuCard.showsPrimaryBalanceDescription)
        #expect(descriptor.presentation.menuCard.hidesPrimaryResetWithoutDate)
        #expect(descriptor.credentials?.tokenAccountSupport == nil)
        #expect(TokenAccountSupportCatalog.support(for: .raycast) == nil)
        #if os(macOS)
        #expect(descriptor.metadata.browserCookieOrder == [.chrome])
        #endif
        let strategies = await descriptor.fetchPlan.pipeline.resolveStrategies(Self.makeContext(cookieSource: .auto))
        #expect(strategies.map(\.id) == ["raycast.js"])
        #expect(strategies.map(\.kind) == [.web])
        let disabled = await descriptor.fetchPlan.pipeline.resolveStrategies(Self.makeContext(cookieSource: .off))
        #expect(await disabled.first?.isAvailable(Self.makeContext(cookieSource: .off)) == false)
    }

    @Test
    func `plugin cookie reads keep an interactive refresh across a detached task`() async throws {
        let seen = try await ProviderInteractionContext.$current.withValue(.userInitiated) {
            try await BrowserCookieAccessGate.withExplicitRetry {
                let access = BrowserCookieAccessGate.captureCookieAccess()
                return await Task.detached {
                    await BrowserCookieAccessGate.withCookieAccess(access) {
                        ProviderInteractionContext.current
                    }
                }.value
            }
        }
        #expect(seen == .userInitiated)
        let dropped = await Task.detached { ProviderInteractionContext.current }.value
        #expect(dropped == .background)
    }

    private static func makeContext(cookieSource: ProviderCookieSource) -> ProviderFetchContext {
        ProviderFetchContext(
            runtime: .app,
            sourceMode: .web,
            includeCredits: false,
            webTimeout: 15,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: .make(raycast: .init(cookieSource: cookieSource, manualCookieHeader: nil)),
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: StubClaudeFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }

    private struct StubClaudeFetcher: ClaudeUsageFetching {
        func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
            throw ClaudeUsageError.parseFailed("stub")
        }

        func debugRawProbe(model _: String) async -> String { "stub" }
        func detectVersion() -> String? { nil }
    }
}
