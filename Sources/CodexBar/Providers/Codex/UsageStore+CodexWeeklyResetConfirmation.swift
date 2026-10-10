import CodexBarCore
import Foundation

extension UsageStore {
    typealias CodexWeeklyConfirmationFetch = @Sendable () async -> ProviderFetchOutcome

    struct CodexWeeklyResetPublicationAdmission {
        let outcome: ProviderFetchOutcome?
        let pendingCandidate: CodexWeeklyResetPublicationCandidate?
        /// Nil publication alone cannot distinguish a withheld success from a failed confirmation.
        var withheldSuccess: ProviderFetchResult?
    }

    struct CodexWeeklyResetPublicationTrace {
        let previousSnapshot: UsageSnapshot?
        let missingWindowBackfillSnapshot: UsageSnapshot?
        let publicationBaseline: UsageSnapshot?
        let initialSnapshot: UsageSnapshot
        let confirmationSnapshot: UsageSnapshot?
    }

    private struct CodexMissingWeeklyAdmissionInput {
        let rawInitialSnapshot: UsageSnapshot
        let previousSnapshot: UsageSnapshot?
        let publicationBaseline: UsageSnapshot?
        let missingWindowBackfillSnapshot: UsageSnapshot?
        let publicationInitialOutcome: ProviderFetchOutcome
        let pendingCandidate: CodexWeeklyResetPublicationCandidate?
        let observedAt: Date
    }

    nonisolated static func codexOutcomeAdmittedForPublication(
        initialOutcome: ProviderFetchOutcome,
        previousSnapshot: UsageSnapshot?,
        previousSourceLabel: String?,
        missingWindowBackfillSnapshot: UsageSnapshot?,
        pendingCandidate: CodexWeeklyResetPublicationCandidate? = nil,
        observedAt: Date = CodexWeeklyResetConfirmation.observationDate,
        fetchConfirmation: @escaping CodexWeeklyConfirmationFetch) async -> CodexWeeklyResetPublicationAdmission
    {
        var candidateForRetry: CodexWeeklyResetPublicationCandidate? = pendingCandidate.flatMap {
            if let reason = CodexWeeklyResetConfirmation.delayedCandidateRejection($0, observedAt: observedAt) {
                Self.logCodexWeeklyResetCandidateDecision(
                    stage: "candidateRetention", decision: "discardCandidate", reason: reason)
                return nil
            }
            return $0
        }
        guard case let .success(rawInitialResult) = initialOutcome.result else {
            return CodexWeeklyResetPublicationAdmission(outcome: initialOutcome, pendingCandidate: candidateForRetry)
        }
        let rawInitialSnapshot = rawInitialResult.usage.scoped(to: .codex)
        let cachedBaseline = [previousSnapshot, missingWindowBackfillSnapshot]
            .compactMap(\.self)
            .max { $0.updatedAt < $1.updatedAt }
        let planBaseline = previousSnapshot ?? missingWindowBackfillSnapshot
        let planChanged = Self.isExactCodexOAuthResult(rawInitialResult)
            && rawInitialSnapshot.updatedAt > (cachedBaseline?.updatedAt ?? .distantFuture)
            && Self.codexPlanChanged(from: planBaseline, to: rawInitialSnapshot)
        // A new subscription has a different quota baseline, not evidence of a reset on the old plan.
        let previousSnapshot = planChanged ? nil : previousSnapshot
        let missingWindowBackfillSnapshot = planChanged ? nil : missingWindowBackfillSnapshot
        let publicationBaseline = planChanged ? nil : cachedBaseline
        if planChanged { candidateForRetry = nil }
        let publicationInitialOutcome = initialOutcome.backfillingCodexResetWindows(from: missingWindowBackfillSnapshot)
        let laneContext = CodexLiveLaneAdmissionContext(
            rawInitialResult: rawInitialResult,
            rawInitialSnapshot: rawInitialSnapshot,
            previousSnapshot: previousSnapshot,
            publicationBaseline: publicationBaseline,
            missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
            publicationInitialOutcome: publicationInitialOutcome,
            previousSourceLabel: previousSourceLabel,
            candidateForRetry: candidateForRetry,
            observedAt: observedAt)
        if let admission = await self.codexOmittedLiveLaneAdmission(
            laneContext,
            fetchConfirmation: fetchConfirmation)
        {
            return admission
        }

        if CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: rawInitialSnapshot) == nil {
            return Self.codexMissingWeeklyAdmission(input: CodexMissingWeeklyAdmissionInput(
                rawInitialSnapshot: rawInitialSnapshot,
                previousSnapshot: previousSnapshot,
                publicationBaseline: publicationBaseline,
                missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
                publicationInitialOutcome: publicationInitialOutcome,
                pendingCandidate: candidateForRetry,
                observedAt: observedAt))
        }

        let initialDecision = CodexWeeklyResetConfirmation.initialDecision(
            previous: publicationBaseline,
            initial: rawInitialSnapshot)
        Self.logCodexWeeklyResetInitialDecision(
            initialDecision,
            previousSnapshot: previousSnapshot,
            missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
            publicationBaseline: publicationBaseline,
            initialSnapshot: rawInitialSnapshot)
        switch initialDecision {
        case .publishInitial:
            return self.codexAdmittedOutcome(
                publicationInitialOutcome,
                baseline: publicationBaseline,
                now: observedAt)
        case .preservePrevious:
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: Self.codexCandidateAfterPreservedInitial(
                    candidateForRetry,
                    previousSnapshot: previousSnapshot,
                    initialSnapshot: rawInitialSnapshot,
                    initialResult: rawInitialResult,
                    observedAt: observedAt),
                withheldSuccess: rawInitialResult)
        case .requiresConfirmation:
            break
        }

        if let pendingCandidate = candidateForRetry {
            let evaluation = CodexWeeklyResetConfirmation.evaluateDelayedCandidate(
                previous: previousSnapshot,
                candidate: pendingCandidate,
                current: rawInitialSnapshot,
                currentIsExactOAuth: Self.isExactCodexOAuthResult(rawInitialResult),
                observedAt: observedAt)
            Self.logCodexWeeklyResetPublicationDecision(
                stage: "delayedConfirmation",
                decision: String(describing: evaluation.decision),
                reason: evaluation.reason,
                trace: CodexWeeklyResetPublicationTrace(
                    previousSnapshot: previousSnapshot,
                    missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
                    publicationBaseline: publicationBaseline,
                    initialSnapshot: rawInitialSnapshot,
                    confirmationSnapshot: pendingCandidate.snapshot))
            switch evaluation.decision {
            case .publishCurrent:
                return self.codexAdmittedOutcome(
                    publicationInitialOutcome,
                    baseline: publicationBaseline,
                    now: observedAt)
            case .retainCandidate:
                return CodexWeeklyResetPublicationAdmission(
                    outcome: nil,
                    pendingCandidate: pendingCandidate,
                    withheldSuccess: rawInitialResult)
            case .discardCandidate:
                candidateForRetry = nil
            }
        }

        var confirmingContext = laneContext
        confirmingContext.candidateForRetry = candidateForRetry
        return await self.codexConfirmingRequiredReset(
            confirmingContext,
            fetchConfirmation: fetchConfirmation)
    }

    private nonisolated static func makeCodexDelayedCandidate(
        previousSourceLabel: String?,
        initialResult: ProviderFetchResult,
        confirmationResult: ProviderFetchResult,
        trace: CodexWeeklyResetPublicationTrace,
        observedAt: Date) -> CodexWeeklyResetPublicationCandidate?
    {
        let evaluation = CodexWeeklyResetConfirmation.evaluateDelayedCandidateCreation(
            previous: trace.previousSnapshot,
            initial: trace.initialSnapshot,
            confirmation: confirmationResult.usage.scoped(to: .codex),
            sourceEvidence: .init(
                previousIsExactOAuth: previousSourceLabel?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == "oauth",
                initialIsExactOAuth: Self.isExactCodexOAuthResult(initialResult),
                confirmationIsExactOAuth: Self.isExactCodexOAuthResult(confirmationResult)),
            observedAt: observedAt)
        Self.logCodexWeeklyResetPublicationDecision(
            stage: "candidateCreation",
            decision: evaluation.candidate == nil ? "rejected" : "created",
            reason: evaluation.reason,
            trace: trace)
        return evaluation.candidate
    }

    private nonisolated static func codexMissingWeeklyAdmission(
        input: CodexMissingWeeklyAdmissionInput) -> CodexWeeklyResetPublicationAdmission
    {
        let rawInitialSnapshot = input.rawInitialSnapshot
        let withheldSuccess: ProviderFetchResult? = if case let .success(result) = input.publicationInitialOutcome
            .result
        {
            result
        } else {
            nil
        }
        guard rawInitialSnapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              input.previousSnapshot.map({
                  $0.updatedAt.timeIntervalSinceReferenceDate.isFinite &&
                      rawInitialSnapshot.updatedAt > $0.updatedAt
              }) ?? true,
              input.missingWindowBackfillSnapshot.map({
                  $0.updatedAt.timeIntervalSinceReferenceDate.isFinite &&
                      rawInitialSnapshot.updatedAt >= $0.updatedAt
              }) ?? true
        else {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: input.pendingCandidate,
                withheldSuccess: withheldSuccess)
        }
        if let baselineWeekly = CodexConsumerProjection.sourceRateWindow(
            for: .weekly,
            snapshot: input.publicationBaseline),
            case let .success(publicationResult) = input.publicationInitialOutcome.result,
            CodexConsumerProjection.sourceRateWindow(
                for: .weekly,
                snapshot: publicationResult.usage.scoped(to: .codex)) == nil
        {
            // Cached weekly usage past the display tolerance no longer hides the current usage view.
            if CodexWeeklyResetConfirmation.resetIsPastDisplayTolerance(baselineWeekly, now: input.observedAt),
               Self.isExactCodexOAuthResult(publicationResult)
            {
                return self.codexAdmittedOutcome(
                    input.publicationInitialOutcome,
                    baseline: input.publicationBaseline,
                    now: input.observedAt)
            }
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: input.pendingCandidate,
                withheldSuccess: withheldSuccess)
        }
        return self.codexAdmittedOutcome(
            input.publicationInitialOutcome,
            baseline: input.publicationBaseline,
            now: input.observedAt)
    }

    private struct CodexLiveLaneAdmissionContext {
        let rawInitialResult: ProviderFetchResult
        let rawInitialSnapshot: UsageSnapshot
        let previousSnapshot: UsageSnapshot?
        let publicationBaseline: UsageSnapshot?
        let missingWindowBackfillSnapshot: UsageSnapshot?
        let publicationInitialOutcome: ProviderFetchOutcome
        let previousSourceLabel: String?
        var candidateForRetry: CodexWeeklyResetPublicationCandidate?
        let observedAt: Date
    }

    private nonisolated static func codexConfirmingRequiredReset(
        _ context: CodexLiveLaneAdmissionContext,
        fetchConfirmation: @escaping CodexWeeklyConfirmationFetch) async -> CodexWeeklyResetPublicationAdmission
    {
        guard !Task.isCancelled else {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: context.candidateForRetry)
        }
        let confirmationOutcome = await fetchConfirmation()
        guard !Task.isCancelled,
              case let .success(confirmationResult) = confirmationOutcome.result
        else {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: context.candidateForRetry)
        }
        let confirmationSnapshot = confirmationResult.usage.scoped(to: .codex)
        let confirmationTrace = CodexWeeklyResetPublicationTrace(
            previousSnapshot: context.previousSnapshot,
            missingWindowBackfillSnapshot: context.missingWindowBackfillSnapshot,
            publicationBaseline: context.publicationBaseline,
            initialSnapshot: context.rawInitialSnapshot,
            confirmationSnapshot: confirmationSnapshot)
        guard CodexIdentityResolver.normalizeEmail(context.rawInitialSnapshot.accountEmail(for: .codex)) ==
            CodexIdentityResolver.normalizeEmail(confirmationSnapshot.accountEmail(for: .codex))
        else {
            Self.logCodexWeeklyResetPublicationDecision(
                stage: "confirmation",
                decision: "preservePreviousAccountMismatch",
                trace: confirmationTrace)
            return CodexWeeklyResetPublicationAdmission(outcome: nil, pendingCandidate: nil)
        }
        // The initial read left no live lane out, so the confirmation may not either.
        guard CodexWeeklyResetConfirmation.omittedLiveLanes(
            baseline: context.publicationBaseline,
            current: confirmationSnapshot,
            currentCarriesExtraLanes: Self.isExactCodexOAuthResult(confirmationResult),
            now: context.observedAt).isEmpty
        else {
            Self.logCodexWeeklyResetPublicationDecision(
                stage: "confirmation",
                decision: "preservePreviousNewOmission",
                trace: confirmationTrace)
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: context.candidateForRetry,
                withheldSuccess: confirmationResult)
        }
        let confirmationDecision = CodexWeeklyResetConfirmation.confirmationDecision(
            previous: context.publicationBaseline,
            previousEvidence: context.previousSnapshot,
            initial: context.rawInitialSnapshot,
            confirmation: confirmationSnapshot)
        Self.logCodexWeeklyResetPublicationDecision(
            stage: "confirmation",
            decision: String(describing: confirmationDecision),
            trace: confirmationTrace)
        switch confirmationDecision {
        case .publishConfirmation:
            return self.codexAdmittedOutcome(
                confirmationOutcome.backfillingCodexResetWindows(from: context.missingWindowBackfillSnapshot),
                baseline: context.publicationBaseline,
                now: context.observedAt)
        case .preservePrevious:
            let candidate = Self.makeCodexDelayedCandidate(
                previousSourceLabel: context.previousSourceLabel,
                initialResult: context.rawInitialResult,
                confirmationResult: confirmationResult,
                trace: confirmationTrace,
                observedAt: context.observedAt)
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: candidate,
                withheldSuccess: confirmationResult)
        }
    }

    /// Nil means no live lane was omitted, so the caller keeps the weekly reset path.
    private nonisolated static func codexOmittedLiveLaneAdmission(
        _ context: CodexLiveLaneAdmissionContext,
        fetchConfirmation: @escaping CodexWeeklyConfirmationFetch) async -> CodexWeeklyResetPublicationAdmission?
    {
        let initialIsExact = Self.isExactCodexOAuthResult(context.rawInitialResult)
        let omitted = CodexWeeklyResetConfirmation.omittedLiveLanes(
            baseline: context.publicationBaseline,
            current: context.rawInitialSnapshot,
            currentCarriesExtraLanes: initialIsExact,
            now: context.observedAt)
        guard !omitted.isEmpty else { return nil }
        let initialIsNewer = context.publicationBaseline.map {
            $0.updatedAt.timeIntervalSinceReferenceDate.isFinite &&
                context.rawInitialSnapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite &&
                context.rawInitialSnapshot.updatedAt > $0.updatedAt
        } ?? false
        // A weekly bar inside the display tolerance still shows "Resets now"; a second read must not drop it.
        let weeklyResetsNow = CodexConsumerProjection.sourceRateWindow(
            for: .weekly,
            snapshot: context.rawInitialSnapshot) == nil
            && CodexWeeklyResetConfirmation.resetIsInsideDisplayTolerance(
                CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: context.publicationBaseline),
                now: context.observedAt)
        guard initialIsNewer, initialIsExact, !weeklyResetsNow else {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: context.candidateForRetry,
                withheldSuccess: context.rawInitialResult)
        }
        guard !Task.isCancelled else {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: context.candidateForRetry)
        }
        let confirmationOutcome = await fetchConfirmation()
        guard !Task.isCancelled,
              case let .success(confirmationResult) = confirmationOutcome.result,
              Self.isExactCodexOAuthResult(confirmationResult)
        else {
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: context.candidateForRetry)
        }
        let confirmationSnapshot = confirmationResult.usage.scoped(to: .codex)
        let trace = CodexWeeklyResetPublicationTrace(
            previousSnapshot: context.previousSnapshot,
            missingWindowBackfillSnapshot: context.missingWindowBackfillSnapshot,
            publicationBaseline: context.publicationBaseline,
            initialSnapshot: context.rawInitialSnapshot,
            confirmationSnapshot: confirmationSnapshot)
        guard confirmationSnapshot.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              confirmationSnapshot.updatedAt > context.rawInitialSnapshot.updatedAt,
              CodexIdentityResolver.normalizeEmail(context.rawInitialSnapshot.accountEmail(for: .codex)) ==
              CodexIdentityResolver.normalizeEmail(confirmationSnapshot.accountEmail(for: .codex))
        else {
            Self.logCodexWeeklyResetPublicationDecision(
                stage: "omittedLiveLane",
                decision: "preservePrevious",
                trace: trace)
            return CodexWeeklyResetPublicationAdmission(outcome: nil, pendingCandidate: nil)
        }
        let admittedConfirmation = self.codexAdmittedOutcome(
            confirmationOutcome.backfillingCodexResetWindows(from: context.missingWindowBackfillSnapshot),
            baseline: context.publicationBaseline,
            now: context.observedAt)
        if Self.codexPlanChanged(from: context.rawInitialSnapshot, to: confirmationSnapshot) {
            return admittedConfirmation
        }
        // The confirmation may only leave out lanes the initial read already left out.
        let confirmationOmitted = CodexWeeklyResetConfirmation.omittedLiveLanes(
            baseline: context.publicationBaseline,
            current: confirmationSnapshot,
            currentCarriesExtraLanes: true,
            now: context.observedAt)
        guard confirmationOmitted.isSubset(of: omitted) else {
            Self.logCodexWeeklyResetPublicationDecision(
                stage: "omittedLiveLane",
                decision: "preservePreviousNewOmission",
                trace: trace)
            return CodexWeeklyResetPublicationAdmission(
                outcome: nil,
                pendingCandidate: context.candidateForRetry,
                withheldSuccess: confirmationResult)
        }
        if let publicationBaseline = context.publicationBaseline {
            for lane in omitted
                where CodexWeeklyResetConfirmation.restoredLaneIsUnconfirmedReset(
                    lane,
                    baseline: publicationBaseline,
                    confirmation: confirmationSnapshot)
            {
                Self.logCodexWeeklyResetPublicationDecision(
                    stage: "omittedLiveLane",
                    decision: "preservePrevious",
                    trace: trace)
                return CodexWeeklyResetPublicationAdmission(
                    outcome: nil,
                    pendingCandidate: nil,
                    withheldSuccess: confirmationResult)
            }
        }
        // Agreed omission publishes the confirmation. A weekly window that is still present keeps the
        // existing reset check, which cannot accept two reads that both left the lane out.
        if !omitted.contains(.weekly),
           CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: context.rawInitialSnapshot) != nil
        {
            let confirmationDecision = CodexWeeklyResetConfirmation.confirmationDecision(
                previous: context.publicationBaseline,
                previousEvidence: context.previousSnapshot,
                initial: context.rawInitialSnapshot,
                confirmation: confirmationSnapshot)
            Self.logCodexWeeklyResetPublicationDecision(
                stage: "omittedLiveLane",
                decision: String(describing: confirmationDecision),
                trace: trace)
            switch confirmationDecision {
            case .publishConfirmation:
                return admittedConfirmation
            case .preservePrevious:
                let candidate = Self.makeCodexDelayedCandidate(
                    previousSourceLabel: context.previousSourceLabel,
                    initialResult: context.rawInitialResult,
                    confirmationResult: confirmationResult,
                    trace: trace,
                    observedAt: context.observedAt)
                return CodexWeeklyResetPublicationAdmission(
                    outcome: nil,
                    pendingCandidate: candidate,
                    withheldSuccess: confirmationResult)
            }
        }
        return admittedConfirmation
    }

    private nonisolated static func codexAdmittedOutcome(
        _ outcome: ProviderFetchOutcome,
        baseline: UsageSnapshot?,
        now: Date) -> CodexWeeklyResetPublicationAdmission
    {
        CodexWeeklyResetPublicationAdmission(
            outcome: self.strippingPastDisplayTolerance(
                self.carryingLiveExtraLanes(outcome, from: baseline, now: now),
                now: now),
            pendingCandidate: nil)
    }

    /// CLI and RPC reads cannot report named lanes such as Spark; a live one stays until an exact read replaces it.
    private nonisolated static func carryingLiveExtraLanes(
        _ outcome: ProviderFetchOutcome,
        from baseline: UsageSnapshot?,
        now: Date) -> ProviderFetchOutcome
    {
        guard let baseline,
              case let .success(result) = outcome.result,
              !Self.isExactCodexOAuthResult(result)
        else { return outcome }
        let snapshot = result.usage.scoped(to: .codex)
        guard !Self.codexPlanChanged(from: baseline, to: snapshot) else { return outcome }
        let presentIDs = Set((snapshot.extraRateWindows ?? []).map(\.id))
        let carried = (baseline.extraRateWindows ?? []).filter { named in
            !presentIDs.contains(named.id) && CodexWeeklyResetConfirmation.isLiveLane(named.window, now: now)
        }
        guard !carried.isEmpty else { return outcome }
        return outcome.replacingUsage(
            snapshot.with(extraRateWindows: (snapshot.extraRateWindows ?? []) + carried))
    }

    private nonisolated static func strippingPastDisplayTolerance(
        _ outcome: ProviderFetchOutcome,
        now: Date) -> ProviderFetchOutcome
    {
        guard case let .success(result) = outcome.result else { return outcome }
        return outcome.replacingUsage(self.removingPastDisplayToleranceWindows(
            result.usage.scoped(to: .codex),
            now: now))
    }

    private nonisolated static func removingPastDisplayToleranceWindows(
        _ snapshot: UsageSnapshot,
        now: Date) -> UsageSnapshot
    {
        let primary = self.keepingCurrentDisplayWindow(snapshot.primary, now: now)
        let secondary = self.keepingCurrentDisplayWindow(snapshot.secondary, now: now)
        var updated = snapshot
        if primary != snapshot.primary || secondary != snapshot.secondary {
            updated = snapshot.with(primary: primary, secondary: secondary)
        }
        guard let extras = snapshot.extraRateWindows else { return updated }
        let kept = extras.filter { named in
            !CodexWeeklyResetConfirmation.resetIsPastDisplayTolerance(named.window, now: now)
        }
        guard kept.count != extras.count else { return updated }
        return updated.with(extraRateWindows: kept.isEmpty ? nil : kept)
    }

    private nonisolated static func keepingCurrentDisplayWindow(
        _ window: RateWindow?,
        now: Date) -> RateWindow?
    {
        guard let window else { return nil }
        let minutes = window.windowMinutes
        let isSessionOrWeeklyLane = minutes == CodexConsumerProjection.sessionWindowMinutes
            || minutes == CodexConsumerProjection.weeklyWindowMinutes
        guard isSessionOrWeeklyLane,
              CodexWeeklyResetConfirmation.resetIsPastDisplayTolerance(window, now: now)
        else {
            return window
        }
        return nil
    }

    private nonisolated static func codexCandidateAfterPreservedInitial(
        _ candidate: CodexWeeklyResetPublicationCandidate?,
        previousSnapshot: UsageSnapshot?,
        initialSnapshot: UsageSnapshot,
        initialResult: ProviderFetchResult,
        observedAt: Date) -> CodexWeeklyResetPublicationCandidate?
    {
        guard let candidate else { return nil }
        let evaluation = CodexWeeklyResetConfirmation.evaluateDelayedCandidate(
            previous: previousSnapshot,
            candidate: candidate,
            current: initialSnapshot,
            currentIsExactOAuth: Self.isExactCodexOAuthResult(initialResult),
            observedAt: observedAt)
        Self.logCodexWeeklyResetCandidateDecision(
            stage: "preservedInitialCandidate",
            decision: String(describing: evaluation.decision),
            reason: evaluation.reason)
        return evaluation.decision == .discardCandidate ? nil : candidate
    }

    private nonisolated static func logCodexWeeklyResetInitialDecision(
        _ decision: CodexWeeklyResetConfirmation.InitialDecision,
        previousSnapshot: UsageSnapshot?,
        missingWindowBackfillSnapshot: UsageSnapshot?,
        publicationBaseline: UsageSnapshot?,
        initialSnapshot: UsageSnapshot)
    {
        guard decision != .publishInitial else { return }
        self.logCodexWeeklyResetPublicationDecision(
            stage: "initial",
            decision: String(describing: decision),
            trace: CodexWeeklyResetPublicationTrace(
                previousSnapshot: previousSnapshot,
                missingWindowBackfillSnapshot: missingWindowBackfillSnapshot,
                publicationBaseline: publicationBaseline,
                initialSnapshot: initialSnapshot,
                confirmationSnapshot: nil))
    }

    private nonisolated static func isExactCodexOAuthResult(_ result: ProviderFetchResult) -> Bool {
        guard case .oauth = result.strategyKind else { return false }
        return result.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "oauth"
            && result.usage.scoped(to: .codex).dataConfidence == .exact
    }

    private nonisolated static func logCodexWeeklyResetPublicationDecision(
        stage: String,
        decision: String,
        reason: CodexWeeklyResetConfirmation.Reason? = nil,
        trace: CodexWeeklyResetPublicationTrace)
    {
        CodexBarLog.logger(LogCategories.provider(.codex, scope: "weekly-reset-publication")).debug(
            "Codex weekly reset publication decision",
            metadata: self.codexWeeklyResetPublicationMetadata(
                stage: stage, decision: decision, reason: reason, trace: trace))
    }

    private nonisolated static func logCodexWeeklyResetCandidateDecision(
        stage: String,
        decision: String,
        reason: CodexWeeklyResetConfirmation.Reason)
    {
        CodexBarLog.logger(LogCategories.provider(.codex, scope: "weekly-reset-publication")).debug(
            "Codex weekly reset candidate decision",
            metadata: ["stage": stage, "decision": decision, "reason": reason.rawValue])
    }

    nonisolated static func codexWeeklyResetPublicationMetadata(
        stage: String,
        decision: String,
        reason: CodexWeeklyResetConfirmation.Reason? = nil,
        trace: CodexWeeklyResetPublicationTrace) -> [String: String]
    {
        var metadata: [String: String] = [
            "stage": stage,
            "decision": decision,
        ]
        if let reason {
            metadata["reason"] = reason.rawValue
        }
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.previousSnapshot,
            prefix: "previousSnapshot",
            metadata: &metadata)
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.missingWindowBackfillSnapshot,
            prefix: "missingWindowBackfillSnapshot",
            metadata: &metadata)
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.publicationBaseline,
            prefix: "publicationBaseline",
            metadata: &metadata)
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.initialSnapshot,
            prefix: "initial",
            metadata: &metadata)
        Self.appendCodexWeeklyResetTrace(
            snapshot: trace.confirmationSnapshot,
            prefix: "confirmation",
            metadata: &metadata)
        metadata["initialConfirmationAccountMatches"] = Self.codexWeeklyResetCompatibility(
            snapshots: [trace.initialSnapshot, trace.confirmationSnapshot],
            value: { CodexIdentityResolver.normalizeEmail($0.accountEmail(for: .codex)) })
        metadata["stableAccountCompatible"] = Self.codexWeeklyResetCompatibility(
            snapshots: [trace.previousSnapshot, trace.initialSnapshot, trace.confirmationSnapshot],
            value: { CodexIdentityResolver.normalizeEmail($0.accountEmail(for: .codex)) })
        metadata["stablePlanCompatible"] = Self.codexWeeklyResetCompatibility(
            snapshots: [trace.previousSnapshot, trace.initialSnapshot, trace.confirmationSnapshot],
            value: { snapshot in
                snapshot.loginMethod(for: .codex)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            })
        return metadata
    }

    private nonisolated static func codexWeeklyResetCompatibility(
        snapshots: [UsageSnapshot?],
        value: (UsageSnapshot) -> String?) -> String
    {
        let values = snapshots.map { $0.flatMap(value) }
        guard let first = values.compactMap(\.self).first,
              values.allSatisfy({ $0 != nil })
        else {
            return "unknown"
        }
        return String(values.allSatisfy { $0 == first })
    }

    private nonisolated static func appendCodexWeeklyResetTrace(
        snapshot: UsageSnapshot?,
        prefix: String,
        metadata: inout [String: String])
    {
        guard let snapshot else {
            metadata["\(prefix).present"] = "false"
            return
        }
        let weekly = CodexConsumerProjection.sourceRateWindow(for: .weekly, snapshot: snapshot)
        metadata["\(prefix).present"] = "true"
        metadata["\(prefix).updatedAt"] = String(format: "%.0f", snapshot.updatedAt.timeIntervalSince1970)
        metadata["\(prefix).weeklyUsedPercent"] = weekly.map { String(format: "%.3f", $0.usedPercent) } ?? "nil"
        metadata["\(prefix).resetBoundary"] = weekly?.resetsAt.map {
            String(format: "%.0f", $0.timeIntervalSince1970)
        } ?? "nil"
        metadata["\(prefix).accountKnown"] = String(
            CodexIdentityResolver.normalizeEmail(snapshot.accountEmail(for: .codex)) != nil)
        metadata["\(prefix).planKnown"] = String(snapshot.loginMethod(for: .codex) != nil)
        metadata["\(prefix).creditsPresent"] = String(snapshot.codexResetCredits != nil)
        metadata["\(prefix).creditsAvailableCount"] = snapshot.codexResetCredits.map {
            String($0.availableCount)
        } ?? "nil"
    }
}
