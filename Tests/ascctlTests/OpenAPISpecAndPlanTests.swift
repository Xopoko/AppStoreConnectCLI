import Foundation
import XCTest

@testable import ascctl

final class OpenAPISpecAndPlanTests: XCTestCase {
    func testPUTIsParsedAndRequiresConfirm() throws {
        let data = Data(Self.specWithPut.utf8)
        let spec = try OpenAPISpec(data: data)

        let op = spec.lookup(method: "PUT", path: "/v1/apps/{id}")
        XCTAssertNotNil(op)

        let plan = spec.plan(for: try XCTUnwrap(op))
        XCTAssertEqual(plan.method, "PUT")
        XCTAssertTrue(plan.requiresConfirm)
        XCTAssertEqual(plan.requiredPathParams, ["id"])
    }

    func testPlanExtractsRequiredQueryAndBodyRequired() throws {
        let data = Data(Self.specWithRequiredQueryAndBody.utf8)
        let spec = try OpenAPISpec(data: data)

        let op = try XCTUnwrap(spec.lookup(method: "POST", path: "/v1/widgets"))
        let plan = spec.plan(for: op)

        XCTAssertTrue(plan.requestBodyRequired)
        XCTAssertEqual(plan.requiredQueryParams, ["q"])
    }

    func testPlanExtractsRequiredHeaderParamsButFiltersAutoHeaders() throws {
        let data = Data(Self.specWithRequiredHeaderParams.utf8)
        let spec = try OpenAPISpec(data: data)

        let op = try XCTUnwrap(spec.lookup(method: "GET", path: "/v1/things"))
        let plan = spec.plan(for: op)

        XCTAssertEqual(plan.requiredHeaderParams, ["If-Match"])
    }

    private static let specWithPut = """
    {
      "openapi": "3.0.0",
      "info": { "title": "Test", "version": "1.0" },
      "paths": {
        "/v1/apps/{id}": {
          "parameters": [
            { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } }
          ],
          "put": {
            "operationId": "updateApp",
            "responses": { "200": { "description": "ok" } }
          }
        }
      }
    }
    """

    private static let specWithRequiredQueryAndBody = """
    {
      "openapi": "3.0.0",
      "info": { "title": "Test", "version": "1.0" },
      "paths": {
        "/v1/widgets": {
          "post": {
            "operationId": "createWidget",
            "parameters": [
              { "name": "q", "in": "query", "required": true, "schema": { "type": "string" } }
            ],
            "requestBody": {
              "required": true,
              "content": { "application/json": { "schema": { "type": "object" } } }
            },
            "responses": { "201": { "description": "created" } }
          }
        }
      }
    }
    """

    private static let specWithRequiredHeaderParams = """
    {
      "openapi": "3.0.0",
      "info": { "title": "Test", "version": "1.0" },
      "paths": {
        "/v1/things": {
          "get": {
            "operationId": "listThings",
            "parameters": [
              { "name": "If-Match", "in": "header", "required": true, "schema": { "type": "string" } },
              { "name": "Authorization", "in": "header", "required": true, "schema": { "type": "string" } },
              { "name": "Accept", "in": "header", "required": true, "schema": { "type": "string" } },
              { "name": "Content-Type", "in": "header", "required": true, "schema": { "type": "string" } }
            ],
            "responses": { "200": { "description": "ok" } }
          }
        }
      }
    }
    """
}
