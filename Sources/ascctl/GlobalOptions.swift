import ArgumentParser
import Foundation

struct GlobalOptions: ParsableArguments {
    @Option(help: "Path to config file (default: ~/.config/ascctl/config.json).")
    var config: String?

    @Option(help: "Profile name from config.json (default: --profile, then ASC_PROFILE, then config.defaultProfile, then \"default\").")
    var profile: String?

    @Flag(help: "Pretty-print JSON output (still machine-readable).")
    var pretty: Bool = false

    @Flag(help: "Verbose logging to stderr.")
    var verbose: Bool = false

    // Credentials overrides
    @Option(name: .customLong("issuer-id"), help: "ASC issuer ID override.")
    var issuerId: String?

    @Option(name: .customLong("key-id"), help: "ASC key ID override.")
    var keyId: String?

    @Option(name: .customLong("private-key-path"), help: "Path to ASC .p8 private key override.")
    var privateKeyPath: String?

    // Client overrides
    @Option(name: .customLong("base-url"), help: "ASC base URL override (default: https://api.appstoreconnect.apple.com/v1/).")
    var baseURL: String?

    @Option(name: .customLong("timeout"), help: "Request timeout in seconds.")
    var timeoutSeconds: Double?

    @Option(name: .customLong("retry-count"), help: "Retry count for 429/5xx.")
    var retryCount: Int?

    @Option(name: .customLong("retry-base-delay"), help: "Retry base delay in seconds (linear backoff).")
    var retryBaseDelaySeconds: Double?
}
