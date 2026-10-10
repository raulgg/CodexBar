import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexWeeklyResetLiveLanePublicationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: CurrentUsageView.allCases)
    func `an expired cached weekly lane publishes the current usage view without confirmation`(
        view: CurrentUsageView) async throws
    {
        let expiredReset = self.now.addingTimeInterval(-17 * 24 * 60 * 60)
        let previous = self.snapshot(at: self.now, weeklyUsed: 20, weeklyReset: expiredReset, monthlyUsed: 25)
        let current = self.currentUsageSnapshot(view, at: self.now.addingTimeInterval(10))
        let calls = FetchCounter()
        let admission = await self.admit(previous: previous, initial: current, calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.isEmpty)
        self.expectCurrentUsage(view, in: published)
    }

    @Test(arguments: CurrentUsageView.viewsThatCanCarryAnExpiredWeekly)
    func `an exact read keeps the current usage view and drops an expired weekly lane`(
        view: CurrentUsageView) async throws
    {
        let expiredReset = self.now.addingTimeInterval(-17 * 24 * 60 * 60)
        let previous = self.snapshot(at: self.now, weeklyUsed: 20, weeklyReset: expiredReset)
        let current = self.currentUsageSnapshot(
            view,
            at: self.now.addingTimeInterval(10),
            expiredWeeklyReset: expiredReset)
        let calls = FetchCounter()
        let admission = await self.admit(previous: previous, initial: current, calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.isEmpty)
        self.expectCurrentUsage(view, in: published)
        #expect(CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: published) == nil)
    }

    @Test(arguments: [30.0, 90.0])
    func `a weekly reset inside the display tolerance still withholds a missing lane`(
        secondsPastReset: TimeInterval) async
    {
        let observedAt = self.now.addingTimeInterval(30)
        let previous = self.snapshot(
            at: self.now.addingTimeInterval(-120),
            weeklyUsed: 20,
            weeklyReset: observedAt.addingTimeInterval(-secondsPastReset))
        let current = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 40)
        let calls = FetchCounter()
        let admission = await self.admit(previous: previous, initial: current, calls: calls)

        #expect(calls.isEmpty)
        #expect(admission.outcome == nil)
    }

    @Test
    func `two exact reads that omit a live weekly lane publish the confirmation`() async throws {
        let previous = self.snapshot(at: self.now, weeklyUsed: 40)
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 30)
        let confirmation = self.snapshot(at: self.now.addingTimeInterval(20), monthlyUsed: 31)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: confirmation,
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.count == 1)
        #expect(published.secondary == nil)
        #expect(published.primary?.usedPercent == 31)
    }

    @Test
    func `a confirmation that restores a live weekly lane publishes that lane`() async throws {
        let previous = self.snapshot(at: self.now, weeklyUsed: 40)
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 30)
        let confirmation = self.snapshot(at: self.now.addingTimeInterval(20), weeklyUsed: 30, monthlyUsed: 31)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: confirmation,
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.count == 1)
        #expect(published.secondary?.usedPercent == 30)
    }

    @Test
    func `a confirmation that restores a collapsed weekly lane withholds the snapshot`() async {
        let previous = self.snapshot(at: self.now, weeklyUsed: 40)
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 30)
        let confirmation = self.snapshot(at: self.now.addingTimeInterval(20), weeklyUsed: 0.4, monthlyUsed: 31)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: confirmation,
            calls: calls)

        #expect(calls.count == 1)
        #expect(admission.outcome == nil)
    }

    @Test
    func `a failed or non-exact confirmation keeps the current bars`() async {
        let previous = self.snapshot(at: self.now, weeklyUsed: 40)
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 30)
        let failed = FetchCounter()
        let failedAdmission = await self.admit(
            previous: previous,
            initial: initial,
            calls: failed,
            confirmationFailure: true)
        #expect(failed.count == 1)
        #expect(failedAdmission.outcome == nil)

        let cliConfirmation = self.snapshot(
            at: self.now.addingTimeInterval(20),
            monthlyUsed: 31,
            confidence: .unknown)
        let cli = FetchCounter()
        let cliAdmission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: cliConfirmation,
            confirmationKind: .cli,
            confirmationLabel: "cli",
            calls: cli)
        #expect(cli.count == 1)
        #expect(cliAdmission.outcome == nil)
    }

    @Test
    func `a non-exact read that omits a live weekly lane publishes and carries it`() async throws {
        let previous = self.snapshot(at: self.now, weeklyUsed: 40)
        let initial = self.snapshot(
            at: self.now.addingTimeInterval(10),
            monthlyUsed: 30,
            confidence: .unknown)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            initialKind: .cli,
            initialLabel: "test-codex",
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.isEmpty)
        #expect(published.updatedAt == initial.updatedAt)
        #expect(published.primary?.usedPercent == 30)
        #expect(CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: published) == previous.secondary)
    }

    @Test
    func `a non-exact read that omits a live session lane publishes and carries it`() async throws {
        let previous = self.snapshot(at: self.now, sessionUsed: 25, weeklyUsed: 40)
        let initial = self.snapshot(
            at: self.now.addingTimeInterval(10),
            weeklyUsed: 41,
            confidence: .unknown)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            initialKind: .cli,
            initialLabel: "test-codex",
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.isEmpty)
        #expect(CodexConsumerProjection.sourceRateWindow(for: .session, snapshot: published) == previous.primary)
        #expect(CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: published)?.usedPercent == 41)
    }

    @Test
    func `a non-exact read that reports only monthly carries both session and weekly`() async throws {
        let previous = self.snapshot(at: self.now, sessionUsed: 25, weeklyUsed: 40)
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 30, confidence: .unknown)
        let published = try await self.publishedNonExact(previous: previous, initial: initial)

        #expect(published.updatedAt == initial.updatedAt)
        #expect(published.primary == previous.primary)
        #expect(published.secondary == previous.secondary)
        #expect(published.tertiary == initial.primary)
        #expect(published.extraRateWindows == nil)
    }

    @Test
    func `a non-exact read that reports session and monthly carries the omitted weekly lane`() async throws {
        let previous = self.snapshot(at: self.now, sessionUsed: 25, weeklyUsed: 40)
        let initial = self.snapshot(
            at: self.now.addingTimeInterval(10),
            sessionUsed: 26,
            monthlyUsed: 30,
            confidence: .unknown)
        let published = try await self.publishedNonExact(previous: previous, initial: initial)

        #expect(published.primary == initial.primary)
        #expect(published.secondary == previous.secondary)
        #expect(published.tertiary == initial.secondary)
    }

    @Test
    func `a non-exact read that reports weekly and monthly carries the omitted session lane`() async throws {
        let previous = self.snapshot(at: self.now, sessionUsed: 25, weeklyUsed: 40)
        let initial = self.snapshot(
            at: self.now.addingTimeInterval(10),
            weeklyUsed: 41,
            monthlyUsed: 30,
            confidence: .unknown)
        let published = try await self.publishedNonExact(previous: previous, initial: initial)

        #expect(published.primary == previous.primary)
        #expect(published.secondary == initial.secondary)
        #expect(published.tertiary == initial.primary)
    }

    @Test
    func `a non-exact monthly-only read drops a weekly lane past the display tolerance`() async throws {
        let observedAt = self.now.addingTimeInterval(30)
        let previous = self.snapshot(
            at: self.now.addingTimeInterval(-20 * 60),
            sessionUsed: 25,
            weeklyUsed: 57,
            weeklyReset: observedAt.addingTimeInterval(-10 * 60))
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 30, confidence: .unknown)
        let published = try await self.publishedNonExact(previous: previous, initial: initial)

        #expect(CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: published) == nil)
        #expect(published.primary == previous.primary)
        #expect(published.secondary == initial.primary)
        #expect(published.tertiary == nil)
    }

    @Test
    func `an exact monthly-only read does not carry session or weekly`() async throws {
        let previous = self.snapshot(at: self.now, sessionUsed: 25, weeklyUsed: 40)
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 30)
        let confirmation = self.snapshot(at: self.now.addingTimeInterval(20), monthlyUsed: 31)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: confirmation,
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.count == 1)
        #expect(published.primary == confirmation.primary)
        #expect(published.secondary == nil)
        #expect(published.tertiary == nil)
    }

    @Test
    func `a non-exact monthly-only read on a changed plan carries nothing`() async throws {
        let previous = self.snapshot(at: self.now, sessionUsed: 25, weeklyUsed: 40, plan: "free")
        let initial = self.snapshot(
            at: self.now.addingTimeInterval(10),
            monthlyUsed: 30,
            plan: "plus",
            confidence: .unknown)
        let published = try await self.publishedNonExact(previous: previous, initial: initial)

        #expect(published.primary == initial.primary)
        #expect(published.secondary == nil)
        #expect(published.tertiary == nil)
    }

    @Test(arguments: [(30.0, true), (10.0 * 60, false)])
    func `a non-exact read carries an omitted weekly lane only inside the display tolerance`(
        secondsPastReset: TimeInterval,
        carried: Bool) async throws
    {
        let observedAt = self.now.addingTimeInterval(30)
        let previous = self.snapshot(
            at: self.now.addingTimeInterval(-20 * 60),
            weeklyUsed: 57,
            weeklyReset: observedAt.addingTimeInterval(-secondsPastReset))
        let initial = self.snapshot(
            at: self.now.addingTimeInterval(10),
            sessionUsed: 31,
            confidence: .unknown)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            initialKind: .cli,
            initialLabel: "test-codex",
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.isEmpty)
        #expect(CodexConsumerProjection.sourceRateWindow(for: .session, snapshot: published)?.usedPercent == 31)
        #expect(
            CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: published)?.usedPercent
                == (carried ? 57 : nil))
    }

    @Test
    func `a stored weekly lane classified by its slot is dropped once past the display tolerance`() async throws {
        let expired = RateWindow(
            usedPercent: 20,
            windowMinutes: nil,
            resetsAt: self.now.addingTimeInterval(-10 * 60),
            resetDescription: nil)
        let previous = self.snapshot(at: self.now.addingTimeInterval(-20 * 60), sessionUsed: 25)
        let current = self.snapshot(at: self.now.addingTimeInterval(10), sessionUsed: 12)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous.with(primary: previous.primary, secondary: expired),
            initial: current.with(primary: current.primary, secondary: expired),
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.isEmpty)
        #expect(published.primary?.usedPercent == 12)
        #expect(published.secondary == nil)
    }

    @Test
    func `a newer exact plan publishes even when the confirmation weekly lane is near zero`() async throws {
        let previous = self.snapshot(at: self.now, weeklyUsed: 40, plan: "free")
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 30, plan: "free")
        let confirmation = self.snapshot(
            at: self.now.addingTimeInterval(20),
            weeklyUsed: 0,
            plan: "plus")
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: confirmation,
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.count == 1)
        #expect(published.loginMethod(for: .codex) == "plus")
        #expect(published.secondary?.usedPercent == 0)
    }

    @Test(arguments: [LaneKind.session, LaneKind.spark])
    func `session and spark lanes follow the same omission outcomes`(lane: LaneKind) async throws {
        let previous = self.laneSnapshot(lane, at: self.now, used: 40)
        let initial = self.laneSnapshot(lane, at: self.now.addingTimeInterval(10), used: nil)
        let agreed = self.laneSnapshot(lane, at: self.now.addingTimeInterval(20), used: nil)
        let restored = self.laneSnapshot(lane, at: self.now.addingTimeInterval(20), used: 30)
        let collapsed = self.laneSnapshot(lane, at: self.now.addingTimeInterval(20), used: 0.4)

        let agreedCalls = FetchCounter()
        let agreedAdmission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: agreed,
            calls: agreedCalls)
        let agreedUsage = try #require(agreedAdmission.outcome).result.get().usage
        #expect(agreedCalls.count == 1)
        #expect(self.laneUsed(lane, in: agreedUsage) == nil)

        let restoredCalls = FetchCounter()
        let restoredAdmission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: restored,
            calls: restoredCalls)
        let restoredUsage = try #require(restoredAdmission.outcome).result.get().usage
        #expect(restoredCalls.count == 1)
        #expect(self.laneUsed(lane, in: restoredUsage) == 30)

        let collapsedCalls = FetchCounter()
        let collapsedAdmission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: collapsed,
            calls: collapsedCalls)
        #expect(collapsedCalls.count == 1)
        #expect(collapsedAdmission.outcome == nil)
    }

    @Test
    func `a weekly reset inside the display tolerance withholds an agreed live session omission`() async {
        let observedAt = self.now.addingTimeInterval(30)
        let previous = self.snapshot(
            at: self.now.addingTimeInterval(-120),
            sessionUsed: 25,
            weeklyUsed: 20,
            weeklyReset: observedAt.addingTimeInterval(-30))
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 40)
        let confirmation = self.snapshot(at: self.now.addingTimeInterval(20), monthlyUsed: 41)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: confirmation,
            calls: calls)

        #expect(calls.isEmpty)
        #expect(admission.outcome == nil)
        #expect(admission.withheldSuccess != nil)
    }

    @Test(arguments: [LaneKind.session, LaneKind.spark])
    func `a confirmation that omits a different live lane keeps the current bars`(lane: LaneKind) async {
        let previous = self.snapshot(
            at: self.now,
            sessionUsed: 25,
            weeklyUsed: 40,
            extras: [self.sparkWindow(usedPercent: 40, at: self.now)])
        let initial = self.snapshot(
            at: self.now.addingTimeInterval(10),
            sessionUsed: 26,
            extras: [self.sparkWindow(usedPercent: 41, at: self.now.addingTimeInterval(10))])
        let confirmation = switch lane {
        case .session:
            self.snapshot(
                at: self.now.addingTimeInterval(20),
                weeklyUsed: 40,
                extras: [self.sparkWindow(usedPercent: 42, at: self.now.addingTimeInterval(20))])
        case .spark:
            self.snapshot(
                at: self.now.addingTimeInterval(20),
                sessionUsed: 27,
                weeklyUsed: 40)
        }
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: confirmation,
            calls: calls)

        #expect(calls.count == 1)
        #expect(admission.outcome == nil)
    }

    @Test
    func `a non-exact read publishes session and weekly while a cached spark lane stays live`() async throws {
        let previous = self.snapshot(
            at: self.now,
            sessionUsed: 25,
            weeklyUsed: 55,
            extras: [self.sparkWindow(usedPercent: 40, at: self.now)])
        let initial = self.snapshot(
            at: self.now.addingTimeInterval(10),
            sessionUsed: 30,
            weeklyUsed: 56,
            confidence: .unknown)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            initialKind: .cli,
            initialLabel: "codex-cli",
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.isEmpty)
        #expect(CodexConsumerProjection.sourceRateWindow(for: .session, snapshot: published)?.usedPercent == 30)
        #expect(CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: published)?.usedPercent == 56)
        #expect(self.laneUsed(.spark, in: published) == 40)
    }

    @Test
    func `a confirmation that restores one of two omitted live lanes publishes`() async throws {
        let previous = self.snapshot(at: self.now, sessionUsed: 25, weeklyUsed: 40)
        let initial = self.snapshot(at: self.now.addingTimeInterval(10), monthlyUsed: 30)
        let confirmation = self.snapshot(at: self.now.addingTimeInterval(20), sessionUsed: 30)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: confirmation,
            calls: calls)

        let published = try #require(admission.outcome).result.get().usage
        #expect(calls.count == 1)
        #expect(CodexConsumerProjection.sourceRateWindow(for: .session, snapshot: published)?.usedPercent == 30)
        #expect(CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: published) == nil)
    }

    @Test
    func `a weekly reset confirmation that drops a live session lane keeps the current bars`() async {
        let previous = self.snapshot(at: self.now, sessionUsed: 25, weeklyUsed: 40)
        let initial = self.snapshot(
            at: self.now.addingTimeInterval(10),
            sessionUsed: 26,
            weeklyUsed: 0.4)
        let confirmation = self.snapshot(at: self.now.addingTimeInterval(20), weeklyUsed: 30)
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            confirmation: confirmation,
            calls: calls)

        #expect(calls.count == 1)
        #expect(admission.outcome == nil)
    }

    enum CurrentUsageView: CaseIterable, Sendable {
        case monthly
        case session
        case sessionAndSpark
        case renewedWeekly

        static let viewsThatCanCarryAnExpiredWeekly: [CurrentUsageView] = [
            .monthly, .session, .sessionAndSpark,
        ]
    }

    enum LaneKind: String, Sendable {
        case session
        case spark
    }

    private var renewedWeeklyReset: Date {
        self.now.addingTimeInterval(5 * 24 * 60 * 60)
    }

    private func currentUsageSnapshot(
        _ view: CurrentUsageView,
        at updatedAt: Date,
        expiredWeeklyReset: Date? = nil) -> UsageSnapshot
    {
        let carriedWeekly = expiredWeeklyReset != nil
        let weeklyUsed: Double? = if carriedWeekly {
            18
        } else if view == .renewedWeekly {
            15
        } else {
            nil
        }
        let weeklyReset = expiredWeeklyReset ?? (view == .renewedWeekly ? self.renewedWeeklyReset : nil)
        switch view {
        case .monthly:
            return self.snapshot(
                at: updatedAt,
                weeklyUsed: weeklyUsed,
                weeklyReset: weeklyReset,
                monthlyUsed: 40)
        case .session:
            return self.snapshot(
                at: updatedAt,
                sessionUsed: 12,
                weeklyUsed: weeklyUsed,
                weeklyReset: weeklyReset)
        case .sessionAndSpark:
            return self.snapshot(
                at: updatedAt,
                sessionUsed: 12,
                weeklyUsed: weeklyUsed,
                weeklyReset: weeklyReset,
                extras: [self.sparkWindow(usedPercent: 7, at: updatedAt)])
        case .renewedWeekly:
            return self.snapshot(
                at: updatedAt,
                weeklyUsed: weeklyUsed,
                weeklyReset: weeklyReset)
        }
    }

    private func expectCurrentUsage(_ view: CurrentUsageView, in snapshot: UsageSnapshot) {
        let session = CodexConsumerProjection.sourceRateWindow(for: .session, snapshot: snapshot)
        let weekly = CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: snapshot)
        let spark = snapshot.extraRateWindows?
            .first { $0.id == CodexAdditionalRateLimitMapper.sparkWindowID }?
            .window
        switch view {
        case .monthly:
            #expect(snapshot.primary?.windowMinutes == CodexConsumerProjection.monthlyWindowMinutes)
            #expect(snapshot.primary?.usedPercent == 40)
            #expect(session == nil)
            #expect(weekly == nil)
            #expect(spark == nil)
        case .session:
            #expect(session?.usedPercent == 12)
            #expect(weekly == nil)
            #expect(spark == nil)
        case .sessionAndSpark:
            #expect(session?.usedPercent == 12)
            #expect(weekly == nil)
            #expect(spark?.usedPercent == 7)
        case .renewedWeekly:
            #expect(session == nil)
            #expect(weekly?.usedPercent == 15)
            #expect(weekly?.resetsAt == self.renewedWeeklyReset)
            #expect(spark == nil)
        }
    }

    private func sparkWindow(usedPercent: Double, at updatedAt: Date) -> NamedRateWindow {
        NamedRateWindow(
            id: CodexAdditionalRateLimitMapper.sparkWindowID,
            title: "Codex Spark 5-hour",
            window: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: updatedAt.addingTimeInterval(2 * 60 * 60),
                resetDescription: nil))
    }

    private func laneSnapshot(_ lane: LaneKind, at updatedAt: Date, used: Double?) -> UsageSnapshot {
        switch lane {
        case .session:
            self.snapshot(at: updatedAt, sessionUsed: used, weeklyUsed: 55)
        case .spark:
            self.snapshot(
                at: updatedAt,
                sessionUsed: 25,
                weeklyUsed: 55,
                extras: used.map { usedPercent in
                    [NamedRateWindow(
                        id: CodexAdditionalRateLimitMapper.sparkWindowID,
                        title: "Codex Spark 5-hour",
                        window: RateWindow(
                            usedPercent: usedPercent,
                            windowMinutes: 300,
                            resetsAt: updatedAt.addingTimeInterval(2 * 60 * 60),
                            resetDescription: nil))]
                })
        }
    }

    private func laneUsed(_ lane: LaneKind, in snapshot: UsageSnapshot) -> Double? {
        switch lane {
        case .session:
            CodexConsumerProjection.sourceRateWindow(for: .session, snapshot: snapshot)?.usedPercent
        case .spark:
            snapshot.extraRateWindows?.first { $0.id == CodexAdditionalRateLimitMapper.sparkWindowID }?
                .window.usedPercent
        }
    }

    private func admit(
        previous: UsageSnapshot,
        initial: UsageSnapshot,
        confirmation: UsageSnapshot? = nil,
        initialKind: ProviderFetchKind = .oauth,
        initialLabel: String = "oauth",
        confirmationKind: ProviderFetchKind = .oauth,
        confirmationLabel: String = "oauth",
        calls: FetchCounter,
        confirmationFailure: Bool = false) async -> UsageStore.CodexWeeklyResetPublicationAdmission
    {
        await UsageStore.codexOutcomeAdmittedForPublication(
            initialOutcome: self.outcome(initial, kind: initialKind, label: initialLabel),
            previousSnapshot: previous,
            previousSourceLabel: "oauth",
            missingWindowBackfillSnapshot: previous,
            observedAt: self.now.addingTimeInterval(30),
            fetchConfirmation: {
                calls.increment()
                if confirmationFailure {
                    return ProviderFetchOutcome(
                        result: .failure(TestRefreshError(message: "confirmation failed")),
                        attempts: [])
                }
                return self.outcome(
                    confirmation ?? initial,
                    kind: confirmationKind,
                    label: confirmationLabel)
            })
    }

    private func publishedNonExact(previous: UsageSnapshot, initial: UsageSnapshot) async throws -> UsageSnapshot {
        let calls = FetchCounter()
        let admission = await self.admit(
            previous: previous,
            initial: initial,
            initialKind: .cli,
            initialLabel: "test-codex",
            calls: calls)
        #expect(calls.isEmpty)
        return try #require(admission.outcome).result.get().usage
    }

    private func outcome(
        _ snapshot: UsageSnapshot,
        kind: ProviderFetchKind,
        label: String) -> ProviderFetchOutcome
    {
        ProviderFetchOutcome(
            result: .success(ProviderFetchResult(
                usage: snapshot,
                credits: nil,
                dashboard: nil,
                sourceLabel: label,
                strategyID: "live-lane-test",
                strategyKind: kind)),
            attempts: [])
    }

    private func snapshot(
        at updatedAt: Date,
        sessionUsed: Double? = nil,
        weeklyUsed: Double? = nil,
        weeklyReset: Date? = nil,
        monthlyUsed: Double? = nil,
        extras: [NamedRateWindow]? = nil,
        plan: String = "free",
        confidence: UsageDataConfidence = .exact) -> UsageSnapshot
    {
        let session = sessionUsed.map {
            RateWindow(
                usedPercent: $0,
                windowMinutes: CodexConsumerProjection.sessionWindowMinutes,
                resetsAt: updatedAt.addingTimeInterval(4 * 60 * 60),
                resetDescription: nil)
        }
        let weekly = weeklyUsed.map {
            RateWindow(
                usedPercent: $0,
                windowMinutes: CodexConsumerProjection.weeklyWindowMinutes,
                resetsAt: weeklyReset ?? updatedAt.addingTimeInterval(3 * 24 * 60 * 60),
                resetDescription: nil)
        }
        let monthly = monthlyUsed.map {
            RateWindow(
                usedPercent: $0,
                windowMinutes: CodexConsumerProjection.monthlyWindowMinutes,
                resetsAt: updatedAt.addingTimeInterval(20 * 24 * 60 * 60),
                resetDescription: nil)
        }
        let primary = session ?? monthly
        let secondary = session == nil ? weekly : (weekly ?? monthly)
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            extraRateWindows: extras,
            updatedAt: updatedAt,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "free@example.com",
                accountOrganization: nil,
                loginMethod: plan),
            dataConfidence: confidence)
    }
}

private final class FetchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        self.lock.lock()
        self.value += 1
        self.lock.unlock()
    }

    var count: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
    }

    var isEmpty: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value == 0
    }
}
