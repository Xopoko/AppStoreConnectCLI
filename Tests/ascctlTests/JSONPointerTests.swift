import XCTest

@testable import ascctl

final class JSONPointerTests: XCTestCase {
    func testSelectEmptyPointerReturnsRoot() throws {
        let json: Any = ["a": 1]
        let out = try JSONPointer.select(json, pointer: "")
        let dict = out as? [String: Any]
        XCTAssertEqual(dict?["a"] as? Int, 1)
    }

    func testSelectObjectKey() throws {
        let json: Any = ["data": ["id": "123"]]
        XCTAssertEqual(try JSONPointer.select(json, pointer: "/data/id") as? String, "123")
    }

    func testSelectArrayIndex() throws {
        let json: Any = ["data": [["id": "a"], ["id": "b"]]]
        XCTAssertEqual(try JSONPointer.select(json, pointer: "/data/1/id") as? String, "b")
    }

    func testSelectDecodesEscapes() throws {
        let json: Any = ["a/b": ["~key": 1]]
        XCTAssertEqual(try JSONPointer.select(json, pointer: "/a~1b/~0key") as? Int, 1)
    }

    func testSelectNotFoundThrows() {
        let json: Any = ["data": []]
        XCTAssertThrowsError(try JSONPointer.select(json, pointer: "/data/0/id")) { error in
            guard let cli = error as? CLIError else {
                XCTFail("Expected CLIError, got: \(error)")
                return
            }
            guard case .selectNotFound = cli else {
                XCTFail("Expected selectNotFound, got: \(error)")
                return
            }
        }
    }

    func testInvalidPointerThrows() {
        let json: Any = ["a": 1]
        XCTAssertThrowsError(try JSONPointer.select(json, pointer: "a")) { error in
            guard let cli = error as? CLIError else {
                XCTFail("Expected CLIError, got: \(error)")
                return
            }
            guard case .invalidArgument = cli else {
                XCTFail("Expected invalidArgument, got: \(error)")
                return
            }
        }
    }
}
