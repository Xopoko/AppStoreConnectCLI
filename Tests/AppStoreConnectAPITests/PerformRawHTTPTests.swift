@testable import AppStoreConnectAPI
import Foundation
import XCTest

final class PerformRawHTTPTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testPerformRawAddsAuthorizationAndJSONHeadersByDefault() async throws {
        let client = makeClient(retryCount: 0)

        MockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            XCTAssertTrue(auth.hasPrefix("Bearer "))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/apps")

            let body = requestBodyData(request)
            XCTAssertEqual(body, Data("{\"hello\":\"world\"}".utf8))

            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("ok".utf8)
            )
        }

        let data = try await client.performRaw(
            method: "POST",
            url: URL(string: "https://example.com/v1/apps")!,
            body: Data("{\"hello\":\"world\"}".utf8)
        )
        XCTAssertEqual(data, Data("ok".utf8))
    }

    func testPerformRawDoesNotAddJSONHeadersWhenDisabled() async throws {
        let client = makeClient(retryCount: 0)

        MockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            XCTAssertTrue(auth.hasPrefix("Bearer "))
            XCTAssertNil(request.value(forHTTPHeaderField: "Accept"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/v1/apps/APPID")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("ok".utf8)
            )
        }

        let data = try await client.performRaw(
            method: "PATCH",
            url: URL(string: "https://example.com/v1/apps/APPID")!,
            body: Data("{\"ok\":true}".utf8),
            authorize: true,
            addJSONHeaders: false
        )
        XCTAssertEqual(data, Data("ok".utf8))
    }

    func testPerformRawRespectsExplicitAcceptAndContentTypeHeaders() async throws {
        let client = makeClient(retryCount: 0)

        MockURLProtocol.requestHandler = { request in
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            XCTAssertTrue(auth.hasPrefix("Bearer "))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.api+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/vnd.api+json")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/custom")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("ok".utf8)
            )
        }

        let data = try await client.performRaw(
            method: "POST",
            url: URL(string: "https://example.com/v1/custom")!,
            body: Data("{}".utf8),
            headers: [
                "Accept": "application/vnd.api+json",
                "Content-Type": "application/vnd.api+json",
            ]
        )
        XCTAssertEqual(data, Data("ok".utf8))
    }
}

