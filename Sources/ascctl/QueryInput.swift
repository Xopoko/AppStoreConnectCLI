import Foundation

enum QueryInput {
    static func parse(pairs: [String]) throws -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw CLIError.invalidArgument("Invalid --query '\(pair)'. Expected key=value.")
            }
            let name = String(parts[0])
            let value = String(parts[1])
            guard !name.isEmpty else {
                throw CLIError.invalidArgument("Invalid --query '\(pair)'. Key must not be empty.")
            }
            items.append(URLQueryItem(name: name, value: value))
        }
        return items
    }
}

