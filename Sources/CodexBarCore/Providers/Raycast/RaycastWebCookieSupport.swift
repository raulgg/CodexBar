import Foundation

enum RaycastWebCookieSupport {
    private static let sessionCookieName = "__raycast_session"
    private static let requestCookieNames: Set<String> = [Self.sessionCookieName, "csrf_token"]

    /// Keeps session + optional CSRF. Requires a nonempty `__raycast_session` value.
    static func requestCookieHeader(from rawHeader: String?) -> String? {
        guard let filtered = CookieHeaderNormalizer.filteredHeader(
            from: rawHeader,
            allowedNames: self.requestCookieNames)
        else { return nil }
        let session = CookieHeaderNormalizer.pairs(from: filtered).first {
            $0.name == self.sessionCookieName
        }
        guard let session, !session.value.isEmpty else { return nil }
        return filtered
    }

    #if os(macOS)
    static func automaticImportOrder(provider: UsageProvider) -> BrowserCookieImportOrder {
        ProviderDefaults.metadata[provider]?.browserCookieOrder ?? [.chrome]
    }
    #endif
}
