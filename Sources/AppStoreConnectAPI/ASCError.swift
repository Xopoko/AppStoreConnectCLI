import Foundation

public struct ASCApiErrorResponse: Decodable, Sendable {
    public let errors: [ASCApiError]
}

public struct ASCApiError: Decodable, Sendable {
    public let status: String?
    public let code: String?
    public let title: String?
    public let detail: String?
}

public enum ASCError: Error, Sendable {
    case invalidURL(String)
    case invalidResponse
    case missingPrivateKey
    case invalidPrivateKey(String)
    case cryptoUnavailable
    case signingFailed(String)
    case transport(String)
    case apiErrors(statusCode: Int, errors: [ASCApiError])
    case invalidStatusCode(Int, String)
}

extension ASCError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .invalidResponse:
            return "App Store Connect API returned an invalid response."
        case .missingPrivateKey:
            return "ASC private key was not provided. Set ASC_PRIVATE_KEY_PATH or ASC_PRIVATE_KEY_PEM, or configure privateKeyPath in config."
        case .invalidPrivateKey(let message):
            return "Invalid ASC private key: \(message)"
        case .cryptoUnavailable:
            return "Crypto is unavailable. JWT signing requires swift-crypto or CryptoKit."
        case .signingFailed(let message):
            return "Failed to sign ASC JWT: \(message)"
        case .transport(let message):
            return "Network request failed: \(message)"
        case .apiErrors(let statusCode, let errors):
            let joined = errors
                .map { err -> String in
                    let parts = [err.status, err.code, err.title, err.detail].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    return parts.joined(separator: " | ")
                }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return joined.isEmpty
                ? "App Store Connect API request failed with status \(statusCode)."
                : "App Store Connect API request failed with status \(statusCode):\n\(joined)"
        case .invalidStatusCode(let code, let body):
            if body.isEmpty {
                return "App Store Connect API request failed with status \(code)."
            }
            return "App Store Connect API request failed with status \(code): \(body)"
        }
    }
}

