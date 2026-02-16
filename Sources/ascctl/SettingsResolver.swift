import AppStoreConnectAPI
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ResolvedSettings {
    let profileName: String
    let issuerID: String?
    let keyID: String?
    let privateKey: ASCPrivateKeySource?

    let baseURL: URL
    let timeoutSeconds: Double
    let retryPolicy: ASCRetryPolicy

    let verbose: Bool
    let pretty: Bool

    let sources: [String: String]

    func makeClient(session: URLSession? = nil) throws -> ASCClient {
        guard let issuerID else {
            throw CLIError.missingRequiredOption("Missing issuer id. Provide --issuer-id, ASC_ISSUER_ID, or config profile issuerId.")
        }
        guard let keyID else {
            throw CLIError.missingRequiredOption("Missing key id. Provide --key-id, ASC_KEY_ID, or config profile keyId.")
        }
        guard let privateKey else {
            throw ASCError.missingPrivateKey
        }
        let credentials = ASCCredentials(issuerID: issuerID, keyID: keyID, privateKey: privateKey)
        let configuration = ASCClientConfiguration(
            baseURL: baseURL,
            timeoutSeconds: timeoutSeconds,
            retryPolicy: retryPolicy
        )
        return ASCClient(credentials: credentials, configuration: configuration, session: session)
    }

    func redactedJSON() -> [String: Any] {
        [
            "profile": profileName,
            "issuerId": issuerID ?? "",
            "keyId": keyID ?? "",
            "privateKey": privateKey.map { key in
                switch key {
                case .file(let path):
                    return ["type": "file", "path": path]
                case .pem:
                    return ["type": "pem", "source": "env:ASC_PRIVATE_KEY_PEM"]
                }
            } ?? ["type": "missing"],
            "baseURL": baseURL.absoluteString,
            "timeoutSeconds": timeoutSeconds,
            "retry": [
                "count": retryPolicy.count,
                "baseDelaySeconds": retryPolicy.baseDelaySeconds
            ],
            "pretty": pretty,
            "sources": sources
        ]
    }
}

enum SettingsResolver {
    static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("ascctl", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    static func resolve(global: GlobalOptions, requireAuth: Bool) throws -> (settings: ResolvedSettings, configURL: URL, configFile: ASCCTLConfigFile?) {
        let env = ProcessInfo.processInfo.environment

        let configURL = resolveConfigURL(global: global)
        let configFile = try loadConfigFile(at: configURL)

        let profileName = normalizedNonEmpty(global.profile)
            ?? normalizedNonEmpty(env["ASC_PROFILE"])
            ?? normalizedNonEmpty(configFile?.defaultProfile)
            ?? "default"

        let profile = configFile?.profiles[profileName]

        var sources: [String: String] = [:]

        let issuerID = firstNonEmpty(
            ("flag", global.issuerId),
            ("env", env["ASC_ISSUER_ID"]),
            ("config", profile?.issuerId)
        ).map { value, src in
            sources["issuerId"] = src
            return value
        }

        let keyID = firstNonEmpty(
            ("flag", global.keyId),
            ("env", env["ASC_KEY_ID"]),
            ("config", profile?.keyId)
        ).map { value, src in
            sources["keyId"] = src
            return value
        }

        let privateKey: ASCPrivateKeySource? = {
            if let path = normalizedNonEmpty(global.privateKeyPath) {
                sources["privateKey"] = "flag:--private-key-path"
                return .file(path: PathUtils.expandTilde(path))
            }
            if let path = normalizedNonEmpty(env["ASC_PRIVATE_KEY_PATH"]) {
                sources["privateKey"] = "env:ASC_PRIVATE_KEY_PATH"
                return .file(path: PathUtils.expandTilde(path))
            }
            if let path = normalizedNonEmpty(profile?.privateKeyPath) {
                sources["privateKey"] = "config:privateKeyPath"
                return .file(path: PathUtils.expandTilde(path))
            }
            if let pem = normalizedNonEmpty(env["ASC_PRIVATE_KEY_PEM"]) {
                sources["privateKey"] = "env:ASC_PRIVATE_KEY_PEM"
                return .pem(pem)
            }
            return nil
        }()

        let baseURLString = firstNonEmpty(
            ("flag", global.baseURL),
            ("config", profile?.baseURL),
            ("default", "https://api.appstoreconnect.apple.com/v1/")
        )?.value
        let baseURL = URL(string: baseURLString ?? "https://api.appstoreconnect.apple.com/v1/") ?? URL(string: "https://api.appstoreconnect.apple.com/v1/")!
        sources["baseURL"] = firstNonEmpty(
            ("flag", global.baseURL),
            ("config", profile?.baseURL),
            ("default", "https://api.appstoreconnect.apple.com/v1/")
        )?.source ?? "default"

        let timeoutSeconds = firstNonEmptyDouble(
            ("flag", global.timeoutSeconds),
            ("config", profile?.timeoutSeconds),
            ("default", 60)
        ).map { value, src in
            sources["timeoutSeconds"] = src
            return value
        } ?? 60

        let retryCount = firstNonEmptyInt(
            ("flag", global.retryCount),
            ("config", profile?.retry?.count),
            ("default", ASCRetryPolicy.default.count)
        ).map { value, src in
            sources["retryCount"] = src
            return value
        } ?? ASCRetryPolicy.default.count

        let retryBaseDelay = firstNonEmptyDouble(
            ("flag", global.retryBaseDelaySeconds),
            ("config", profile?.retry?.baseDelaySeconds),
            ("default", ASCRetryPolicy.default.baseDelaySeconds)
        ).map { value, src in
            sources["retryBaseDelaySeconds"] = src
            return value
        } ?? ASCRetryPolicy.default.baseDelaySeconds

        let retryPolicy = ASCRetryPolicy(count: retryCount, baseDelaySeconds: retryBaseDelay)

        let verbose = global.verbose
        let pretty = global.pretty

        if requireAuth {
            // Provide clearer errors than "missingPrivateKey" for each missing field.
            if normalizedNonEmpty(issuerID) == nil {
                throw CLIError.missingRequiredOption("Missing issuer id. Provide --issuer-id, ASC_ISSUER_ID, or config profile issuerId.")
            }
            if normalizedNonEmpty(keyID) == nil {
                throw CLIError.missingRequiredOption("Missing key id. Provide --key-id, ASC_KEY_ID, or config profile keyId.")
            }
            if privateKey == nil {
                throw ASCError.missingPrivateKey
            }
        }

        let settings = ResolvedSettings(
            profileName: profileName,
            issuerID: issuerID,
            keyID: keyID,
            privateKey: privateKey,
            baseURL: baseURL,
            timeoutSeconds: timeoutSeconds,
            retryPolicy: retryPolicy,
            verbose: verbose,
            pretty: pretty,
            sources: sources
        )

        return (settings, configURL, configFile)
    }

    private static func resolveConfigURL(global: GlobalOptions) -> URL {
        if let path = normalizedNonEmpty(global.config) {
            return URL(fileURLWithPath: PathUtils.expandTilde(path))
        }
        return defaultConfigURL()
    }

    private static func loadConfigFile(at url: URL) throws -> ASCCTLConfigFile? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ASCCTLConfigFile.self, from: data)
    }
}

private func normalizedNonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func firstNonEmpty(_ candidates: (String, String?)...) -> (value: String, source: String)? {
    for (source, value) in candidates {
        if let normalized = normalizedNonEmpty(value) {
            return (normalized, source)
        }
    }
    return nil
}

private func firstNonEmptyInt(_ candidates: (String, Int?)...) -> (value: Int, source: String)? {
    for (source, value) in candidates {
        if let value { return (value, source) }
    }
    return nil
}

private func firstNonEmptyDouble(_ candidates: (String, Double?)...) -> (value: Double, source: String)? {
    for (source, value) in candidates {
        if let value { return (value, source) }
    }
    return nil
}
