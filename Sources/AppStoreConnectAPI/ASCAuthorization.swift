import Foundation
#if canImport(Crypto)
import Crypto
#elseif canImport(CryptoKit)
import CryptoKit
#endif

struct ASCAuthorization {
    private let credentials: ASCCredentials
    private var cachedToken: (token: String, expiration: Date)?
    private let clock: () -> Date

    init(credentials: ASCCredentials, clock: @escaping () -> Date = Date.init) {
        self.credentials = credentials
        self.clock = clock
    }

    mutating func bearerToken() throws -> String {
        let now = clock()
        if let cachedToken, cachedToken.expiration.timeIntervalSince(now) > 60 {
            return cachedToken.token
        }

        let privateKeyPEM = try readPrivateKey()
        let jwt = try signJWT(privateKeyPEM: privateKeyPEM, now: now)
        cachedToken = (jwt.token, jwt.expiration)
        return jwt.token
    }

    private func readPrivateKey() throws -> String {
        switch credentials.privateKey {
        case .pem(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ASCError.missingPrivateKey }
            return trimmed
        case .file(let path):
            guard FileManager.default.fileExists(atPath: path) else {
                throw ASCError.missingPrivateKey
            }
            let content = try String(contentsOfFile: path)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ASCError.missingPrivateKey }
            return trimmed
        }
    }

    private func signJWT(privateKeyPEM: String, now: Date) throws -> (token: String, expiration: Date) {
        #if canImport(Crypto) || canImport(CryptoKit)
        let nowSeconds = Int(now.timeIntervalSince1970)
        let expSeconds = nowSeconds + 60 * 18

        let header: [String: Any] = ["alg": "ES256", "kid": credentials.keyID, "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": credentials.issuerID,
            "aud": "appstoreconnect-v1",
            "iat": nowSeconds,
            "exp": expSeconds
        ]

        let headerData = try jsonData(from: header)
        let payloadData = try jsonData(from: payload)

        let signingInput = base64URL(headerData) + "." + base64URL(payloadData)
        let signingInputData = Data(signingInput.utf8)

        do {
            let privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
            let signature = try privateKey.signature(for: signingInputData)
            let signatureData = signature.rawRepresentation
            let jwt = signingInput + "." + base64URL(signatureData)
            return (jwt, Date(timeIntervalSince1970: TimeInterval(expSeconds)))
        } catch {
            throw ASCError.signingFailed(String(describing: error))
        }
        #else
        throw ASCError.cryptoUnavailable
        #endif
    }

    private func jsonData(from object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ASCError.invalidResponse
        }
        return try JSONSerialization.data(withJSONObject: object, options: [])
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

