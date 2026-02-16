import Foundation
import XCTest

@testable import ascctl

final class OpenAPIRunnerValidationTests: XCTestCase {
    func testPaginatedGETMergesDataAndDedupsIncludedAndUsesLastLinks() async throws {
        let plan = OpenAPICallPlan(op: OpenAPIOperation(
            method: "GET",
            path: "/v1/things",
            operationId: "listThings",
            summary: nil,
            description: nil,
            tags: [],
            parameters: [],
            requestBody: nil,
            responses: nil
        ))

        let page1: [String: Any] = [
            "data": [
                ["type": "apps", "id": "1"],
                ["type": "apps", "id": "2"],
            ],
            "included": [
                ["type": "builds", "id": "b1"],
            ],
            "links": [
                "self": "/v1/things",
                "next": "/v1/things?page=2",
            ],
        ]
        let page2: [String: Any] = [
            "data": [
                ["type": "apps", "id": "3"],
            ],
            "included": [
                ["type": "builds", "id": "b1"], // duplicate
                ["type": "builds", "id": "b2"],
            ],
            "links": [
                "self": "/v1/things?page=2",
            ],
        ]

        let performer = FakePerformer(responses: [
            .json(status: 200, json: page1),
            .json(status: 200, json: page2),
        ])

        let result = try await OpenAPIRunner.executePaginatedGET(
            plan: plan,
            apiRoot: URL(string: "https://example.test")!,
            pathParams: [:],
            queryItems: [],
            extraHeaders: [:],
            acceptOverride: nil,
            noJSONHeaders: false,
            performer: performer,
            limit: nil
        )

        XCTAssertEqual(performer.calls.count, 2)
        XCTAssertTrue(performer.calls[0].url.absoluteString.contains("limit=200"))
        XCTAssertTrue(performer.calls[1].url.absoluteString.contains("limit=200"))
        XCTAssertEqual(result.pages, 2)
        XCTAssertEqual(result.items, 3)

        let mergedData = result.json["data"] as? [Any]
        XCTAssertEqual(mergedData?.count, 3)

        let included = result.json["included"] as? [Any]
        XCTAssertEqual(included?.count, 2)

        let links = result.json["links"] as? [String: Any]
        XCTAssertEqual(links?["self"] as? String, "/v1/things?page=2")
        XCTAssertNil(links?["next"])
    }

    func testPaginatedGETStopsAtLimitWithoutFetchingNextPage() async throws {
        let plan = OpenAPICallPlan(op: OpenAPIOperation(
            method: "GET",
            path: "/v1/things",
            operationId: "listThings",
            summary: nil,
            description: nil,
            tags: [],
            parameters: [],
            requestBody: nil,
            responses: nil
        ))

        let page1: [String: Any] = [
            "data": [
                ["type": "apps", "id": "1"],
                ["type": "apps", "id": "2"],
            ],
            "links": [
                "next": "/v1/things?page=2",
            ],
        ]
        let page2: [String: Any] = [
            "data": [
                ["type": "apps", "id": "3"],
            ],
            "links": [
                "self": "/v1/things?page=2",
            ],
        ]

        let performer = FakePerformer(responses: [
            .json(status: 200, json: page1),
            .json(status: 200, json: page2),
        ])

        let result = try await OpenAPIRunner.executePaginatedGET(
            plan: plan,
            apiRoot: URL(string: "https://example.test")!,
            pathParams: [:],
            queryItems: [],
            extraHeaders: [:],
            acceptOverride: nil,
            noJSONHeaders: false,
            performer: performer,
            limit: 2
        )

        XCTAssertEqual(performer.calls.count, 1, "Expected only the first page to be fetched when limit is reached.")
        XCTAssertTrue(performer.calls[0].url.absoluteString.contains("limit=2"))
        XCTAssertEqual(result.pages, 1)
        XCTAssertEqual(result.items, 2)
    }
}

private final class FakePerformer: RawHTTPPerformer {
    struct Call {
        let method: String
        let url: URL
        let addJSONHeaders: Bool
        let headers: [String: String]
    }

    enum Response {
        case json(status: Int, json: [String: Any], headers: [String: String])

        static func json(status: Int, json: [String: Any]) -> Response {
            .json(status: status, json: json, headers: ["Content-Type": "application/json"])
        }
    }

    private var queue: [Response]
    private(set) var calls: [Call] = []

    init(responses: [Response]) {
        self.queue = responses
    }

    func perform(
        method: String,
        url: URL,
        body: Data?,
        addJSONHeaders: Bool,
        headers: [String: String]
    ) async throws -> OpenAPIRawResponse {
        calls.append(Call(method: method, url: url, addJSONHeaders: addJSONHeaders, headers: headers))
        guard !queue.isEmpty else {
            return OpenAPIRawResponse(statusCode: 500, headers: [:], body: Data())
        }
        let next = queue.removeFirst()
        switch next {
        case .json(let status, let json, let headers):
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            return OpenAPIRawResponse(statusCode: status, headers: headers, body: data)
        }
    }
}
