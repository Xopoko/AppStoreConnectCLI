import Foundation

enum KeyValueInput {
    static func parse(pairs: [String]) throws -> [(name: String, value: String)] {
        var out: [(name: String, value: String)] = []
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw CLIError.invalidArgument("Invalid pair '\(pair)'. Expected key=value.")
            }
            let name = String(parts[0])
            let value = String(parts[1])
            guard !name.isEmpty else {
                throw CLIError.invalidArgument("Invalid pair '\(pair)'. Key must not be empty.")
            }
            out.append((name: name, value: value))
        }
        return out
    }

    static func parseDictionary(pairs: [String]) throws -> [String: String] {
        var dict: [String: String] = [:]
        for p in try parse(pairs: pairs) {
            dict[p.name] = p.value
        }
        return dict
    }
}

