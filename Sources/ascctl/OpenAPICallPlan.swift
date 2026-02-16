import Foundation

struct OpenAPICallPlan: Sendable {
    let method: String
    let pathTemplate: String
    let operationId: String

    let requiredPathParams: [String]
    let requiredQueryParams: [String]
    let requiredHeaderParams: [String]
    let suggestedQueryPairs: [String]

    let requestBodyRequired: Bool
    let requestContentTypes: [String]
    let responseContentTypes: [String]

    let accept: String?
    let contentType: String?
    let addJSONHeaders: Bool
    let requiresConfirm: Bool

    init(op: OpenAPIOperation) {
        self.method = op.method
        self.pathTemplate = op.path
        self.operationId = op.operationId

        self.requiredPathParams = Self.extractPathParams(pathTemplate: op.path)
        self.requiredQueryParams = Self.requiredQueryParams(op: op)
        self.requiredHeaderParams = Self.requiredHeaderParams(op: op)
        self.suggestedQueryPairs = Self.suggestedQueryPairs(op: op, requiredQueryParams: requiredQueryParams)

        let rb = op.requestBody
        self.requestBodyRequired = (rb?["required"] as? Bool) == true
        self.requestContentTypes = Self.requestContentTypes(op: op)

        let responseTypes = Self.responseContentTypes(op: op)
        self.responseContentTypes = responseTypes
        let accept: String? = {
            if responseTypes.contains("application/json") { return "application/json" }
            return responseTypes.first
        }()
        self.accept = accept

        let requestTypes = Self.requestContentTypes(op: op)
        let contentType: String? = {
            if requestTypes.contains("application/json") { return "application/json" }
            return requestTypes.first
        }()
        self.contentType = contentType

        self.addJSONHeaders = (accept == nil || accept == "application/json")
        self.requiresConfirm = Self.methodRequiresConfirm(op.method)
    }

    private static func extractPathParams(pathTemplate: String) -> [String] {
        // /v1/apps/{id}/builds -> ["id"]
        let pattern = #"\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let ns = pathTemplate as NSString
        let matches = regex.matches(in: pathTemplate, options: [], range: NSRange(location: 0, length: ns.length))
        var names: [String] = []
        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let name = ns.substring(with: m.range(at: 1))
            if !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    private static func responseContentTypes(op: OpenAPIOperation) -> [String] {
        guard let responses = op.responses else { return [] }
        var types: [String] = []
        for (_, rAny) in responses.sorted(by: { $0.key < $1.key }) {
            guard let r = rAny as? [String: Any] else { continue }
            let content = r["content"] as? [String: Any] ?? [:]
            for ct in content.keys.sorted() {
                if !types.contains(ct) {
                    types.append(ct)
                }
            }
            if !types.isEmpty {
                break
            }
        }
        return types
    }

    private static func requestContentTypes(op: OpenAPIOperation) -> [String] {
        guard let rb = op.requestBody else { return [] }
        let content = rb["content"] as? [String: Any] ?? [:]
        return content.keys.sorted()
    }

    private static func requiredQueryParams(op: OpenAPIOperation) -> [String] {
        let names = op.parameters.compactMap { p -> String? in
            guard (p["in"] as? String) == "query",
                  (p["required"] as? Bool) == true,
                  let name = p["name"] as? String
            else { return nil }
            return name
        }
        return Array(Set(names)).sorted()
    }

    private static func requiredHeaderParams(op: OpenAPIOperation) -> [String] {
        let excluded = Set(["authorization", "accept", "content-type"])
        let names = op.parameters.compactMap { p -> String? in
            guard (p["in"] as? String) == "header",
                  (p["required"] as? Bool) == true,
                  let name = p["name"] as? String
            else { return nil }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if excluded.contains(trimmed.lowercased()) { return nil }
            return trimmed
        }
        return Array(Set(names)).sorted()
    }

    private static func suggestedQueryPairs(op: OpenAPIOperation, requiredQueryParams: [String]) -> [String] {
        var pairs: [String] = []
        let queryParams = op.parameters.compactMap { p -> (name: String, required: Bool)? in
            guard (p["in"] as? String) == "query",
                  let name = p["name"] as? String
            else { return nil }
            let required = (p["required"] as? Bool) == true
            return (name, required)
        }

        if queryParams.contains(where: { $0.name == "limit" }) {
            pairs.append("limit=50")
        }
        for name in requiredQueryParams where name != "limit" {
            pairs.append("\(name)=VALUE")
        }
        return pairs
    }

    private static func methodRequiresConfirm(_ method: String) -> Bool {
        switch method.uppercased() {
        case "POST", "PUT", "PATCH", "DELETE":
            return true
        default:
            return false
        }
    }
}

extension OpenAPISpec {
    func plan(for op: OpenAPIOperation) -> OpenAPICallPlan {
        OpenAPICallPlan(op: op)
    }
}
