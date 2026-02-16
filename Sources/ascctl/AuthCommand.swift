import AppStoreConnectAPI
import ArgumentParser
import Foundation

struct AuthCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Authentication utilities.",
        subcommands: [
            Validate.self
        ]
    )

    struct Validate: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "validate",
            abstract: "Validate ASC credentials by calling a lightweight endpoint."
        )

        @OptionGroup
        var global: GlobalOptions

        func run() async throws {
            let command = "auth.validate"
            let (settings, _, _) = try SettingsResolver.resolve(global: global, requireAuth: true)
            let client = try settings.makeClient()

            let url: URL = {
                let base = settings.baseURL.appendingPathComponent("users")
                guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
                    return base
                }
                components.queryItems = [URLQueryItem(name: "limit", value: "1")]
                return components.url ?? base
            }()

            let raw = try await client.performRawResponse(method: "GET", url: url, body: nil, authorize: true, addJSONHeaders: true)

            if (200..<300).contains(raw.statusCode) {
                try Output.envelopeOK(command: command, data: ["ok": true], pretty: global.pretty)
                return
            }

            // Some keys can be valid but not authorized to read users; treat 403 as "auth ok".
            if raw.statusCode == 403 {
                try Output.envelopeOK(
                    command: command,
                    data: [
                        "ok": true,
                        "warning": "Forbidden to list users; credentials appear valid but lack permission for this endpoint.",
                    ],
                    pretty: global.pretty
                )
                return
            }

            let details: [String: Any] = {
                if raw.body.isEmpty { return [:] }
                if let any = try? JSONSerialization.jsonObject(with: raw.body, options: []),
                   JSONSerialization.isValidJSONObject(any)
                {
                    return ["body": any]
                }
                return ["body": String(data: raw.body, encoding: .utf8) ?? ""]
            }()

            throw CLIError.apiError(
                status: raw.statusCode,
                message: "Auth validation request failed with status \(raw.statusCode).",
                details: details
            )
        }
    }
}
