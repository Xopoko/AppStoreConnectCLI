import Foundation

public enum ASCPrivateKeySource: Sendable, Equatable {
    case file(path: String)
    case pem(String)
}

public struct ASCCredentials: Sendable, Equatable {
    public let issuerID: String
    public let keyID: String
    public let privateKey: ASCPrivateKeySource

    public init(issuerID: String, keyID: String, privateKey: ASCPrivateKeySource) {
        self.issuerID = issuerID
        self.keyID = keyID
        self.privateKey = privateKey
    }
}

public struct ASCRetryPolicy: Sendable, Equatable {
    public let count: Int
    public let baseDelaySeconds: Double

    public init(count: Int, baseDelaySeconds: Double) {
        self.count = max(0, count)
        self.baseDelaySeconds = max(0, baseDelaySeconds)
    }

    public static let `default` = ASCRetryPolicy(count: 3, baseDelaySeconds: 1.0)
}

public struct ASCClientConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let timeoutSeconds: Double
    public let retryPolicy: ASCRetryPolicy

    public init(
        baseURL: URL = URL(string: "https://api.appstoreconnect.apple.com/v1/")!,
        timeoutSeconds: Double = 60,
        retryPolicy: ASCRetryPolicy = .default
    ) {
        // Ensure trailing slash for URL(relativeTo:)
        if baseURL.absoluteString.hasSuffix("/") {
            self.baseURL = baseURL
        } else {
            self.baseURL = baseURL.appendingPathComponent("")
        }
        self.timeoutSeconds = max(1, timeoutSeconds)
        self.retryPolicy = retryPolicy
    }

    public static let `default` = ASCClientConfiguration()
}

