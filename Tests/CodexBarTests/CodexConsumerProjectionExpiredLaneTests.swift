import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension CodexConsumerProjectionTests {
    @Test
    func `an expired weekly lane is hidden while the current usage lanes stay`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiredWeekly = now.addingTimeInterval(-17 * 24 * 60 * 60)
        let monthly = Self.projection(
            now: now,
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 43200,
                resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 20,
                windowMinutes: 10080,
                resetsAt: expiredWeekly,
                resetDescription: nil))
        #expect(monthly.visibleRateLanes == [.monthly])
        #expect(monthly.rateWindow(for: .weekly) == nil)
        #expect(monthly.rateWindow(for: .monthly)?.usedPercent == 25)

        let session = Self.projection(
            now: now,
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(4 * 60 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 20,
                windowMinutes: 10080,
                resetsAt: expiredWeekly,
                resetDescription: nil))
        #expect(session.visibleRateLanes == [.session])
        #expect(session.rateWindow(for: .weekly) == nil)
        #expect(session.rateWindow(for: .session)?.usedPercent == 12)

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
