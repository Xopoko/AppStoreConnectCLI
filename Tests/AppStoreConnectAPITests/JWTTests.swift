import Crypto
@testable import AppStoreConnectAPI
import Foundation
import XCTest

final class JWTTests: XCTestCase {
    func testJWTContainsExpectedClaimsAndHeader() throws {
        let privateKey = P256.Signing.PrivateKey()
        let pem = privateKey.pemRepresentation

        let credentials = ASCCredentials(
            issuerID: "issuer-123",
            keyID: "KEYID12345",
            privateKey: .pem(pem)
        )

        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        var auth = ASCAuthorization(credentials: credentials, clock: { fixedNow })
        let jwt = try auth.bearerToken()

        let parts = jwt.split(separator: ".").map(String.init)
        XCTAssertEqual(parts.count, 3)

        let header = try decodeJSON(parts[0])
        XCTAssertEqual(header["alg"] as? String, "ES256")
        XCTAssertEqual(header["kid"] as? String, "KEYID12345")
        XCTAssertEqual(header["typ"] as? String, "JWT")

        let payload = try decodeJSON(parts[1])
        XCTAssertEqual(payload["iss"] as? String, "issuer-123")
        XCTAssertEqual(payload["aud"] as? String, "appstoreconnect-v1")
        XCTAssertEqual(payload["iat"] as? Int, Int(fixedNow.timeIntervalSince1970))
        XCTAssertEqual(payload["exp"] as? Int, Int(fixedNow.timeIntervalSince1970) + 60 * 18)
    }

    func testJWTIsCachedUntilNearExpiration() throws {
        let privateKey = P256.Signing.PrivateKey()
        let pem = privateKey.pemRepresentation

        let credentials = ASCCredentials(
            issuerID: "issuer-123",
            keyID: "KEYID12345",
            privateKey: .pem(pem)
        )

        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var auth = ASCAuthorization(credentials: credentials, clock: { now })

        let jwt1 = try auth.bearerToken()
        now.addTimeInterval(120)
        let jwt2 = try auth.bearerToken()
        XCTAssertEqual(jwt1, jwt2, "Token should be reused while still valid.")

        // Advance close to exp, within the 60s safety window.
        let payload = try decodeJSON(jwt1.split(separator: ".").map(String.init)[1])
        let exp = payload["exp"] as? Int ?? 0
        now = Date(timeIntervalSince1970: TimeInterval(exp - 30))

        let jwt3 = try auth.bearerToken()
        XCTAssertNotEqual(jwt1, jwt3, "Token should be refreshed when near expiration.")
    }
}

private func decodeJSON(_ base64URL: String) throws -> [String: Any] {
    guard let data = base64URLDecode(base64URL) else {
        XCTFail("Failed to base64url decode segment")
        return [:]
    }
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    return object as? [String: Any] ?? [:]
}

private func base64URLDecode(_ value: String) -> Data? {
    var base64 = value
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - (base64.count % 4)) % 4
    if padding > 0 {
        base64 += String(repeating: "=", count: padding)
    }
    return Data(base64Encoded: base64)
}

