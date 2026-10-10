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

    @Test
    func `expired session and weekly lanes fall back to the credits balance in the menu bar`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let primary = RateWindow(
            usedPercent: 12,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(-10 * 60),
            resetDescription: nil)
        let secondary = RateWindow(
            usedPercent: 20,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(-17 * 24 * 60 * 60),
            resetDescription: nil)
        let credits = CreditsSnapshot(remaining: 80, events: [], updatedAt: now)
        let expired = Self.projection(
            surface: .menuBar,
            now: now,
            primary: primary,
            secondary: secondary,
            credits: credits)
        #expect(expired.visibleRateLanes.isEmpty)
        #expect(expired.menuBarFallback == .creditsBalance)

        let live = Self.projection(
            surface: .menuBar,
            now: now,
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(60 * 60),
                resetDescription: nil),
            secondary: secondary,
            credits: credits)
        #expect(live.visibleRateLanes == [.session])
        #expect(live.menuBarFallback == .none)
    }

    @Test
    func `an elapsed session reset stays visible while a live exhausted weekly lane caps it`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let weeklyReset = now.addingTimeInterval(2 * 24 * 60 * 60)
        let projection = Self.projection(
            surface: .menuBar,
            now: now,
            primary: RateWindow(
                usedPercent: 40,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(-10 * 60),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 100,
                windowMinutes: 10080,
                resetsAt: weeklyReset,
                resetDescription: nil))

        #expect(projection.visibleRateLanes == [.session, .weekly])
        let card = try #require(projection.rateWindow(for: .session))
        #expect(card.usedPercent == 100)
        #expect(card.resetsAt == weeklyReset)
        #expect(projection.menuBarSelectableRateWindow(for: .session) == card)
    }

    @Test
    func `the menu bar redraws when a displayed lane passes the display tolerance`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionReset = now.addingTimeInterval(60 * 60)
        let weekly = RateWindow(
            usedPercent: 57,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60),
            resetDescription: nil)
        let live = Self.projection(
            surface: .menuBar,
            now: now,
            primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: sessionReset, resetDescription: nil),
            secondary: weekly)
        #expect(live.nextMenuBarStateChangeAt == sessionReset.addingTimeInterval(2 * 60))

        let resetsNow = Self.projection(
            surface: .menuBar,
            now: now,
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(-30),
                resetDescription: nil),
            secondary: weekly)
        #expect(resetsNow.nextMenuBarStateChangeAt == now.addingTimeInterval(90))

        let expired = Self.projection(
            surface: .menuBar,
            now: now,
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(-10 * 60),
                resetDescription: nil),
            secondary: nil)
        #expect(expired.nextMenuBarStateChangeAt == nil)
    }

    @Test
    func `the default icon drops a weekly lane once its reset is past the display tolerance`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func icon(weeklyResetOffset: TimeInterval) -> (primary: RateWindow?, secondary: RateWindow?) {
            IconRemainingResolver.resolvedWindows(
                snapshot: UsageSnapshot(
                    primary: RateWindow(
                        usedPercent: 12,
                        windowMinutes: 300,
                        resetsAt: now.addingTimeInterval(60 * 60),
                        resetDescription: nil),
                    secondary: RateWindow(
                        usedPercent: 57,
                        windowMinutes: 10080,
                        resetsAt: now.addingTimeInterval(weeklyResetOffset),
                        resetDescription: nil),
                    updatedAt: now),
                style: .codex,
                now: now)
        }

        let expired = icon(weeklyResetOffset: -3 * 60)
        #expect(expired.primary?.usedPercent == 12)
        #expect(expired.secondary == nil)

        let resetsNow = icon(weeklyResetOffset: -30)
        #expect(resetsNow.primary?.usedPercent == 12)
        #expect(resetsNow.secondary?.usedPercent == 57)
    }

    @Test
    func `the default icon shows session and weekly when monthly sits in the tertiary slot`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let icon = IconRemainingResolver.resolvedWindows(
            snapshot: Self.threeLaneSnapshot(now: now, sessionResetOffset: 60 * 60, weeklyResetOffset: 86400),
            style: .codex,
            now: now)

        #expect(icon.primary?.windowMinutes == 300)
        #expect(icon.secondary?.windowMinutes == 10080)
    }

    @Test
    func `a tertiary monthly window stays after session and weekly pass the display tolerance`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = Self.threeLaneSnapshot(now: now, sessionResetOffset: -10 * 60, weeklyResetOffset: -10 * 60)
        let projection = CodexConsumerProjection.make(
            surface: .liveCard,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: nil,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: now))

        #expect(projection.visibleRateLanes == [.monthly])
        #expect(projection.rateWindow(for: .monthly) == snapshot.tertiary)
        #expect(CodexConsumerProjection.displayableRateLanes(snapshot: snapshot, now: now) == [.monthly])

        let icon = IconRemainingResolver.resolvedWindows(snapshot: snapshot, style: .codex, now: now)
        #expect(icon.primary?.windowMinutes == 43200)
        #expect(icon.secondary == nil)
    }

    private static func threeLaneSnapshot(
        now: Date,
        sessionResetOffset: TimeInterval,
        weeklyResetOffset: TimeInterval) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(sessionResetOffset),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: 57,
                windowMinutes: 10080,
                resetsAt: now.addingTimeInterval(weeklyResetOffset),
                resetDescription: nil),
            tertiary: RateWindow(
                usedPercent: 30,
                windowMinutes: 43200,
                resetsAt: now.addingTimeInterval(20 * 86400),
                resetDescription: nil),
            updatedAt: now)
    }

    @Test
    func `the menu card hides a codex spark window once its reset is past the display tolerance`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func titles(sparkResetOffset: TimeInterval) throws -> [String] {
            let snapshot = UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(60 * 60),
                    resetDescription: nil),
                secondary: nil,
                extraRateWindows: [NamedRateWindow(
                    id: CodexAdditionalRateLimitMapper.sparkWindowID,
                    title: "Codex Spark 5-hour",
                    window: RateWindow(
                        usedPercent: 40,
                        windowMinutes: 300,
                        resetsAt: now.addingTimeInterval(sparkResetOffset),
                        resetDescription: nil))],
                updatedAt: now)
            return try UsageMenuCardView.Model.extraRateWindowMetrics(
                snapshot: snapshot,
                input: Self.menuCardInput(snapshot: snapshot, now: now),
                percentStyle: .left).map(\.title)
        }

        #expect(try titles(sparkResetOffset: -3 * 60).isEmpty)
        #expect(try titles(sparkResetOffset: -30) == ["Codex Spark 5-hour"])
        #expect(try titles(sparkResetOffset: 60 * 60) == ["Codex Spark 5-hour"])
    }

    @Test
    func `the weekly quota window is dropped once the codex weekly reset is past the display tolerance`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func weekly(resetOffset: TimeInterval) throws -> RateWindow? {
            let snapshot = UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(60 * 60),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 57,
                    windowMinutes: 10080,
                    resetsAt: now.addingTimeInterval(resetOffset),
                    resetDescription: nil),
                updatedAt: now)
            return try UsageMenuCardView.Model.weeklyQuotaWindow(
                from: Self.menuCardInput(snapshot: snapshot, now: now))
        }

        #expect(try weekly(resetOffset: -3 * 60) == nil)
        #expect(try weekly(resetOffset: -30)?.usedPercent == 57)
    }

    fileprivate static func menuCardInput(snapshot: UsageSnapshot, now: Date) throws -> UsageMenuCardView.Model.Input {
        try UsageMenuCardView.Model.Input(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: "user@example.com", plan: "Pro"),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now)
    }

    fileprivate static func projection(
        surface: CodexConsumerProjection.Surface = .liveCard,
        now: Date,
        primary: RateWindow?,
        secondary: RateWindow?,
        credits: CreditsSnapshot? = nil) -> CodexConsumerProjection
    {
        CodexConsumerProjection.make(
            surface: surface,
            context: CodexConsumerProjection.Context(
                snapshot: UsageSnapshot(primary: primary, secondary: secondary, updatedAt: now),
                rawUsageError: nil,
                liveCredits: credits,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: now))
    }
}
