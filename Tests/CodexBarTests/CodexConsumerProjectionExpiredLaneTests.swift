import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension CodexConsumerProjectionTests {
    @Test
    func `a weekly reset past the display tolerance is hidden and a fresh reset stays`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expired = Self.projection(
            now: now,
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 43200,
                resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 20,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(-17 * 24 * 60 * 60),
                resetDescription: nil))
        #expect(expired.visibleRateLanes == [.monthly])
        #expect(expired.rateWindow(for: .weekly) == nil)
        #expect(expired.rateWindow(for: .monthly)?.usedPercent == 25)

        let recent = Self.projection(
            now: now,
            primary: nil,
            secondary: RateWindow(
                usedPercent: 20,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(-30),
                resetDescription: nil))
        #expect(recent.visibleRateLanes == [.weekly])
        #expect(recent.rateWindow(for: .weekly)?.usedPercent == 20)
    }

    fileprivate static func projection(
        now: Date,
        primary: RateWindow?,
        secondary: RateWindow?) -> CodexConsumerProjection
    {
        CodexConsumerProjection.make(
            surface: .liveCard,
            context: CodexConsumerProjection.Context(
                snapshot: UsageSnapshot(primary: primary, secondary: secondary, updatedAt: now),
                rawUsageError: nil,
                liveCredits: nil,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: now))
    }
}
