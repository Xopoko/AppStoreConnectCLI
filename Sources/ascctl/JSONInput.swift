import Foundation

enum JSONInput {
    static func attributes(fromJson json: String?, fromFile file: String?) throws -> [String: Any] {
        let data = try data(
            fromJson: json,
            fromFile: file,
            jsonFlag: "--attributes-json",
            fileFlag: "--attributes-file"
        )
        guard let data else { return [:] }

        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = object as? [String: Any] else {
            throw CLIError.invalidArgument("Expected a JSON object for attributes.")
        }
        return dict
    }

    static func data(fromJson json: String?, fromFile file: String?, jsonFlag: String, fileFlag: String) throws -> Data? {
        if json != nil, file != nil {
            throw CLIError.invalidArgument("Provide only one of \(jsonFlag) or \(fileFlag).")
        }
        if let json {
            let raw = Data(json.utf8)
            // Validate JSON and normalize output (no whitespace) for stable requests.
            let obj = try JSONSerialization.jsonObject(with: raw, options: [])
            return try JSONSerialization.data(withJSONObject: obj, options: [])
        }
        if let file {
            return try Data(contentsOf: URL(fileURLWithPath: file))
        }
        return nil
    }
}
