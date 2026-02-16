@testable import AppStoreConnectAPI
import Foundation
import XCTest

final class RawHTTPTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testDownloadDoesNotSendAuthorizationOrJSONHeaders() async throws {
        let client = makeClient(retryCount: 0)

        MockURLProtocol.requestHandler = { request in
            assertNoAuthorizationHeader(request)
            XCTAssertNil(request.value(forHTTPHeaderField: "Accept"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://downloads.example.com/file.bin")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("ok".utf8)
            )
        }

        let data = try await client.download(url: URL(string: "https://downloads.example.com/file.bin")!)
        XCTAssertEqual(data, Data("ok".utf8))
    }

    func testPerformRawAuthorizedWithoutJSONHeadersDoesNotSetAccept() async throws {
        let client = makeClient(retryCount: 0, baseURL: URL(string: "https://example.com/v1/")!)

        MockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            XCTAssertTrue(auth.hasPrefix("Bearer "))
            XCTAssertNil(request.value(forHTTPHeaderField: "Accept"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))

            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/custom")

            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(items.contains(URLQueryItem(name: "filter[platform]", value: "IOS")))

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"ok\":true}".utf8)
            )
        }

        var url = URL(string: "custom", relativeTo: URL(string: "https://example.com/v1/")!)!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "filter[platform]", value: "IOS")]
        url = components.url!

        let data = try await client.performRaw(method: "GET", url: url, body: nil, authorize: true, addJSONHeaders: false)
        XCTAssertEqual(data, Data("{\"ok\":true}".utf8))
    }
}
