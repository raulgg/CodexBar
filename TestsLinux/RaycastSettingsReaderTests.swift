import Foundation
import Testing
@testable import CodexBarCore

struct RaycastSettingsReaderTests {
    private static func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("raycast-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".config/raycast", isDirectory: true),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".config/raycast-x", isDirectory: true),
            withIntermediateDirectories: true)
        return home
    }

    @Test
    func `environment token wins over the legacy config file`() throws {
        let home = try Self.makeHome()
        try Data(#"{"token":"file-token"}"#.utf8)
            .write(to: home.appendingPathComponent(".config/raycast/config.json"))
        #expect(RaycastSettingsReader.apiKey(
            environment: [
                "HOME": home.path,
                "RAYCAST_ACCESS_TOKEN": "env-token",
            ],
            homeDirectory: home) == "env-token")
    }

    @Test
    func `RAYCAST_TOKEN is accepted when RAYCAST_ACCESS_TOKEN is unset`() throws {
        let home = try Self.makeHome()
        #expect(RaycastSettingsReader.apiKey(
            environment: ["RAYCAST_TOKEN": "alias-token"],
            homeDirectory: home) == "alias-token")
    }

    @Test
    func `reads token Token and accessToken keys from the legacy config file`() throws {
        let home = try Self.makeHome()
        let url = home.appendingPathComponent(".config/raycast/config.json")
        try Data(#"{"Token":"legacy-token"}"#.utf8).write(to: url)
        #expect(RaycastSettingsReader.apiKey(environment: [:], homeDirectory: home) == "legacy-token")

        try Data(#"{"accessToken":"access-token"}"#.utf8).write(to: url)
        #expect(RaycastSettingsReader.apiKey(environment: [:], homeDirectory: home) == "access-token")
    }

    @Test
    func `RAYCAST_CONFIG_PATH is exclusive and does not fall through`() throws {
        let home = try Self.makeHome()
        try Data(#"{"token":"default-token"}"#.utf8)
            .write(to: home.appendingPathComponent(".config/raycast/config.json"))
        let custom = home.appendingPathComponent("custom-raycast.json")
        try Data(#"{"token":"custom-token"}"#.utf8).write(to: custom)
        #expect(RaycastSettingsReader.apiKey(
            environment: ["RAYCAST_CONFIG_PATH": custom.path],
            homeDirectory: home) == "custom-token")
        #expect(RaycastSettingsReader.apiKey(
            environment: ["RAYCAST_CONFIG_PATH": home.appendingPathComponent("missing.json").path],
            homeDirectory: home) == nil)
    }

    @Test
    func `windows config path is a fallback when the mac file is absent`() throws {
        let home = try Self.makeHome()
        try Data(#"{"token":"windows-token"}"#.utf8)
            .write(to: home.appendingPathComponent(".config/raycast-x/config.json"))
        #expect(RaycastSettingsReader.apiKey(environment: [:], homeDirectory: home) == "windows-token")
    }

    @Test
    func `quoted tokens are cleaned`() {
        #expect(RaycastSettingsReader.apiKey(environment: ["RAYCAST_ACCESS_TOKEN": "\"quoted\""]) == "quoted")
    }

    @Test
    func `descriptor exposes API-token fetch without inventing a public key`() {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: .raycast)
        #expect(!descriptor.metadata.defaultEnabled)
        #expect(descriptor.fetchPlan.sourceModes == Set([.auto, .api]))
        #expect(descriptor.credentials?.supportsAPIKeyOverride == true)
        #expect(descriptor.cli.name == "raycast")
    }
}
