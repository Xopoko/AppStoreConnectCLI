import XCTest
import Foundation
import AppStoreConnectAPI
import Crypto

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import ascctl

final class IDsCommandTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    func testIDsAppLookupBuildsExpectedRequestAndReturnsID() async throws {
        let spec = try makeMinimalSpec()

        let expectedBundleId = "com.example.app"
        let expectedID = "APP_ID_1"

        let exp = expectation(description: "request")
        let session = makeMockedSession()
        let (settings, client) = makeContext(session: session)

        MockURLProtocol.requestHandler = { request in
            defer { exp.fulfill() }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "example.com")
            XCTAssertEqual(request.url?.path, "/v1/apps")

            let query = self.queryDict(from: request.url)
            XCTAssertEqual(query["filter[bundleId]"], expectedBundleId)
            XCTAssertEqual(query["limit"], "1")

            let body = #"{"data":[{"id":"\#(expectedID)","type":"apps"}]}"#
            return self.okJSONResponse(for: request, body: body)
        }

        let id = try await IDsLookup.appID(bundleId: expectedBundleId, spec: spec, settings: settings, client: client)
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(id, expectedID)
    }

    func testIDsBundleIDLookupBuildsExpectedRequestAndReturnsID() async throws {
        let spec = try makeMinimalSpec()

        let expectedIdentifier = "com.example.app"
        let expectedID = "BUNDLE_ID_1"

        let exp = expectation(description: "request")
        let session = makeMockedSession()
        let (settings, client) = makeContext(session: session)

        MockURLProtocol.requestHandler = { request in
            defer { exp.fulfill() }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/bundleIds")

            let query = self.queryDict(from: request.url)
            XCTAssertEqual(query["filter[identifier]"], expectedIdentifier)
            XCTAssertEqual(query["limit"], "1")

            let body = #"{"data":[{"id":"\#(expectedID)","type":"bundleIds"}]}"#
            return self.okJSONResponse(for: request, body: body)
        }

        let id = try await IDsLookup.bundleID(identifier: expectedIdentifier, spec: spec, settings: settings, client: client)
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(id, expectedID)
    }

    func testIDsVersionLookupBuildsExpectedRequestAndReturnsID() async throws {
        let spec = try makeMinimalSpec()

        let appId = "123456789"
        let platform = "IOS"
        let versionString = "1.2.3"
        let expectedID = "VERSION_ID_1"

        let exp = expectation(description: "request")
        let session = makeMockedSession()
        let (settings, client) = makeContext(session: session)

        MockURLProtocol.requestHandler = { request in
            defer { exp.fulfill() }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/apps/\(appId)/appStoreVersions")

            let query = self.queryDict(from: request.url)
            XCTAssertEqual(query["filter[platform]"], platform)
            XCTAssertEqual(query["filter[versionString]"], versionString)
            XCTAssertEqual(query["limit"], "1")

            let body = #"{"data":[{"id":"\#(expectedID)","type":"appStoreVersions"}]}"#
            return self.okJSONResponse(for: request, body: body)
        }

        let id = try await IDsLookup.versionID(appId: appId, platform: platform, versionString: versionString, spec: spec, settings: settings, client: client)
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(id, expectedID)
    }

    func testIDsBuildLatestLookupBuildsExpectedRequestAndReturnsID() async throws {
        let spec = try makeMinimalSpec()

        let appId = "123456789"
        let expectedID = "BUILD_ID_1"

        let exp = expectation(description: "request")
        let session = makeMockedSession()
        let (settings, client) = makeContext(session: session)

        MockURLProtocol.requestHandler = { request in
            defer { exp.fulfill() }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/builds")

            let query = self.queryDict(from: request.url)
            XCTAssertEqual(query["filter[app]"], appId)
            XCTAssertEqual(query["sort"], "-uploadedDate")
            XCTAssertEqual(query["limit"], "1")

            let body = #"{"data":[{"id":"\#(expectedID)","type":"builds"}]}"#
            return self.okJSONResponse(for: request, body: body)
        }

        let id = try await IDsLookup.latestBuildID(appId: appId, spec: spec, settings: settings, client: client)
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(id, expectedID)
    }

    func testIDsBetaGroupLookupBuildsExpectedRequestAndReturnsID() async throws {
        let spec = try makeMinimalSpec()

        let appId = "123456789"
        let name = "Internal"
        let expectedID = "BETAGROUP_ID_1"

        let exp = expectation(description: "request")
        let session = makeMockedSession()
        let (settings, client) = makeContext(session: session)

        MockURLProtocol.requestHandler = { request in
            defer { exp.fulfill() }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/betaGroups")

            let query = self.queryDict(from: request.url)
            XCTAssertEqual(query["filter[app]"], appId)
            XCTAssertEqual(query["filter[name]"], name)
            XCTAssertEqual(query["limit"], "1")

            let body = #"{"data":[{"id":"\#(expectedID)","type":"betaGroups"}]}"#
            return self.okJSONResponse(for: request, body: body)
        }

        let id = try await IDsLookup.betaGroupID(appId: appId, name: name, spec: spec, settings: settings, client: client)
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(id, expectedID)
    }

    func testIDsTesterLookupBuildsExpectedRequestAndReturnsID() async throws {
        let spec = try makeMinimalSpec()

        let email = "a@b.com"
        let expectedID = "TESTER_ID_1"

        let exp = expectation(description: "request")
        let session = makeMockedSession()
        let (settings, client) = makeContext(session: session)

        MockURLProtocol.requestHandler = { request in
            defer { exp.fulfill() }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/betaTesters")

            let query = self.queryDict(from: request.url)
            XCTAssertEqual(query["filter[email]"], email)
            XCTAssertEqual(query["limit"], "1")

            let body = #"{"data":[{"id":"\#(expectedID)","type":"betaTesters"}]}"#
            return self.okJSONResponse(for: request, body: body)
        }

        let id = try await IDsLookup.testerID(email: email, spec: spec, settings: settings, client: client)
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(id, expectedID)
    }

    // MARK: - Helpers

    private func makeMinimalSpec() throws -> OpenAPISpec {
        let json = """
        {
          "openapi": "3.0.0",
          "info": { "title": "Test", "version": "0" },
          "paths": {
            "/v1/apps": { "get": { "operationId": "listApps" } },
            "/v1/bundleIds": { "get": { "operationId": "listBundleIds" } },
            "/v1/apps/{id}/appStoreVersions": { "get": { "operationId": "listAppStoreVersions" } },
            "/v1/builds": { "get": { "operationId": "listBuilds" } },
            "/v1/betaGroups": { "get": { "operationId": "listBetaGroups" } },
            "/v1/betaTesters": { "get": { "operationId": "listBetaTesters" } }
          }
        }
        """
        return try OpenAPISpec(data: Data(json.utf8))
    }

    private func makeMockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeContext(session: URLSession) -> (settings: ResolvedSettings, client: ASCClient) {
        let privateKey = P256.Signing.PrivateKey()
        let pem = privateKey.pemRepresentation

        let baseURL = URL(string: "https://example.com/v1/")!
        let retry = ASCRetryPolicy(count: 0, baseDelaySeconds: 0)
        let config = ASCClientConfiguration(baseURL: baseURL, timeoutSeconds: 5, retryPolicy: retry)
        let creds = ASCCredentials(issuerID: "issuer", keyID: "kid", privateKey: .pem(pem))
        let client = ASCClient(credentials: creds, configuration: config, session: session)

        let settings = ResolvedSettings(
            profileName: "default",
            issuerID: "issuer",
            keyID: "kid",
            privateKey: .pem(pem),
            baseURL: config.baseURL,
            timeoutSeconds: config.timeoutSeconds,
            retryPolicy: config.retryPolicy,
            verbose: false,
            pretty: false,
            sources: [:]
        )

        return (settings, client)
    }

    private func okJSONResponse(for request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        let url = request.url ?? URL(string: "https://example.com/")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    private func queryDict(from url: URL?) -> [String: String] {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else {
            return [:]
        }
        var out: [String: String] = [:]
        for item in items {
            out[item.name] = item.value ?? ""
        }
        return out
    }

}
