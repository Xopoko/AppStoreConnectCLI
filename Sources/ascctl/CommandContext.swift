import AppStoreConnectAPI
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum CommandContext {
    // Test-only escape hatch: allows unit tests to inject a URLSession configured with URLProtocol mocks.
    // Defaults to nil (production behavior).
    static var urlSessionOverride: URLSession? = nil

    static func resolveContext(global: GlobalOptions, requireAuth: Bool) throws -> (settings: ResolvedSettings, client: ASCClient?) {
        let (settings, _, _) = try SettingsResolver.resolve(global: global, requireAuth: requireAuth)
        if requireAuth {
            return (settings: settings, client: try settings.makeClient(session: urlSessionOverride))
        }
        return (settings: settings, client: nil)
    }

    static func withClient<T>(
        global: GlobalOptions,
        body: (ResolvedSettings, ASCClient) async throws -> T
    ) async throws -> T {
        let (settings, client) = try resolveContext(global: global, requireAuth: true)
        guard let client else {
            throw CLIError.missingRequiredOption("Missing App Store Connect credentials.")
        }
        return try await body(settings, client)
    }
}
