import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RaycastUsageError: LocalizedError, Sendable, Equatable {
    case invalidCredentials
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Raycast session cookie is invalid or expired."
        case let .networkError(message):
            "Raycast network error: \(message)"
        case let .apiError(message):
            "Raycast API error: \(message)"
        case let .parseFailed(message):
            "Raycast parse error: \(message)"
        }
    }
}

enum RaycastSettingsError: LocalizedError {
    case missingCookie
    case invalidCookie

    var errorDescription: String? {
        switch self {
        case .missingCookie:
            "No Raycast session cookies found in browsers."
        case .invalidCookie:
            "Raycast cookie header is invalid."
        }
    }
}

public struct RaycastUsageFetcher: Sendable {
    private static let creditsURL = URL(string: "https://www.raycast.com/frontend_api/current_user/ai_credits")!
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"

    public static func fetchUsage(
        cookieHeader: String,
        timeout: TimeInterval,
        transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        now: Date = Date()) async throws -> UsageSnapshot
    {
        var request = URLRequest(url: self.creditsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.raycast.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.raycast.com/settings", forHTTPHeaderField: "Referer")

        let response: ProviderHTTPResponse
        do {
            response = try await transport.response(for: request, retryPolicy: .transientIdempotent)
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            throw RaycastUsageError.networkError(error.localizedDescription)
        }

        switch response.statusCode {
        case 200:
            break
        case 401, 403:
            throw RaycastUsageError.invalidCredentials
        case 429:
            throw RaycastUsageError.apiError("Raycast credits requests are rate limited.")
        default:
            throw RaycastUsageError.apiError("Raycast credits API returned HTTP \(response.statusCode).")
        }

        return try self.parseSnapshot(data: response.data, now: now)
    }

    static func parseSnapshot(data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RaycastUsageError.parseFailed("expected JSON object")
            }
            object = parsed
        } catch let error as RaycastUsageError {
            throw error
        } catch {
            throw RaycastUsageError.parseFailed("expected JSON")
        }

        let remaining = try self.number(object["remaining_balance_credits"], field: "remaining_balance_credits")
        let total = try self.number(object["total_balance_credits"], field: "total_balance_credits")
        if remaining == nil, total == nil {
            throw RaycastUsageError.parseFailed("no credit amounts")
        }
        if let remaining, remaining < 0 {
            throw RaycastUsageError.parseFailed("remaining_balance_credits")
        }
        if let total, total < 0 {
            throw RaycastUsageError.parseFailed("total_balance_credits")
        }

        var renewal: Date?
        if let raw = object["next_credits_at"], !(raw is NSNull) {
            guard let text = raw as? String else {
                throw RaycastUsageError.parseFailed("next_credits_at")
            }
            renewal = self.date(text)
            if renewal == nil {
                throw RaycastUsageError.parseFailed("next_credits_at")
            }
        }

        let funding = object["funding_subscription"] as? [String: Any] ?? [:]
        let plan = self.planLabel(funding["tier"] as? String)
        var rows: [ProviderDetailSection.Row] = []
        if let remaining {
            try rows.append(ProviderDetailSection.Row(label: "Left", value: self.amount(remaining)))
        }
        if let total {
            try rows.append(ProviderDetailSection.Row(label: "Total", value: self.amount(total)))
        }
        if let renewal {
            try rows.append(ProviderDetailSection.Row(label: "Renews", value: self.renewalText(renewal)))
        }

        let primary: RateWindow?
        if let remaining, let total, total > 0 {
            let usedPercent = min(max(((total - remaining) / total) * 100, 0), 100)
            primary = RateWindow(
                usedPercent: usedPercent,
                windowMinutes: nil,
                resetsAt: renewal,
                resetDescription: nil)
        } else {
            primary = nil
        }

        return try UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            details: rows.isEmpty ? [] : [ProviderDetailSection(title: "Credits", rows: rows)],
            subscriptionRenewsAt: renewal,
            updatedAt: now,
            identity: plan.map {
                ProviderIdentitySnapshot(
                    providerID: .raycast,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: $0)
            },
            dataConfidence: .exact)
    }

    static func renewalText(_ date: Date) -> String {
        self.renewalFormatter.string(from: date)
    }

    private static let renewalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy, h:mm a"
        return formatter
    }()

    private static func number(_ raw: Any?, field: String) throws -> Double? {
        switch raw {
        case nil, is NSNull:
            return nil
        case let value as Double:
            guard value.isFinite else { throw RaycastUsageError.parseFailed(field) }
            return value
        case let value as Int:
            return Double(value)
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let parsed = Double(trimmed), parsed.isFinite else {
                throw RaycastUsageError.parseFailed(field)
            }
            return parsed
        default:
            throw RaycastUsageError.parseFailed(field)
        }
    }

    private static func amount(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private static func planLabel(_ tier: String?) -> String? {
        switch tier?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case nil, .some(""):
            nil
        case "pro":
            "Pro"
        case "pro_plus":
            "Pro+"
        case "max":
            "Max"
        case let value?:
            value
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
}
