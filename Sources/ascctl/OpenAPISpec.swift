import Foundation

struct OpenAPIOperation {
    let method: String // uppercase
    let path: String
    let operationId: String
    let summary: String?
    let description: String?
    let tags: [String]
    let parameters: [[String: Any]]
    let requestBody: [String: Any]?
    let responses: [String: Any]?

    var key: String { "\(method) \(path)" }
}

struct OpenAPISpec {
    let raw: [String: Any]
    let operations: [OpenAPIOperation]
    let operationById: [String: OpenAPIOperation]
    let operationByMethodPath: [String: OpenAPIOperation]

    let title: String?
    let version: String?
    let openapi: String?
    let serverURL: String?
    let pathsCount: Int
    let operationsCount: Int

    init(data: Data) throws {
        let any = try JSONSerialization.jsonObject(with: data, options: [])
        guard let json = any as? [String: Any] else {
            throw CLIError.invalidArgument("Invalid OpenAPI spec: top-level JSON is not an object.")
        }
        self.raw = json

        self.openapi = json["openapi"] as? String
        if let info = json["info"] as? [String: Any] {
            self.title = info["title"] as? String
            self.version = info["version"] as? String
        } else {
            self.title = nil
            self.version = nil
        }
        if let servers = json["servers"] as? [[String: Any]], let first = servers.first {
            self.serverURL = first["url"] as? String
        } else {
            self.serverURL = nil
        }

        let paths = json["paths"] as? [String: Any] ?? [:]
        self.pathsCount = paths.count

        var ops: [OpenAPIOperation] = []
        ops.reserveCapacity(1200)

        let httpMethods = ["get", "post", "put", "patch", "delete"]
        for (path, itemAny) in paths {
            guard let item = itemAny as? [String: Any] else { continue }
            let pathParameters = (item["parameters"] as? [Any] ?? [])
                .compactMap { $0 as? [String: Any] }

            for m in httpMethods {
                guard let opAny = item[m] as? [String: Any] else { continue }
                let method = m.uppercased()

                let opId = (opAny["operationId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let operationId = (opId?.isEmpty == false) ? opId! : "\(method) \(path)"
                let summary = opAny["summary"] as? String
                let description = opAny["description"] as? String
                let tags = opAny["tags"] as? [String] ?? []

                let opParameters = (opAny["parameters"] as? [Any] ?? [])
                    .compactMap { $0 as? [String: Any] }

                let mergedParams = pathParameters + opParameters
                let requestBody = opAny["requestBody"] as? [String: Any]
                let responses = opAny["responses"] as? [String: Any]

                ops.append(OpenAPIOperation(
                    method: method,
                    path: path,
                    operationId: operationId,
                    summary: summary,
                    description: description,
                    tags: tags,
                    parameters: mergedParams,
                    requestBody: requestBody,
                    responses: responses
                ))
            }
        }

        ops.sort { lhs, rhs in
            if lhs.path == rhs.path { return lhs.method < rhs.method }
            return lhs.path < rhs.path
        }

        self.operations = ops
        self.operationsCount = ops.count

        var byId: [String: OpenAPIOperation] = [:]
        var byMethodPath: [String: OpenAPIOperation] = [:]
        byId.reserveCapacity(ops.count)
        byMethodPath.reserveCapacity(ops.count)
        for op in ops {
            byId[op.operationId] = op
            byMethodPath[op.key] = op
        }
        self.operationById = byId
        self.operationByMethodPath = byMethodPath
    }

    func tagCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for op in operations {
            for tag in op.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
    }

    func filterOperations(
        tags: [String],
        methods: [String],
        pathPrefix: String?,
        text: String?
    ) -> [OpenAPIOperation] {
        let wantedTags = tags.map { $0.lowercased() }.filter { !$0.isEmpty }
        let wantedMethods = Set(methods.map { $0.uppercased() }.filter { !$0.isEmpty })
        let prefix: String? = {
            guard let value = pathPrefix?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }()
        let needle: String? = {
            guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else { return nil }
            return value
        }()

        return operations.filter { op in
            if !wantedMethods.isEmpty, !wantedMethods.contains(op.method) {
                return false
            }
            if let prefix, !op.path.hasPrefix(prefix) {
                return false
            }
            if !wantedTags.isEmpty {
                let opTags = op.tags.map { $0.lowercased() }
                if !wantedTags.contains(where: { opTags.contains($0) }) {
                    return false
                }
            }
            if let needle {
                let haystack = searchHaystack(op: op)
                if !haystack.contains(needle) {
                    return false
                }
            }
            return true
        }
    }

    func lookup(operationId: String?) -> OpenAPIOperation? {
        guard let operationId, !operationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return operationById[operationId]
    }

    func lookup(method: String?, path: String?) -> OpenAPIOperation? {
        guard let method, let path else { return nil }
        let m = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty || p.isEmpty { return nil }
        return operationByMethodPath["\(m) \(p)"]
    }

    private func searchHaystack(op: OpenAPIOperation) -> String {
        var parts: [String] = []
        parts.append(op.path)
        parts.append(op.method)
        parts.append(op.operationId)
        if let summary = op.summary { parts.append(summary) }
        if let description = op.description { parts.append(description) }
        parts.append(op.tags.joined(separator: " "))
        let paramNames = op.parameters.compactMap { $0["name"] as? String }
        if !paramNames.isEmpty {
            parts.append(paramNames.joined(separator: " "))
        }
        return parts.joined(separator: "\n").lowercased()
    }
}
