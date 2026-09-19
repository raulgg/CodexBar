import Foundation

/// Resolves the Raycast account access token CodexBar uses for the unofficial credits API.
///
/// Raycast does not publish a usage API key. The desktop app stores its OAuth session inside an
/// encrypted database, so CodexBar reads an explicit token from settings/environment or from the
/// legacy `~/.config/raycast/config.json` file older Raycast builds wrote.
public enum RaycastSettingsReader: Sendable {
    public static let apiKeyEnvironmentKey = "RAYCAST_ACCESS_TOKEN"
    public static let alternateAPIKeyEnvironmentKey = "RAYCAST_TOKEN"
    public static let configPathEnvironmentKey = "RAYCAST_CONFIG_PATH"
    public static let apiKeyEnvironmentKeys = [
        Self.apiKeyEnvironmentKey,
        Self.alternateAPIKeyEnvironmentKey,
    ]

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String?
    {
        for key in self.apiKeyEnvironmentKeys {
            if let token = SettingsValue.cleaned(environment[key]) {
                return token
            }
        }
        return self.configFileToken(environment: environment, homeDirectory: homeDirectory)
    }

    static func configFileToken(
        environment: [String: String],
        homeDirectory: URL) -> String?
    {
        for url in self.configFileCandidates(environment: environment, homeDirectory: homeDirectory) {
            guard FileManager.default.isReadableFile(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let token = self.parseConfigFile(data: data)
            else { continue }
            return token
        }
        return nil
    }

    /// An explicit `RAYCAST_CONFIG_PATH` is exclusive: the default `~/.config/raycast` files are
    /// never consulted, so a missing custom file cannot fall through to another profile's token.
    static func configFileCandidates(
        environment: [String: String],
        homeDirectory: URL) -> [URL]
    {
        if let override = SettingsValue.cleaned(environment[self.configPathEnvironmentKey]) {
            return [self.expandedPath(override, homeDirectory: homeDirectory)]
        }
        let configRoot = homeDirectory.appendingPathComponent(".config", isDirectory: true)
        return [
            configRoot.appendingPathComponent("raycast/config.json"),
            configRoot.appendingPathComponent("raycast-x/config.json"),
        ]
    }

    /// Accepts the three keys the unofficial Raycast backend clients historically read.
    static func parseConfigFile(data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["token", "Token", "accessToken"] {
            if let token = SettingsValue.cleaned(root[key] as? String) {
                return token
            }
        }
        return nil
    }

    private static func expandedPath(_ path: String, homeDirectory: URL) -> URL {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }
}
