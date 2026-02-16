import Foundation

struct OpenAPISchemaResolver {
    private let root: [String: Any]
    private let schemas: [String: Any]

    init(spec: OpenAPISpec) {
        self.root = spec.raw
        let components = (spec.raw["components"] as? [String: Any]) ?? [:]
        self.schemas = (components["schemas"] as? [String: Any]) ?? [:]
    }

    func resolveSchema(_ schema: [String: Any]) -> [String: Any] {
        if let ref = schema["$ref"] as? String, let resolved = resolveRef(ref) {
            return resolved
        }
        return schema
    }

    func resolveRef(_ ref: String) -> [String: Any]? {
        // Only support local component schema refs for now.
        let prefix = "#/components/schemas/"
        guard ref.hasPrefix(prefix) else { return nil }
        let name = String(ref.dropFirst(prefix.count))
        return schemas[name] as? [String: Any]
    }

    func skeleton(from schema: [String: Any], depth: Int = 0) -> Any {
        if depth > 6 { return "VALUE" }

        let schema = resolveSchema(schema)

        if let allOf = schema["allOf"] as? [Any], !allOf.isEmpty {
            // Merge object-like skeletons.
            var merged: [String: Any] = [:]
            for item in allOf {
                guard let dict = item as? [String: Any] else { continue }
                let skel = skeleton(from: dict, depth: depth + 1)
                if let obj = skel as? [String: Any] {
                    for (k, v) in obj { merged[k] = v }
                }
            }
            return merged
        }

        if let oneOf = schema["oneOf"] as? [Any], let first = oneOf.first as? [String: Any] {
            return skeleton(from: first, depth: depth + 1)
        }

        if let anyOf = schema["anyOf"] as? [Any], let first = anyOf.first as? [String: Any] {
            return skeleton(from: first, depth: depth + 1)
        }

        // Prefer explicit type, but fall back to properties presence.
        let type = (schema["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if type == "object" || schema["properties"] != nil {
            let props = (schema["properties"] as? [String: Any]) ?? [:]
            let required = (schema["required"] as? [String]) ?? []
            var out: [String: Any] = [:]
            for name in required.sorted() {
                guard let propAny = props[name] else {
                    out[name] = "VALUE"
                    continue
                }
                let propSchema = (propAny as? [String: Any]) ?? [:]
                out[name] = skeleton(from: propSchema, depth: depth + 1)
            }
            return out
        }

        if type == "array" {
            // Minimal skeleton: empty array.
            return []
        }

        if type == "string" || type == nil {
            if let values = schema["enum"] as? [Any], let first = values.first {
                return first
            }
            return "VALUE"
        }

        if type == "integer" || type == "number" {
            return 0
        }

        if type == "boolean" {
            return false
        }

        return "VALUE"
    }
}

