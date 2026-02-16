import Foundation
import XCTest

final class AgentExitTests: XCTestCase {
    func testOpenAPIOpsListIsSingleJSONOnStdoutAndStderrEmpty() throws {
        let tmp = try TempDir()
        let specURL = try tmp.write(name: "spec.json", data: Data(Self.minimalSpec.utf8))

        let result = try runAscctl(args: ["openapi", "ops", "list", "--spec", specURL.path, "--all"], cwd: tmp.url)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stderr.count, 0)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(json["command"] as? String, "openapi.ops.list")
        let data = json["data"] as? [String: Any]
        XCTAssertNotNil(data?["operations"])
    }

    func testHelpIsJSONAndExit0() throws {
        let tmp = try TempDir()
        let result = try runAscctl(args: ["--help"], cwd: tmp.url)
        XCTAssertEqual(result.status, 0)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(json["command"] as? String, "ascctl")
        let help = ((json["data"] as? [String: Any])?["help"] as? String) ?? ""
        XCTAssertTrue(help.contains("USAGE:"), "Expected help text to contain USAGE:, got: \(help.prefix(120))")
    }

    func testUnknownFlagIsUsageErrorExit2() throws {
        let tmp = try TempDir()
        let specURL = try tmp.write(name: "spec.json", data: Data(Self.minimalSpec.utf8))

        let result = try runAscctl(args: ["openapi", "ops", "list", "--spec", specURL.path, "--nope"], cwd: tmp.url)
        XCTAssertEqual(result.status, 2)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, false)
        XCTAssertEqual(json["command"] as? String, "openapi.ops.list")
        let error = json["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "usage_error")
    }

    func testConfirmRequiredForMutatingMethods() throws {
        let tmp = try TempDir()
        let specURL = try tmp.write(name: "spec.json", data: Data(Self.minimalSpec.utf8))

        let result = try runAscctl(
            args: ["openapi", "op", "run", "--spec", specURL.path, "--method", "POST", "--path", "/v1/things"],
            cwd: tmp.url
        )
        XCTAssertEqual(result.status, 2)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, false)
        XCTAssertEqual(json["command"] as? String, "openapi.op.run")
        let error = json["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "confirm_required")
    }

    func testValidationMissingRequiredQuery() throws {
        let tmp = try TempDir()
        let specURL = try tmp.write(name: "spec.json", data: Data(Self.minimalSpec.utf8))

        let result = try runAscctl(
            args: ["openapi", "op", "run", "--spec", specURL.path, "--method", "GET", "--path", "/v1/needsQuery"],
            cwd: tmp.url
        )
        XCTAssertEqual(result.status, 2)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, false)
        let error = json["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "validation_failed")
        let details = error?["details"] as? [String: Any]
        let missing = details?["missingQuery"] as? [String]
        XCTAssertEqual(missing ?? [], ["q"])
    }

    func testValidationMissingRequiredBody() throws {
        let tmp = try TempDir()
        let specURL = try tmp.write(name: "spec.json", data: Data(Self.minimalSpec.utf8))

        let result = try runAscctl(
            args: [
                "openapi", "op", "run",
                "--spec", specURL.path,
                "--method", "POST",
                "--path", "/v1/things",
                "--confirm",
            ],
            cwd: tmp.url
        )
        XCTAssertEqual(result.status, 2)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, false)
        let error = json["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "validation_failed")
        let details = error?["details"] as? [String: Any]
        XCTAssertEqual(details?["missingBody"] as? Bool, true)
    }

    func testValidationEnumAndTypeChecks() throws {
        let tmp = try TempDir()
        let specURL = try tmp.write(name: "spec.json", data: Data(Self.minimalSpec.utf8))

        let result = try runAscctl(
            args: [
                "openapi", "op", "run",
                "--spec", specURL.path,
                "--method", "GET",
                "--path", "/v1/validate",
                "--query", "limit=not-an-int",
                "--query", "mode=c",
            ],
            cwd: tmp.url
        )
        XCTAssertEqual(result.status, 2)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, false)
        let error = json["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "validation_failed")
        let details = error?["details"] as? [String: Any]
        let invalid = (details?["invalid"] as? [[String: Any]]) ?? []
        XCTAssertEqual(invalid.count, 2)
    }

    func testReplayWithSelectReturnsOnlyResult() throws {
        let tmp = try TempDir()
        let specURL = try tmp.write(name: "spec.json", data: Data(Self.minimalSpec.utf8))

        let replayDir = tmp.url.appendingPathComponent("replay", isDirectory: true)
        try FileManager.default.createDirectory(at: replayDir, withIntermediateDirectories: true)

        let record: [String: Any] = [
            "request": ["method": "GET", "url": "https://example.test/v1/things", "headers": [:]],
            "response": ["status": 200, "headers": ["Content-Type": "application/json"]],
        ]
        let recordData = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try recordData.write(to: replayDir.appendingPathComponent("record.json"))

        let body = #"{"data":[{"id":"abc"}]}"#
        try Data(body.utf8).write(to: replayDir.appendingPathComponent("response.body"))

        let result = try runAscctl(
            args: [
                "openapi", "op", "run",
                "--spec", specURL.path,
                "--method", "GET",
                "--path", "/v1/things",
                "--replay", replayDir.path,
                "--select", "/data/0/id",
            ],
            cwd: tmp.url
        )
        XCTAssertEqual(result.status, 0)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, true)
        let data = json["data"] as? [String: Any]
        XCTAssertEqual(data?["result"] as? String, "abc")

        let response = data?["response"] as? [String: Any]
        XCTAssertNil(response?["body"], "Expected no body when --select is used.")
    }

    func testReplayNonJSONRequiresOut() throws {
        let tmp = try TempDir()
        let specURL = try tmp.write(name: "spec.json", data: Data(Self.minimalSpec.utf8))

        let replayDir = tmp.url.appendingPathComponent("replay-nonjson", isDirectory: true)
        try FileManager.default.createDirectory(at: replayDir, withIntermediateDirectories: true)

        let record: [String: Any] = [
            "request": ["method": "GET", "url": "https://example.test/v1/things", "headers": [:]],
            "response": ["status": 200, "headers": ["Content-Type": "application/octet-stream"]],
        ]
        let recordData = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try recordData.write(to: replayDir.appendingPathComponent("record.json"))
        try Data([0x00, 0x01, 0x02]).write(to: replayDir.appendingPathComponent("response.body"))

        let result = try runAscctl(
            args: [
                "openapi", "op", "run",
                "--spec", specURL.path,
                "--method", "GET",
                "--path", "/v1/things",
                "--replay", replayDir.path,
            ],
            cwd: tmp.url
        )
        XCTAssertEqual(result.status, 2)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, false)
        let error = json["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "non_json_requires_out")
    }

    func testOpenAPIOpTemplateGeneratesBodyAndArgvForPOST() throws {
        let tmp = try TempDir()

        let spec = """
        {
          "openapi": "3.0.0",
          "info": { "title": "Test", "version": "1.0" },
          "paths": {
            "/v1/things": {
              "post": {
                "operationId": "createThing",
                "requestBody": {
                  "required": true,
                  "content": {
                    "application/json": {
                      "schema": { "$ref": "#/components/schemas/CreateThingRequest" }
                    }
                  }
                },
                "responses": { "201": { "description": "created" } }
              }
            }
          },
          "components": {
            "schemas": {
              "CreateThingRequest": {
                "type": "object",
                "required": ["name"],
                "properties": { "name": { "type": "string" } }
              }
            }
          }
        }
        """

        let specURL = try tmp.write(name: "spec.json", data: Data(spec.utf8))
        let result = try runAscctl(
            args: ["openapi", "op", "template", "--spec", specURL.path, "--method", "POST", "--path", "/v1/things"],
            cwd: tmp.url
        )
        XCTAssertEqual(result.status, 0)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(json["command"] as? String, "openapi.op.template")

        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let body = try XCTUnwrap(data["body"] as? [String: Any])
        XCTAssertEqual(body["name"] as? String, "VALUE")

        let argv = (data["argv"] as? [String]) ?? []
        XCTAssertTrue(argv.contains("--confirm"))

        if let idx = argv.firstIndex(of: "--body-json"), argv.indices.contains(idx + 1) {
            let bodyArg = argv[idx + 1]
            XCTAssertTrue(bodyArg.contains(#""name":"VALUE""#))
        } else {
            XCTFail("Expected argv to include --body-json <json>")
        }
    }

    func testOpenAPIOpTemplateIncludesRequiredQueryInArgv() throws {
        let tmp = try TempDir()

        let spec = """
        {
          "openapi": "3.0.0",
          "info": { "title": "Test", "version": "1.0" },
          "paths": {
            "/v1/needsQuery": {
              "get": {
                "operationId": "needsQuery",
                "parameters": [
                  { "name": "q", "in": "query", "required": true, "schema": { "type": "string" } }
                ],
                "responses": { "200": { "description": "ok" } }
              }
            }
          }
        }
        """

        let specURL = try tmp.write(name: "spec.json", data: Data(spec.utf8))
        let result = try runAscctl(
            args: ["openapi", "op", "template", "--spec", specURL.path, "--method", "GET", "--path", "/v1/needsQuery"],
            cwd: tmp.url
        )
        XCTAssertEqual(result.status, 0)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(json["command"] as? String, "openapi.op.template")

        let data = try XCTUnwrap(json["data"] as? [String: Any])
        let argv = (data["argv"] as? [String]) ?? []
        XCTAssertTrue(argv.contains("--query"))
        XCTAssertTrue(argv.contains("q=VALUE"))
    }

    func testOpenAPISpecUpdateAcceptsRawJSONFromFileURLAndWritesOutput() throws {
        let tmp = try TempDir()

        let sourceSpec = """
        {
          "openapi": "3.0.0",
          "info": { "title": "Test", "version": "1.0" },
          "paths": {
            "/v1/things": {
              "get": {
                "operationId": "listThings",
                "responses": { "200": { "description": "ok" } }
              }
            }
          }
        }
        """

        let sourceURL = try tmp.write(name: "source.json", data: Data(sourceSpec.utf8))
        let outURL = tmp.url.appendingPathComponent("openapi.oas.json")

        let result = try runAscctl(
            args: ["openapi", "spec", "update", "--url", sourceURL.absoluteString, "--out", outURL.path],
            cwd: tmp.url
        )
        XCTAssertEqual(result.status, 0)

        let json = try Self.parseObject(result.stdout)
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(json["command"] as? String, "openapi.spec.update")

        let data = try XCTUnwrap(json["data"] as? [String: Any])
        XCTAssertEqual(data["out"] as? String, outURL.path)

        func intValue(_ any: Any?) -> Int? {
            if let i = any as? Int { return i }
            if let n = any as? NSNumber { return n.intValue }
            return nil
        }
        XCTAssertEqual(intValue(data["paths"]), 1)
        XCTAssertEqual(intValue(data["operations"]), 1)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
        let written = try Data(contentsOf: outURL)
        _ = try JSONSerialization.jsonObject(with: written, options: [])

        let result2 = try runAscctl(
            args: ["openapi", "spec", "update", "--url", sourceURL.absoluteString, "--out", outURL.path],
            cwd: tmp.url
        )
        XCTAssertEqual(result2.status, 2)
        let json2 = try Self.parseObject(result2.stdout)
        XCTAssertEqual(json2["ok"] as? Bool, false)
        let error = json2["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? String, "invalid_argument")
    }

    // MARK: - Helpers

    private struct TempDir {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("ascctl-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        func write(name: String, data: Data) throws -> URL {
            let out = url.appendingPathComponent(name)
            try data.write(to: out, options: [.atomic])
            return out
        }
    }

    private struct RunResult {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    private func runAscctl(args: [String], cwd: URL) throws -> RunResult {
        let exe = try ascctlExecutableURL()

        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        proc.currentDirectoryURL = cwd

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        try proc.run()
        proc.waitUntilExit()

        return RunResult(
            status: proc.terminationStatus,
            stdout: out.fileHandleForReading.readDataToEndOfFile(),
            stderr: err.fileHandleForReading.readDataToEndOfFile()
        )
    }

    private func ascctlExecutableURL() throws -> URL {
        let productsDir = Bundle(for: AgentExitTests.self).bundleURL.deletingLastPathComponent()
        let exe = productsDir.appendingPathComponent("ascctl")
        guard FileManager.default.isExecutableFile(atPath: exe.path) else {
            throw XCTSkip("ascctl executable not found at \(exe.path)")
        }
        return exe
    }

    private static func parseObject(_ data: Data) throws -> [String: Any] {
        let any = try JSONSerialization.jsonObject(with: data, options: [])
        guard let obj = any as? [String: Any] else {
            throw XCTSkip("stdout was not a JSON object: \(String(data: data, encoding: .utf8) ?? "")")
        }
        return obj
    }

    private static let minimalSpec = """
    {
      "openapi": "3.0.0",
      "info": { "title": "Test", "version": "1.0" },
      "paths": {
        "/v1/things": {
          "get": {
            "operationId": "listThings",
            "responses": {
              "200": { "description": "ok", "content": { "application/json": { "schema": { "type": "object" } } } }
            }
          },
          "post": {
            "operationId": "createThing",
            "requestBody": {
              "required": true,
              "content": { "application/json": { "schema": { "type": "object" } } }
            },
            "responses": {
              "201": { "description": "created", "content": { "application/json": { "schema": { "type": "object" } } } }
            }
          }
        },
        "/v1/needsQuery": {
          "get": {
            "operationId": "needsQuery",
            "parameters": [
              { "name": "q", "in": "query", "required": true, "schema": { "type": "string" } }
            ],
            "responses": {
              "200": { "description": "ok", "content": { "application/json": { "schema": { "type": "object" } } } }
            }
          }
        },
        "/v1/validate": {
          "get": {
            "operationId": "validate",
            "parameters": [
              { "name": "limit", "in": "query", "schema": { "type": "integer" } },
              { "name": "mode", "in": "query", "schema": { "type": "string", "enum": ["a", "b"] } }
            ],
            "responses": {
              "200": { "description": "ok", "content": { "application/json": { "schema": { "type": "object" } } } }
            }
          }
        }
      }
    }
    """
}
