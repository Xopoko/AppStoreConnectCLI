import Foundation

struct ASCCTLConfigFile: Codable {
    var defaultProfile: String?
    var profiles: [String: ASCCTLProfile]

    static func empty() -> ASCCTLConfigFile {
        ASCCTLConfigFile(defaultProfile: "default", profiles: [:])
    }
}

struct ASCCTLProfile: Codable {
    var issuerId: String?
    var keyId: String?
    var privateKeyPath: String?

    var baseURL: String?
    var timeoutSeconds: Double?
    var retry: ASCCTLRetry?
}

struct ASCCTLRetry: Codable {
    var count: Int?
    var baseDelaySeconds: Double?
}
