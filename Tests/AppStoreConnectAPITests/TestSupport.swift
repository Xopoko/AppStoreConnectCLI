import Crypto
@testable import AppStoreConnectAPI
import Foundation
import XCTest

func assertJSONHeaders(_ request: URLRequest, expectsBody: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
    let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
    XCTAssertTrue(auth.hasPrefix("Bearer "), "Authorization header must be Bearer token.", file: file, line: line)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", file: file, line: line)
    if expectsBody {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json", file: file, line: line)
    }
}

func assertNoAuthorizationHeader(_ request: URLRequest, file: StaticString = #filePath, line: UInt = #line) {
    let auth = request.value(forHTTPHeaderField: "Authorization")
    XCTAssertTrue(auth == nil || auth == "", "Authorization header must not be present.", file: file, line: line)
}

func requestBodyData(_ request: URLRequest) -> Data {
    if let data = request.httpBody {
        return data
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)

    while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count > 0 {
            result.append(buffer, count: count)
            continue
        }
        break
    }

    return result
}

func makeClient(retryCount: Int, baseURL: URL = URL(string: "https://example.com/v1/")!) -> ASCClient {
    let privateKey = P256.Signing.PrivateKey()
    let pem = privateKey.pemRepresentation
    let creds = ASCCredentials(issuerID: "issuer", keyID: "kid", privateKey: .pem(pem))

    let retry = ASCRetryPolicy(count: retryCount, baseDelaySeconds: 0)
    let config = ASCClientConfiguration(baseURL: baseURL, timeoutSeconds: 5, retryPolicy: retry)

    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [MockURLProtocol.self]
    sessionConfig.timeoutIntervalForRequest = 5
    sessionConfig.timeoutIntervalForResource = 5
    let session = URLSession(configuration: sessionConfig)

    return ASCClient(credentials: creds, configuration: config, session: session)
}

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: ASCError.invalidResponse)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

