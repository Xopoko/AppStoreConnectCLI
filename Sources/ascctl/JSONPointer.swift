import Foundation

enum JSONPointer {
    static func select(_ json: Any, pointer: String) throws -> Any {
        if pointer.isEmpty { return json }
        guard pointer.hasPrefix("/") else {
            throw CLIError.invalidArgument("Invalid --select JSON pointer. Must be empty or start with '/'.")
        }

        var current: Any = json
        let rawSegments = pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        for raw in rawSegments {
            let segment = decode(String(raw))
            if let dict = current as? [String: Any] {
                guard let next = dict[segment] else {
                    throw CLIError.selectNotFound(pointer: pointer)
                }
                current = next
                continue
            }
            if let array = current as? [Any] {
                guard let idx = Int(segment) else {
                    throw CLIError.invalidArgument("Invalid JSON pointer segment '\(segment)'. Expected an array index.")
                }
                guard idx >= 0, idx < array.count else {
                    throw CLIError.selectNotFound(pointer: pointer)
                }
                current = array[idx]
                continue
            }
            // Can't traverse into scalars/null.
            throw CLIError.selectNotFound(pointer: pointer)
        }
        return current
    }

    private static func decode(_ segment: String) -> String {
        // RFC 6901
        segment
            .replacingOccurrences(of: "~1", with: "/")
            .replacingOccurrences(of: "~0", with: "~")
    }
}

