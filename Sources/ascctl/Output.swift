import Foundation

enum Output {
    static func printJSON(_ object: Any, pretty: Bool) throws {
        let object = sanitizeJSON(object)
        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if pretty {
            options.insert(.prettyPrinted)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func sanitizeJSON(_ value: Any) -> Any {
        // Recursively unwrap Optionals and ensure everything is JSONSerialization-compatible.
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first {
                return sanitizeJSON(child.value)
            }
            return NSNull()
        }

        if value is NSNull { return value }
        if value is String { return value }
        if value is Bool { return value }
        if value is Int { return value }
        if value is Double { return value }
        if value is Float { return Double(value as! Float) }
        if value is NSNumber { return value }

        if let data = value as? Data {
            // Never emit raw bytes to stdout; represent them safely.
            return data.base64EncodedString()
        }

        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (k, v) in dict {
                out[k] = sanitizeJSON(v)
            }
            return out
        }

        if let dict = value as? [String: String] {
            return dict
        }

        if let array = value as? [Any] {
            return array.map { sanitizeJSON($0) }
        }

        // Fallback: stringify.
        return String(describing: value)
    }

    static func envelopeOK(command: String, data: Any, meta: [String: Any] = [:], pretty: Bool) throws {
        try printJSON(
            [
                "ok": true,
                "command": command,
                "data": data,
                "meta": meta,
            ],
            pretty: pretty
        )
    }

    static func envelopeError(command: String, code: String, message: String, status: Int? = nil, details: [String: Any] = [:], meta: [String: Any] = [:], pretty: Bool) throws {
        try printJSON(
            [
                "ok": false,
                "command": command,
                "error": [
                    "code": code,
                    "message": message,
                    "status": status as Any,
                    "details": details,
                ],
                "meta": meta,
            ],
            pretty: pretty
        )
    }

    static func warn(_ message: String) {
        FileHandle.standardError.write(Data(("warning: \(message)\n").utf8))
    }

    static func info(_ message: String) {
        FileHandle.standardError.write(Data(("\(message)\n").utf8))
    }
}
